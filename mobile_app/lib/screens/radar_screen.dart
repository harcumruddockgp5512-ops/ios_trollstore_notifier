import 'package:flutter/material.dart';

class MarketTickerItem {
  final String symbol;
  final double price;
  final String priceStr;
  final double change24h;
  final double volumeUsdt;
  final String volumeStr;
  final double high24h;
  final double low24h;

  MarketTickerItem({
    required this.symbol,
    required this.price,
    required this.priceStr,
    required this.change24h,
    required this.volumeUsdt,
    required this.volumeStr,
    required this.high24h,
    required this.low24h,
  });

  factory MarketTickerItem.fromJson(Map<String, dynamic> json) {
    return MarketTickerItem(
      symbol: json['symbol'] ?? '',
      price: (json['price'] ?? 0.0).toDouble(),
      priceStr: json['price_str'] ?? '${json['price']}',
      change24h: (json['change_24h'] ?? 0.0).toDouble(),
      volumeUsdt: (json['volume_usdt'] ?? 0.0).toDouble(),
      volumeStr: json['volume_str'] ?? '',
      high24h: (json['high_24h'] ?? 0.0).toDouble(),
      low24h: (json['low_24h'] ?? 0.0).toDouble(),
    );
  }
}

class RadarScreen extends StatefulWidget {
  final List<MarketTickerItem> tickers;
  final bool isConnected;
  final Function(double threshold) onFilterChanged;

  const RadarScreen({
    super.key,
    required this.tickers,
    required this.isConnected,
    required this.onFilterChanged,
  });

  @override
  State<RadarScreen> createState() => _RadarScreenState();
}

class _RadarScreenState extends State<RadarScreen>
    with SingleTickerProviderStateMixin {
  static const Color bgDark = Color(0xFF0F1115);
  static const Color cardDark = Color(0xFF161A1E);
  static const Color cardBorder = Color(0xFF23272E);
  static const Color textWhite = Color(0xFFFFFFFF);
  static const Color textMuted = Color(0xFF848E9C);
  static const Color upGreen = Color(0xFF0ECB81);
  static const Color downRed = Color(0xFFF6465D);
  static const Color alertGold = Color(0xFFF0B90B);

  double selectedThreshold = -999.0;
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = selectedThreshold > -900
        ? widget.tickers.where((t) => t.change24h >= selectedThreshold).toList()
        : widget.tickers;

    return Scaffold(
      backgroundColor: bgDark,
      body: SafeArea(
        child: Column(
          children: [
            // 1. 顶部 Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: cardBorder, width: 0.6)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Text(
                        '实时行情雷达 (Rankings)',
                        style: TextStyle(color: textWhite, fontSize: 17, fontWeight: FontWeight.bold),
                      ),
                      SizedBox(height: 2),
                      Text(
                        '按当天 24h 涨跌幅实时排序',
                        style: TextStyle(color: textMuted, fontSize: 11),
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: cardDark,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: cardBorder),
                    ),
                    child: Row(
                      children: [
                        AnimatedBuilder(
                          animation: _pulseController,
                          builder: (context, child) {
                            return Container(
                              width: 7,
                              height: 7,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: widget.isConnected
                                    ? upGreen.withOpacity(0.4 + (_pulseController.value * 0.6))
                                    : downRed,
                              ),
                            );
                          },
                        ),
                        const SizedBox(width: 6),
                        Text(
                          widget.isConnected ? 'Connected' : 'Offline',
                          style: const TextStyle(color: textMuted, fontSize: 11, fontFamily: 'monospace'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // 2. 涨幅天轮筛选 Chips (涨幅 > 10%, 20%, 30%, 50%, 100%)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Row(
                  children: [
                    _buildChip('全部币种', selectedThreshold == -999.0, () {
                      setState(() => selectedThreshold = -999.0);
                      widget.onFilterChanged(-999.0);
                    }),
                    _buildChip('🔥 涨幅 > 10%', selectedThreshold == 10.0, () {
                      setState(() => selectedThreshold = 10.0);
                      widget.onFilterChanged(10.0);
                    }),
                    _buildChip('🚀 涨幅 > 20%', selectedThreshold == 20.0, () {
                      setState(() => selectedThreshold = 20.0);
                      widget.onFilterChanged(20.0);
                    }),
                    _buildChip('⚡ 涨幅 > 30%', selectedThreshold == 30.0, () {
                      setState(() => selectedThreshold = 30.0);
                      widget.onFilterChanged(30.0);
                    }),
                    _buildChip('💥 涨幅 > 50%', selectedThreshold == 50.0, () {
                      setState(() => selectedThreshold = 50.0);
                      widget.onFilterChanged(50.0);
                    }),
                    _buildChip('🌟 涨幅 > 100%', selectedThreshold == 100.0, () {
                      setState(() => selectedThreshold = 100.0);
                      widget.onFilterChanged(100.0);
                    }),
                  ],
                ),
              ),
            ),

            // 3. 排序行情列表
            Expanded(
              child: filtered.isEmpty
                  ? Center(
                      child: Text(
                        '当前全市场暂无涨幅超过 ${selectedThreshold.toInt()}% 的币种',
                        style: const TextStyle(color: textMuted, fontSize: 13),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      itemCount: filtered.length,
                      itemBuilder: (context, index) {
                        return _buildTickerRow(filtered[index], index);
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChip(String label, bool isSelected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? alertGold.withOpacity(0.18) : cardDark,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? alertGold : cardBorder,
            width: 0.8,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? alertGold : textMuted,
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _buildTickerRow(MarketTickerItem item, int index) {
    final bool isUp = item.change24h >= 0;
    final bool isPump50 = item.change24h >= 50.0;

    Color rankColor = textMuted;
    if (index == 0) rankColor = const Color(0xFFFFD700);
    else if (index == 1) rankColor = const Color(0xFFC0C0C0);
    else if (index == 2) rankColor = const Color(0xFFCD7F32);

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: cardDark,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isPump50 ? alertGold.withOpacity(0.6) : cardBorder,
          width: 0.8,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              SizedBox(
                width: 26,
                child: Text(
                  '#${index + 1}',
                  style: TextStyle(color: rankColor, fontSize: 12, fontWeight: FontWeight.bold, fontFamily: 'monospace'),
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(item.symbol, style: const TextStyle(color: textWhite, fontSize: 14, fontWeight: FontWeight.bold)),
                      const SizedBox(width: 5),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                        decoration: BoxDecoration(color: const Color(0xFF1E2833), borderRadius: BorderRadius.circular(3)),
                        child: const Text('SPOT', style: TextStyle(color: Color(0xFF5CA4FF), fontSize: 8, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text('24h量: ${item.volumeStr} | 高: \$${item.high24h}', style: const TextStyle(color: textMuted, fontSize: 11)),
                ],
              ),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('\$${item.priceStr}', style: const TextStyle(color: textWhite, fontSize: 14, fontWeight: FontWeight.w600, fontFamily: 'monospace')),
              const SizedBox(height: 3),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: (isUp ? upGreen : downRed).withOpacity(0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '${isUp ? '+' : ''}${item.change24h.toStringAsFixed(2)}%',
                  style: TextStyle(
                    color: isUp ? upGreen : downRed,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
