import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';

import 'diag_log.dart';
import 'onnx_runtime_ffi.dart';

/// MODNet 权重在 assets 里的位置（`assets/models/` 已在 pubspec 里声明，
/// 所以把 .onnx 丢进去**不需要改 pubspec**）。
const String kModnetAssetPath = 'assets/models/modnet.onnx';

/// int8 量化版（6.6MB）：NPU（NNAPI）最爱吃的格式，质量与 fp32 几乎无损
/// （PC 实测输出分布 mean 0.675 vs fp32 0.672）。只在 NNAPI 真挂上时才用它——
/// int8 在纯 CPU 上反而比 fp32 慢 2 倍（实测）。
const String kModnetInt8AssetPath = 'assets/models/modnet_int8.onnx';

/// 人像抠图引擎：输入 RGB 像素，输出 0~1 的**软 alpha**。
///
/// 约定（调用方只需记这两条）：
/// * [load] 失败返回 false，[matting] 失败返回 null —— **永不抛异常**，
///   所以调用方（UI）不可能拿到英文异常/堆栈。
/// * [matting] 是**非阻塞跳帧**语义：上一次推理还没回来时立即返回 null，
///   调用方沿用上一帧 alpha 即可（这就是 30fps 方案里的"跳帧插值"）。
abstract class MattingEngine {
  /// 加载模型（幂等）。失败返回 false。
  Future<bool> load();

  /// [rgb] 长度 >= w*h*3；返回长度 = [inputH]×[inputW] 的软 alpha；失败返回 null。
  Future<Float32List?> matting(Uint8List rgb, int w, int h);

  Future<void> dispose();

  /// 模型输入张量的高（NCHW 的 [2]）。★支持非方形，见 OrtSession.inputH 的说明。
  int get inputH;

  /// 模型输入张量的宽（NCHW 的 [3]）
  int get inputW;

  /// 连续错误次数。★**跳帧不算错误**（上一次还没推完就返回 null 是正常节流），
  /// 调用方据此判断"引擎是不是真的坏了"，到阈值才熔断。
  int get errorStreak;

  /// 诊断串（执行提供器 / ORT 版本 / 输入尺寸），只给 HUD 和日志用
  String get diag;

  /// ★最近一次失败的原因（原始文本，排障用；正常时为空串）。
  /// 容器里没有 logcat，这个字符串会被直接显示在画面上。
  String get lastError;
}

/// 基于 ONNX Runtime + MODNet 的实现。
///
/// * 推理跑在**独立 isolate**，主 isolate 只做合成与上屏，绝不卡 UI。
/// * 复用 App 里已有的 `libonnxruntime.so`（sherpa_onnx 提供），不新增 .so。
/// * 首启把 assets 里的 .onnx 拷到 `ApplicationSupport/models/`（ORT 吃文件路径）。
///
/// ★为什么输入只用 256（而模型官方是 512）：
///   MODNet 导出的 ONNX 输入是**动态轴**，可以直接喂 256×256。
///   实测（桌面 CPU，同一张半身人像，见 `直播/_matting_work/bench.txt`）：
///     512×512 → 309ms，384 → 160ms，**256 → 78ms**（intra_op=3）
///   而掩膜和 512 的一致性极高：IoU@0.5 = 0.9976、MAE = 0.0036。
///   也就是说 256 用 1/4 的算力换到几乎一样的抠像结果，是这个模型上最划算的一档。
class ModnetMattingEngine implements MattingEngine {
  ModnetMattingEngine({
    this.assetPath = kModnetAssetPath,
    this.threads = 3,
    this.preferSize = 256,
    this.preferW,
    this.preferH,
  });

  final String assetPath;
  final int threads;

  /// 模型输入是动态轴时用的边长（模型若写死尺寸则以模型为准）
  final int preferSize;

  /// 动态轴时的目标输入宽 / 高。★传了就用非方形（画面同长宽比），
  /// 这样画面 100% 进模型 —— 既不裁掉上下、也不留边。
  final int? preferW;
  final int? preferH;

  Isolate? _iso;
  SendPort? _cmd;
  ReceivePort? _rsp;
  final Map<int, Completer<Map<Object?, Object?>?>> _pending = {};
  int _seq = 0;
  bool _ready = false;
  bool _busy = false; // 上一帧还没推完 → 本帧直接跳过（跳帧）
  int _inputH = 512;
  int _inputW = 512;
  int _errStreak = 0;
  String _lastError = '';

  @override
  String diag = '';

  @override
  int get errorStreak => _errStreak;

  @override
  String get lastError => _lastError;

  @override
  int get inputH => _inputH;

  @override
  int get inputW => _inputW;

  bool get isReady => _ready;

  @override
  Future<bool> load() async {
    if (_ready) return true;
    try {
      // ---- 尝试组合（从最优到兜底）----
      // ① int8 + NNAPI：NPU 加速，帧率质变（手机已确认 ORT 注册了
      //    NnapiExecutionProvider）。要求 provider 真挂上，否则 int8 在纯
      //    CPU 上比 fp32 慢 2 倍（实测）→ 直接弃用换下一组。
      // ② fp32 + XNNPACK：现状兜底（纯 CPU 优化）。
      const attempts = <String, String>{
        kModnetInt8AssetPath: 'NNAPI',
        kModnetAssetPath: 'XNNPACK',
      };
      final rp = ReceivePort();
      _rsp = rp;
      final portReady = Completer<SendPort>();
      rp.listen((dynamic m) {
        if (m is SendPort) {
          if (!portReady.isCompleted) portReady.complete(m);
          return;
        }
        _onMessage(m);
      });
      _iso = await Isolate.spawn(_modnetWorker, rp.sendPort);
      _cmd = await portReady.future.timeout(const Duration(seconds: 10));
      DiagLog.instance.log('MATTING', '推理 isolate 就绪');

      for (final entry in attempts.entries) {
        final path = await _ensureModelFile(entry.key);
        DiagLog.instance.log('MATTING',
            '尝试 ${entry.key}（provider=${entry.value}）→ ${path ?? "模型落盘失败"}');
        if (path == null) {
          _lastError = '模型资产落盘失败: ${entry.key}';
          continue;
        }
        final r = await _send(<String, Object?>{
          'cmd': 'load',
          'id': _seq++,
          'path': path,
          'threads': threads,
          'size': preferSize,
          'iw': preferW,
          'ih': preferH,
          'provider': entry.value,
        }, const Duration(seconds: 90));
        if (r == null) {
          _lastError = 'load 超时/无响应（90s）';
          DiagLog.instance.log('MATTING', _lastError);
          continue;
        }
        if (r['ok'] != true) {
          _lastError = 'load 失败: ${r['err'] ?? "worker 返回 ok=false"}';
          DiagLog.instance.log('MATTING', _lastError);
          continue;
        }
        final active = (r['provider'] as String?) ?? '';
        final gotNnapi = active.toLowerCase().contains('nnapi');
        if (entry.key == kModnetInt8AssetPath && !gotNnapi) {
          // NNAPI 没吃上 → int8 留在 CPU 太慢，worker 会重建 session 换模型
          DiagLog.instance.log('MATTING', 'NNAPI 未生效（$active），弃用 int8');
          continue;
        }
        _inputH = (r['h'] as int?) ?? (r['size'] as int?) ?? 512;
        _inputW = (r['w'] as int?) ?? (r['size'] as int?) ?? 512;
        if (_inputH <= 0) _inputH = 512;
        if (_inputW <= 0) _inputW = 512;
        final model = entry.key == kModnetInt8AssetPath ? 'int8' : 'fp32';
        diag = '$active · $model · ${_inputW}x$_inputH';
        _ready = true;
        DiagLog.instance.log('MATTING', 'MODNet 就绪：$diag');
        return true;
      }
      if (_lastError.isEmpty) {
        _lastError = '所有尝试都失败（NNAPI/int8 与 XNNPACK/fp32 均不可用）';
      }
      DiagLog.instance.log('MATTING', _lastError);
      diag = '';
      return false;
    } catch (e) {
      _lastError = '加载链路异常: $e';
      DiagLog.instance.log('MATTING', _lastError);
      diag = '';
      return false;
    }
  }

  @override
  Future<Float32List?> matting(Uint8List rgb, int w, int h) async {
    if (!_ready || _cmd == null) {
      _lastError = '引擎未就绪（ready=$_ready）';
      _errStreak++;
      return null;
    }
    if (_busy) return null; // ★跳帧：推理还在跑，本帧沿用上一帧 alpha（不算错误）
    if (w <= 0 || h <= 0 || rgb.length < w * h * 3) {
      _lastError = '入参异常 w=$w h=$h rgb=${rgb.length}';
      _errStreak++;
      return null;
    }
    _busy = true;
    try {
      final r = await _send(<String, Object?>{
        'cmd': 'run',
        'id': _seq++,
        'rgb': rgb,
        'w': w,
        'h': h,
      }, const Duration(seconds: 5));
      final a = r?['alpha'];
      if (a is! Float32List) {
        // ★把 worker 的真实错误（ORT 报错 / 异常文本）带出来
        _lastError = r == null
            ? '推理请求超时/无响应（5s，引擎忙或已卡死）'
            : '${r['err'] ?? "worker 未返回 alpha"} '
                '（in=${r['in'] ?? '?'} 出元素=${r['outN'] ?? '?'}）';
        _errStreak++;
        return null;
      }
      _errStreak = 0;
      _lastError = '';
      return a;
    } catch (e) {
      _lastError = '推理取回失败: $e';
      _errStreak++;
      return null;
    } finally {
      _busy = false;
    }
  }

  @override
  Future<void> dispose() async {
    try {
      _cmd?.send(<String, Object?>{'cmd': 'dispose', 'id': _seq++});
    } catch (_) {}
    await Future<void>.delayed(const Duration(milliseconds: 40));
    _iso?.kill(priority: Isolate.immediate);
    _iso = null;
    _cmd = null;
    _rsp?.close();
    _rsp = null;
    _pending.clear();
    _ready = false;
    _busy = false;
  }

  /// 把 assets 里的模型拷到可读写的应用目录（ORT 需要文件路径）。
  /// 拷贝在**主 isolate** 完成（rootBundle 只能在主 isolate 用），但只是一次性的。
  Future<String?> _ensureModelFile(String assetPath) async {
    try {
      final dir = await getApplicationSupportDirectory();
      final base = assetPath.split('/').last;
      final target = File('${dir.path}${Platform.pathSeparator}models'
          '${Platform.pathSeparator}$base');
      final data = await rootBundle.load(assetPath);
      final len = data.lengthInBytes;
      if (len <= 0) return null;
      if (await target.exists() && await target.length() == len) {
        return target.path;
      }
      await target.parent.create(recursive: true);
      await target.writeAsBytes(
        data.buffer.asUint8List(data.offsetInBytes, len),
        flush: true,
      );
      debugPrint('[MATTING] 模型已就位: ${target.path} ($len B)');
      return target.path;
    } catch (e) {
      DiagLog.instance.log('MATTING', '模型准备失败($assetPath): $e');
      return null;
    }
  }

  Future<Map<Object?, Object?>?> _send(
      Map<String, Object?> msg, Duration timeout) {
    final cmd = _cmd;
    if (cmd == null) return Future<Map<Object?, Object?>?>.value(null);
    final id = msg['id'] as int;
    final c = Completer<Map<Object?, Object?>?>();
    _pending[id] = c;
    cmd.send(msg);
    return c.future.timeout(timeout, onTimeout: () {
      _pending.remove(id);
      return null;
    });
  }

  void _onMessage(dynamic m) {
    if (m is! Map) return;
    final id = m['id'];
    if (id is! int) return;
    final c = _pending.remove(id);
    if (c == null || c.isCompleted) return;
    c.complete(m);
  }
}

// ==================================================================
// 后台推理 isolate
// ==================================================================

Future<void> _modnetWorker(SendPort replyPort) async {
  final rp = ReceivePort();
  replyPort.send(rp.sendPort);
  OrtSession? sess;
  await for (final dynamic msg in rp) {
    if (msg is! Map) continue;
    final id = msg['id'];
    final cmd = msg['cmd'];
    try {
      if (cmd == 'load') {
        // 支持"换模型/provider 重建"：先释放旧 session
        sess?.dispose();
        sess = null;
        sess = OrtSession.open(
          msg['path'] as String,
          threads: (msg['threads'] as int?) ?? 3,
          preferSize: (msg['size'] as int?) ?? 512,
          preferW: msg['iw'] as int?,
          preferH: msg['ih'] as int?,
          preferProvider: (msg['provider'] as String?) ?? 'XNNPACK',
        );
        final s = sess;
        if (s == null) {
          replyPort.send(<String, Object?>{
            'id': id,
            'ok': false,
            'err': OrtSession.lastOpenError.isEmpty
                ? 'OrtSession.open 返回 null'
                : OrtSession.lastOpenError,
          });
        } else {
          final providers = OrtSession.availableProviders();
          debugPrint('[MATTING] ORT 执行提供器: $providers');
          debugPrint('[MATTING] 实际使用: ${s.activeProvider} · '
              '输入 ${s.inputW}x${s.inputH} · 类型 ${s.inputElementType}');
          replyPort.send(<String, Object?>{
            'id': id,
            'ok': true,
            'w': s.inputW,
            'h': s.inputH,
            'provider': s.activeProvider,
            'version': s.ortVersion,
            'providers': providers,
          });
        }
      } else if (cmd == 'run') {
        final s = sess;
        if (s == null) {
          replyPort.send(<String, Object?>{'id': id});
          continue;
        }
        _fillInput(s, msg['rgb'] as Uint8List, msg['w'] as int, msg['h'] as int);
        final alpha = s.run();
        replyPort.send(<String, Object?>{
          'id': id,
          'alpha': alpha,
          'err': alpha == null ? s.lastError : null,
          'in': '${s.inputW}x${s.inputH}',
          'outN': s.outputElementCount,
        });
      } else if (cmd == 'dispose') {
        sess?.dispose();
        sess = null;
        rp.close();
        break;
      }
    } catch (e) {
      debugPrint('[MATTING] 推理异常: $e');
      replyPort.send(<String, Object?>{'id': id, 'err': '$e'});
    }
  }
}

/// RGB(w×h) → NCHW(S×S) 且归一化到 [-1,1]（MODNet 官方预处理：
/// `rescale 1/255` + `mean .5` + `std .5` → `x/127.5 - 1`）。
///
/// 双线性降采样：直接把相机大图缩到模型输入尺寸，不做中间全尺寸拷贝。
void _fillInput(OrtSession s, Uint8List rgb, int w, int h) {
  final iw = s.inputW;
  final ih = s.inputH;
  final plane = iw * ih;
  final asFloat = s.inputElementType == kOrtTypeFloat;
  final f = s.inputF32;
  final u = s.inputU8;

  // 快路径：调用方已经按模型输入尺寸给好了（view 层就是这么做的），
  // 直接逐像素写 NCHW，省掉一次"恒等双线性"。
  if (w == iw && h == ih) {
    final n = plane;
    if (asFloat) {
      for (int i = 0, p = 0; i < n; i++) {
        f[i] = rgb[p] / 127.5 - 1.0;
        f[plane + i] = rgb[p + 1] / 127.5 - 1.0;
        f[plane * 2 + i] = rgb[p + 2] / 127.5 - 1.0;
        p += 3;
      }
    } else {
      for (int i = 0, p = 0; i < n; i++) {
        u[i] = rgb[p];
        u[plane + i] = rgb[p + 1];
        u[plane * 2 + i] = rgb[p + 2];
        p += 3;
      }
    }
    return;
  }

  final xr = w > 1 ? (w - 1) / (iw - 1) : 0.0;
  final yr = h > 1 ? (h - 1) / (ih - 1) : 0.0;

  for (int y = 0; y < ih; y++) {
    final fy = y * yr;
    final y0 = fy.floor();
    final y1 = y0 + 1 < h ? y0 + 1 : h - 1;
    final ty = fy - y0;
    final row0 = y0 * w;
    final row1 = y1 * w;
    final outRow = y * iw;
    for (int x = 0; x < iw; x++) {
      final fx = x * xr;
      final x0 = fx.floor();
      final x1 = x0 + 1 < w ? x0 + 1 : w - 1;
      final tx = fx - x0;

      final i00 = (row0 + x0) * 3;
      final i01 = (row0 + x1) * 3;
      final i10 = (row1 + x0) * 3;
      final i11 = (row1 + x1) * 3;
      final b00 = (1 - tx) * (1 - ty);
      final b01 = tx * (1 - ty);
      final b10 = (1 - tx) * ty;
      final b11 = tx * ty;

      final o = outRow + x;
      for (int c = 0; c < 3; c++) {
        final v = rgb[i00 + c] * b00 +
            rgb[i01 + c] * b01 +
            rgb[i10 + c] * b10 +
            rgb[i11 + c] * b11;
        if (asFloat) {
          f[c * plane + o] = v / 127.5 - 1.0;
        } else {
          final q = v.round();
          u[c * plane + o] = q < 0 ? 0 : (q > 255 ? 255 : q);
        }
      }
    }
  }
}
