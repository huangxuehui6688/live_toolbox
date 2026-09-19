import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:tflite_flutter/tflite_flutter.dart';

import 'matting_engine.dart';

/// MODNet 转 tflite 的 GPU 抠像引擎（标准算子，Mali GPU 兼容版）。
///
/// * 用 tflite_flutter 的 **GPU delegate（OpenGL ES 3.1 compute）** 跑端侧 GPU。
///   （容器已确认透传 GLES 3.2，见 GpuProbeChannel。）
/// * 模型：`assets/models/modnet_gpu.tflite`（litert-community/MODNet-LiteRT，
///   26MB，专门修过 Mali fp16 溢出，GPU corr 0.99994）。
/// * 输入 512×512 RGB、归一化 [-1,1]；输出 512×512 软 alpha [0,1]。
/// * 实现 MattingEngine 接口 → 复用现有 view 层的「转正裁方 → 推理 → 逆变换贴回」，
///   上层无需改动。
class TfliteGpuEngine implements MattingEngine {
  TfliteGpuEngine({this.threads = 4});

  final int threads;

  Interpreter? _it;
  int _inputSize = 512;
  int _errStreak = 0;
  bool _nchw = true; // 模型输入是 NCHW 还是 NHWC（从 tensor shape 判断）
  int _outIdx = 0;
  Float32List? _inBuf;
  Float32List? _outBuf;
  List<int> _inShape = const [1, 3, 512, 512];

  @override
  String diag = '';

  /// 上次加载失败的原因（HUD 显示用，排查容器兼容性）
  String lastFailReason = '';

  @override
  int get errorStreak => _errStreak;

  @override
  int get inputH => _inputSize;

  @override
  int get inputW => _inputSize;

  @override
  Future<bool> load() async {
    if (_it != null) return true;
    // ★GPU delegate 初始化可能挂起（容器里 EGL 无 surface 时），必须带超时，
    //   否则整个 AI 加载链被卡死（实测表现：fps 掉到 2、AI 永远不出来）。
    //   超时/失败直接 return false → 上层回退 onnx CPU 引擎（可用性优先）。
    const t = Duration(seconds: 25);
    String lastErr = '';
    try {
      final opts = InterpreterOptions()..addDelegate(GpuDelegateV2());
      _it = await Interpreter.fromAsset(
        'assets/models/modnet_gpu.tflite',
        options: opts,
      ).timeout(t);
    } catch (e) {
      lastErr = '$e';
      debugPrint('[TFLITE] GPU delegate 失败/超时: $e');
      try { await dispose(); } catch (_) {}
      diag = '';
      lastFailReason = 'GPU失败: ${lastErr.length > 60 ? lastErr.substring(0, 60) : lastErr}';
      return false;
    }
    try {
      final inputs = _it!.getInputTensors();
      final outputs = _it!.getOutputTensors();
      _inShape = inputs.first.shape;
      _inputSize = _inShape.length >= 4 ? _inShape[2] : 512;
      // NCHW（shape[1]==3）vs NHWC（shape[3]==3）
      _nchw = _inShape.length >= 4 && _inShape[1] == 3;
      _outIdx = 0;
      final outShape = outputs.first.shape;
      final outSize = outShape.length >= 3
          ? (outShape[1] * outShape[2] * outShape[3])
          : _inputSize * _inputSize;
      _outBuf = Float32List(outSize);
      _inBuf = Float32List(_inShape.fold(1, (a, b) => a * b));
      diag = 'TFLite[gpu] ${_inShape}';
      debugPrint('[TFLITE] 就绪: $diag');
      return true;
    } catch (e) {
      debugPrint('[TFLITE] 读 tensor 失败: $e');
      diag = '';
      _it?.close();
      _it = null;
      return false;
    }
  }

  @override
  Future<Float32List?> matting(Uint8List rgb, int w, int h) async {
    final it = _it;
    if (it == null) {
      _errStreak++;
      return null;
    }
    final s = _inputSize;
    if (w != s || h != s) {
      // 调用方应已按 inputSize 给方形图；不一致则无法正确映射，直接报错计数
      _errStreak++;
      return null;
    }
    try {
      _fillInput(rgb, s);
      final out = _outBuf!;
      final outMap = <int, Object>{_outIdx: out};
      it.runForMultipleInputs(<Object>[_inBuf!], outMap);
      // 输出若含 batch 维，返回的仍是 s*s 的 alpha
      final alpha = Float32List(s * s);
      final n = s * s;
      // 直接拷贝（out 长度应 == n 或含 batch=1）
      final src = out;
      final off = src.length - n;
      for (int i = 0; i < n; i++) {
        final v = src[off + i];
        alpha[i] = v < 0 ? 0.0 : (v > 1 ? 1.0 : v);
      }
      _errStreak = 0;
      return alpha;
    } catch (e) {
      debugPrint('[TFLITE] 推理失败: $e');
      _errStreak++;
      return null;
    }
  }

  /// rgb(s×s×3) → 模型输入（NCHW 或 NHWC，[-1,1]）
  void _fillInput(Uint8List rgb, int s) {
    final n = s * s;
    final buf = _inBuf!;
    if (_nchw) {
      for (int i = 0, p = 0; i < n; i++) {
        final r = rgb[p++], g = rgb[p++], b = rgb[p++];
        buf[i] = r / 127.5 - 1.0;
        buf[n + i] = g / 127.5 - 1.0;
        buf[n * 2 + i] = b / 127.5 - 1.0;
      }
    } else {
      // NHWC
      for (int i = 0, p = 0, o = 0; i < n; i++) {
        buf[o++] = rgb[p++] / 127.5 - 1.0;
        buf[o++] = rgb[p++] / 127.5 - 1.0;
        buf[o++] = rgb[p++] / 127.5 - 1.0;
      }
    }
  }

  @override
  Future<void> dispose() async {
    try {
      _it?.close();
    } catch (_) {}
    _it = null;
    _inBuf = null;
    _outBuf = null;
  }
}
