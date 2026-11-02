"""
Market Feed & Scanner (纯 U 本位合约价值回归 / 急拉做空全量实时引擎 - 双通道网络容灾版)
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
import httpx
from collections import deque
from typing import Dict, List, Any, Callable, Tuple
from anomaly_rules import evaluate_all_rules
from alert_manager import alert_manager
from screening_config import screening_config

BINANCE_FUTURES_TICKER = "https://www.binance.com/fapi/v1/ticker/24hr"
BINANCE_FUTURES_EXCHANGE_INFO = "https://www.binance.com/fapi/v1/exchangeInfo"
BINANCE_FUTURES_PREMIUM = "https://www.binance.com/fapi/v1/premiumIndex"
BINANCE_FUTURES_OI = "https://www.binance.com/fapi/v1/openInterest"

class MarketScanner:
    def __init__(self, on_anomaly_callback: Callable[[Dict[str, Any]], Any]):
        self.on_anomaly = on_anomaly_callback
        self.is_running = False
        self.raw_pool: List[Dict[str, Any]] = []          # 未过滤的全量 U 本位合约池 (750+对)
        self.latest_rankings: List[Dict[str, Any]] = []     # 过滤生效后的实时监控榜单
        self.monitored_count = 0
        self.total_pairs_count = 0
        
        # 资产类型映射表 (COIN, EQUITY, PREMARKET, COMMODITY)
        self.symbol_type_map: Dict[str, str] = {}
        
        # 资金费率与合约溢价缓存 {symbol: (funding_rate, premium_pct)}
        self.premium_cache: Dict[str, Tuple[float, float]] = {}
        
        # 历史价格时间序列缓存: symbol -> deque of (timestamp, price, volume_usdt)
        self.price_history: Dict[str, deque] = {}
        
        # 瞬时放量前的基线成交量跟踪
        self.last_volume_usdt: Dict[str, Tuple[float, float]] = {}
        self.volume_flow_history: Dict[str, deque] = {}
        
        # 持仓量 OI 缓存 {symbol: (timestamp, oi_val)}
        self.oi_cache: Dict[str, Tuple[float, float]] = {}

    async def _safe_get(self, url: str, timeout: float = 6.0) -> Any:
        """双通道智能容灾请求：先直连，直连遇阻立刻切代理；杜绝 All connection attempts failed"""
        headers = {"User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64)"}
        proxies_to_try = [None, "http://127.0.0.1:10085"]

        for proxy in proxies_to_try:
            try:
                async with httpx.AsyncClient(proxy=proxy, headers=headers, timeout=timeout) as client:
                    res = await client.get(url)
                    if res.status_code == 200:
                        return res.json()
            except Exception:
                continue
        return None

    def reapply_filter(self) -> int:
        """根据当前配置立即重新应用筛选过滤"""
        if self.raw_pool:
            filtered = screening_config.filter_tickers(self.raw_pool)
            self.latest_rankings = filtered
            self.monitored_count = len(filtered)
            self.total_pairs_count = len(self.raw_pool)
        return self.monitored_count

    async def update_exchange_info(self):
        """拉取币安 U 本位合约资产类型信息"""
        data = await self._safe_get(BINANCE_FUTURES_EXCHANGE_INFO, timeout=10.0)
        if data and isinstance(data, dict):
            symbols = data.get("symbols", [])
            type_map = {}
            for s in symbols:
                sym = s.get("symbol", "")
                raw_type = s.get("underlyingType", "COIN")
                if raw_type in ("EQUITY", "HK_EQUITY", "KR_EQUITY", "CN_EQUITY"):
                    asset_type = "EQUITY"
                elif raw_type == "PREMARKET":
                    asset_type = "PREMARKET"
                elif raw_type in ("COMMODITY", "FX"):
                    asset_type = "COMMODITY"
                else:
                    asset_type = "COIN"
                type_map[sym] = asset_type
            self.symbol_type_map = type_map
            print(f"[MarketScanner] 合约底层资产映射更新成功: 共有 {len(type_map)} 个定义")

    async def update_premium_and_funding(self):
        """一次性批量拉取全市场的资金费率与溢价"""
        data = await self._safe_get(BINANCE_FUTURES_PREMIUM, timeout=8.0)
        if data and isinstance(data, list):
            new_cache = {}
            for item in data:
                sym = item.get("symbol", "")
                if sym.endswith("USDT") and "_" not in sym:
                    try:
                        fr = float(item.get("lastFundingRate", 0.0))
                        mark = float(item.get("markPrice", 0.0))
                        idx = float(item.get("indexPrice", 0.0))
                        premium_pct = ((mark - idx) / idx * 100) if idx > 0 else 0.0
                        new_cache[sym] = (fr, round(premium_pct, 3))
                    except Exception:
                        continue
            if new_cache:
                self.premium_cache = new_cache

    async def fetch_oi_for_symbol(self, symbol: str) -> float:
        """针对正在急拉的可疑标的，快速请求其实时持仓量 OI"""
        data = await self._safe_get(f"{BINANCE_FUTURES_OI}?symbol={symbol}", timeout=4.0)
        if data and isinstance(data, dict):
            try:
                oi = float(data.get("openInterest", 0.0))
                now = time.time()
                old_oi_info = self.oi_cache.get(symbol)
                self.oi_cache[symbol] = (now, oi)
                if old_oi_info and old_oi_info[1] > 0:
                    pct_change = (oi - old_oi_info[1]) / old_oi_info[1] * 100
                    return round(pct_change, 2)
            except Exception:
                pass
        return 0.0

    async def fetch_futures_tickers(self) -> List[Dict[str, Any]]:
        """拉取全量 U 本位永续合约 24h Ticker，并注入多周期脉冲指标"""
        now = time.time()
        data = await self._safe_get(BINANCE_FUTURES_TICKER, timeout=8.0)
        if not data or not isinstance(data, list):
            return []

        items = []
        for d in data:
            sym = d.get("symbol", "")
            if sym.endswith("USDT") and "_" not in sym:
                try:
                    price = float(d.get("lastPrice", 0.0))
                    qv = float(d.get("quoteVolume", 0.0))
                    pct = float(d.get("priceChangePercent", 0.0))
                    if qv <= 0 or price <= 0:
                        continue

                    asset_type = self.symbol_type_map.get(sym, "COIN")
                    funding_rate, premium_pct = self.premium_cache.get(sym, (0.0, 0.0))

                    # 记录历史价格与增量成交量 (保留 3200 采样点，覆盖 4 小时历史以计算 5m/15m/30m/1h/4h 脉冲)
                    if sym not in self.price_history:
                        self.price_history[sym] = deque(maxlen=3200)
                        self.volume_flow_history[sym] = deque(maxlen=60)
                    
                    q = self.price_history[sym]
                    q.append((now, price))

                    # 计算短时间成交量流速
                    vol_ratio = 1.0
                    last_vol_info = self.last_volume_usdt.get(sym)
                    if last_vol_info:
                        time_diff = now - last_vol_info[0]
                        qv_diff = max(0.0, qv - last_vol_info[1])
                        if time_diff > 0:
                            flow_rate = qv_diff / time_diff
                            v_history = self.volume_flow_history[sym]
                            v_history.append((now, flow_rate))
                            if len(v_history) >= 4:
                                avg_flow = sum(x[1] for x in v_history) / len(v_history)
                                if avg_flow > 0:
                                    vol_ratio = round(flow_rate / avg_flow, 2)
                    
                    self.last_volume_usdt[sym] = (now, qv)

                    # 计算 5m / 15m / 30m / 1h / 4h 多级周期价格脉冲
                    def get_base_price(target_t: float):
                        bp = None
                        for t_item, p_item in q:
                            if t_item <= target_t:
                                bp = p_item
                            else:
                                break
                        if bp is None and len(q) > 0:
                            bp = q[0][1]
                        return bp

                    bp_5m = get_base_price(now - 300)
                    bp_15m = get_base_price(now - 900)
                    bp_30m = get_base_price(now - 1800)
                    bp_1h = get_base_price(now - 3600)
                    bp_4h = get_base_price(now - 14400)

                    spike_5m = round((price - bp_5m) / bp_5m * 100, 2) if (bp_5m and bp_5m > 0) else 0.0
                    spike_15m = round((price - bp_15m) / bp_15m * 100, 2) if (bp_15m and bp_15m > 0) else 0.0
                    spike_30m = round((price - bp_30m) / bp_30m * 100, 2) if (bp_30m and bp_30m > 0) else 0.0
                    spike_1h = round((price - bp_1h) / bp_1h * 100, 2) if (bp_1h and bp_1h > 0) else 0.0
                    spike_4h = round((price - bp_4h) / bp_4h * 100, 2) if (bp_4h and bp_4h > 0) else 0.0

                    items.append({
                        "symbol": sym,
                        "price": price,
                        "price_str": f"{price:.8f}".rstrip("0").rstrip(".") if price < 1 else f"{price:.4f}" if price < 10 else f"{price:.2f}",
                        "change_24h": round(pct, 2),
                        "volume_usdt": qv,
                        "volume_str": f"${qv/1e6:.1f}M" if qv >= 1e6 else f"${qv/1e3:.0f}K",
                        "high_24h": float(d.get("highPrice", 0.0)),
                        "low_24h": float(d.get("lowPrice", 0.0)),
                        "is_perp": True,
                        "asset_type": asset_type,
                        "spike_pct": spike_15m,
                        "spike_5m": spike_5m,
                        "spike_15m": spike_15m,
                        "spike_30m": spike_30m,
                        "spike_1h": spike_1h,
                        "spike_4h": spike_4h,
                        "vol_ratio": vol_ratio,
                        "funding_rate": funding_rate,
                        "premium_pct": premium_pct
                    })
                except Exception:
                    continue
        return items

    async def fetch_and_rank_tickers(self) -> List[Dict[str, Any]]:
        futures_res = await self.fetch_futures_tickers()
        if futures_res:
            self.raw_pool = futures_res
            self.total_pairs_count = len(futures_res)
            self.reapply_filter()

        # 检查是否触发“价值回归 / 暴涨见顶做空规则”
        for t in self.latest_rankings:
            spike = t.get("spike_pct", 0.0)
            if spike >= 2.0 or t.get("change_24h", 0.0) >= 20.0:
                sym = t["symbol"]
                oi_change = 0.0
                if spike >= 3.0:
                    oi_change = await self.fetch_oi_for_symbol(sym)

                is_exhaustion = (spike >= 4.0 and t.get("vol_ratio", 1.0) < 0.6)

                metrics = {
                    "symbol": sym,
                    "price": t["price"],
                    "change_24h": t["change_24h"],
                    "volume_24h": t["volume_usdt"],
                    "asset_type": t["asset_type"],
                    "spike_pct": spike,
                    "spike_3m": t.get("spike_3m", 0.0),
                    "spike_5m": t.get("spike_5m", 0.0),
                    "spike_15m": t.get("spike_15m", 0.0),
                    "pulse_window": t.get("pulse_window", "5m"),
                    "vol_ratio": t.get("vol_ratio", 1.0),
                    "funding_rate": t.get("funding_rate", 0.0),
                    "premium_pct": t.get("premium_pct", 0.0),
                    "oi_change_pct": oi_change,
                    "is_exhaustion": is_exhaustion
                }

                alert = evaluate_all_rules(metrics)
                if alert and alert_manager.should_trigger(sym):
                    record = alert_manager.record_alert(alert)
                    print(f"[做空信号触发] {sym} 评分:{alert['score']}: {record['message']}")
                    if self.on_anomaly:
                        asyncio.create_task(self.on_anomaly(record))

        return self.latest_rankings

    async def start_loop(self, interval_seconds: int = 5):
        self.is_running = True
        print(f"[MarketScanner] 纯 U 本位合约【价值回归 / 急拉做空】引擎启动 (间隔: {interval_seconds}s)")
        
        await self.update_exchange_info()
        await self.update_premium_and_funding()

        counter = 0
        while self.is_running:
            try:
                await self.fetch_and_rank_tickers()
                counter += 1
                if counter % 2 == 0:
                    asyncio.create_task(self.update_premium_and_funding())
                if counter >= 720:
                    counter = 0
                    asyncio.create_task(self.update_exchange_info())
            except Exception as e:
                print(f"Loop error: {e}")
            await asyncio.sleep(interval_seconds)

    def stop(self):
        self.is_running = False
