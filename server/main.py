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

async def broadcast_anomaly(alert: Dict[str, Any]):
    """广播新预警事件"""
    payload = {
        "type": "ANOMALY_ALERT",
        "data": alert
    }
    await ws_manager.broadcast(payload)

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
        return FileResponse(index_file)
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
    market_types: List[str] = ["spot", "usdt_perp"]
    min_volume_usdt: float = 1000000.0
    market_cap_rank: str = "unlimited"
    blacklist: List[str] = []
    enable_push: bool = True
    cooldown_minutes: int = 5
    enable_sound: bool = True
    enable_vibrate: bool = True

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

@app.get("/api/status")
def get_status():
    return {
        "status": "online",
        "ws_clients": len(ws_manager.active_connections),
        "monitored_pairs": scanner.monitored_count,
        "total_pairs": getattr(scanner, "total_raw_pairs", 770),
        "active_rule": "strategy.daily_pump_50 (当日涨幅超过50%)",
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
    【重点测试接口】手动模拟触发当日涨幅 > 50% 预警
    """
    ticker = {
        "symbol": req.symbol,
        "priceChangePercent": req.priceChangePercent,
        "lastPrice": req.lastPrice,
        "quoteVolume": req.quoteVolume,
        "is_perp": req.is_perp
    }
    
    alert = anomaly_rules.rule_daily_pump_50(ticker)
    if not alert:
        return {"status": "rejected", "reason": "Rule conditions not met (e.g. change < 50%)"}

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
