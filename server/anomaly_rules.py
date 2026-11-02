"""
Crypto Mean Reversion / Fade the Pump Anomaly Rules
价值回归 / 暴涨做空量化异动规则体系
File: anomaly_rules.py
"""

from typing import Optional, Dict, Any, List

# 核心策略阈值参数 (支持由配置动态调整)
THRESHOLD_PUMP_SURGE_PCT = 3.0       # 短周期急拉阈值 (例如 3~5分钟拉升 >= 3%)
THRESHOLD_VOLUME_SURGE_RATIO = 2.5   # 成交量短时放大倍数 (当前成交额为基线量的 2.5 倍以上)
THRESHOLD_EXTREME_NEGATIVE_FUNDING = -0.0025  # 极端负资金费率 (-0.25%)，轧空高危/见顶预兆
THRESHOLD_HIGH_PREMIUM_PCT = 1.0     # 合约相对现货指数超额溢价 (+1.0%)

def evaluate_mean_reversion_rules(metrics: Dict[str, Any]) -> Optional[Dict[str, Any]]:
    """
    均值回归做空规则评估引擎 (不包含 K 线形态，纯客观量化指标驱动):
    
    输入 metrics 包含:
      - symbol: 标的代码 (如 SUIUSDT)
      - price: 最新价格
      - change_24h: 24h 涨跌幅
      - volume_24h: 24h 成交金额 (USDT)
      - asset_type: 资产类型 (COIN / EQUITY / PREMARKET 等)
      - spike_pct: 短周期脉冲拉升幅度 (%) (如近 3~5 分钟涨幅)
      - vol_ratio: 瞬时成交量放大倍数 (如当前成交量 / 前期均量)
      - funding_rate: 当前资金费率 (如 -0.005 代表 -0.5%)
      - premium_pct: 合约相对指数溢价率 (%)
      - oi_change_pct: 持仓量变化率 (%) (负值代表空头爆仓潮或主力平仓撤退)
      - is_exhaustion: 是否出现缩量滞涨/量价背离 (买盘衰竭)
    """
    symbol = str(metrics.get("symbol", ""))
    price = float(metrics.get("price", 0.0))
    change_24h = float(metrics.get("change_24h", 0.0))
    volume_24h = float(metrics.get("volume_24h", 0.0))
    spike_pct = float(metrics.get("spike_pct", 0.0))
    vol_ratio = float(metrics.get("vol_ratio", 1.0))
    funding_rate = float(metrics.get("funding_rate", 0.0))
    premium_pct = float(metrics.get("premium_pct", 0.0))
    oi_change_pct = float(metrics.get("oi_change_pct", 0.0))
    is_exhaustion = bool(metrics.get("is_exhaustion", False))

    badges: List[str] = []
    reasons: List[str] = []
    score = 0  # 异动强度评分 (达到 60 分触发预警，80 分以上极速做空)

    # 1. 15分钟周期脉冲暴拉 (Spike Momentum)
    if spike_pct >= 6.0:
        score += 45
        badges.append(f"15m暴拉 +{spike_pct:.1f}%")
        reasons.append(f"15分钟极速脉冲拉升 +{spike_pct:.2f}%")
    elif spike_pct >= 3.0:
        score += 30
        badges.append(f"15m拉升 +{spike_pct:.1f}%")
        reasons.append(f"15分钟拉升 +{spike_pct:.2f}%")
    elif spike_pct >= 2.0 and change_24h >= 15.0:
        score += 20
        badges.append(f"24h高位续拉 +{spike_pct:.1f}%")
        reasons.append(f"日内强势高位继续上冲 +{spike_pct:.2f}%")

    if score == 0:
        # 没有拉升脉冲，不触发做空监控
        return None

    # 2. 瞬时放量异动 (Volume Surge)
    if vol_ratio >= 4.0:
        score += 25
        badges.append(f"爆量 {vol_ratio:.1f}x")
        reasons.append(f"成交量急剧放大至均量的 {vol_ratio:.1f} 倍")
    elif vol_ratio >= 2.0:
        score += 15
        badges.append(f"异常放量 {vol_ratio:.1f}x")
        reasons.append(f"成交量放大 {vol_ratio:.1f} 倍")

    # 3. 量能衰竭 / 缩量滞涨 (买盘接力断档信号)
    if is_exhaustion:
        score += 25
        badges.append("买盘动能衰竭")
        reasons.append("高位量能迅速萎缩，出现严重量价背离")

    # 4. 合约微观结构：极端负资金费率 (轧空极值)
    if funding_rate <= THRESHOLD_EXTREME_NEGATIVE_FUNDING:
        score += 25
        fr_pct = funding_rate * 100
        badges.append(f"极端负费率 {fr_pct:.3f}%")
        reasons.append(f"资金费率被打至极值 {fr_pct:.3f}% (逼空动能衰竭)")

    # 5. 合约微观结构：超高基差/溢价
    if premium_pct >= THRESHOLD_HIGH_PREMIUM_PCT:
        score += 15
        badges.append(f"异常高溢价 +{premium_pct:.2f}%")
        reasons.append(f"合约相对现货指数溢价达到 +{premium_pct:.2f}%")

    # 6. 持仓量 OI 骤降 (空头已被爆完 / 主力平仓止盈)
    if oi_change_pct <= -2.0:
        score += 20
        badges.append(f"OI暴跌 {oi_change_pct:.1f}%")
        reasons.append(f"持仓量迅速下降 {abs(oi_change_pct):.1f}% (多空对决进入收尾)")

    # 触发判断：总分达到 50 分即触发价值回归做空预警
    if score >= 50:
        severity = "CRITICAL" if score >= 75 else "WARNING"
        summary_msg = f"[{symbol}] 暴拉见顶异动 (评分:{score})！" + "，".join(reasons) + f"！现价: ${price}"
        
        return {
            "rule_id": "strategy.mean_reversion_fade_pump",
            "rule_name": "急速拉升做空 / 价值回归信号",
            "symbol": symbol,
            "is_perp": True,
            "price": price,
            "change_24h": change_24h,
            "volume_24h": volume_24h,
            "score": score,
            "spike_pct": spike_pct,
            "vol_ratio": vol_ratio,
            "funding_rate": funding_rate,
            "premium_pct": premium_pct,
            "oi_change_pct": oi_change_pct,
            "badges": badges,
            "severity": severity,
            "message": summary_msg
        }

    return None

def evaluate_all_rules(ticker: Dict[str, Any]) -> Optional[Dict[str, Any]]:
    """统一规则入口"""
    return evaluate_mean_reversion_rules(ticker)
