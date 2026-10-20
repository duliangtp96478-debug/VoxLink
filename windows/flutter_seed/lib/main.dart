import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show FontFeature, PlatformDispatcher;
import 'package:flutter/gestures.dart' show PointerScrollEvent;

import 'package:flutter/material.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

// Stable release: diagnostic breadcrumbs are intentionally disabled.
class StableLog {
  static void event(String name, [String detail = '']) {}
}

const kAccent = Color(0xFF4CC9F0);
const kBg = Color(0xFF0A0F1A);
const kSurface = Color(0xFF111827);
const kText = Color(0xFFF2F5FA);
const kGood = Color(0xFF56D8A0);
const kWarn = Color(0xFFFFC857);
const kBad = Color(0xFFFF7B86);

class CoreClient {
  Future<Map<String, dynamic>?> call(String command) async {
    Socket? socket;
    try {
      socket = await Socket.connect(
        InternetAddress.loopbackIPv4,
        28110,
        timeout: const Duration(milliseconds: 500),
      );
      socket.write('$command\n');
      await socket.flush();

      String buffer = '';
      final completer = Completer<Map<String, dynamic>?>();
      late StreamSubscription<List<int>> sub;
      sub = socket.listen(
        (data) {
          buffer += utf8.decode(data, allowMalformed: true);
          final p = buffer.indexOf('\n');
          if (p >= 0 && !completer.isCompleted) {
            try {
              completer.complete(
                Map<String, dynamic>.from(
                  jsonDecode(buffer.substring(0, p)) as Map,
                ),
              );
            } catch (_) {
              completer.complete(null);
            }
            sub.cancel();
          }
        },
        onError: (_) {
          if (!completer.isCompleted) completer.complete(null);
        },
        onDone: () {
          if (!completer.isCompleted) completer.complete(null);
        },
        cancelOnError: true,
      );

      return await completer.future.timeout(
        const Duration(milliseconds: 900),
        onTimeout: () => null,
      );
    } catch (_) {
      return null;
    } finally {
      socket?.destroy();
    }
  }
}

const int kInstancePort = 28111;
const String kShowInstanceCommand = 'VOXLINK_SHOW_V1';

Future<void> main() async {
  StableLog.event('PROCESS_START', 'VoxLink 1.0.1 Stable');
  // Binding is atomic: only one UI instance can own this local endpoint.
  // The operating system releases it automatically when the process exits.
  ServerSocket instanceServer;
  try {
    instanceServer = await ServerSocket.bind(
      InternetAddress.loopbackIPv4, kInstancePort, shared: false,
    );
  } on SocketException {
    Socket? existing;
    try {
      existing = await Socket.connect(
        InternetAddress.loopbackIPv4, kInstancePort,
        timeout: const Duration(seconds: 2),
      );
      existing.write('$kShowInstanceCommand\n');
      await existing.flush();
      final reply = await utf8.decoder.bind(existing)
          .transform(const LineSplitter()).first
          .timeout(const Duration(seconds: 15));
      if (reply != 'VOXLINK_SHOWN_V1') {
        throw StateError('The single-instance endpoint is occupied.');
      }
      existing.destroy();
      exit(0);
    } catch (error) {
      existing?.destroy();
      stderr.writeln('Cannot activate the existing VoxLink window: $error');
      exit(1);
    }
  }

  final windowReady = Completer<void>();
  instanceServer.listen((client) {
    unawaited(() async {
      try {
        final command = await utf8.decoder.bind(client)
            .transform(const LineSplitter()).first
            .timeout(const Duration(seconds: 3));
        if (command != kShowInstanceCommand) return;
        await windowReady.future;
        await windowManager.setSkipTaskbar(false);
        await windowManager.show();
        if (await windowManager.isMinimized()) {
          await windowManager.restore();
        }
        await windowManager.focus();
        client.write('VOXLINK_SHOWN_V1\n');
        await client.flush();
      } catch (error) {
        debugPrint('VoxLink window activation failed: $error');
      } finally {
        client.destroy();
      }
    }());
  });

  WidgetsFlutterBinding.ensureInitialized();
  FlutterError.onError = (details) { StableLog.event('FLUTTER_ERROR', details.exceptionAsString()); FlutterError.presentError(details); };
  PlatformDispatcher.instance.onError = (error, stack) {
    StableLog.event('DART_UNHANDLED', '$error\n$stack');
    return false;
  };
  StableLog.event('WINDOW_MANAGER_INIT_BEGIN');
  await windowManager.ensureInitialized();
  StableLog.event('WINDOW_MANAGER_INIT_OK');

  const options = WindowOptions(
    size: Size(900, 700),
    minimumSize: Size(720, 600),
    center: true,
    backgroundColor: kBg,
    titleBarStyle: TitleBarStyle.hidden,
    windowButtonVisibility: false,
  );

  await windowManager.waitUntilReadyToShow(options, () async {
    await windowManager.setPreventClose(true);
    await windowManager.show();
    await windowManager.focus();
  });

  StableLog.event('RUN_APP_BEGIN');
  runApp(const VoxLinkApp());
  StableLog.event('RUN_APP_OK');
  windowReady.complete();
}

class VoxLinkApp extends StatelessWidget {
  const VoxLinkApp({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(
      seedColor: kAccent,
      brightness: Brightness.dark,
      surface: kSurface,
    );
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'VoxLink',
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: scheme,
        scaffoldBackgroundColor: kBg,
        fontFamilyFallback: const ['Microsoft YaHei UI', 'Segoe UI'],
        cardTheme: CardThemeData(
          color: kSurface,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: BorderSide(color: kText.withValues(alpha: .08)),
          ),
        ),
        sliderTheme: SliderThemeData(
          trackHeight: 3.5,
          activeTrackColor: kAccent,
          inactiveTrackColor: kText.withValues(alpha: .11),
          thumbColor: kAccent,
          overlayColor: kAccent.withValues(alpha: .13),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: kText.withValues(alpha: .045),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: kText.withValues(alpha: .10)),
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

class _HomePageState extends State<HomePage>
    with WindowListener, TrayListener {
  final CoreClient core = CoreClient();
  Timer? timer;
  bool refreshBusy = false;
  bool trayReady = false;
  final Set<String> editingParams = {};
  int configRevision = 0;
  int pendingWrites = 0;
  Future<void> writeQueue = Future<void>.value();
  bool exiting = false;
  bool coreOnline = false;
  Map<String, dynamic> state = {};
  List<Map<String, dynamic>> devices = [];
  double gainDb = 0, lowDb = 0, midDb = 0, highDb = 0;
  int denoise = 2;
  bool muted = false;

  @override
  void initState() {
    super.initState();
    StableLog.event('HOMEPAGE_INIT');
    windowManager.addListener(this);
    trayManager.addListener(this);
    unawaited(boot());
  }

  Future<void> boot() async {
    await setupTray();
    await ensureCore();
    await refresh();
    timer = Timer.periodic(
      const Duration(milliseconds: 500),
      (_) => unawaited(refresh()),
    );
  }

  Future<void> ensureCore() async {
    if ((await core.call('STATE'))?['ok'] == true) {
      coreOnline = true;
      return;
    }
    final dir = File(Platform.resolvedExecutable).parent.path;
    final exe = File('$dir${Platform.pathSeparator}VoxLinkCore.exe');
    if (!await exe.exists()) return;
    try {
      await Process.start(
        exe.path,
        const [],
        workingDirectory: dir,
        mode: ProcessStartMode.detached,
      );
      for (var i = 0; i < 25; i++) {
        await Future.delayed(const Duration(milliseconds: 120));
        if ((await core.call('STATE'))?['ok'] == true) {
          coreOnline = true;
          return;
        }
      }
    } catch (_) {}
  }

  Future<void> setupTray() async {
    trayReady = false;
    try {
      // tray_manager resolves this path through Flutter's asset bundle.
      await trayManager.setIcon('assets/app_icon.ico');
      await trayManager.setToolTip('VoxLink · 手机无线麦克风');
      await rebuildTrayMenu();
      trayReady = true;
    } catch (error) {
      debugPrint('VoxLink tray initialization failed: $error');
      try { await trayManager.destroy(); } catch (_) {}
    }
  }

  Future<void> showMainWindow() async {
    await windowManager.setSkipTaskbar(false);
    await windowManager.show();
    if (await windowManager.isMinimized()) await windowManager.restore();
    await windowManager.focus();
  }

  Future<void> rebuildTrayMenu() async {
    await trayManager.setContextMenu(
      Menu(items: [
        MenuItem(key: 'open', label: '打开主界面'),
        MenuItem.separator(),
        MenuItem(key: 'mute', label: muted ? '恢复麦克风' : '麦克风静音'),
        MenuItem(key: 'up', label: '麦克风音量 +2 dB'),
        MenuItem(key: 'down', label: '麦克风音量 -2 dB'),
        MenuItem.separator(),
        MenuItem(key: 'exit', label: '退出 VoxLink'),
      ]),
    );
  }

  Future<void> refresh() async {
    if (refreshBusy) return;
    refreshBusy = true;
    final requestedRevision = configRevision;
    final startedDuringEdit = editingParams.isNotEmpty || pendingWrites > 0;
    try {
      final r = await core.call('STATE');
      if (r?['ok'] != true) {
        if (mounted) setState(() => coreOnline = false);
        return;
      }
      final next = Map<String, dynamic>.from(r!['state'] as Map);
      final cfg = Map<String, dynamic>.from((next['config'] as Map?) ?? {});
      final list = ((next['devices'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      final nextMuted = cfg['muted'] == true;
      final acceptConfig = !startedDuringEdit &&
          editingParams.isEmpty && pendingWrites == 0 &&
          requestedRevision == configRevision;
      final trayChanged = acceptConfig && nextMuted != muted;
      if (!mounted) return;
      setState(() {
        coreOnline = true;
        state = next;
        devices = list;
        if (acceptConfig) {
        gainDb = (cfg['gain_db'] ?? 0).toDouble();
        lowDb = (cfg['eq_low_db'] ?? 0).toDouble();
        midDb = (cfg['eq_mid_db'] ?? 0).toDouble();
        highDb = (cfg['eq_high_db'] ?? 0).toDouble();
        denoise = (cfg['denoise'] ?? 2).toInt();
        muted = nextMuted;
        }
      });
      if (trayChanged && trayReady) {
        try { await rebuildTrayMenu(); } catch (error) {
          debugPrint('VoxLink tray menu update failed: $error');
        }
      }
    } finally {
      refreshBusy = false;
    }
  }

  void applyLocalParam(String key, dynamic value) {
    switch (key) {
      case 'gain_db': gainDb = (value as num).toDouble(); break;
      case 'eq_low_db': lowDb = (value as num).toDouble(); break;
      case 'eq_mid_db': midDb = (value as num).toDouble(); break;
      case 'eq_high_db': highDb = (value as num).toDouble(); break;
      case 'denoise': denoise = (value as num).toInt(); break;
      case 'muted': muted = value as bool; break;
    }
  }

  void dragParam(String key, double value) {
    configRevision++;
    editingParams.add(key);
    setState(() => applyLocalParam(key, value));
  }

  void finishDrag(String key, double value) {
    // Enqueue before clearing the edit guard, leaving no unprotected interval.
    unawaited(setParam(key, value));
    editingParams.remove(key);
  }

  Future<void> setParam(String key, dynamic value) {
    configRevision++;
    pendingWrites++;
    if (mounted) setState(() => applyLocalParam(key, value));
    final v = value is bool ? (value ? 1 : 0) : value;
    final operation = writeQueue.then((_) async {
      try {
        final reply = await core.call('SET $key $v');
        if (reply?['ok'] != true && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('参数未保存，请检查音频核心连接后重试。')),
          );
        }
      } finally {
        pendingWrites--;
        configRevision++;
      }
    });
    writeQueue = operation.catchError((Object error) {
      debugPrint('VoxLink parameter write failed: $error');
    });
    return writeQueue;
  }

  Future<void> quit() async {
    if (exiting) return;
    exiting = true;
    timer?.cancel();
    try { await core.call('SHUTDOWN'); } catch (_) {}
    try { await trayManager.destroy(); } catch (_) {}
    await windowManager.setPreventClose(false);
    await windowManager.destroy();
  }

  @override
  void onWindowResize() { StableLog.event('WINDOW_RESIZE'); }

  @override
  void onWindowMaximize() { StableLog.event('WINDOW_MAXIMIZE'); }

  @override
  void onWindowUnmaximize() { StableLog.event('WINDOW_UNMAXIMIZE'); }

  @override
  Future<void> onWindowClose() async {
    if (exiting) return;
    if (!trayReady) await setupTray();
    if (trayReady) {
      await windowManager.hide();
    } else {
      await windowManager.setSkipTaskbar(false);
      await windowManager.minimize();
    }
  }

  @override
  void onTrayIconMouseDown() => unawaited(showMainWindow());

  @override
  void onTrayIconRightMouseDown() => unawaited(trayManager.popUpContextMenu());

  @override
  void onTrayMenuItemClick(MenuItem item) {
    if (item.key == 'open') {
      unawaited(showMainWindow());
    } else if (item.key == 'mute') {
      unawaited(setParam('muted', !muted));
    } else if (item.key == 'up') {
      unawaited(setParam('gain_db', (gainDb + 2).clamp(-12, 18)));
    } else if (item.key == 'down') {
      unawaited(setParam('gain_db', (gainDb - 2).clamp(-12, 18)));
    } else if (item.key == 'exit') {
      unawaited(quit());
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    windowManager.removeListener(this);
    trayManager.removeListener(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final phoneOnline = state['phone_online'] == true;
    final inputDb = (state['input_db'] ?? -90).toDouble();
    final outputDb = (state['output_db'] ?? -90).toDouble();
    final kbps = (state['kbps'] ?? 0).toDouble();
    final outputIndex = (state['output_index'] ?? -1).toInt();
    final outputActive = outputIndex >= 0;

    return Scaffold(
      body: Stack(children: [
        const Positioned.fill(child: _Background()),
        Column(children: [
          _TitleBar(onExit: quit),
          Expanded(
            child: Listener(
              onPointerSignal: (event) { if (event is PointerScrollEvent) StableLog.event('POINTER_SCROLL', 'dy=${event.scrollDelta.dy}'); },
              child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 28),
              children: [
                Row(children: [
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('VoxLink', style: TextStyle(fontSize: 31, fontWeight: FontWeight.w800, letterSpacing: -.8)),
                        SizedBox(height: 4),
                        Text('Wireless Microphone', style: TextStyle(color: Color(0xFF8592A6), fontSize: 13)),
                      ],
                    ),
                  ),
                  _StatusPill(coreOnline: coreOnline, phoneOnline: phoneOnline),
                ]),
                const SizedBox(height: 18),
                _Panel(
                  title: '连接状态',
                  icon: Icons.lan_rounded,
                  child: Row(children: [
                    Expanded(child: _InfoTile(title: '手机', value: phoneOnline ? (state['phone_ip'] ?? '').toString() : '等待连接', good: phoneOnline)),
                    const SizedBox(width: 10),
                    Expanded(child: _InfoTile(title: '音频', value: phoneOnline ? '${kbps.toStringAsFixed(1)} KB/s' : '—', good: phoneOnline)),
                    const SizedBox(width: 10),
                    Expanded(child: _InfoTile(title: '输出', value: outputActive ? '正常' : '未就绪', good: outputActive)),
                  ]),
                ),
                const SizedBox(height: 14),
                LayoutBuilder(builder: (context, c) {
                  final meters = _Panel(
                    title: '实时电平',
                    icon: Icons.multiline_chart_rounded,
                    child: Column(children: [
                      _Meter(label: '输入', db: inputDb),
                      const SizedBox(height: 14),
                      _Meter(label: '输出', db: outputDb),
                    ]),
                  );
                  final output = _Panel(
                    title: '输出到电脑',
                    icon: Icons.output_rounded,
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      DropdownButtonFormField<int>(
                        value: devices.any((d) => (d['id'] as num).toInt() == outputIndex) ? outputIndex : null,
                        isExpanded: true,
                        hint: const Text('选择 Windows 输出设备'),
                        items: devices.map((d) => DropdownMenuItem<int>(
                          value: (d['id'] as num).toInt(),
                          child: Text(d['name'].toString(), overflow: TextOverflow.ellipsis),
                        )).toList(),
                        onChanged: (v) async {
                          if (v != null) await core.call('SETOUT $v');
                          await refresh();
                        },
                      ),
                      const SizedBox(height: 10),
                      Text('推荐 CABLE Input；QQ / 微信 / ChatGPT 中选择 CABLE Output 作为麦克风。', style: TextStyle(color: kText.withValues(alpha: .52), fontSize: 12.5, height: 1.45)),
                    ]),
                  );
                  if (c.maxWidth >= 760) {
                    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: meters), const SizedBox(width: 14), Expanded(child: output)]);
                  }
                  return Column(children: [meters, const SizedBox(height: 14), output]);
                }),
                const SizedBox(height: 14),
                _Panel(
                  title: '麦克风音量',
                  icon: Icons.mic_rounded,
                  child: Column(children: [
                    _DbSlider(label: '输入增益', value: gainDb, min: -12, max: 18, onChanged: (v) => dragParam('gain_db', v), onChangeEnd: (v) => finishDrag('gain_db', v)),
                    Row(children: [
                      const Expanded(child: Text('麦克风', style: TextStyle(fontWeight: FontWeight.w600))),
                      Switch(value: !muted, onChanged: (v) => unawaited(setParam('muted', !v))),
                    ]),
                  ]),
                ),
                const SizedBox(height: 14),
                _Panel(
                  title: '降噪',
                  icon: Icons.noise_control_off_rounded,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('实时抑制办公室底噪、风扇等稳定环境噪声。', style: TextStyle(color: kText.withValues(alpha: .52), fontSize: 12.5)),
                    const SizedBox(height: 14),
                    SegmentedButton<int>(
                      segments: const [
                        ButtonSegment(value: 0, label: Text('关闭')),
                        ButtonSegment(value: 1, label: Text('轻度')),
                        ButtonSegment(value: 2, label: Text('标准')),
                        ButtonSegment(value: 3, label: Text('强力')),
                      ],
                      selected: {denoise},
                      showSelectedIcon: false,
                      onSelectionChanged: (s) => unawaited(setParam('denoise', s.first)),
                    ),
                  ]),
                ),
                const SizedBox(height: 14),
                _Panel(
                  title: '三段 EQ',
                  icon: Icons.equalizer_rounded,
                  child: Column(children: [
                    _DbSlider(label: '低频', value: lowDb, min: -12, max: 12, onChanged: (v) => dragParam('eq_low_db', v), onChangeEnd: (v) => finishDrag('eq_low_db', v)),
                    _DbSlider(label: '中频', value: midDb, min: -12, max: 12, onChanged: (v) => dragParam('eq_mid_db', v), onChangeEnd: (v) => finishDrag('eq_mid_db', v)),
                    _DbSlider(label: '高频', value: highDb, min: -12, max: 12, onChanged: (v) => dragParam('eq_high_db', v), onChangeEnd: (v) => finishDrag('eq_high_db', v)),
                  ]),
                ),
              ],
            ),
            ), // Fix4 diagnostic Listener
          ),
        ]),
      ]),
    );
  }
}

class _Background extends StatelessWidget {
  const _Background();
  @override
  Widget build(BuildContext context) => const DecoratedBox(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF080D17), Color(0xFF0D1422), Color(0xFF090E19)],
      ),
    ),
  );
}

class _TitleBar extends StatelessWidget {
  const _TitleBar({required this.onExit});
  final Future<void> Function() onExit;
  @override
  Widget build(BuildContext context) => SizedBox(
    height: 44,
    child: Row(children: [
      const Expanded(child: DragToMoveArea(child: SizedBox.expand())),
      IconButton(onPressed: windowManager.minimize, icon: const Icon(Icons.remove_rounded, size: 17)),
      IconButton(onPressed: () async { StableLog.event('MAX_BUTTON_CLICK'); if (await windowManager.isMaximized()) { await windowManager.unmaximize(); } else { await windowManager.maximize(); } }, icon: const Icon(Icons.crop_square_rounded, size: 17)),
      IconButton(onPressed: windowManager.close, icon: const Icon(Icons.close_rounded, size: 17)),
    ]),
  );
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.coreOnline, required this.phoneOnline});
  final bool coreOnline, phoneOnline;
  @override
  Widget build(BuildContext context) {
    final color = !coreOnline ? kBad : (phoneOnline ? kGood : kText.withValues(alpha: .5));
    final text = !coreOnline ? '核心未启动' : (phoneOnline ? '手机已连接' : '等待手机');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(color: color.withValues(alpha: .10), borderRadius: BorderRadius.circular(99)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 7, height: 7, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 7),
        Text(text, style: const TextStyle(fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.title, required this.icon, required this.child});
  final String title;
  final IconData icon;
  final Widget child;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(19),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [Icon(icon, color: kAccent, size: 20), const SizedBox(width: 9), Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700))]),
        const SizedBox(height: 15),
        child,
      ]),
    ),
  );
}

class _InfoTile extends StatelessWidget {
  const _InfoTile({required this.title, required this.value, required this.good});
  final String title, value;
  final bool good;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(13),
    decoration: BoxDecoration(color: kText.withValues(alpha: .035), borderRadius: BorderRadius.circular(13)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: TextStyle(fontSize: 11.5, color: kText.withValues(alpha: .48))),
      const SizedBox(height: 5),
      Row(children: [
        Container(width: 6, height: 6, decoration: BoxDecoration(shape: BoxShape.circle, color: good ? kGood : kText.withValues(alpha: .35))),
        const SizedBox(width: 7),
        Expanded(child: Text(value, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600))),
      ]),
    ]),
  );
}

class _Meter extends StatelessWidget {
  const _Meter({required this.label, required this.db});
  final String label;
  final double db;
  @override
  Widget build(BuildContext context) {
    final v = ((db + 60) / 60).clamp(0.0, 1.0);
    final color = v > .9 ? kBad : (v > .72 ? kWarn : kGood);
    return Column(children: [
      Row(children: [
        Expanded(child: Text(label)),
        Text('${db.toStringAsFixed(1)} dB', style: TextStyle(color: kText.withValues(alpha: .55), fontFeatures: const [FontFeature.tabularFigures()])),
      ]),
      const SizedBox(height: 7),
      ClipRRect(borderRadius: BorderRadius.circular(99), child: LinearProgressIndicator(value: v, minHeight: 8, backgroundColor: kText.withValues(alpha: .08), color: color)),
    ]);
  }
}

class _DbSlider extends StatelessWidget {
  const _DbSlider({required this.label, required this.value, required this.min, required this.max, required this.onChanged, required this.onChangeEnd});
  final String label;
  final double value, min, max;
  final ValueChanged<double> onChanged, onChangeEnd;
  @override
  Widget build(BuildContext context) => Row(children: [
    SizedBox(width: 72, child: Text(label)),
    Expanded(child: Slider(value: value.clamp(min, max), min: min, max: max, onChanged: onChanged, onChangeEnd: onChangeEnd)),
    SizedBox(width: 74, child: Text('${value.toStringAsFixed(1)} dB', textAlign: TextAlign.right, style: TextStyle(color: kText.withValues(alpha: .55), fontFeatures: const [FontFeature.tabularFigures()]))),
  ]);
}
