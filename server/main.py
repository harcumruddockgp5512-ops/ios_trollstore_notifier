"""
FastAPI Server & WebSocket Broadcast Hub
"""

import os
import sys

try:
    if sys.stdout.encoding and sys.stdout.encoding.lower() != 'utf-8':
        sys.stdout.reconfigure(encoding='utf-8')
except Exception:
    pass

import time
import asyncio
import urllib.parse
import httpx

# 将当前目录加入 python 查找路径
sys.path.insert(0, os.path.dirname(__file__))

from typing import List, Dict, Any
from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from fastapi.responses import FileResponse
from pydantic import BaseModel

from alert_manager import alert_manager
from market_feed import MarketScanner
from screening_config import screening_config
import anomaly_rules

app = FastAPI(title="TrollStore Crypto Anomaly Hub")

# 允许跨域（方便本地 Flutter Web 或客户端联调）
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# WebSocket 连接池
class ConnectionManager:
    def __init__(self):
        self.active_connections: List[WebSocket] = []

    async def connect(self, websocket: WebSocket):
        await websocket.accept()
        self.active_connections.append(websocket)

    def disconnect(self, websocket: WebSocket):
        if websocket in self.active_connections:
            self.active_connections.remove(websocket)

    async def broadcast(self, message: Dict[str, Any]):
        for connection in list(self.active_connections):
            try:
                await connection.send_json(message)
            except Exception:
                self.disconnect(connection)

ws_manager = ConnectionManager()

async def send_external_push(alert: Dict[str, Any]):
    """向 iOS Bark (走苹果 APNs 官方通道，支持锁屏直接点亮屏幕) 或 Webhook 发送远程推送"""
    cfg = screening_config.settings
    if not cfg.get("enable_push", True):
        return

    sym = alert.get("symbol", "未知标的")
    score = alert.get("score", 70)
    title = f"🚨 异动做空: {sym} (评分:{score})"
    msg = alert.get("message", f"{alert.get('rule_name', '急拉见顶')} 现价: ${alert.get('price')}")

    # 1. iOS Bark 推送: 走苹果官方 APNs 信道，锁屏即刻点亮屏幕 + 震动 + 提示音
    bark_key = (cfg.get("bark_key") or "").strip()
    if bark_key:
        try:
            if bark_key.startswith("http://") or bark_key.startswith("https://"):
                base_bark = bark_key.rstrip("/")
            else:
                base_bark = f"https://api.day.app/{bark_key}"

            enc_title = urllib.parse.quote(title)
            enc_msg = urllib.parse.quote(msg)
            jump_url = urllib.parse.quote("http://47.92.99.47:15926/?tab=alerts")
            # level=timeSensitive 触发 iOS 锁屏点亮唤醒屏幕；sound=minuet 清脆提醒音；isArchive=1 保存历史
            bark_url = f"{base_bark}/{enc_title}/{enc_msg}?group=CryptoRadar&level=timeSensitive&sound=minuet&isArchive=1&url={jump_url}"

            async with httpx.AsyncClient(timeout=4.0) as client:
                res = await client.get(bark_url)
                if res.status_code == 200:
                    print(f"[Bark推送成功] {sym} 已发送苹果 APNs 锁屏亮屏通知")
                else:
                    print(f"[Bark推送返回异常] HTTP {res.status_code}")
        except Exception as e:
            print(f"[Bark推送异常]: {e}")

    # 2. 自定义 Webhook 推送
    webhook_url = (cfg.get("webhook_url") or "").strip()
    if webhook_url:
        try:
            payload = {
                "msg_type": "text",
                "content": {"text": f"{title}\n{msg}"},
                "alert": alert
            }
            async with httpx.AsyncClient(timeout=4.0) as client:
                await client.post(webhook_url, json=payload)
        except Exception as e:
            print(f"[Webhook推送异常]: {e}")

async def broadcast_anomaly(alert: Dict[str, Any]):
    """广播新预警事件并分发锁屏推送"""
    payload = {
        "type": "ANOMALY_ALERT",
        "data": alert
    }
    await ws_manager.broadcast(payload)
    asyncio.create_task(send_external_push(alert))

scanner = MarketScanner(on_anomaly_callback=broadcast_anomaly)

@app.on_event("startup")
async def startup_event():
    # 启动后台行情扫描任务
    asyncio.create_task(scanner.start_loop(interval_seconds=6))

@app.on_event("shutdown")
def shutdown_event():
    scanner.stop()

# 挂载静态资源目录
static_dir = os.path.join(os.path.dirname(__file__), "static")
if os.path.exists(static_dir):
    app.mount("/static", StaticFiles(directory=static_dir), name="static")

@app.get("/")
def get_index():
    index_file = os.path.join(static_dir, "index.html")
    if os.path.exists(index_file):
        headers = {
            "Cache-Control": "no-cache, no-store, must-revalidate, max-age=0",
            "Pragma": "no-cache",
            "Expires": "0"
        }
        return FileResponse(index_file, headers=headers)
    return {"message": "TrollStore Anomaly Server Running"}

# --- API 路由 ---

@app.get("/api/market/rankings")
def get_rankings(min_change: float = -999.0):
    """
    获取按当天涨幅从大到小排序的清洗后实时行情列表
    支持通过 min_change 过滤 (例如: 10, 20, 30, 50, 100)
    """
    all_items = scanner.latest_rankings
    if min_change > -900:
        filtered = [x for x in all_items if x["change_24h"] >= min_change]
    else:
        filtered = all_items

    return {
        "total": len(filtered),
        "total_monitored": len(all_items),
        "min_change_filter": min_change,
        "rankings": filtered
    }

@app.get("/api/screening")
def get_screening_settings():
    return {
        "settings": screening_config.settings,
        "monitored_count": scanner.monitored_count,
        "total_count": getattr(scanner, "total_pairs_count", 750)
    }

class ScreeningUpdateRequest(BaseModel):
    monitor_all: bool = True
    include_crypto: bool = True
    include_equity: bool = False
    include_premarket: bool = False
    include_commodity_fx: bool = False
    min_volume_usdt: float = 1000000.0
    pulse_window: str = "5m"
    blacklist: List[str] = []
    enable_push: bool = True
    cooldown_minutes: int = 5
    enable_sound: bool = True
    enable_vibrate: bool = True
    bark_key: str = ""
    webhook_url: str = ""

@app.post("/api/screening")
async def update_screening_settings(req: ScreeningUpdateRequest):
    screening_config.save(req.dict())
    alert_manager.cooldown_seconds = req.cooldown_minutes * 60
    # 立即对当前行情池重新应用指标筛选 (毫秒级即时生效)
    scanner.reapply_filter()
    return {
        "status": "ok",
        "message": "已更新监测范围，生效中",
        "monitored_count": scanner.monitored_count,
        "total_count": getattr(scanner, "total_pairs_count", 750)
    }

class BarkTestRequest(BaseModel):
    bark_key: str = ""

@app.post("/api/push/test_bark")
async def test_bark_push(req: BarkTestRequest = None):
    bark_key = req.bark_key if req and req.bark_key else screening_config.settings.get("bark_key", "")
    if not bark_key:
        return {"status": "error", "message": "尚未配置 Bark Key"}
    
    # 构造测试做空异动对象
    test_alert = {
        "symbol": "HOTUSDT",
        "score": 85,
        "price": 0.0004116,
        "rule_name": "脉冲急拉 / 均值回归信号",
        "message": "[HOTUSDT] 异动 (评分:85)：15分钟急拉 +6.8%，高位爆量见顶衰竭，负费率 -1.56%，现价: $0.0004116"
    }
    # 临时覆盖 key 测试
    old_key = screening_config.settings.get("bark_key")
    screening_config.settings["bark_key"] = bark_key
    try:
        await send_external_push(test_alert)
    finally:
        if old_key is not None:
            screening_config.settings["bark_key"] = old_key
    return {"status": "ok", "message": "测试亮屏推送已发出，请查看 iPhone 锁屏"}

@app.get("/api/status")
def get_status():
    return {
        "status": "online",
        "ws_clients": len(ws_manager.active_connections),
        "monitored_pairs": scanner.monitored_count,
        "total_pairs": getattr(scanner, "total_pairs_count", 756),
        "active_rule": "strategy.mean_reversion_fade_pump (急拉做空 / 价值回归引擎)",
        "server_time": time.strftime("%Y-%m-%d %H:%M:%S")
    }

@app.get("/api/rules/code")
def get_rule_code():
    rule_file_path = os.path.join(os.path.dirname(__file__), "anomaly_rules.py")
    code = ""
    modified_time = ""
    if os.path.exists(rule_file_path):
        mtime = os.path.getmtime(rule_file_path)
        modified_time = time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(mtime))
        with open(rule_file_path, "r", encoding="utf-8") as f:
            code = f.read()

    return {
        "filename": "anomaly_rules.py",
        "status": "Active",
        "last_loaded": modified_time,
        "code": code
    }

@app.get("/api/alerts")
def get_alerts(limit: int = 50):
    return {
        "total": len(alert_manager.alerts),
        "alerts": alert_manager.get_alerts(limit)
    }

@app.post("/api/alerts/mark_read")
def mark_read():
    alert_manager.mark_all_as_read()
    return {"status": "ok"}

@app.post("/api/alerts/clear")
def clear_alerts():
    alert_manager.clear_history()
    return {"status": "ok"}

class MockAlertRequest(BaseModel):
    symbol: str = "PEPEUSDT"
    priceChangePercent: float = 58.6
    lastPrice: float = 0.0000095
    quoteVolume: float = 18_500_000.0
    is_perp: bool = True

@app.post("/api/alerts/mock")
async def trigger_mock_alert(req: MockAlertRequest):
    """
    【重点测试接口】手动模拟触发异动做空预警并全网 WebSocket 广播
    """
    alert = {
        "rule_id": "strategy.mean_reversion_fade_pump",
        "rule_name": "脉冲急拉 / 均值回归信号",
        "symbol": req.symbol,
        "is_perp": req.is_perp,
        "price": req.lastPrice,
        "change_24h": req.priceChangePercent,
        "volume_24h": req.quoteVolume,
        "score": 75,
        "spike_pct": 6.8,
        "vol_ratio": 4.5,
        "funding_rate": -0.0156,
        "premium_pct": 0.42,
        "oi_change_pct": -2.5,
        "badges": ["15m急拉 +6.8%", "高位萎缩爆量", "负费率 -1.56%"],
        "severity": "WARNING",
        "message": f"[{req.symbol}] 异动 (评分:75)：15分钟急拉 +6.8%，高位迅速萎缩爆量，负费率 -1.56%，现价: ${req.lastPrice}"
    }

    record = alert_manager.record_alert(alert)
    await broadcast_anomaly(record)
    return {
        "status": "triggered",
        "record": record
    }

# --- WebSocket 终端连接端点 ---

@app.websocket("/ws/radar")
async def websocket_radar(websocket: WebSocket):
    await ws_manager.connect(websocket)
    try:
        # 发送初始欢迎与状态帧
        await websocket.send_json({
            "type": "INIT",
            "message": "Connected to TrollStore Anomaly Hub",
            "server_time": time.strftime("%H:%M:%S")
        })
        while True:
            try:
                data = await asyncio.wait_for(websocket.receive_text(), timeout=25.0)
                if data == "ping":
                    await websocket.send_text("pong")
            except asyncio.TimeoutError:
                # 定期下发保活心跳
                await websocket.send_json({"type": "HEARTBEAT"})
    except WebSocketDisconnect:
        ws_manager.disconnect(websocket)
    except Exception as e:
        ws_manager.disconnect(websocket)

if __name__ == "__main__":
    import uvicorn
    uvicorn.run("main:app", host="0.0.0.0", port=8080, reload=True)
