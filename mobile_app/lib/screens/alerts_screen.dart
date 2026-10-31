import 'package:flutter/material.dart';

class AlertsScreen extends StatefulWidget {
  final List<Map<String, dynamic>> alerts;
  final VoidCallback onMarkAllRead;
  final VoidCallback onClearAll;

  const AlertsScreen({
    super.key,
    required this.alerts,
    required this.onMarkAllRead,
    required this.onClearAll,
  });

  @override
  State<AlertsScreen> createState() => _AlertsScreenState();
}

class _AlertsScreenState extends State<AlertsScreen> {
  static const Color bgDark = Color(0xFF0F1115);
  static const Color cardDark = Color(0xFF161A1E);
  static const Color cardBorder = Color(0xFF23272E);
  static const Color textWhite = Color(0xFFFFFFFF);
  static const Color textMuted = Color(0xFF848E9C);
  static const Color upGreen = Color(0xFF0ECB81);
  static const Color downRed = Color(0xFFF6465D);
  static const Color perpPurple = Color(0xFFB57AFF);
  static const Color alertGold = Color(0xFFF0B90B);

  void _showDetailBottomSheet(BuildContext context, Map<String, dynamic> item) {
    showModalBottomSheet(
      context: context,
      backgroundColor: cardDark,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${item['symbol']} 预警详情',
                    style: const TextStyle(color: textWhite, fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: textMuted),
                    onPressed: () => Navigator.pop(context),
                  )
                ],
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: bgDark,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  item['message'] ?? '无详细描述',
                  style: const TextStyle(color: textWhite, fontSize: 14),
                ),
              ),
              const SizedBox(height: 16),
              // 跳转币安 Deep link
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: alertGold,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  icon: const Icon(Icons.open_in_new, size: 18),
                  label: const Text('跳转币安 App (Deep Link)', style: TextStyle(fontWeight: FontWeight.bold)),
                  onPressed: () {
                    Navigator.pop(context);
                  },
                ),
              ),
              const SizedBox(height: 10),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final unreadCount = widget.alerts.where((a) => a['is_read'] != true).length;

    return Scaffold(
      backgroundColor: bgDark,
      appBar: AppBar(
        backgroundColor: bgDark,
        elevation: 0,
        title: Row(
          children: [
            const Text(
              '预警中心 (Alerts)',
              style: TextStyle(color: textWhite, fontSize: 18, fontWeight: FontWeight.bold),
            ),
            if (unreadCount > 0) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: downRed, borderRadius: BorderRadius.circular(10)),
                child: Text('$unreadCount', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
              ),
            ]
          ],
        ),
        actions: [
          TextButton(
            onPressed: widget.onMarkAllRead,
            child: const Text('已读全部', style: TextStyle(color: alertGold, fontSize: 13)),
          ),
          IconButton(
            icon: const Icon(Icons.delete_sweep_outlined, color: textMuted, size: 20),
            onPressed: widget.onClearAll,
          ),
        ],
      ),
      body: widget.alerts.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  Icon(Icons.notifications_none_rounded, size: 48, color: cardBorder),
                  SizedBox(height: 12),
                  Text('暂无真实触发的预警记录', style: TextStyle(color: textMuted, fontSize: 13)),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: widget.alerts.length,
              itemBuilder: (context, index) {
                final item = widget.alerts[index];
                final isRead = item['is_read'] == true;
                final bool isPump = (item['change_24h'] ?? 0.0) >= 0;

                return Dismissible(
                  key: Key(item['id'] ?? index.toString()),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    color: downRed.withOpacity(0.8),
                    child: const Icon(Icons.delete, color: Colors.white),
                  ),
                  onDismissed: (direction) {
                    setState(() {
                      widget.alerts.removeAt(index);
                    });
                  },
                  child: GestureDetector(
                    onTap: () => _showDetailBottomSheet(context, item),
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      decoration: BoxDecoration(
                        color: isRead ? cardDark.withOpacity(0.5) : cardDark,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isRead ? Colors.transparent : cardBorder,
                          width: 0.8,
                        ),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          decoration: BoxDecoration(
                            border: Border(
                              left: BorderSide(
                                color: isRead
                                    ? Colors.transparent
                                    : (item['is_perp'] == true ? perpPurple : (isPump ? upGreen : downRed)),
                                width: 4,
                              ),
                            ),
                          ),
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    item['rule_id'] ?? 'strategy.daily_pump_50',
                                    style: TextStyle(
                                      color: isRead ? textMuted : alertGold,
                                      fontSize: 12,
                                      fontFamily: 'monospace',
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  Text(
                                    item['time_str'] ?? '刚刚',
                                    style: const TextStyle(color: textMuted, fontSize: 11),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                '${item['symbol']} | 现价: \$${item['price']} | 涨幅: +${item['change_24h']}%',
                                style: TextStyle(
                                  color: isRead ? textMuted : textWhite,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                item['message'] ?? '',
                                style: TextStyle(
                                  color: isRead ? textMuted.withOpacity(0.6) : const Color(0xFFD1D4DC),
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}
