"""
Screening & Filter Configuration Manager (监控范围与过滤配置管理器 - 纯 U 本位合约引擎)
"""

import os
import json
from typing import Dict, Any, List

CONFIG_FILE = os.path.join(os.path.dirname(__file__), "screening_settings.json")

DEFAULT_SETTINGS: Dict[str, Any] = {
    "monitor_all": True,
    "include_crypto": True,           # 币圈原生代币 (BTC, ETH, SOL 等)
    "include_equity": False,          # 股票/公司代币 (TSLA, NVDA, AAPL 等)
    "include_premarket": False,       # 盘前代币 (OPENAI, ANTHROPIC 等)
    "include_commodity_fx": False,    # 大宗商品/外汇 (XAU, CL 等)
    "min_volume_usdt": 1_000_000.0,   # 默认 24h 最低成交量 100万 USDT
    "pulse_window": "5m",             # 脉冲检测周期: 5m (推荐), 15m, 3m
    "blacklist": [],
    "enable_push": True,
    "cooldown_minutes": 5,
    "enable_sound": True,
    "enable_vibrate": True,
    "bark_key": "",                   # iOS 专属锁屏亮屏推送 (Bark Key / URL)
    "webhook_url": ""                 # 自定义 Webhook 推送
}

class ScreeningConfigManager:
    def __init__(self):
        self.settings: Dict[str, Any] = DEFAULT_SETTINGS.copy()
        self.load()

    def load(self):
        if os.path.exists(CONFIG_FILE):
            try:
                with open(CONFIG_FILE, "r", encoding="utf-8") as f:
                    saved = json.load(f)
                    self.settings.update(saved)
            except Exception as e:
                print(f"Error loading screening config: {e}")

    def save(self, new_settings: Dict[str, Any]):
        self.settings.update(new_settings)
        try:
            with open(CONFIG_FILE, "w", encoding="utf-8") as f:
                json.dump(self.settings, f, ensure_ascii=False, indent=2)
        except Exception as e:
            print(f"Error saving screening config: {e}")

    def filter_tickers(self, all_tickers: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
        """
        根据用户配置对 U 本位合约标的进行过滤
        """
        cfg = self.settings
        include_crypto = bool(cfg.get("include_crypto", True))
        include_equity = bool(cfg.get("include_equity", False))
        include_premarket = bool(cfg.get("include_premarket", False))
        include_commodity_fx = bool(cfg.get("include_commodity_fx", False))
        
        min_vol = float(cfg.get("min_volume_usdt", 0.0))
        blacklist = {b.upper().strip() for b in cfg.get("blacklist", [])}

        filtered = []
        for t in all_tickers:
            sym = t.get("symbol", "").upper().strip()
            vol = float(t.get("volume_usdt", 0.0))
            asset_type = t.get("asset_type", "COIN")

            # 1. 黑名单排除
            if sym in blacklist:
                continue

            # 2. 标的类型过滤 (币圈原生 vs 股票公司代币 vs 盘前 vs 大宗商品外汇)
            if asset_type == "COIN" and not include_crypto:
                continue
            elif asset_type == "EQUITY" and not include_equity:
                continue
            elif asset_type == "PREMARKET" and not include_premarket:
                continue
            elif asset_type in ("COMMODITY", "FX") and not include_commodity_fx:
                continue

            # 3. 24h 最低成交量过滤 (过滤僵尸流动性)
            if vol < min_vol:
                continue

            filtered.append(t)

        return filtered

screening_config = ScreeningConfigManager()
