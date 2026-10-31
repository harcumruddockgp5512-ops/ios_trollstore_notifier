"""
Screening & Filter Configuration Manager (监控范围与过滤配置管理器)
"""

import os
import json
from typing import Dict, Any, List

CONFIG_FILE = os.path.join(os.path.dirname(__file__), "screening_settings.json")

DEFAULT_SETTINGS: Dict[str, Any] = {
    "monitor_all": True,
    "market_types": ["spot", "usdt_perp"],  # spot, usdt_perp, coin_perp
    "min_volume_usdt": 1_000_000.0,         # 默认 24h 最低成交量 100万 USDT
    "market_cap_rank": "unlimited",          # unlimited, vol_top50, vol_top100, vol_top200, gainers_top50, gainers_top100, losers_top50, losers_top100
    "blacklist": [],
    "enable_push": True,
    "cooldown_minutes": 5,
    "enable_sound": True,
    "enable_vibrate": True
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
        根据用户配置的核心 5 大维度对全市场币种进行真正的筛选过滤
        """
        cfg = self.settings
        types = set(cfg.get("market_types", ["spot", "usdt_perp"]))
        min_vol = float(cfg.get("min_volume_usdt", 0.0))
        blacklist = {b.upper().strip() for b in cfg.get("blacklist", [])}
        rank_limit = cfg.get("market_cap_rank", "unlimited")

        filtered = []
        for t in all_tickers:
            sym = t.get("symbol", "").upper().strip()
            is_perp = bool(t.get("is_perp", False))
            vol = float(t.get("volume_usdt", 0.0))

            # 1. 黑名单排除 (无论是否开启全市场，黑名单必须排除)
            if sym in blacklist:
                continue

            # 2. 市场类型过滤 (现货 vs U本位合约 vs 币本位)
            if is_perp and "usdt_perp" not in types:
                continue
            if not is_perp and "spot" not in types:
                continue

            # 3. 24h 最低成交量过滤 (过滤空气垃圾币)
            if vol < min_vol:
                continue

            filtered.append(t)

        # 4. 榜单与排名过滤 (支持成交量、涨幅榜前N名、跌幅榜前N名)
        is_losers_rank = False

        if rank_limit in ("top50", "vol_top50"):
            filtered = sorted(filtered, key=lambda x: x.get("volume_usdt", 0), reverse=True)[:50]
        elif rank_limit in ("top100", "vol_top100"):
            filtered = sorted(filtered, key=lambda x: x.get("volume_usdt", 0), reverse=True)[:100]
        elif rank_limit in ("top200", "vol_top200"):
            filtered = sorted(filtered, key=lambda x: x.get("volume_usdt", 0), reverse=True)[:200]
        elif rank_limit == "gainers_top50":
            filtered = sorted(filtered, key=lambda x: x.get("change_24h", 0.0), reverse=True)[:50]
        elif rank_limit == "gainers_top100":
            filtered = sorted(filtered, key=lambda x: x.get("change_24h", 0.0), reverse=True)[:100]
        elif rank_limit == "gainers_top200":
            filtered = sorted(filtered, key=lambda x: x.get("change_24h", 0.0), reverse=True)[:200]
        elif rank_limit == "losers_top50":
            filtered = sorted(filtered, key=lambda x: x.get("change_24h", 0.0))[:50]
            is_losers_rank = True
        elif rank_limit == "losers_top100":
            filtered = sorted(filtered, key=lambda x: x.get("change_24h", 0.0))[:100]
            is_losers_rank = True
        elif rank_limit == "losers_top200":
            filtered = sorted(filtered, key=lambda x: x.get("change_24h", 0.0))[:200]
            is_losers_rank = True

        # 最终排序: 如果是跌幅榜，按跌幅由大到小展示(即从最大跌幅开始); 否则默认按涨幅从大到小排序
        if is_losers_rank:
            filtered.sort(key=lambda x: x.get("change_24h", 0.0))
        else:
            filtered.sort(key=lambda x: x.get("change_24h", 0.0), reverse=True)
        return filtered

screening_config = ScreeningConfigManager()
