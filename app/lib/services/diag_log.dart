import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;

/// 端侧排障日志开关。排障期 true，发版前改 false（不影响任何功能）。
const bool kDiagLogOn = true;

/// 本机排障台地址（PC 内网 IP:端口）。手机不在同一网段时收不到，属正常。
const String kDiagHost = '192.168.3.67:18899';

/// 端侧排障日志。
///
/// ★为什么非要有它：华为鸿蒙（卓易通容器）里**没有 logcat**——
///   `hdc shell logcat` 直接 "inaccessible or not found"，hilog 里也看不到
///   容器内 App 的输出。所以真机现场只能靠两条"带得出来"的通道：
///     ① 落到手机「下载」目录的 `livetoolbox_diag.txt`（`hdc file recv` 直接取）
///     ② HTTP 打到本机排障台（手机不用连电脑，PC 收）
///   两条同时写，任一条通就能拿到现场；两条都不通也只是丢日志，不影响直播。
///
/// 写入策略：内存攒批 + 定时刷盘（2 秒 / 攒够 40 行），**绝不逐行 fsync**，
/// 避免日志本身拖慢主链路。超过 [_maxBytes] 自动停写，防止塞爆手机。
class DiagLog {
  DiagLog._();

  static final DiagLog instance = DiagLog._();

  static const int _maxBytes = 512 * 1024;

  /// 容器里 Android「下载」目录可能的挂载点，挨个试，第一个可写的就用
  static const List<String> _dirs = <String>[
    '/sdcard/Download',
    '/storage/emulated/0/Download',
    '/storage/media/100/local/files/Docs/Download',
  ];

  final List<String> _buf = <String>[];
  File? _file;
  bool _started = false;
  int _written = 0;
  Timer? _timer;

  /// App 启动时调一次。之后 [log] 才有效（未 start 时只打印不落盘）。
  void start() {
    if (!kDiagLogOn) return;
    if (_started) return;
    _started = true;
    _timer = Timer.periodic(const Duration(seconds: 2), (_) => _flush());
  }

  /// 停掉定时刷盘（测试用；正常运行期一直开着）
  void stop() {
    _timer?.cancel();
    _timer = null;
    _started = false;
  }

  void log(String tag, String msg) {
    final line = '${DateTime.now().toIso8601String().substring(11, 23)} '
        '[$tag] $msg';
    debugPrint(line);
    if (!kDiagLogOn) return;
    if (_buf.length < 400) _buf.add(line);
    if (_buf.length >= 40) _flush();
  }

  Future<void> _flush() async {
    if (_buf.isEmpty) return;
    final lines = _buf.take(40).toList();
    _buf.removeRange(0, lines.length);
    final body = lines.join('\n');
    await _toFile(body);
    _beacon(body);
  }

  Future<void> _toFile(String body) async {
    try {
      final f = await _target();
      if (f == null) return;
      if (_written > _maxBytes) return; // 到顶就不写了（防爆）
      _written += body.length;
      await f.writeAsString('$body\n', mode: FileMode.append, flush: true);
    } catch (_) {
      // 落盘失败不影响直播，静默
    }
  }

  /// 找到第一个可写的「下载」目录，并把本次运行的日志清零重开
  Future<File?> _target() async {
    final cached = _file;
    if (cached != null) return cached;
    for (final dir in _dirs) {
      try {
        final d = Directory(dir);
        if (!await d.exists()) {
          await d.create(recursive: true); // 有的容器里目录还没建
        }
        final f = File('$dir${Platform.pathSeparator}livetoolbox_diag.txt');
        await f.writeAsString('', flush: true); // 每次启动重开，只留本次现场
        _file = f;
        return f;
      } catch (_) {
        // 这个挂载点不可写，试下一个
      }
    }
    return null;
  }

  /// 打到 PC 排障台。收不到就当没这回事——它不是功能路径。
  void _beacon(String body) {
    unawaited(() async {
      try {
        final c = HttpClient()..connectionTimeout = const Duration(seconds: 2);
        final req = await c
            .postUrl(Uri.parse('http://$kDiagHost/dbg'))
            .timeout(const Duration(seconds: 3));
        req.headers.contentType = ContentType.text;
        req.add(utf8.encode(body));
        await req.close().timeout(const Duration(seconds: 3));
        c.close(force: true);
      } catch (_) {}
    }());
  }
}
