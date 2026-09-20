import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';

import 'diag_log.dart';
import 'onnx_runtime_ffi.dart';

/// 挂上硬件加速后，允许的最长单次**纯推理**耗时（ms）。超过就往下退一档尺寸。
/// ★口径不能只看推理：一整轮的周期还包含后处理与等下一帧（约 130ms），
///   所以预算是按「**周期 ≤ ~320ms（≥3fps）**」倒推的 → 推理 ≤ 180ms。
///   老板的头号痛点就是「一动遮罩就延迟跟着」，所以宁可尺寸小一点，也不把延迟做大。
const int kAiBudgetMs = 180;

/// 自适应输入尺寸候选（宽×高，都是 32 的倍数、长宽比≈9:16）——**从大到小**试，
/// 取第一个「跑得进预算」的：越大，遮罩边缘越细（放大到 1300+ 物理像素越不糊）。
/// CPU 配置实测扫描的总时间预算（ms）。超了就提前收工 ——
/// 宁可少试两组，也不能把"AI 出不来"拖太久。
const int kSweepBudgetMs = 20000;

/// ★配置实测扫描的开关。**默认关**。
///
/// 为什么关掉：这台机器上 UI 线程与推理**抢同一份 CPU**，
/// 而 `bench` 是在"没人抢"的启动期测的 —— 同一个基线配置，
/// bench 说 98ms、真实运行却 449ms（差 4.6 倍）。用它比较配置会**选错**，
/// 上一版就是这样把 session 留在"并行模式"上、整版变慢的。
/// 要重启这个实验，必须先让 bench 在有负载时也准（或改成用真实运行耗时比较）。
const bool kCfgSweep = false;

/// 启动期要在真机上实测的一组配置（模型 × 执行模式 × 线程数）。
///
/// 为什么必须实测：这些量在桌面和手机上**结论相反** ——
///   · int8 在 x86 上比 fp32 慢近一倍，但 ARM64 的 ORT 有专门的 int8 GEMM
///     （sdot/udot），很可能反过来快一大截；
///   · 移动 SoC 是 big.LITTLE，"线程开满"会被摊到小核上互抢，常常更慢；
///   · 并行执行模式对多分支的图有用，但也可能因竞争变慢。
/// 所以不猜，逐个重开 session + 真实推理计时。（每次约 2~4s，条目刻意少。）
class CpuCfg {
  const CpuCfg(this.label, this.model, this.par, this.threads, this.gain);
  final String label;
  final String model;
  final bool par;
  final int threads;

  /// 必须比当前最优**再快**这个比例才采纳（<1）。int8 有画质风险，门槛更高。
  final double gain;
}

const List<CpuCfg> kCpuCfgs = <CpuCfg>[
  CpuCfg('int8顺序', kModnetInt8AssetPath, false, 5, 0.72),
  CpuCfg('fp32顺序3线程', kModnetAssetPath, false, 3, 0.90),
  CpuCfg('fp32并行5线程', kModnetAssetPath, true, 5, 0.90),
];

const List<List<int>> kAutoMattingSizes = <List<int>>[
  <int>[384, 672],
  <int>[288, 512],
  <int>[192, 352],
];

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

  /// ★最近一次**纯推理**耗时（ms，不含采样与后处理）。0 = 还没跑过。
  int get lastInferMs;

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
  int lastInferMs = 0;

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

  /// 当前挂上的是不是"真硬件/向量加速"（NNAPI=NPU/GPU、XNNPACK=ARM 向量优化）。
  static bool _isAccel(String p) {
    final s = p.toLowerCase();
    return s.contains('nnapi') || s.contains('xnnpack');
  }

  static int _inWOf(Map<Object?, Object?> r) {
    final w = (r['w'] as int?) ?? (r['size'] as int?) ?? 512;
    return w <= 0 ? 512 : w;
  }

  static int _inHOf(Map<Object?, Object?> r) {
    final h = (r['h'] as int?) ?? (r['size'] as int?) ?? 512;
    return h <= 0 ? 512 : h;
  }

  /// 在当前 session 上测一次纯推理耗时（ms）。<0 = 测不出来（别据此改任何东西）。
  Future<int> _benchAt(int w, int h) async {
    final br = await _send(<String, Object?>{
      'cmd': 'bench',
      'id': _seq++,
      'w': w,
      'h': h,
    }, const Duration(seconds: 60));
    return (br?['ms'] as int?) ?? -1;
  }

  /// 换配置重开 session 并测一次；返回耗时（ms），失败 -1。
  Future<int> _reopenAndBench(String path, int tt, String prov, int w, int h,
      {bool par = false}) async {
    final rr = await _send(<String, Object?>{
      'cmd': 'load',
      'id': _seq++,
      'path': path,
      'threads': tt,
      'size': h,
      'iw': w,
      'ih': h,
      'provider': prov,
      'par': par,
    }, const Duration(seconds: 90));
    if (rr == null || rr['ok'] != true) return -1;
    return _benchAt(w, h);
  }

  @override
  Future<bool> load() async {
    if (_ready) return true;
    try {
      // ---- 尝试组合（从最优到兜底）----
      // ① int8 + NNAPI：NPU 加速，帧率质变（手机已确认 ORT 注册了
      //    NnapiExecutionProvider）。要求 provider 真挂上，否则 int8 在纯
      //    CPU 上比 fp32 慢 2 倍（实测）→ 直接弃用换下一组。
      // ② fp32 + XNNPACK：现状兜底（纯 CPU 优化）。
      // 尝试顺序：加速器（按理论收益）→ CPU 兜底。
      // ★fp32 排在 int8 前面：int8 只在**真挂上 NNAPI** 时才划算（纯 CPU 上 int8
      //   比 fp32 慢近一倍，桌面实测），而 fp32 无论挂 NNAPI / XNNPACK 都不吃亏，
      //   而且 fp32 的遮罩质量明显更稳（int8 在发丝/眼镜边会掉细节）。
      // ★'CPU' 是兜底：不挂任何 EP，用 ORT 默认的 CPU。
      const attempts = <List<String>>[
        <String>[kModnetAssetPath, 'NNAPI'],
        <String>[kModnetInt8AssetPath, 'NNAPI'],
        <String>[kModnetAssetPath, 'XNNPACK'],
        <String>[kModnetAssetPath, 'CPU'],
      ];
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

      // ★先枚举一次运行时注册的执行提供器，用来**剪枝**：
      //   本机没注册的加速器直接跳过 —— 否则 4 组依次试（每组都要加载 25MB 模型、
      //   还可能各等一次 90s 超时），很容易把外层 45s 的加载超时耗光，
      //   现场表现就是「AI 一直不出来」。
      final rtProvs = OrtSession.availableProviders();
      OrtSession.lastProviders = rtProvs;
      DiagLog.instance.log('MATTING', '运行时执行提供器: ${rtProvs.join("/")}');

      // ★每个失败组合的**原始原因**都攒起来、最后一起上 HUD。
      //   容器里没有 logcat，而"最后一个成功的组合"会把中间失败原因覆盖掉 ——
      //   上一版就是这样把 NNAPI 的真实报错吞了，白跑一轮。
      final fails = <String>[];
      for (final entry in attempts) {
        if (entry[1] != 'CPU' && rtProvs.isNotEmpty) {
          final w = entry[1].toLowerCase();
          if (!rtProvs.any((n) => n.toLowerCase().contains(w))) {
            DiagLog.instance.log('MATTING', '跳过 ${entry[1]}：运行时未注册');
            continue;
          }
        }
        final path = await _ensureModelFile(entry[0]);
        DiagLog.instance.log('MATTING',
            '尝试 ${entry[0]}（provider=${entry[1]}）→ ${path ?? "模型落盘失败"}');
        if (path == null) {
          _lastError = '模型资产落盘失败: ${entry[0]}';
          fails.add('${entry[1]}:模型落盘失败');
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
          'provider': entry[1],
        }, const Duration(seconds: 90));
        if (r == null) {
          _lastError = 'load 超时/无响应（90s）';
          DiagLog.instance.log('MATTING', _lastError);
          fails.add('${entry[1]}:超时');
          continue;
        }
        if (r['ok'] != true) {
          _lastError = 'load 失败: ${r['err'] ?? "worker 返回 ok=false"}';
          DiagLog.instance.log('MATTING', _lastError);
          fails.add('${entry[1]}:${r['err'] ?? "ok=false"}');
          continue;
        }
        final active = (r['provider'] as String?) ?? '';
        final gotNnapi = active.toLowerCase().contains('nnapi');
        if (entry[0] == kModnetInt8AssetPath && !gotNnapi) {
          // NNAPI 没吃上 → int8 留在 CPU 太慢，worker 会重建 session 换模型
          DiagLog.instance.log('MATTING', 'NNAPI 未生效（$active），弃用 int8');
          fails.add('${entry[1]}:未生效');
          continue;
        }
        var pickedW = _inWOf(r);
        var pickedH = _inHOf(r);

        // ---- ★自适应输入尺寸（只在**真挂上硬件加速**时才做）----
        // "抠像看着不清晰"的头号来源就是模型输入太小：192 宽 → 遮罩的有效边缘
        // 分辨率只有 192px，铺到 1300+ 物理像素的屏幕上必然是一圈糊边。
        // 但纯 CPU 上放大就是自杀（192 宽都要 350ms/次）—— **先挂上 NPU/XNNPACK，
        // 才有资格放大**。这里用"真实推理计时"从大到小阶梯试探，而不是拍一个尺寸：
        // 拍大了直接掉到 1fps，拍小了白瞎了硬件。
        if (_isAccel(active)) {
          for (final c in kAutoMattingSizes) {
            final lr = await _send(<String, Object?>{
              'cmd': 'load',
              'id': _seq++,
              'path': path,
              'threads': threads,
              'size': c[1],
              'iw': c[0],
              'ih': c[1],
              'provider': entry[1],
            }, const Duration(seconds: 90));
            // 重建失败（该尺寸硬件不吃 / 超时）→ 保留上一个成功尺寸
            if (lr == null || lr['ok'] != true) break;
            final br = await _send(<String, Object?>{
              'cmd': 'bench',
              'id': _seq++,
              'w': c[0],
              'h': c[1],
            }, const Duration(seconds: 60));
            final ms = (br?['ms'] as int?) ?? -1;
            DiagLog.instance.log(
                'MATTING', '自适应尺寸 ${c[0]}x${c[1]} → ${ms}ms（预算 $kAiBudgetMs）');
            if (ms <= 0) break; // 测不出来 → 别乱改
            pickedW = c[0];
            pickedH = c[1];
            if (ms <= kAiBudgetMs) break; // 跑得动 → 就它
          }
        }
        _inputW = pickedW;
        _inputH = pickedH;

        // ---- ★CPU 配置实测扫描（纯 CPU 路径才有意义）----
        // 见 kCpuCfgs 的说明：这些量在桌面和手机上结论相反，只能实测。
        // 这一步是启动期一次性成本（每组都要重开 session = 重新加载模型），
        // 换来的是**之后每一帧**的推理时间 —— 而"alpha 多久刷新一次"直接决定
        // 人动了遮罩跟不跟得上（老板的头号痛点）。
        var bestMs = -1;
        var bestLabel = '基线';
        if (kCfgSweep && !_isAccel(active)) {
          bestMs = await _benchAt(pickedW, pickedH);
          DiagLog.instance.log('MATTING',
              '基线（${entry[0].split('/').last} 顺序 $threads 线程）→ ${bestMs}ms');
          // ★起点就是"基线配置"，它同样要参与比较与**回滚** ——
          //   上一版只在"有候选胜出"时才回滚，结果 session 被留在了**最后试的
          //   那个候选**（并行模式）上：实测推理 202ms → 449ms，整版变慢。
          var curModel = entry[0];
          var curPar = false;
          var curT = threads;
          var bestModel = entry[0];
          var bestPar = false;
          var bestT2 = threads;
          final t0s = DateTime.now();
          for (final c in kCpuCfgs) {
            if (DateTime.now().difference(t0s).inMilliseconds > kSweepBudgetMs) {
              DiagLog.instance.log('MATTING', '配置扫描超出预算，提前收工');
              break;
            }
            if (c.model == curModel && c.par == curPar && c.threads == curT) {
              continue;
            }
            final mp = await _ensureModelFile(c.model);
            if (mp == null) continue;
            final ms = await _reopenAndBench(
                mp, c.threads, entry[1], pickedW, pickedH, par: c.par);
            if (ms < 0) continue;
            curModel = c.model;
            curPar = c.par;
            curT = c.threads;
            DiagLog.instance.log('MATTING', '${c.label} → ${ms}ms');
            if (bestMs < 0 || ms < bestMs * c.gain) {
              bestMs = ms;
              bestLabel = c.label;
              bestModel = c.model;
              bestPar = c.par;
              bestT2 = c.threads;
            }
          }
          // ★无条件确保 session 停在最优配置上（**基线也算**）——
          //   省掉这一步正是上次"整版变慢"的直接原因，别再省。
          if (bestModel != curModel || bestPar != curPar || bestT2 != curT) {
            final mp = await _ensureModelFile(bestModel);
            if (mp != null) {
              final back = await _reopenAndBench(
                  mp, bestT2, entry[1], pickedW, pickedH, par: bestPar);
              DiagLog.instance.log('MATTING', '回滚到 $bestLabel → ${back}ms');
            }
          }
          DiagLog.instance.log('MATTING', '选定配置 $bestLabel（$bestMs ms）');
        }
        final model = entry[0] == kModnetInt8AssetPath ? 'int8' : 'fp32';
        // ★没挂上加速时，把「本机注册了哪些提供器 / 动态轴钉住了没 / 每个组合
        //   到底报什么错」全写进 HUD —— 一张截图定位完，不用再猜、不用再白跑一轮。
        final provs = (r['providers'] as List?)?.join('/') ?? '';
        final pin = OrtSession.lastPinLog;
        var failTxt = fails.join(' | ');
        if (failTxt.length > 90) failTxt = failTxt.substring(0, 90);
        diag = '$active · $model · ${_inputW}x$_inputH'
            '${bestMs > 0 ? ' · $bestLabel(${bestMs}ms)' : ''}'
            ' · 库[${OrtSession.probeRuntimeLibs()}]'
            '${_isAccel(active) ? '' : ' · 可用[$provs]'}'
            '${_isAccel(active) ? '' : ' · 钉轴[${pin.isEmpty ? "无" : pin}]'}'
            '${_isAccel(active) || failTxt.isEmpty ? '' : ' · 败[$failTxt]'}';
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
      final tm = r?['tMs'];
      if (tm is int && tm > 0) lastInferMs = tm;
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
          parMode: (msg['par'] as bool?) ?? false,
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
        final t0r = DateTime.now();
        _fillInput(s, msg['rgb'] as Uint8List, msg['w'] as int, msg['h'] as int);
        final alpha = s.run();
        final tMs = DateTime.now().difference(t0r).inMilliseconds;
        replyPort.send(<String, Object?>{
          'id': id,
          'alpha': alpha,
          'err': alpha == null ? s.lastError : null,
          'in': '${s.inputW}x${s.inputH}',
          'outN': s.outputElementCount,
          'tMs': tMs,
        });
      } else if (cmd == 'bench') {
        // 只服务"开播前自适应尺寸"：拿纯色假图跑 2 次，取**较小**耗时。
        // ★必须取两次的较小值：第 1 次往往包含图优化/硬件编译（NNAPI 尤其慢），
        //   拿第一次的耗时会误判成"这个尺寸跑不动"，从而白白退到小尺寸。
        final s = sess;
        final bw = msg['w'] as int;
        final bh = msg['h'] as int;
        final dummy = Uint8List(bw * bh * 3);
        // ★必须用**有纹理**的假图：全 0 输入会让访存/缓存表现过于理想
        //   （实测基线 bench 说 98ms、真跑却 449ms，差 4 倍，就是被它骗的）。
        for (int q = 0; q < dummy.length; q++) {
          dummy[q] = (q * 37 + (q >> 5) * 11) & 0xFF;
        }
        var best = -1;
        var err = '';
        if (s != null) {
          for (int k = 0; k < 2; k++) {
            final t0b = DateTime.now();
            _fillInput(s, dummy, bw, bh);
            final ab = s.run();
            final ms = DateTime.now().difference(t0b).inMilliseconds;
            if (ab == null) {
              err = s.lastError;
              break;
            }
            if (best < 0 || ms < best) best = ms;
          }
        }
        replyPort.send(<String, Object?>{
          'id': id,
          'ok': best >= 0,
          'ms': best,
          'err': err,
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
