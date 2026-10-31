import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const TrollStoreHotReloadApp());
}

class TrollStoreHotReloadApp extends StatelessWidget {
  const TrollStoreHotReloadApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Crypto Terminal (Hot-Update)',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0F1115),
      ),
      home: const HotContainerScreen(),
    );
  }
}

class HotContainerScreen extends StatefulWidget {
  const HotContainerScreen({super.key});

  @override
  State<HotContainerScreen> createState() => _HotContainerScreenState();
}

class _HotContainerScreenState extends State<HotContainerScreen> {
  late final WebViewController _controller;
  final FlutterLocalNotificationsPlugin _notificationsPlugin = FlutterLocalNotificationsPlugin();
  
  // FRP 公网穿透地址，出门在手机流量/任何外网下均能秒连与推送！
  String _serverHost = "47.92.99.47:8081";
  WebSocketChannel? _channel;
  Timer? _reconnectTimer;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _initNotifications();
    _loadHostAndStart();
  }

  Future<void> _initNotifications() async {
    const darwinInit = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    await _notificationsPlugin.initialize(
      const InitializationSettings(iOS: darwinInit),
    );
  }

  Future<void> _showNotification(String title, String body) async {
    const details = NotificationDetails(
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        interruptionLevel: InterruptionLevel.timeSensitive,
      ),
    );
    await _notificationsPlugin.show(
      DateTime.now().millisecond,
      title,
      body,
      details,
    );
  }

  Future<void> _loadHostAndStart() async {
    final prefs = await SharedPreferences.getInstance();
    final savedHost = prefs.getString('server_host');
    if (savedHost != null && savedHost.isNotEmpty) {
      _serverHost = savedHost;
    }

    _initWebView();
    _startBackgroundWs();
  }

  void _initWebView() {
    final targetUrl = 'http://$_serverHost/';
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF0F1115))
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            if (mounted) setState(() => _isLoading = false);
          },
          onWebResourceError: (err) {
            debugPrint("Web error: ${err.description}");
          },
        ),
      )
      ..loadRequest(Uri.parse(targetUrl));
  }

  void _startBackgroundWs() {
    _channel?.sink.close();
    final wsUrl = 'ws://$_serverHost/ws/radar';
    try {
      _channel = WebSocketChannel.connect(Uri.parse(wsUrl));
      _channel!.stream.listen(
        (data) {
          try {
            final decoded = jsonDecode(data);
            if (decoded['type'] == 'ANOMALY_ALERT') {
              final d = decoded['data'];
              _showNotification(
                '🚨 暴涨预警: ${d['symbol']} +${d['change_24h']}%',
                '${d['rule_name']}\n现价: \$${d['price']}',
              );
            }
          } catch (_) {}
        },
        onDone: () => _retryWs(),
        onError: (_) => _retryWs(),
      );
    } catch (_) {
      _retryWs();
    }
  }

  void _retryWs() {
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 5), _startBackgroundWs);
  }

  void _showHostDialog() {
    final textController = TextEditingController(text: _serverHost);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF161A1E),
        title: const Text('配置服务器地址', style: TextStyle(color: Colors.white, fontSize: 16)),
        content: TextField(
          controller: textController,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: '如 192.168.1.2:8080 或 域名',
            hintStyle: TextStyle(color: Colors.grey),
            enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFFF0B90B))),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFF0B90B)),
            onPressed: () async {
              final val = textController.text.trim();
              if (val.isNotEmpty) {
                final prefs = await SharedPreferences.getInstance();
                await prefs.setString('server_host', val);
                setState(() {
                  _serverHost = val;
                  _isLoading = true;
                });
                _initWebView();
                _startBackgroundWs();
              }
              if (mounted) Navigator.pop(ctx);
            },
            child: const Text('保存并重连', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _channel?.sink.close();
    _reconnectTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: const Color(0xFF0F1115),
        body: SafeArea(
          bottom: false,
          child: Stack(
            children: [
              WebViewWidget(controller: _controller),
              if (_isLoading)
                const Center(
                  child: CircularProgressIndicator(color: Color(0xFFF0B90B)),
                ),
              // 右上角浮动轻量配置齿轮 (长按可改 IP，防断连)
              Positioned(
                top: 8,
                right: 8,
                child: GestureDetector(
                  onLongPress: _showHostDialog,
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.3),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.wifi_tethering, size: 14, color: Colors.white24),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
