import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';

import 'screens/radar_screen.dart';
import 'screens/alerts_screen.dart';
import 'screens/rules_screen.dart';
import 'screens/settings_screen.dart';

void main() {
  runApp(const TrollStoreCryptoApp());
}

class TrollStoreCryptoApp extends StatelessWidget {
  const TrollStoreCryptoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Crypto Anomaly Terminal',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0F1115),
        primaryColor: const Color(0xFFF0B90B),
      ),
      home: const MainTabContainer(),
    );
  }
}

class MainTabContainer extends StatefulWidget {
  const MainTabContainer({super.key});

  @override
  State<MainTabContainer> createState() => _MainTabContainerState();
}

class _MainTabContainerState extends State<MainTabContainer> {
  int _currentIndex = 0;
  final String serverBaseUrl = "http://127.0.0.1:8080";
  final String wsUrl = "ws://127.0.0.1:8080/ws/radar";

  bool isConnected = false;
  WebSocketChannel? _channel;
  Timer? _reconnectTimer;

  // 数据集
  final List<MarketTickerItem> _marketRankings = [];
  final List<Map<String, dynamic>> _alerts = [];
  String _ruleCode = "# Loading rule code...";
  String _ruleFile = "anomaly_rules.py";
  String _lastLoaded = "";
  int monitoredPairs = 0;
  int totalPairs = 0;

  @override
  void initState() {
    super.initState();
    _fetchRuleCode();
    _fetchAlerts();
    _fetchStatus();
    _fetchMarketRankings();
    _connectWebSocket();

    // 定时轮询排行榜
    Timer.periodic(const Duration(seconds: 4), (_) => _fetchMarketRankings());
  }

  Future<void> _fetchMarketRankings([double minChange = -999.0]) async {
    try {
      final res = await http.get(Uri.parse('$serverBaseUrl/api/market/rankings?min_change=$minChange'));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        setState(() {
          _marketRankings.clear();
          for (var item in (data['rankings'] as List)) {
            _marketRankings.add(MarketTickerItem.fromJson(item));
          }
        });
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _channel?.sink.close();
    _reconnectTimer?.cancel();
    super.dispose();
  }

  void _connectWebSocket() {
    try {
      _channel = WebSocketChannel.connect(Uri.parse(wsUrl));
      setState(() => isConnected = true);

      _channel!.stream.listen(
        (data) {
          try {
            final decoded = jsonDecode(data);
            if (decoded['type'] == 'ANOMALY_ALERT') {
              final alertData = decoded['data'];
              setState(() {
                _alerts.insert(0, alertData as Map<String, dynamic>);
              });
            }
          } catch (e) {
            // ping/pong or raw string
          }
        },
        onDone: () {
          setState(() => isConnected = false);
          _scheduleReconnect();
        },
        onError: (err) {
          setState(() => isConnected = false);
          _scheduleReconnect();
        },
      );
    } catch (e) {
      setState(() => isConnected = false);
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 5), () {
      if (!isConnected) {
        _connectWebSocket();
      }
    });
  }

  Future<void> _fetchStatus() async {
    try {
      final res = await http.get(Uri.parse('$serverBaseUrl/api/status'));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        setState(() {
          monitoredPairs = data['monitored_pairs'] ?? 0;
          totalPairs = data['total_pairs'] ?? 0;
        });
      }
    } catch (_) {}
  }

  Future<void> _fetchRuleCode() async {
    try {
      final res = await http.get(Uri.parse('$serverBaseUrl/api/rules/code'));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        setState(() {
          _ruleCode = data['code'] ?? '';
          _ruleFile = data['filename'] ?? 'anomaly_rules.py';
          _lastLoaded = data['last_loaded'] ?? '';
        });
      }
    } catch (_) {}
  }

  Future<void> _fetchAlerts() async {
    try {
      final res = await http.get(Uri.parse('$serverBaseUrl/api/alerts'));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        setState(() {
          _alerts.clear();
          for (var a in (data['alerts'] as List)) {
            _alerts.add(Map<String, dynamic>.from(a));
          }
        });
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final unreadAlerts = _alerts.where((a) => a['is_read'] != true).length;

    final screens = [
      RadarScreen(
        tickers: _marketRankings,
        isConnected: isConnected,
        onFilterChanged: (th) => _fetchMarketRankings(th),
      ),
      AlertsScreen(
        alerts: _alerts,
        onMarkAllRead: () async {
          await http.post(Uri.parse('$serverBaseUrl/api/alerts/mark_read'));
          setState(() {
            for (var a in _alerts) {
              a['is_read'] = true;
            }
          });
        },
        onClearAll: () async {
          await http.post(Uri.parse('$serverBaseUrl/api/alerts/clear'));
          setState(() => _alerts.clear());
        },
      ),
      RulesScreen(
        ruleCode: _ruleCode,
        filename: _ruleFile,
        lastLoaded: _lastLoaded,
        onReload: _fetchRuleCode,
      ),
      SettingsScreen(
        monitoredCount: monitoredPairs,
        totalCount: totalPairs,
      ),
    ];

    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: screens,
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: Color(0xFF23272E), width: 0.8)),
        ),
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          backgroundColor: const Color(0xFF161A1E),
          selectedItemColor: const Color(0xFFF0B90B),
          unselectedItemColor: const Color(0xFF848E9C),
          type: BottomNavigationBarType.fixed,
          selectedFontSize: 11,
          unselectedFontSize: 11,
          onTap: (index) => setState(() => _currentIndex = index),
          items: [
            const BottomNavigationBarItem(
              icon: Icon(Icons.radar_rounded),
              label: '实时雷达',
            ),
            BottomNavigationBarItem(
              icon: Badge(
                isLabelVisible: unreadAlerts > 0,
                label: Text('$unreadAlerts', style: const TextStyle(fontSize: 10)),
                backgroundColor: const Color(0xFFF6465D),
                child: const Icon(Icons.notifications_active_outlined),
              ),
              label: '预警记录',
            ),
            const BottomNavigationBarItem(
              icon: Icon(Icons.terminal_rounded),
              label: '规则代码',
            ),
            const BottomNavigationBarItem(
              icon: Icon(Icons.tune_rounded),
              label: '监控配置',
            ),
          ],
        ),
      ),
    );
  }
}
