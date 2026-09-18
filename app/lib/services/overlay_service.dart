import 'dart:async';
import 'dart:developer' as dev;
import 'dart:isolate';
import 'dart:ui';

import 'package:flutter/services.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';

/// 主 App 与悬浮窗之间通信用的命名端口（与 teleprompter_overlay.dart 保持一致）。
const String kOverlayHomePort = 'teleprompter_overlay_home_port';
const String kOverlayPort = 'teleprompter_overlay_port';

/// 自建的悬浮窗权限通道（原生实现见 android/.../OverlayPermissionChannel.kt）。
///
/// 插件自带的 requestPermission() 在华为鸿蒙（卓易通容器）上会落到应用列表页，
/// 用户得一个个翻找本应用；这里优先走自建通道：先查后弹、带包名直达本应用
/// 的授权页（一个开关），插件仅作为兜底保留。
const MethodChannel _overlayPermissionChannel =
    MethodChannel('live_toolbox/overlay_permission');

/// 悬浮窗权限申请结果（与原生多态字符串一一对应）。
///
/// 状态机核心：自动弹系统设置页全局只发生一次，之后交给 UI 弹中文指引层，
/// 用户必须主动去点，杜绝「授权死循环」。
enum OverlayPermResult {
  /// 已授权
  granted,

  /// 打开了系统页但用户没给（自动弹这一轮已置 planBFlag，下次不再自动弹）
  denied,

  /// 自动弹已发生过一次，交回 UI 弹中文指引层
  needGuide,

  /// 本会话「手动重开设置页」已达上限，UI 只显示指引
  guideOnly,

  /// 系统里找不到可用授权页
  unavailable,
}

OverlayPermResult _parsePermResult(String? r) {
  switch (r) {
    case 'granted':
      return OverlayPermResult.granted;
    case 'denied':
      return OverlayPermResult.denied;
    case 'needGuide':
      return OverlayPermResult.needGuide;
    case 'guideOnly':
      return OverlayPermResult.guideOnly;
    default:
      return OverlayPermResult.unavailable;
  }
}

/// 提词器系统悬浮窗载体（单例）。
///
/// 悬浮窗跑在 flutter_overlay_window 创建的独立 Flutter engine 里，与主 App
/// 处于同一进程。两者通过 [IsolateNameServer] 命名的 SendPort 交换消息（主 engine
/// 与悬浮窗 engine 共享进程级端口名注册表）。
///
/// 通信协议（SendPort 传输的 Map）：
/// - 主 -> 悬浮窗：`{'type': 'lines', 'lines': List<String>, 'index': int}`
///   换话术并重置进度；`{'type': 'index', 'index': int}` 更新当前行。
/// - 悬浮窗 -> 主：`{'type': 'close'}` 请求关闭。
class OverlayService {
  OverlayService._() {
    _init();
  }

  static final OverlayService instance = OverlayService._();

  final ReceivePort _receivePort = ReceivePort();
  SendPort? _overlayPort;

  bool _isShowing = false;

  bool get isShowing => _isShowing;

  void _init() {
    IsolateNameServer.registerPortWithName(
      _receivePort.sendPort,
      kOverlayHomePort,
    );
    _receivePort.listen(_onMessage);
    _resetSessionFlags();
  }

  /// 会话开始（App 冷启动）时重置「本会话手动重开」标记。
  ///
  /// manualReopenUsed 存的是原生 SharedPreferences（持久化），但语义是「同会话只
  /// 1 次」；这里在单例首次创建时清一次，让每次冷启动都能再手动重开一次。旧安装包
  /// 没有该通道时静默忽略。
  Future<void> _resetSessionFlags() async {
    try {
      await _overlayPermissionChannel.invokeMethod<dynamic>('resetSession');
    } on MissingPluginException {
      // 旧安装包没有该通道，忽略
    } on PlatformException {
      // 忽略
    }
  }

  void _onMessage(dynamic message) {
    // 悬浮窗里的关闭按钮请求关闭
    if (message is Map && message['type'] == 'close') {
      hide();
    }
  }

  /// 是否有悬浮窗权限。
  ///
  /// 优先用自建通道读原生的 Settings.canDrawOverlays（最权威）；通道不可用时
  /// 回退到插件的 isPermissionGranted，保证任何安装包都不会卡在这里。
  Future<bool> hasPermission() async {
    try {
      final bool? v =
          await _overlayPermissionChannel.invokeMethod<bool>('hasPermission');
      if (v != null) return v;
    } on MissingPluginException {
      // 通道不存在（例如还没带上新原生代码的旧安装包），走插件兜底
    } on PlatformException catch (e) {
      dev.log('原生查询悬浮窗权限失败，回退插件: $e', name: 'OverlayService');
    }
    return FlutterOverlayWindow.isPermissionGranted();
  }

  /// 请求悬浮窗权限（状态机第一入口）。
  ///
  /// 原生侧按「已授权 / 首次自动弹 / 已置 planBFlag」三态返回，具体见
  /// [OverlayPermResult]。只有原生通道整个不存在（旧安装包）时才回退插件。
  Future<OverlayPermResult> requestPermission() async {
    if (await hasPermission()) return OverlayPermResult.granted;

    try {
      final String? r = await _overlayPermissionChannel
          .invokeMethod<String>('requestPermission');
      return _parsePermResult(r);
    } on MissingPluginException {
      // 原生通道不存在（例如还没带上新原生代码的旧安装包）→ 走插件兜底
    } on PlatformException catch (e) {
      dev.log('原生申请悬浮窗权限失败: $e', name: 'OverlayService');
      return OverlayPermResult.unavailable;
    }

    // 兜底：插件实现（同样会打开系统授权页）
    try {
      final bool? r = await FlutterOverlayWindow.requestPermission();
      return (r ?? false) ? OverlayPermResult.granted : OverlayPermResult.denied;
    } on PlatformException catch (e) {
      dev.log('插件申请悬浮窗权限失败: $e', name: 'OverlayService');
      return OverlayPermResult.unavailable;
    }
  }

  /// 用户主动点「仍然不行？手动打开系统设置页」（状态机第二入口）。
  ///
  /// 原生侧按 manualReopenUsed 限流：同会话只放行 1 次，之后返回 guideOnly。
  Future<OverlayPermResult> openManualPermission() async {
    if (await hasPermission()) return OverlayPermResult.granted;

    try {
      final String? r =
          await _overlayPermissionChannel.invokeMethod<String>('openManual');
      return _parsePermResult(r);
    } on MissingPluginException {
      // 原生通道不存在 → 走插件兜底
    } on PlatformException catch (e) {
      dev.log('原生手动打开设置页失败: $e', name: 'OverlayService');
      return OverlayPermResult.unavailable;
    }

    try {
      final bool? r = await FlutterOverlayWindow.requestPermission();
      return (r ?? false) ? OverlayPermResult.granted : OverlayPermResult.denied;
    } on PlatformException catch (e) {
      dev.log('插件申请悬浮窗权限失败: $e', name: 'OverlayService');
      return OverlayPermResult.unavailable;
    }
  }

  /// 显示悬浮窗（台词按行拆分）
  Future<bool> show(List<String> lines) async {
    dev.log('show() 开始 lines=${lines.length}', name: 'OverlayService');
    final hasP = await hasPermission();
    dev.log('show() hasPermission=$hasP', name: 'OverlayService');
    if (!hasP) return false;
    if (_isShowing) {
      await FlutterOverlayWindow.closeOverlay();
      _isShowing = false;
    }

    // 注意：插件的 showOverlay 把 height 当像素用（与 resizeOverlay 的 dp 不一致），
    // 这里按 devicePixelRatio 换算成 px。
    final double dpr = PlatformDispatcher.instance.views.first.devicePixelRatio;
    final int heightPx = (240 * dpr).round();

    dev.log('show() 调 showOverlay height=$heightPx', name: 'OverlayService');
    await FlutterOverlayWindow.showOverlay(
      height: heightPx,
      width: WindowSize.matchParent,
      alignment: OverlayAlignment.topCenter,
      // focusPointer(FLAG_NOT_TOUCH_MODAL)：悬浮窗窄条之外的触摸穿透给抖音，
      // 主播才能边播边操作抖音；窄条内部可拖动、可点按钮。
      flag: OverlayFlag.focusPointer,
      enableDrag: true,
      positionGravity: PositionGravity.none,
      startPosition: const OverlayPosition(0, 110),
      overlayTitle: '提词器悬浮窗',
      overlayContent: '台词已开启，可拖动调整位置',
    );
    dev.log('show() showOverlay 完成', name: 'OverlayService');
    _isShowing = true;
    // 悬浮窗 engine 在 MainActivity attach 时异步启动，冷启动后极快开启悬浮窗时
    // 其 Dart isolate 可能尚未注册好通信端口，直接 send 会丢首帧台词。先等它就绪。
    await _waitForOverlayPort();
    dev.log('show() 等待端口完成，port=${IsolateNameServer.lookupPortByName(kOverlayPort) != null}',
        name: 'OverlayService');
    _send({'type': 'lines', 'lines': lines, 'index': -1});
    return true;
  }

  /// 等待悬浮窗 engine 注册好通信端口（最多 3s）。
  /// engine 是懒加载常驻的，通常几百毫秒内就绪；这里只兜底冷启动极快操作的竞态。
  Future<void> _waitForOverlayPort() async {
    final sw = Stopwatch()..start();
    while (sw.elapsedMilliseconds < 3000) {
      if (IsolateNameServer.lookupPortByName(kOverlayPort) != null) return;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    dev.log('等待悬浮窗端口超时（3s）', name: 'OverlayService');
  }

  /// 更新当前行（0-based，-1=未开始）
  Future<void> updateLine(int index) async {
    if (!_isShowing) return;
    _send({'type': 'index', 'index': index});
  }

  /// 换一套话术
  Future<void> updateLines(List<String> lines) async {
    if (!_isShowing) return;
    _send({'type': 'lines', 'lines': lines, 'index': -1});
  }

  /// 关闭悬浮窗
  Future<void> hide() async {
    if (!_isShowing) return;
    _isShowing = false;
    await FlutterOverlayWindow.closeOverlay();
  }

  void _send(Map<String, dynamic> data) {
    _overlayPort ??= IsolateNameServer.lookupPortByName(kOverlayPort);
    final SendPort? port = _overlayPort;
    if (port != null) {
      port.send(data);
    } else {
      dev.log('悬浮窗 engine 尚未就绪，消息被丢弃', name: 'OverlayService');
    }
  }
}
