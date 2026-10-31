"""
Alert Manager (预警管理与去重冷却器)
"""

import time
import json
import os
from typing import Dict, List, Any, Optional

ALERTS_FILE = os.path.join(os.path.dirname(__file__), "alerts_history.json")

class AlertManager:
    def __init__(self, cooldown_seconds: int = 300):
        self.cooldown_seconds = cooldown_seconds  # 默认 5 分钟冷却
        self.last_alert_times: Dict[str, float] = {}
        self.alerts: List[Dict[str, Any]] = []
        self._load_history()

    def _load_history(self):
        if os.path.exists(ALERTS_FILE):
            try:
                with open(ALERTS_FILE, "r", encoding="utf-8") as f:
                    self.alerts = json.load(f)
            except Exception:
                self.alerts = []

    def _save_history(self):
        try:
            with open(ALERTS_FILE, "w", encoding="utf-8") as f:
                json.dump(self.alerts[-200:], f, ensure_ascii=False, indent=2)
        except Exception as e:
            print(f"Failed to save alerts: {e}")

    def should_trigger(self, symbol: str) -> bool:
        """检查冷却时间，防止刷屏"""
        now = time.time()
        last_time = self.last_alert_times.get(symbol, 0)
        if now - last_time < self.cooldown_seconds:
            return False
        return True

    def record_alert(self, alert_data: Dict[str, Any]) -> Dict[str, Any]:
        """记录并返回标准预警事件"""
        now = time.time()
        symbol = alert_data.get("symbol", "UNKNOWN")
        self.last_alert_times[symbol] = now

        record = {
            "id": f"alt_{int(now * 1000)}",
            "timestamp": now,
            "time_str": time.strftime("%H:%M:%S", time.localtime(now)),
            "date_str": time.strftime("%Y-%m-%d", time.localtime(now)),
            "is_read": False,
            **alert_data
        }

        self.alerts.insert(0, record)
        self._save_history()
        return record

    def get_alerts(self, limit: int = 50) -> List[Dict[str, Any]]:
        return self.alerts[:limit]

    def mark_all_as_read(self):
        for a in self.alerts:
            a["is_read"] = True
        self._save_history()

    def clear_history(self):
        self.alerts = []
        self._save_history()

alert_manager = AlertManager()
