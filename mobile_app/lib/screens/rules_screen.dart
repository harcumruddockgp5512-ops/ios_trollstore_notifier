import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class RulesScreen extends StatefulWidget {
  final String ruleCode;
  final String filename;
  final String lastLoaded;
  final VoidCallback onReload;

  const RulesScreen({
    super.key,
    required this.ruleCode,
    required this.filename,
    required this.lastLoaded,
    required this.onReload,
  });

  @override
  State<RulesScreen> createState() => _RulesScreenState();
}

class _RulesScreenState extends State<RulesScreen> {
  static const Color ideBg = Color(0xFF1E1E1E);
  static const Color headerBg = Color(0xFF161A1E);
  static const Color cardBorder = Color(0xFF2D3139);
  static const Color textWhite = Color(0xFFD4D4D4);
  static const Color lineNumColor = Color(0xFF5A5D63);
  static const Color alertGold = Color(0xFFF0B90B);
  static const Color activeGreen = Color(0xFF0ECB81);

  @override
  Widget build(BuildContext context) {
    final lines = widget.ruleCode.split('\n');

    return Scaffold(
      backgroundColor: ideBg,
      body: SafeArea(
        child: Column(
          children: [
            // 1. 顶部状态栏 (Meta Header)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: const BoxDecoration(
                color: headerBg,
                border: Border(bottom: BorderSide(color: cardBorder, width: 0.8)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.code_rounded, color: alertGold, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        widget.filename,
                        style: const TextStyle(
                          color: Colors.white,
                          fontFamily: 'monospace',
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 10),
                      // 运行状态胶囊
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: activeGreen.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: activeGreen.withOpacity(0.6), width: 0.6),
                        ),
                        child: Row(
                          children: const [
                            CircleAvatar(radius: 3, backgroundColor: activeGreen),
                            SizedBox(width: 4),
                            Text('Active', style: TextStyle(color: activeGreen, fontSize: 10, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      IconButton(
                        tooltip: '复制完整代码',
                        icon: const Icon(Icons.copy_rounded, color: textWhite, size: 18),
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: widget.ruleCode));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('代码已复制到剪贴板'), duration: Duration(seconds: 1)),
                          );
                        },
                      ),
                      IconButton(
                        tooltip: '热重载规则',
                        icon: const Icon(Icons.refresh_rounded, color: alertGold, size: 20),
                        onPressed: widget.onReload,
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // 2. 核心代码区域 (严格只读，自动换行，禁止横向滚动)
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.vertical,
                padding: const EdgeInsets.all(12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 行号列
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: List.generate(lines.length, (i) {
                        return Text(
                          '${i + 1} ',
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            color: lineNumColor,
                            fontSize: 12,
                            height: 1.5,
                          ),
                        );
                      }),
                    ),
                    const SizedBox(width: 10),
                    // 代码内容列 (Expanded 自动折行换行)
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: List.generate(lines.length, (i) {
                          return Text(
                            lines[i].isEmpty ? ' ' : lines[i],
                            softWrap: true,
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              color: textWhite,
                              fontSize: 12,
                              height: 1.5,
                            ),
                          );
                        }),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // 3. 底部轻量提示条
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: headerBg,
              child: Row(
                children: [
                  const Icon(Icons.lock_outline_rounded, size: 13, color: alertGold),
                  const SizedBox(width: 6),
                  Text(
                    '只读模式 · 修改策略逻辑请直接编辑 server/${widget.filename}',
                    style: const TextStyle(color: Color(0xFF848E9C), fontSize: 11),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
