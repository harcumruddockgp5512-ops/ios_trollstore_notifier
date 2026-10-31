import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class SettingsScreen extends StatefulWidget {
  final int monitoredCount;
  final int totalCount;
  final String serverBaseUrl;

  const SettingsScreen({
    super.key,
    required this.monitoredCount,
    required this.totalCount,
    this.serverBaseUrl = 'http://127.0.0.1:8080',
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  // 暗黑终端视觉主题
  static const Color bgDark = Color(0xFF0F1115);
  static const Color cardDark = Color(0xFF161A1E);
  static const Color cardBorder = Color(0xFF23272E);
  static const Color textWhite = Color(0xFFFFFFFF);
  static const Color textMuted = Color(0xFF848E9C);
  static const Color alertGold = Color(0xFFF0B90B);
  static const Color inputBg = Color(0xFF1A1E24);
  static const Color downRed = Color(0xFFF6465D);

  // 1. 全局与范围控制状态
  late int _monitoredCount;
  late int _totalCount;
  bool _monitorAll = true;
  final Set<String> _selectedMarkets = {'spot', 'usdt_perp'}; // spot, usdt_perp, coin_perp

  // 2. 动态指标筛选器状态
  final TextEditingController _volumeController = TextEditingController(text: '1000000');
  double _minVolume = 1000000;
  String _selectedRank = 'unlimited'; // unlimited, vol_top50, vol_top100, vol_top200, gainers_top50, gainers_top100, losers_top50, losers_top100

  // 3. 本地通知与防打扰状态
  bool _enableLocalPush = true;
  double _cooldownMinutes = 5.0; // 默认 5 分钟，范围 1m - 30m
  bool _enableSound = true;
  bool _enableVibrate = true;

  @override
  void initState() {
    super.initState();
    _monitoredCount = widget.monitoredCount;
    _totalCount = widget.totalCount;
    _loadSettingsFromServer();
  }

  Future<void> _loadSettingsFromServer() async {
    try {
      final res = await http.get(Uri.parse('${widget.serverBaseUrl}/api/screening'));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final s = data['settings'] ?? {};
        setState(() {
          _monitoredCount = data['monitored_count'] ?? _monitoredCount;
          _totalCount = data['total_count'] ?? _totalCount;
          _monitorAll = s['monitor_all'] ?? true;
          _selectedMarkets.clear();
          for (var m in (s['market_types'] as List? ?? ['spot', 'usdt_perp'])) {
            _selectedMarkets.add(m.toString());
          }
          _minVolume = (s['min_volume_usdt'] ?? 1000000.0).toDouble();
          _volumeController.text = _minVolume.toInt().toString();
          _selectedRank = s['market_cap_rank'] ?? 'unlimited';
          _enableLocalPush = s['enable_push'] ?? true;
          _cooldownMinutes = (s['cooldown_minutes'] ?? 5).toDouble();
          _enableSound = s['enable_sound'] ?? true;
          _enableVibrate = s['enable_vibrate'] ?? true;
        });
      }
    } catch (_) {}
  }

  Future<void> _saveSettingsToServer() async {
    final payload = {
      "monitor_all": _monitorAll,
      "market_types": _selectedMarkets.toList(),
      "min_volume_usdt": double.tryParse(_volumeController.text) ?? _minVolume,
      "market_cap_rank": _selectedRank,
      "blacklist": [],
      "enable_push": _enableLocalPush,
      "cooldown_minutes": _cooldownMinutes.toInt(),
      "enable_sound": _enableSound,
      "enable_vibrate": _enableVibrate,
    };

    try {
      final res = await http.post(
        Uri.parse('${widget.serverBaseUrl}/api/screening'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode(payload),
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        setState(() {
          _monitoredCount = data['monitored_count'] ?? _monitoredCount;
          _totalCount = data['total_count'] ?? _totalCount;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('已更新监测范围，生效中', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
              backgroundColor: alertGold,
              duration: Duration(seconds: 2),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存失败: $e'), backgroundColor: downRed),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgDark,
      appBar: AppBar(
        backgroundColor: bgDark,
        elevation: 0,
        title: const Text(
          '监控范围与筛选配置',
          style: TextStyle(color: textWhite, fontSize: 17, fontWeight: FontWeight.bold),
        ),
      ),
      body: Stack(
        children: [
          // 可滚动主体设置区
          SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 90),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 1. 顶部全局监控状态看板
                _buildStatusBanner(),

                const SizedBox(height: 20),

                // 2. 默认监控与范围控制
                _buildSectionTitle('范围控制 (Scope Control)'),
                _buildScopeControls(),

                const SizedBox(height: 22),

                // 3. 动态指标筛选器 (过滤低流动性垃圾币)
                _buildSectionTitle('动态指标筛选器 (Liquidity Filter)'),
                _buildDynamicMetrics(),

                const SizedBox(height: 22),

                // 4. 本地通知与防打扰控制 (TrollStore 特性)
                _buildSectionTitle('本地通知与防打扰控制 (Local Push & Cooldown)'),
                _buildNotificationControls(),

                const SizedBox(height: 20),
              ],
            ),
          ),

          // 5. 底部悬浮固定保存栏
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _buildBottomFixedBar(),
          ),
        ],
      ),
    );
  }

  // --- 组件 1: 顶部全局监控状态看板 ---
  Widget _buildStatusBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: cardDark,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: alertGold.withOpacity(0.5), width: 1.0),
        boxShadow: [
          BoxShadow(
            color: alertGold.withOpacity(0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: alertGold.withOpacity(0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.radar_rounded, color: alertGold, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '当前全局监控引擎生效状态',
                  style: TextStyle(color: textMuted, fontSize: 12),
                ),
                const SizedBox(height: 4),
                RichText(
                  text: TextSpan(
                    text: '当前正在监控 ',
                    style: const TextStyle(color: textWhite, fontSize: 15, fontWeight: FontWeight.w600),
                    children: [
                      TextSpan(
                        text: '$_monitoredCount',
                        style: const TextStyle(color: alertGold, fontSize: 17, fontWeight: FontWeight.bold, fontFamily: 'monospace'),
                      ),
                      TextSpan(
                        text: ' / $_totalCount 个交易对',
                        style: const TextStyle(color: textMuted, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // --- 组件 2: 默认监控与范围控制 ---
  Widget _buildScopeControls() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cardDark,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cardBorder, width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 主开关
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text(
                    '监控全市场币种（默认开启）',
                    style: TextStyle(color: textWhite, fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 2),
                  Text(
                    '关闭后仅监控满足下方流动性与市场类型的币种',
                    style: TextStyle(color: textMuted, fontSize: 11),
                  ),
                ],
              ),
              Switch(
                value: _monitorAll,
                activeColor: alertGold,
                onChanged: (val) => setState(() => _monitorAll = val),
              ),
            ],
          ),

          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Divider(color: cardBorder, height: 1),
          ),

          // 市场类型多选 Chips
          const Text('市场类型多选：', style: TextStyle(color: textMuted, fontSize: 12)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              _buildMarketChip('USDT 现货交易对', 'spot'),
              _buildMarketChip('U本位永续合约', 'usdt_perp'),
              _buildMarketChip('币本位合约', 'coin_perp'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMarketChip(String label, String key) {
    final isSelected = _selectedMarkets.contains(key);
    return FilterChip(
      label: Text(label),
      selected: isSelected,
      selectedColor: alertGold.withOpacity(0.18),
      checkmarkColor: alertGold,
      backgroundColor: inputBg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: isSelected ? alertGold : cardBorder, width: 0.8),
      ),
      labelStyle: TextStyle(
        color: isSelected ? alertGold : textMuted,
        fontSize: 12,
        fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
      ),
      onSelected: (selected) {
        setState(() {
          if (selected) {
            _selectedMarkets.add(key);
          } else {
            if (_selectedMarkets.length > 1) {
              _selectedMarkets.remove(key);
            }
          }
        });
      },
    );
  }

  // --- 组件 3: 动态指标筛选器 ---
  Widget _buildDynamicMetrics() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cardDark,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cardBorder, width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 24h 成交额下限
          const Text(
            '24小时成交量下限 (Volume Threshold)：',
            style: TextStyle(color: textWhite, fontSize: 13, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Container(
                  height: 42,
                  decoration: BoxDecoration(
                    color: inputBg,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: cardBorder),
                  ),
                  child: TextField(
                    controller: _volumeController,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(color: textWhite, fontSize: 14, fontFamily: 'monospace'),
                    decoration: const InputDecoration(
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      border: InputBorder.none,
                      suffixText: 'USDT',
                      suffixStyle: TextStyle(color: textMuted, fontSize: 12),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // 快捷步进按钮
          Wrap(
            spacing: 8,
            children: [
              _buildStepButton('> 1,000,000 USDT', 1000000),
              _buildStepButton('> 5,000,000 USDT', 5000000),
              _buildStepButton('> 10,000,000 USDT', 10000000),
            ],
          ),

          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Divider(color: cardBorder, height: 1),
          ),

          // 榜单与排名筛选 (Rank Filter)
          const Text(
            '榜单与排名筛选 (Rank Filter)：',
            style: TextStyle(color: textWhite, fontSize: 13, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          const Text(
            '支持按 24h 成交额、涨幅前100或跌幅前100精确监控',
            style: TextStyle(color: textMuted, fontSize: 11),
          ),
          const SizedBox(height: 10),

          // 全局范围
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              _buildRankOption('不限制', 'unlimited'),
            ],
          ),
          const SizedBox(height: 12),

          // 1. 成交额排名
          const Text('按 24h 成交额排名：', style: TextStyle(color: alertGold, fontSize: 11, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              _buildRankOption('成交量前 50 名', 'vol_top50'),
              _buildRankOption('成交量前 100 名', 'vol_top100'),
              _buildRankOption('成交量前 200 名', 'vol_top200'),
            ],
          ),
          const SizedBox(height: 12),

          // 2. 涨幅榜
          const Text('按 24h 涨幅榜排名：', style: TextStyle(color: Color(0xFF0ECB81), fontSize: 11, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              _buildRankOption('涨幅前 50 名', 'gainers_top50'),
              _buildRankOption('涨幅前 100 名', 'gainers_top100'),
              _buildRankOption('涨幅前 200 名', 'gainers_top200'),
            ],
          ),
          const SizedBox(height: 12),

          // 3. 跌幅榜
          const Text('按 24h 跌幅榜排名：', style: TextStyle(color: Color(0xFFF6465D), fontSize: 11, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              _buildRankOption('跌幅前 50 名', 'losers_top50'),
              _buildRankOption('跌幅前 100 名', 'losers_top100'),
              _buildRankOption('跌幅前 200 名', 'losers_top200'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStepButton(String text, double val) {
    return GestureDetector(
      onTap: () {
        setState(() {
          _minVolume = val;
          _volumeController.text = val.toInt().toString();
        });
      },
      child: Container(
        margin: const EdgeInsets.only(top: 4),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: inputBg,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: cardBorder, width: 0.6),
        ),
        child: Text(text, style: const TextStyle(color: alertGold, fontSize: 11)),
      ),
    );
  }

  Widget _buildRankOption(String title, String rankKey) {
    final isSelected = _selectedRank == rankKey;
    return ChoiceChip(
      label: Text(title),
      selected: isSelected,
      selectedColor: alertGold.withOpacity(0.2),
      backgroundColor: inputBg,
      labelStyle: TextStyle(
        color: isSelected ? alertGold : textMuted,
        fontSize: 12,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
      ),
      onSelected: (_) => setState(() => _selectedRank = rankKey),
    );
  }

  // --- 组件 4: 本地通知与防打扰控制 ---
  Widget _buildNotificationControls() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cardDark,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cardBorder, width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 本地推送总开关
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text('本地系统推送总开关', style: TextStyle(color: textWhite, fontSize: 14, fontWeight: FontWeight.w600)),
                  SizedBox(height: 2),
                  Text('基于 TrollStore 无限常驻长连接分发系统横幅', style: TextStyle(color: textMuted, fontSize: 11)),
                ],
              ),
              Switch(
                value: _enableLocalPush,
                activeColor: alertGold,
                onChanged: (val) => setState(() => _enableLocalPush = val),
              ),
            ],
          ),

          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Divider(color: cardBorder, height: 1),
          ),

          // 冷却时间滑块
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('报警冷却时间 (Cooldown)', style: TextStyle(color: textWhite, fontSize: 13)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: alertGold.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '${_cooldownMinutes.toInt()} 分钟',
                  style: const TextStyle(color: alertGold, fontWeight: FontWeight.bold, fontSize: 12, fontFamily: 'monospace'),
                ),
              ),
            ],
          ),
          Slider(
            value: _cooldownMinutes,
            min: 1.0,
            max: 30.0,
            divisions: 29,
            activeColor: alertGold,
            inactiveColor: cardBorder,
            onChanged: (val) => setState(() => _cooldownMinutes = val),
          ),

          // 声音与震动独立开关
          Row(
            children: [
              Expanded(
                child: CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  activeColor: alertGold,
                  checkColor: Colors.black,
                  title: const Text('声音提醒', style: TextStyle(color: textWhite, fontSize: 13)),
                  value: _enableSound,
                  onChanged: (val) => setState(() => _enableSound = val ?? true),
                ),
              ),
              Expanded(
                child: CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  activeColor: alertGold,
                  checkColor: Colors.black,
                  title: const Text('强震动提醒', style: TextStyle(color: textWhite, fontSize: 13)),
                  value: _enableVibrate,
                  onChanged: (val) => setState(() => _enableVibrate = val ?? true),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // --- 组件 5: 底部固定栏悬浮保存按钮 ---
  Widget _buildBottomFixedBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: cardDark,
        border: const Border(top: BorderSide(color: cardBorder, width: 0.8)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.5),
            blurRadius: 10,
            offset: const Offset(0, -3),
          )
        ],
      ),
      child: SizedBox(
        width: double.infinity,
        height: 48,
        child: ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: alertGold,
            foregroundColor: Colors.black,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            elevation: 2,
          ),
          icon: const Icon(Icons.check_circle_rounded, size: 20),
          label: const Text(
            '保存并应用过滤规则',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          ),
          onPressed: _saveSettingsToServer,
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        color: alertGold,
        fontSize: 13,
        fontWeight: FontWeight.bold,
        letterSpacing: 0.3,
      ),
    );
  }
}
