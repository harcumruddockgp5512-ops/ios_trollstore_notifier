"""
Market Feed & Scanner (现货 + 合约 极速双引擎 + 动态指标过滤)
"""

import os
import sys

try:
    if sys.stdout.encoding and sys.stdout.encoding.lower() != 'utf-8':
        sys.stdout.reconfigure(encoding='utf-8')
except Exception:
    pass

import asyncio
import httpx
from typing import Dict, List, Any, Callable
from anomaly_rules import evaluate_all_rules
from alert_manager import alert_manager
from screening_config import screening_config

BINANCE_SPOT_TICKER = "https://www.binance.com/api/v3/ticker/24hr"
BINANCE_FUTURES_TICKER = "https://www.binance.com/fapi/v1/ticker/24hr"

class MarketScanner:
    def __init__(self, on_anomaly_callback: Callable[[Dict[str, Any]], Any]):
        self.on_anomaly = on_anomaly_callback
        self.is_running = False
        self.raw_pool: List[Dict[str, Any]] = []      # 未过滤的全量有效池 (1080+对)
        self.latest_rankings: List[Dict[str, Any]] = [] # 过滤生效后的实时监控榜单
        self.monitored_count = 0
        self.total_pairs_count = 0
        self.proxy = os.environ.get("HTTP_PROXY") or os.environ.get("ALL_PROXY") or "http://127.0.0.1:10085"

    def reapply_filter(self) -> int:
        """根据当前配置立即重新应用筛选过滤"""
        if self.raw_pool:
            filtered = screening_config.filter_tickers(self.raw_pool)
            self.latest_rankings = filtered
            self.monitored_count = len(filtered)
            self.total_pairs_count = len(self.raw_pool)
        return self.monitored_count

    async def fetch_futures_tickers(self) -> List[Dict[str, Any]]:
        headers = {"User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64)"}
        for attempt in range(2):
            items = []
            try:
                async with httpx.AsyncClient(proxy=self.proxy, headers=headers, timeout=15.0) as client:
                    res = await client.get(BINANCE_FUTURES_TICKER)
                    if res.status_code == 200:
                        for d in res.json():
                            sym = d.get("symbol", "")
                            if sym.endswith("USDT"):
                                try:
                                    pct = float(d.get("priceChangePercent", 0.0))
                                    price = float(d.get("lastPrice", 0.0))
                                    qv = float(d.get("quoteVolume", 0.0))
                                    if qv <= 0:
                                        continue
                                    items.append({
                                        "symbol": sym,
                                        "price": price,
                                        "price_str": f"{price:.8f}".rstrip("0").rstrip(".") if price < 1 else f"{price:.4f}" if price < 10 else f"{price:.2f}",
                                        "change_24h": round(pct, 2),
                                        "volume_usdt": qv,
                                        "volume_str": f"${qv/1e6:.1f}M" if qv >= 1e6 else f"${qv/1e3:.0f}K",
                                        "high_24h": float(d.get("highPrice", 0.0)),
                                        "low_24h": float(d.get("lowPrice", 0.0)),
                                        "is_perp": True
                                    })
                                except Exception:
                                    continue
                        if items:
                            return items
            except Exception as e:
                if attempt == 1:
                    print(f"[Futures fetch note]: {e}")
                await asyncio.sleep(0.5)
        return []

    async def fetch_spot_tickers(self) -> List[Dict[str, Any]]:
        headers = {"User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64)"}
        for attempt in range(2):
            items = []
            try:
                async with httpx.AsyncClient(proxy=self.proxy, headers=headers, timeout=15.0) as client:
                    res = await client.get(BINANCE_SPOT_TICKER)
                    if res.status_code == 200:
                        for d in res.json():
                            sym = d.get("symbol", "")
                            if sym.endswith("USDT") and not any(sym.endswith(x) for x in ["UPUSDT", "DOWNUSDT", "BULLUSDT", "BEARUSDT"]):
                                base = sym[:-4]
                                if base in {'USDC', 'FDUSD', 'TUSD', 'BUSD', 'DAI', 'EUR', 'AEUR'}:
                                    continue
                                try:
                                    pct = float(d.get("priceChangePercent", 0.0))
                                    price = float(d.get("lastPrice", 0.0))
                                    qv = float(d.get("quoteVolume", 0.0))
                                    if qv < 10000:
                                        continue
                                    items.append({
                                        "symbol": sym,
                                        "price": price,
                                        "price_str": f"{price:.8f}".rstrip("0").rstrip(".") if price < 1 else f"{price:.4f}" if price < 10 else f"{price:.2f}",
                                        "change_24h": round(pct, 2),
                                        "volume_usdt": qv,
                                        "volume_str": f"${qv/1e6:.1f}M" if qv >= 1e6 else f"${qv/1e3:.0f}K",
                                        "high_24h": float(d.get("highPrice", 0.0)),
                                        "low_24h": float(d.get("lowPrice", 0.0)),
                                        "is_perp": False
                                    })
                                except Exception:
                                    continue
                        if items:
                            return items
            except Exception as e:
                if attempt == 1:
                    print(f"[Spot fetch note]: {e}")
                await asyncio.sleep(0.5)
        return []

    async def fetch_and_rank_tickers(self) -> List[Dict[str, Any]]:
        futures_res = await self.fetch_futures_tickers()
        spot_res = await self.fetch_spot_tickers()

        pool: Dict[str, Dict[str, Any]] = {}
        for item in futures_res:
            pool[item["symbol"]] = item

        for item in spot_res:
            sym = item["symbol"]
            if sym not in pool or item["volume_usdt"] > pool[sym]["volume_usdt"]:
                pool[sym] = item

        all_raw = list(pool.values())
        if all_raw:
            self.raw_pool = all_raw
            self.total_pairs_count = len(all_raw)
            # 应用用户设定的指标与范围过滤
            self.reapply_filter()
        
        # 针对当前实际监控中的币种，检查是否触及 50% 报警
        for t in self.latest_rankings:
            if t["change_24h"] >= 50.0:
                mock_ticker = {
                    "symbol": t["symbol"],
                    "priceChangePercent": t["change_24h"],
                    "lastPrice": t["price"],
                    "quoteVolume": t["volume_usdt"],
                    "is_perp": t["is_perp"]
                }
                alert = evaluate_all_rules(mock_ticker)
                if alert and alert_manager.should_trigger(t["symbol"]):
                    record = alert_manager.record_alert(alert)
                    print(f"[Trigger] {t['symbol']} 达到暴涨 +{t['change_24h']}%: {record['message']}")
                    if self.on_anomaly:
                        asyncio.create_task(self.on_anomaly(record))

        return self.latest_rankings

    async def start_loop(self, interval_seconds: int = 10):
        self.is_running = True
        print(f"[MarketScanner] 现货+合约极速双引擎启动 (间隔: {interval_seconds}s)")
        while self.is_running:
            try:
                await self.fetch_and_rank_tickers()
            except Exception as e:
                print(f"Ranking loop error: {e}")
            await asyncio.sleep(interval_seconds)

    def stop(self):
        self.is_running = False
