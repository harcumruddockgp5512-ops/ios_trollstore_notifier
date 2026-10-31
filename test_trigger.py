"""
Test Script: 验证当日涨幅超过 50% 规则
"""

import sys
import os

if sys.stdout.encoding.lower() != 'utf-8':
    try:
        sys.stdout.reconfigure(encoding='utf-8')
    except Exception:
        pass

# 将 server 目录加入路径
sys.path.append(os.path.join(os.path.dirname(__file__), "server"))

from anomaly_rules import rule_daily_pump_50

def run_tests():
    print("========================================")
    print("  开始验证规则: 当日涨幅超过 50%")
    print("========================================")

    # 1. 测试用例：涨幅 58.5% (应该触发)
    ticker_pump = {
        "symbol": "PEPEUSDT",
        "priceChangePercent": "58.5",
        "lastPrice": "0.0000095",
        "quoteVolume": "12000000.0",
        "is_perp": True
    }
    res_pump = rule_daily_pump_50(ticker_pump)
    print("\n[测试 1] 涨幅 +58.5% 标的测试:")
    if res_pump:
        print("  -> 成功触发预警!")
        print(f"  -> 规则 ID: {res_pump['rule_id']}")
        print(f"  -> 警报内容: {res_pump['message']}")
        print(f"  -> 标签徽章: {res_pump['badges']}")
    else:
        print("  -> FAIL: 未能触发!")
        sys.exit(1)

    # 2. 测试用例：涨幅 22.0% (不应该触发)
    ticker_normal = {
        "symbol": "BTCUSDT",
        "priceChangePercent": "22.0",
        "lastPrice": "68500.0",
        "quoteVolume": "95000000.0",
        "is_perp": True
    }
    res_normal = rule_daily_pump_50(ticker_normal)
    print("\n[测试 2] 涨幅 +22.0% 标的测试 (未达50%阈值):")
    if res_normal is None:
        print("  -> 正常忽略 (未达阈值)")
    else:
        print("  -> FAIL: 错误触发!")
        sys.exit(1)

    # 3. 测试用例：涨幅 60.0% 但成交量仅 100 USDT (垃圾假币/无流动性，应过滤)
    ticker_low_vol = {
        "symbol": "SHITCOINUSDT",
        "priceChangePercent": "60.0",
        "lastPrice": "0.0001",
        "quoteVolume": "100.0",
        "is_perp": False
    }
    res_low_vol = rule_daily_pump_50(ticker_low_vol)
    print("\n[测试 3] 涨幅 +60.0% 但成交量仅 $100 (低流动性过滤):")
    if res_low_vol is None:
        print("  -> 正常过滤 (成交量低于 50万 USDT 阈值)")
    else:
        print("  -> FAIL: 错误触发!")
        sys.exit(1)

    print("\n========================================")
    print("  ALL TESTS PASSED: 当日涨幅>50% 规则验证通过!")
    print("========================================")

if __name__ == "__main__":
    run_tests()
