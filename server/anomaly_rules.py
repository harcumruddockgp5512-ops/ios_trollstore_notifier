"""
Crypto Anomaly Detection Rules (量化异动检测规则)
File: anomaly_rules.py
Status: Active (已加载运行中)
"""

from typing import Optional, Dict, Any

THRESHOLD_DAILY_PUMP = 50.0  # 当日涨幅阈值 (+50%)
MIN_QUOTE_VOLUME_USDT = 100_000.0  # 最低24h成交量过滤（10万 USDT，过滤纯死币）

def rule_daily_pump_50(ticker: Dict[str, Any]) -> Optional[Dict[str, Any]]:
    """
    【首选测试规则】当日涨幅超过 50% 异动警报
    
    参数 ticker 包含:
      - symbol: 交易对 (例如: PEPEUSDT)
      - lastPrice: 最新成交价
      - priceChangePercent: 24h 涨跌幅百分比
      - quoteVolume: 24h 成交金额 (USDT)
      - is_perp: 是否为合约
    """
    try:
        symbol = str(ticker.get("symbol", ""))
        price_change_pct = float(ticker.get("priceChangePercent", 0.0))
        last_price = float(ticker.get("lastPrice", 0.0))
        quote_volume = float(ticker.get("quoteVolume", 0.0))
        is_perp = bool(ticker.get("is_perp", False))

        # 成交量过低过滤
        if quote_volume < MIN_QUOTE_VOLUME_USDT:
            return None

        # 核心判断：当日涨幅 >= 50%
        if price_change_pct >= THRESHOLD_DAILY_PUMP:
            return {
                "rule_id": "strategy.daily_pump_50",
                "rule_name": "当日暴拉突破 +50%",
                "symbol": symbol,
                "is_perp": is_perp,
                "price": last_price,
                "change_24h": price_change_pct,
                "volume_24h": quote_volume,
                "badges": [
                    f"🚀 当日暴涨 +{price_change_pct:.1f}%",
                    f"📊 24h成交量 ${(quote_volume / 1_000_000):.1f}M"
                ],
                "severity": "CRITICAL",
                "message": f"[{symbol}] 当日暴涨达到 +{price_change_pct:.2f}%！现价: ${last_price}，24h 成交额: ${(quote_volume / 1_000_000):.2f}M USDT"
            }
    except Exception as e:
        print(f"Error evaluating rule_daily_pump_50: {e}")
        return None

    return None


def evaluate_all_rules(ticker: Dict[str, Any]) -> Optional[Dict[str, Any]]:
    """
    规则执行流水线
    """
    # 1. 优先执行当日 50% 暴涨检测
    alert = rule_daily_pump_50(ticker)
    if alert:
        return alert

    return None
