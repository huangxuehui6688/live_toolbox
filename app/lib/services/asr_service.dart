import 'dart:async';
import 'dart:developer' show log;
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

/// 一句流式识别结果
class AsrResult {
  /// 当前累计识别出的文本（含标点）
  final String text;

  /// 是否为一句的结束（检测到句末静音）
  final bool isFinal;

  const AsrResult({required this.text, required this.isFinal});
}

/// 唯一的 ASR 接入点：跟读（提词器）和字幕（直播间）共用这一份。
///
/// 技术栈：端侧 sherpa-onnx + FunASR Paraformer 流式双语模型（带标点），
/// 音频采集用 record（16k / 单声道 / PCM16）。
class AsrService {
  AsrService._();
  static final AsrService instance = AsrService._();

  sherpa.OnlineRecognizer? _recognizer;
  sherpa.OnlineStream? _stream;
  AudioRecorder? _recorder;
  StreamSubscription<Uint8List>? _micSub;

  final StreamController<AsrResult> _ctrl =
      StreamController<AsrResult>.broadcast();

  /// 流式识别结果（每喂一段音频推一次）
  Stream<AsrResult> get results => _ctrl.stream;

  bool _initialized = false;
  bool _running = false;
  bool get isRunning => _running;

  /// 初始化 Future 复用：防止并发 start()/toggle 时重复加载模型
  Future<void>? _initFuture;

  /// 最近一次启动失败的原因（**供 UI 展示 → 只放中文人话**）
  /// 技术细节一律走 [_log]，不进这里，避免英文异常被甩到界面上。
  String? _lastError;
  String? get lastError => _lastError;

  static const String _modelDir =
      'assets/sherpa-onnx-streaming-zipformer-zh-14M-2023-02-23';

  /// 用 dart:developer 的 log() 输出：真机 logcat 里 tag=ASR，比 debugPrint 可靠得多。
  static void _log(String msg) => log(msg, name: 'ASR');

  Future<void> _init() {
    if (_initialized) return Future.value();
    // 并发保护：复用同一个初始化 Future，避免重复拷贝/加载模型
    return _initFuture ??= _doInit().whenComplete(() => _initFuture = null);
  }

  Future<void> _doInit() async {
    final sw = Stopwatch()..start();
    _log('初始化开始');

    // 1. 加载原生库（可能因 ABI 不匹配/缺 .so 抛异常）
    try {
      _log('调用 initBindings ...');
      sherpa.initBindings();
      _log('initBindings 完成 (${sw.elapsedMilliseconds}ms)');
    } catch (e, s) {
      _log('initBindings 失败: $e\n$s');
      throw Exception('sherpa-onnx 原生库加载失败: $e');
    }

    // 2. 拷贝模型到可读路径（首次启动慢，之后命中磁盘缓存）
    late final String encoder, decoder, joiner, tokens;
    try {
      encoder = await _copyAsset('$_modelDir/encoder-epoch-99-avg-1.int8.onnx');
      decoder = await _copyAsset('$_modelDir/decoder-epoch-99-avg-1.onnx');
      joiner = await _copyAsset('$_modelDir/joiner-epoch-99-avg-1.int8.onnx');
      tokens = await _copyAsset('$_modelDir/tokens.txt');
      _log('模型文件就绪 (${sw.elapsedMilliseconds}ms)');
    } catch (e, s) {
      _log('模型文件拷贝失败: $e\n$s');
      throw Exception('模型资源加载失败: $e');
    }

    // 3. 创建识别器（加载 ONNX，最耗时的一步）
    try {
      final config = sherpa.OnlineRecognizerConfig(
        model: sherpa.OnlineModelConfig(
          transducer: sherpa.OnlineTransducerModelConfig(
            encoder: encoder,
            decoder: decoder,
            joiner: joiner,
          ),
          tokens: tokens,
          modelType: 'zipformer',
          numThreads: 2,
          debug: false,
        ),
        enableEndpoint: true,
        // 提词器跟读要连续读稿，断句太快会导致累计文本被频繁清空、对齐滞后。
        // 放宽到 1.5s 静音才断句（默认 2.4s 太慢，1s 太激进）。
        rule1MinTrailingSilence: 1.5,
        rule2MinTrailingSilence: 0.8,
        rule3MinUtteranceLength: 8.0,
      );
      _recognizer = sherpa.OnlineRecognizer(config);
      _log('OnlineRecognizer 创建完成 (${sw.elapsedMilliseconds}ms)');
    } catch (e, s) {
      _log('识别器创建失败: $e\n$s');
      _recognizer?.free();
      _recognizer = null;
      throw Exception('识别器创建失败（模型配置或文件异常）: $e');
    }

    // 4. 创建识别流
    try {
      _stream = _recognizer!.createStream();
      _log('createStream 完成');
    } catch (e, s) {
      _log('createStream 失败: $e\n$s');
      _recognizer?.free();
      _recognizer = null;
      _stream = null;
      throw Exception('创建识别流失败: $e');
    }

    _recorder = AudioRecorder();
    _initialized = true;
    _log('初始化完成，总耗时 ${sw.elapsedMilliseconds}ms');
  }

  /// 启动识别（申请权限 → 加载模型 → 开流）
  ///
  /// 权限申请被提到最前面：用户拒绝时快速失败，避免先等数秒加载模型。
  Future<void> start() async {
    if (_running) {
      _log('start(): 已在运行，忽略');
      return;
    }
    _lastError = null;
    _log('start() 开始');

    // 1. 提前申请麦克风权限（record.hasPermission 默认会弹系统授权框）
    final probe = AudioRecorder();
    try {
      final granted = await probe
          .hasPermission()
          .timeout(const Duration(seconds: 20));
      if (!granted) {
        throw Exception('用户未授予麦克风权限');
      }
      _log('麦克风权限已授予');
    } catch (e) {
      _lastError = '麦克风权限申请失败，请检查系统权限设置';
      _log('麦克风权限申请失败: $e'); // 技术细节只进日志
      throw Exception(_lastError);
    } finally {
      await probe.dispose();
    }

    // 2. 初始化模型（首次冷启动会拷贝并加载 ONNX，耗时数秒到数十秒）
    try {
      await _init().timeout(const Duration(seconds: 90), onTimeout: () {
        _log('模型初始化超时（>90s），疑似原生 onnx 加载卡死');
        throw TimeoutException('ASR 模型加载超时（90s）');
      });
      _log('start(): 模型就绪');
    } catch (e) {
      _lastError = '语音识别功能初始化失败，请重试';
      _log('ASR 模型初始化失败: $e'); // 技术细节只进日志
      rethrow;
    }

    // 3. 启动录音流
    try {
      const config = RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 16000,
        numChannels: 1,
      );
      final stream = await _recorder!
          .startStream(config)
          .timeout(const Duration(seconds: 15));
      _running = true;
      _log('录音已启动');
      _micSub = stream.listen(_onAudio, onError: (Object e) {
        _log('录音流错误: $e');
      });
    } catch (e, s) {
      _lastError = '录音启动失败，请检查麦克风是否被其他应用占用';
      _log('启动录音失败: $e\n$s'); // 技术细节只进日志
      await stop();
      rethrow;
    }
  }

  int _audioCount = 0;
  String _lastText = '';
  void _onAudio(Uint8List data) {
    final recognizer = _recognizer;
    final stream = _stream;
    if (recognizer == null || stream == null) {
      _log('_onAudio: recognizer/stream 为空，丢弃本段音频');
      return;
    }

    _audioCount++;
    try {
      final samples = _bytesToFloat32(data);

      // 计算峰值，用于在 logcat 里判断麦克风是否真的采到了声音（排除静音）
      var peak = 0.0;
      for (final s in samples) {
        final a = s.abs();
        if (a > peak) peak = a;
      }
      if (_audioCount == 1 || _audioCount % 50 == 0) {
        _log('音频 #$_audioCount: ${data.lengthInBytes}B, '
            '样本=${samples.length}, 峰值=$peak');
      }

      stream.acceptWaveform(samples: samples, sampleRate: 16000);

      while (recognizer.isReady(stream)) {
        recognizer.decode(stream);
      }

      final result = recognizer.getResult(stream);
      if (result.text != _lastText) {
        _log('识别文本变化: "$_lastText" -> "${result.text}"');
        _lastText = result.text;
      }

      final isEndpoint = recognizer.isEndpoint(stream);
      if (isEndpoint) {
        recognizer.reset(stream);
      }
      if (!_ctrl.isClosed) {
        _ctrl.add(AsrResult(text: result.text, isFinal: isEndpoint));
      }
    } catch (e, s) {
      _log('音频处理异常: $e\n$s');
    }
  }

  /// 停止识别并复位流
  Future<void> stop() async {
    if (!_running) return;
    await _micSub?.cancel();
    _micSub = null;
    await _recorder?.stop();
    _running = false;

    _stream?.free();
    _stream = _recognizer?.createStream();
  }

  /// 释放所有资源（页面退出时调用）
  Future<void> dispose() async {
    await stop();
    _stream?.free();
    _stream = null;
    _recognizer?.free();
    _recognizer = null;
    await _recorder?.dispose();
    _recorder = null;
    _initialized = false;
    if (!_ctrl.isClosed) await _ctrl.close();
  }

  /// 把 asset 里的模型拷贝到可读路径（sherpa-onnx 需要文件路径）
  Future<String> _copyAsset(String src) async {
    final dir = await getApplicationSupportDirectory();
    final dst = p.join(dir.path, p.basename(src));
    final file = File(dst);
    final data = await rootBundle.load(src);
    final bytes =
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    if (!await file.exists() || await file.length() != bytes.length) {
      await file.writeAsBytes(bytes);
    }
    return dst;
  }

  /// PCM16 转 float32（sherpa-onnx 输入格式）
  ///
  /// 用 [ByteData.sublistView] 而非 `ByteData.view(bytes.buffer)`，这样能正确
  /// 处理 record 返回的可能是大缓冲区子视图（offsetInBytes != 0）的情况，
  /// 避免从错误的字节位置开始解析导致识别结果为空。
  Float32List _bytesToFloat32(Uint8List bytes) {
    final sampleCount = bytes.lengthInBytes ~/ 2;
    final values = Float32List(sampleCount);
    final data = ByteData.sublistView(bytes);
    for (var i = 0; i < sampleCount; i++) {
      values[i] = data.getInt16(i * 2, Endian.little) / 32768.0;
    }
    return values;
  }
}
