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
  
  // FRP 公网穿透地址 (flowproxy 隧道)，出门在手机流量/任何外网下均能秒连与推送！
  String _serverHost = "47.92.99.47:15926";
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
      requestCriticalPermission: true,
    );
    await _notificationsPlugin.initialize(
      const InitializationSettings(iOS: darwinInit),
    );
    final iosPlugin = _notificationsPlugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
    await iosPlugin?.requestPermissions(
      alert: true,
      badge: true,
      sound: true,
      critical: true,
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
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
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

  Timer? _heartbeatTimer;

  void _startBackgroundWs() {
    _channel?.sink.close();
    _heartbeatTimer?.cancel();
    final wsUrl = 'ws://$_serverHost/ws/radar';
    try {
      _channel = WebSocketChannel.connect(Uri.parse(wsUrl));

      // 每 15 秒发送一次心跳 ping，维持长连接与运营商通道活跃
      _heartbeatTimer = Timer.periodic(const Duration(seconds: 15), (_) {
        try {
          _channel?.sink.add('ping');
        } catch (_) {}
      });

      _channel!.stream.listen(
        (data) {
          try {
            final decoded = jsonDecode(data);
            if (decoded['type'] == 'ANOMALY_ALERT') {
              final d = decoded['data'] ?? {};
              final sym = d['symbol'] ?? '未知标的';
              final score = d['score'] != null ? ' (评分:${d['score']})' : '';
              final title = '🚨 异动做空预警: $sym$score';
              final msg = d['message'] ?? '${d['rule_name'] ?? '急拉回归信号'}\n现价: \$${d['price']}';
              _showNotification(title, msg);
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
    _heartbeatTimer?.cancel();
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 4), _startBackgroundWs);
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
              // 右上角隐形配置热区 (长按可改 IP，防断连，完全透明不挡视觉)
              Positioned(
                top: 0,
                right: 0,
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onLongPress: _showHostDialog,
                  child: Container(
                    width: 44,
                    height: 44,
                    color: Colors.transparent,
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
