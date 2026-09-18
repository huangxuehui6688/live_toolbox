import 'dart:developer' as dev;
import 'dart:io';
import 'dart:isolate';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa_onnx;

/// 统一日志入口：dart:developer 的 log 会输出到真机 logcat（tag=TTS），
/// 比 debugPrint 可靠（debugPrint 在部分场景被节流/吞掉，导致定位不到问题）。
void _log(String msg) => dev.log(msg, name: 'TTS');

/// 端侧中文 TTS 服务（sherpa-onnx VITS）。
///
/// 用法：
///   await TtsService.instance.init();
///   await TtsService.instance.speak('欢迎新进直播间的家人');
///
/// 模型：assets/tts/vits-zh-aishell3/（AISHELL3 数据集，可商用，多说话人）。
/// 首启时把模型从 asset 复制到应用支持目录（sherpa 需要真实文件路径）。
///
/// 音频生成（generate）跑在**后台 isolate** 里：39MB VITS 模型在 CPU 上生成
/// 长文本需要数秒~十几秒，若放在 UI isolate 会卡死界面、导致停止/试听无响应。
/// 因 sherpa-onnx 的 OfflineTts 是 FFI 对象、指针不能跨 isolate 复用，
/// 每次 speak 都会在后台 isolate 内重新 initBindings + 重新加载模型 + 生成 WAV，
/// 再把 WAV 路径传回主 isolate 用 audioplayers 播放。
class TtsService {
  TtsService._();
  static final TtsService instance = TtsService._();

  static const String _modelAssetDir = 'assets/tts/vits-zh-aishell3';

  /// 模型运行所需的全部文件（标准 sherpa-onnx vits-zh-aishell3 包内容）。
  ///
  /// 用显式清单而不是 AssetManifest 枚举目录，原因是：Flutter 对目录型
  /// asset（`- assets/tts/`）在增量构建时可能漏枚举「后加进目录」的文件，
  /// 导致运行时根本复制不到模型。显式清单 + 逐个 load，缺哪个能立刻定位。
  static const List<String> _modelFiles = [
    'vits-aishell3.int8.onnx',
    'lexicon.txt',
    'tokens.txt',
    'date.fst',
    'phone.fst',
    'number.fst',
    'new_heteronym.fst',
  ];

  final AudioPlayer _player = AudioPlayer();
  bool _ready = false;
  bool _initializing = false;

  /// 常驻后台 worker isolate：模型只加载一次，后续 speak 直接发消息生成，
  /// 避免 compute 每次新建 isolate + 重新加载 39MB 模型的 ~1s 开销。
  Isolate? _worker;
  SendPort? _workerSend;

  /// 单调递增的播报序号，用于「停止 / 最新一次播报」取消在途的生成结果。
  int _speakSeq = 0;

  /// 当前正在播放的 WAV 文件路径，用于清理上一次的临时文件。
  String? _activeWavPath;

  // ===== 预取（边播边合成流水线）=====
  /// 预取缓存：key = 'text|sid|speed' → 生成 Future（WAV 路径，失败 null）。
  /// ★把「已生成好」和「正在生成」合并成一张表：Future 会缓存结果，
  ///   speak() 命中时 await 一下立刻拿到——已经好的直接播、还在生成的等它，
  ///   绝不会再重复发一遍生成请求（worker 串行，重复发只会让播报更慢）。
  /// ★键用**这句话的文本本身**：预取永远不可能张冠李戴（只有一字不差才命中）。
  final Map<String, Future<String?>> _prefetched = {};

  /// 预取文件名序号。**不能复用 _speakSeq**——那会把正在播的这句直接取消掉。
  int _prefetchSeq = 0;

  bool get ready => _ready;

  /// 播放完成事件（用于驱动数字人说话动画的停止）。
  Stream<void> get onComplete => _player.onPlayerComplete.map((_) {});

  /// 初始化：绑定 sherpa 原生库 + 解包模型。
  ///
  /// 引擎实例在常驻后台 isolate 构造一次，后续 speak 直接发消息生成，
  /// 不再每次重新加载模型。
  Future<void> init() async {
    if (_ready) return;
    if (_initializing) return;
    _initializing = true;
    try {
      dev.log('[TtsService] step1 解包模型开始', name: 'TTS');
      final dir = await _unpackModel();
      dev.log('[TtsService] step2 解包模型完成 dir=$dir', name: 'TTS');

      dev.log('[TtsService] step3 spawn 常驻 worker 开始', name: 'TTS');
      await _spawnWorker(dir);
      dev.log('[TtsService] step4 worker 就绪（模型已加载）', name: 'TTS');

      _ready = true;
      dev.log('[TtsService] init 全部完成', name: 'TTS');
    } catch (e, st) {
      dev.log('[TtsService] init 失败: $e\n$st', name: 'TTS');
      rethrow;
    } finally {
      _initializing = false;
    }
  }

  /// spawn 常驻后台 worker isolate，等待其加载完模型并回传 SendPort。
  Future<void> _spawnWorker(String dir) async {
    final rp = ReceivePort();
    _worker = await Isolate.spawn(_ttsWorkerMain, [rp.sendPort, dir]);
    // worker 第一件事：回传它的 SendPort（此时模型已加载完成）
    _workerSend = await rp.first as SendPort;
    rp.close();
  }

  /// 把 asset 模型文件复制到应用支持目录，返回目录绝对路径。
  ///
  /// 逐个加载并校验落盘结果；任一必需文件缺失/为空都会抛 [StateError]，
  /// 并提示「模型未打包进 APK」这一最常见根因，便于排查。
  Future<String> _unpackModel() async {
    final base = await getApplicationSupportDirectory();
    final dir = p.join(base.path, 'tts', 'vits-zh-aishell3');
    await Directory(dir).create(recursive: true);

    final missing = <String>[];
    for (final name in _modelFiles) {
      final assetKey = '$_modelAssetDir/$name';
      final target = p.join(dir, name);
      try {
        final data = await rootBundle.load(assetKey);
        final f = File(target);
        if (!f.existsSync() || f.lengthSync() != data.lengthInBytes) {
          await f.parent.create(recursive: true);
          await f.writeAsBytes(
            data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
          );
          _log('[TtsService] 解包写出 $name (${data.lengthInBytes} bytes)');
        }
      } catch (e) {
        missing.add(name);
        _log('[TtsService] 解包失败 $name: $e');
      }
    }

    if (missing.isNotEmpty) {
      throw StateError(
        'TTS 模型资源缺失：[${missing.join(', ')}]。'
        '请确认 pubspec.yaml 已声明 - assets/tts/，并执行 '
        'flutter clean 后重新构建 APK（当前 APK 未打包这些资源）。',
      );
    }
    return dir;
  }

  /// 播报文字。生成（常驻后台 isolate）+ 写 WAV + 播放。
  /// speed 默认 1.35：VITS 默认语速偏慢显机械，调快接近真人说话节奏。
  ///
  /// ★签名、返回值、异常与取消语义都没变；只是**开头多一次预取命中检查**：
  ///   命中（同一句已经被 [prefetch] 生成好）就跳过一次生成、直接播，
  ///   播报的听感完全一样，只是快了几秒。没命中就是原来的老路径。
  Future<void> speak(String text, {int sid = 0, double speed = 1.35}) async {
    if (text.trim().isEmpty) return;
    if (!_ready) await init();
    final send = _workerSend;
    if (send == null) {
      _log('[TtsService] speak 失败：worker 未就绪');
      return;
    }

    final seq = ++_speakSeq;

    // ★预取命中：认领这份生成（已生成好 → 立刻拿到；还在生成 → 等它完成），
    //   跳过重复生成。键是文本本身，绝不会把别的句子播出来。
    final cached = _prefetched.remove(_prefetchKey(text, sid, speed));
    String? wavPath = cached == null ? null : await cached;

    if (wavPath == null) {
      // 没预取到（或预取这份生成失败了）→ 走现场生成的老路径
      final base = await getApplicationSupportDirectory();
      final path = p.join(base.path, 'tts_out_$seq.wav');

      dev.log('[TtsService] speak 开始 text=${text.length} 字 seq=$seq',
          name: 'TTS');

      try {
        // 发消息给常驻 worker：worker 用已加载的模型生成 + 写盘，回传完成信号。
        final reply = ReceivePort();
        send.send(<Object, Object>{
          'text': text,
          'sid': sid,
          'speed': speed,
          'wavPath': path,
          'reply': reply.sendPort,
        });
        final ok = await reply.first;
        reply.close();
        if (ok != 'ok') {
          throw StateError('worker 返回异常: $ok');
        }
      } catch (e, st) {
        dev.log('[TtsService] generate 失败: $e\n$st', name: 'TTS');
        _deleteQuietly(path);
        rethrow; // 抛给 UI，让试听按钮弹「试听失败」而非静默无反应
      }
      wavPath = path;
    } else {
      _log('[TtsService] speak 命中预取，跳过生成 seq=$seq');
    }

    if (seq != _speakSeq) {
      // 期间调用了 stop() 或又触发了新的 speak()，丢弃本次结果。
      _log('[TtsService] 本次播报已取消 seq=$seq（最新=$_speakSeq）');
      _deleteQuietly(wavPath);
      return;
    }

    await _player.stop();
    if (_activeWavPath != null && _activeWavPath != wavPath) {
      _deleteQuietly(_activeWavPath!);
    }
    _activeWavPath = wavPath;
    await _player.play(DeviceFileSource(wavPath));
    _log('[TtsService] 开始播放 $wavPath');
  }

  /// 预取：把这一句**先在后台生成好**（写 WAV 存着），但**不播**。
  /// 之后 `speak()` 传**完全相同的 text / sid / speed** 时会直接复用这份，
  /// 省掉生成耗时——逐句循环播报时，这一下就消掉了"句与句之间的静默"。
  ///
  /// ★为什么用"文本"当键、而不是"下一句的下标"：预取**永远不可能**张冠李戴。
  ///   只有一字不差地同一句才会命中；话术中途被改、用户切走，最坏结果只是
  ///   有条用不上的缓存被自动清掉，绝不会把过期音频播出来。
  ///
  /// ★它是纯优化：**任何失败都只进日志、不抛异常**，绝不能让播报跟着挂掉。
  ///
  /// ★已合并「已生成」和「正在生成」：同一句在生成中就只发一次，
  ///   speak() 命中时会 await 这份 Future（生成完了直接用、没完就等），
  ///   不会再重复发一遍生成请求。
  Future<void> prefetch(String text, {int sid = 0, double speed = 1.35}) async {
    if (text.trim().isEmpty) return;
    if (!_ready) await init();
    if (_workerSend == null) return;

    final k = _prefetchKey(text, sid, speed);
    if (_prefetched.containsKey(k)) return; // 已生成 / 正在生成 → 不重复做
    _prefetched[k] = _generatePrefetch(text, sid, speed);
    // ★不 await：后台预热；speak() 命中时自己会 await 这份 Future。
  }

  /// 后台预生成一句并写盘，返回 WAV 路径；失败返回 null（不抛异常，不影响播报）。
  Future<String?> _generatePrefetch(String text, int sid, double speed) async {
    final send = _workerSend;
    if (send == null) return null;
    final base = await getApplicationSupportDirectory();
    final path = p.join(base.path, 'tts_pre_${_prefetchSeq++}.wav');
    try {
      final reply = ReceivePort();
      send.send(<Object, Object>{
        'text': text,
        'sid': sid,
        'speed': speed,
        'wavPath': path,
        'reply': reply.sendPort,
      });
      final ok = await reply.first;
      reply.close();
      if (ok != 'ok') throw StateError('worker 返回异常: $ok');
      return path;
    } catch (e) {
      _log('[TtsService] 预取失败（忽略，正式播报时会重新生成）: $e');
      _deleteQuietly(path);
      return null;
    }
  }

  static String _prefetchKey(String text, int sid, double speed) =>
      '$text|$sid|$speed';

  /// 作废全部预取（连同临时文件）。stop() 时 worker 还活着，在途的会等它写完再删。
  Future<void> _clearPrefetch() async {
    final pending = _prefetched.values.toList();
    _prefetched.clear();
    for (final f in pending) {
      final path = await f;
      if (path != null) _deleteQuietly(path);
    }
  }

  Future<void> stop() async {
    // 使在途的生成结果失效，避免停止后又突然出声。
    _speakSeq++;
    // ★预取的也一起作废：既然停了，话术很可能已经变了，别留着过期音频占磁盘
    await _clearPrefetch();
    await _player.stop();
  }

  void dispose() {
    _speakSeq++;
    // 已完成未播的预取尽量删掉；在途的随 worker 一起作废（不 await，避免卡死）。
    for (final f in _prefetched.values) {
      f.then((path) {
        if (path != null) _deleteQuietly(path);
      });
    }
    _prefetched.clear();
    _deleteQuietly(_activeWavPath);
    _activeWavPath = null;
    _worker?.kill(priority: Isolate.immediate);
    _worker = null;
    _workerSend = null;
    _ready = false;
    _player.dispose();
  }

  void _deleteQuietly(String? path) {
    if (path == null) return;
    try {
      final f = File(path);
      if (f.existsSync()) f.deleteSync();
    } catch (e) {
      _log('[TtsService] 清理临时文件失败 $path: $e');
    }
  }
}

/// 常驻后台 worker isolate 主函数：加载模型一次，之后持续接收生成请求。
///
/// 协议：
/// - 入参 [mainSendPort, modelDir]
/// - worker 加载完模型后，立即向 mainSendPort 回传自己的 SendPort（表示就绪）
/// - 之后收到的消息是 Map{'text','sid','speed','wavPath','reply'(SendPort)}，
///   生成 + 写盘后向 reply 回传 'ok'（或错误字符串）
void _ttsWorkerMain(List<Object> args) {
  final mainSendPort = args[0] as SendPort;
  final dir = args[1] as String;

  dev.log('[TtsService] worker 开始 initBindings', name: 'TTS');
  sherpa_onnx.initBindings();

  final modelPath = p.join(dir, 'vits-aishell3.int8.onnx');
  final lexiconPath = p.join(dir, 'lexicon.txt');
  final tokensPath = p.join(dir, 'tokens.txt');
  final ruleFsts = [
    'date.fst',
    'phone.fst',
    'number.fst',
    'new_heteronym.fst',
  ].map((f) => p.join(dir, f)).join(',');

  final cfg = sherpa_onnx.OfflineTtsConfig(
    model: sherpa_onnx.OfflineTtsModelConfig(
      vits: sherpa_onnx.OfflineTtsVitsModelConfig(
        model: modelPath,
        lexicon: lexiconPath,
        tokens: tokensPath,
        dataDir: '',
        noiseScale: 0.667,
        noiseScaleW: 0.8,
        lengthScale: 0.9, // 略快语速
      ),
      numThreads: 4, // 多线程加速 CPU 生成
      debug: false,
      provider: 'cpu',
    ),
    ruleFsts: ruleFsts,
    ruleFars: '',
  );

  dev.log('[TtsService] worker 构造 OfflineTts 中', name: 'TTS');
  final tts = sherpa_onnx.OfflineTts(cfg);
  dev.log('[TtsService] worker 模型加载完成', name: 'TTS');

  // 回传自己的 SendPort，表示就绪
  final rp = ReceivePort();
  mainSendPort.send(rp.sendPort);

  rp.listen((msg) {
    final m = msg as Map;
    final reply = m['reply'] as SendPort;
    try {
      final audio = tts.generate(
        text: m['text'] as String,
        sid: m['sid'] as int,
        speed: m['speed'] as double,
      );
      if (audio.samples.isEmpty) {
        reply.send('error: 空音频');
        return;
      }
      final ok = sherpa_onnx.writeWave(
        filename: m['wavPath'] as String,
        samples: audio.samples,
        sampleRate: audio.sampleRate,
      );
      reply.send(ok ? 'ok' : 'error: 写盘失败');
    } catch (e) {
      reply.send('error: $e');
    }
  });
}
