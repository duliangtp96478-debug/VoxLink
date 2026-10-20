import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const kAccent = Color(0xFF4CC9F0);
const kBg = Color(0xFF0A0F1A);
const kSurface = Color(0xFF111827);
const kText = Color(0xFFF2F5FA);
const kGood = Color(0xFF56D8A0);
const kWarn = Color(0xFFFFC857);
const channel = MethodChannel('voxlink/native');

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const VoxLinkMobileApp());
}

class VoxLinkMobileApp extends StatelessWidget {
  const VoxLinkMobileApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'VoxLink',
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: kBg,
        colorScheme: ColorScheme.fromSeed(seedColor: kAccent, brightness: Brightness.dark, surface: kSurface),
        fontFamilyFallback: const ['Noto Sans CJK SC', 'sans-serif'],
        cardTheme: CardThemeData(
          color: kSurface,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
            side: BorderSide(color: kText.withValues(alpha: .08)),
          ),
        ),
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final ipController = TextEditingController();
  Timer? timer;
  Map<String, dynamic> state = {};
  bool discovering = false;
  bool starting = false;

  @override
  void initState() {
    super.initState();
    unawaited(initialLoad());
    timer = Timer.periodic(const Duration(milliseconds: 700), (_) => unawaited(poll()));
  }

  Future<void> initialLoad() async {
    await poll();
    if (ipController.text.trim().isEmpty) {
      await Future.delayed(const Duration(milliseconds: 350));
      if (mounted) await discover(silent: true);
    }
  }

  Future<void> poll() async {
    try {
      final raw = await channel.invokeMethod<Map>('getState');
      final next = Map<String, dynamic>.from(raw ?? const {});
      if (ipController.text.isEmpty) ipController.text = (next['serverIp'] ?? '').toString();
      if (mounted) setState(() => state = next);
    } catch (_) {}
  }

  Future<void> discover({bool silent = false}) async {
    if (discovering) return;
    setState(() => discovering = true);
    try {
      final raw = await channel.invokeMethod<List>('discover') ?? const [];
      if (raw.isNotEmpty) {
        final first = Map<String, dynamic>.from(raw.first as Map);
        ipController.text = (first['ip'] ?? '').toString();
        if (!silent && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('发现电脑：${first['name'] ?? first['ip']}')));
        }
      } else if (!silent && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('没有自动发现电脑，可以手动填写电脑 IP')));
      }
    } finally {
      if (mounted) setState(() => discovering = false);
    }
  }

  Future<void> start() async {
    if (starting) return;
    final ip = ipController.text.trim();
    if (ip.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请先填写或自动发现电脑 IP')));
      return;
    }
    setState(() => starting = true);
    try {
      final granted = await channel.invokeMethod<bool>('requestMic') ?? false;
      if (!granted) return;
      await channel.invokeMethod('start', {'ip': ip});
      await poll();
    } finally {
      if (mounted) setState(() => starting = false);
    }
  }

  Future<void> stop() async {
    await channel.invokeMethod('stop');
    await poll();
  }

  @override
  void dispose() {
    timer?.cancel();
    ipController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final running = state['running'] == true;
    final connected = state['connected'] == true;
    final error = (state['lastError'] ?? '').toString();
    final frames = (state['framesSent'] ?? 0).toString();
    final color = connected ? kGood : (running ? kWarn : kText.withValues(alpha: .38));

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF080D17), Color(0xFF0D1422), Color(0xFF090E19)],
          ),
        ),
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(22, 22, 22, 28),
            children: [
              const Text('VoxLink', style: TextStyle(fontSize: 35, fontWeight: FontWeight.w800, letterSpacing: -.9)),
              const SizedBox(height: 5),
              Text('无线麦克风 · 回声消除测试版 1', style: TextStyle(color: kText.withValues(alpha: .57), fontSize: 15)),
              const SizedBox(height: 28),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Container(width: 10, height: 10, decoration: BoxDecoration(shape: BoxShape.circle, color: color)),
                      const SizedBox(width: 10),
                      Expanded(child: Text(connected ? '已连接电脑' : (running ? '正在等待 / 自动重连' : '服务未启动'), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700))),
                    ]),
                    const SizedBox(height: 10),
                    Text(
                      connected ? '${state['serverIp']} · 已发送 $frames 帧' : (running ? '前台服务运行中，锁屏后会继续连接' : '48 kHz · 16 bit · Mono'),
                      style: TextStyle(color: kText.withValues(alpha: .52), height: 1.45),
                    ),
                    if (error.isNotEmpty && !connected) ...[
                      const SizedBox(height: 8),
                      Text(error, style: const TextStyle(color: kWarn, fontSize: 12.5)),
                    ],
                  ]),
                ),
              ),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    const Text('电脑连接', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 14),
                    TextField(
                      controller: ipController,
                      enabled: !running,
                      keyboardType: TextInputType.url,
                      autocorrect: false,
                      decoration: const InputDecoration(labelText: '电脑 IP', hintText: '例如 192.168.1.100', prefixIcon: Icon(Icons.lan_rounded)),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: running || discovering ? null : () => discover(),
                      icon: const Icon(Icons.radar_rounded),
                      label: Text(discovering ? '正在搜索…' : '自动发现电脑'),
                    ),
                  ]),
                ),
              ),
              const SizedBox(height: 16),
              Card(
                child: Column(children: [
                  SwitchListTile(
                    title: const Text('通话模式 / 回声消除'),
                    subtitle: const Text('默认开启；停止麦克风后可切换，对比音质与外放串音'),
                    value: state['echoCancellation'] != false,
                    onChanged: running || starting ? null : (enabled) async {
                      await channel.invokeMethod('setEchoCancellation', {'enabled': enabled});
                      await poll();
                    },
                  ),
                  if (running) Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: Text((state['aecStatus'] ?? '正在初始化').toString(), style: const TextStyle(fontSize: 12, color: kWarn)),
                  ),
                ]),
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: starting ? null : (running ? stop : start),
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(58), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(17))),
                icon: Icon(running ? Icons.stop_rounded : Icons.mic_rounded),
                label: Text(starting ? '正在启动…' : (running ? '停止 VoxLink' : '启动无线麦克风'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              ),
              const SizedBox(height: 18),
              Text(
                '首次启动需要允许麦克风权限。运行后系统会显示 VoxLink 前台服务通知，以提高锁屏和后台稳定性。',
                textAlign: TextAlign.center,
                style: TextStyle(height: 1.55, fontSize: 12.5, color: kText.withValues(alpha: .44)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
