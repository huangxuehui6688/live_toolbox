import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import '../services/beauty_settings.dart';
import '../services/diag_log.dart';
import '../services/matting_engine.dart';

/// AI 抠像连续失败多少次即熔断（停止重试 + 自动降级到实景）。
const int kAiFailLimit = 8;

/// 真机实时相机 + 可选抠像换背景。
/// [enableSegmentation]=true：AI 人像抠像（MODNet + ONNX Runtime）+ 与 [background] 合成。
/// [enableSegmentation]=false：纯相机原图（实景模式，不抠像、不耗时）。
///
/// ★AI 抠像推理在**独立 isolate** 的 ONNX Runtime 里跑（复用 App 里 sherpa_onnx
///   带来的 libonnxruntime.so，不新增任何 .so / 依赖），主 isolate 只做合成上屏。
///   上一次推理没回来时本帧直接沿用上一帧 alpha（跳帧），所以预览不会卡住。
///
/// ★AI 抠像有熔断保护：连续失败 [kAiFailLimit] 次即停止调用模型（不再每帧重试），
///   并通过 [onSegmentationUnavailable] 通知父层自动降级到实景。
///   模型加载/推理失败同样走这条中文降级路径。
class VirtualBackgroundView extends StatefulWidget {
  final Gradient background;
  final bool mirror;
  final double strength; // 0~1，越大抠得越狠（阈值越高，背景越干净）
  final bool enableSegmentation;
  final bool useFront; // 前置/后置摄像头
  /// 真·色键抠像：-1=不做色键（纯 AI 抠像）；0=绿幕 1=红幕 2=蓝幕。
  /// 与 AI 抠像**取并集**（任一说"这是背景"就透明），所以有真幕布时更干净，
  /// 没幕布时退回 AI 效果，不会更差。
  final int keyColor;

  /// ★AI 抠像在这台设备上不可用时的回调（父层据此切到「实景」并提示用户）。
  /// 只在熔断触发时回调一次。
  final VoidCallback? onSegmentationUnavailable;

  const VirtualBackgroundView({
    super.key,
    required this.background,
    this.mirror = true,
    this.strength = .7,
    this.enableSegmentation = true,
    this.useFront = true,
    this.keyColor = -1,
    this.onSegmentationUnavailable,
  });

  @override
  State<VirtualBackgroundView> createState() => _VirtualBackgroundViewState();
}

class _VirtualBackgroundViewState extends State<VirtualBackgroundView> {
  CameraController? _camera;
  MattingEngine? _engine; // MODNet + ONNX Runtime（后台 isolate）
  /// ★上一帧的软 alpha（模型输出尺寸）。推理跳帧时本帧直接复用它。
  Float32List? _prevAlpha;
  /// 是否有一次推理还在路上（在途时不再发新请求 → 天然跳帧，出画不被阻塞）
  bool _aiReqPending = false;
  ui.Image? _frame;
  bool _busy = false;
  String _status = '初始化中…';
  double _fps = 0;
  int _frames = 0;
  DateTime _lastFps = DateTime.now();
  // ===== AI 抠像推理 fps（alpha 实际刷新率）=====
  // 只在拿到新 alpha 时计数，每秒结算一次并随现有 setState 上屏（不额外 setState）
  double _aiFps = 0;
  int _aiFrames = 0;
  int _frameOrientation = 0; // 当前 _frame 对应的传感器方向（切摄像头时冻结旧画面用）
  int _camGen = 0; // 摄像头"代号"：每次重建 +1，用于丢弃旧摄像头残留的帧
  bool _frameMirror = true; // ★当前 _frame 对应的"是否镜像"，与帧绑定（切摄像头时不串位）
  String _maskDbg = '';
  bool _loadingEngine = false; // ★引擎加载互斥锁：加载耗时期间每帧都会进 _loadEngine，防并发 spawn 多个引擎
  /// 诊断：掩膜尺寸/背景占比/均值（排查"抠像没生效"用）
  DateTime? _busySince; // 进入 _busy 的时刻（看门狗用）
  int _loadFails = 0; // 引擎"加载"失败次数（比单帧失败严重，2 次即熔断）

  // ===== ★B 方案：合成搬到 GPU =====
  /// true = 相机纹理零拷贝上屏 + alpha 当 ShaderMask 遮罩（GPU 合成）。
  /// false = 回到"每帧 CPU 全分辨率合成 + decode 全屏图"的老路径（代码原样保留）。
  static const bool kGpuComposite = true;

  ui.Image? _alphaImg; // 256² alpha 小图（RGBA 白底，只取 alpha 通道当遮罩）
  bool _alphaImgBusy = false; // 上一张还没建好就跳过（alpha 本身只有 2~4fps）
  int _alphaSeq = 0;
  bool _hasFrame = false; // 出过至少一帧（HUD 用它决定显不显示 fps）
  Size _frameSize = Size.zero; // 相机原始 buffer 尺寸（GPU 层算 cover 比例用）

  // ===== 耗时剖析（定位"为什么只有 7fps"：每帧各阶段分别烧多少毫秒）=====
  // 只在每秒结算一次时求平均并进 HUD，本身几乎零开销（6 次 now() + 整数累加）。
  int _tRgb = 0, _tSample = 0, _tAlpha = 0, _tDecode = 0, _tFrame = 0, _tN = 0;
  String _perfDbg = '';

  // ===== 跨帧复用的缓冲（避免每帧几十 MB 的分配触发 GC 抖动）=====
  Uint8List? _rgbaBuf; // 全分辨率 RGBA
  Uint8List? _aiRgbBuf; // 喂给模型的方形 RGB

  // ===== ★AI 抠像熔断（止血）=====
  // 背景：在卓易通等安卓兼容容器里 ML Kit 起不来，每帧都抛异常并被重试，
  //   既抠不出人像，又是手机发烫的主要来源。所以：连续失败到阈值就彻底停掉这条管线。
  int _aiFail = 0; // 连续失败计数（任一帧成功即清零）
  bool _aiOff = false; // 熔断已触发：不再创建/调用分割模型
  bool _fallbackNotified = false; // 降级提示只报一次，避免刷屏

  /// 是否真的走 AI 抠像：开了抠像、不是色布模式、且熔断未触发。
  bool get _useAi =>
      widget.enableSegmentation && widget.keyColor < 0 && !_aiOff;

  /// 是否需要画背景层：色布模式总是要；AI 抠像熔断后不画（等父层切实景）。
  bool get _needBackground =>
      widget.enableSegmentation && (widget.keyColor >= 0 || !_aiOff);

  @override
  void initState() {
    super.initState();
    _init();
    // 美颜参数变化时重绘
    BeautySettings.smooth.addListener(_onBeautyChanged);
    BeautySettings.whiten.addListener(_onBeautyChanged);
  }

  void _onBeautyChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(VirtualBackgroundView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 切换前后摄像头：重建 CameraController
    if (widget.useFront != oldWidget.useFront) {
      // _init() 会把 _camGen +1，旧摄像头的在途帧随即全部作废。
      // ★这是"点翻转先倒立一下"的根因：旧 controller.dispose() 后仍会有几帧回调进来，
      //   旧帧被按「新摄像头」的方向旋转 → 画面先歪/倒一下，再切过去。
      _camera?.dispose();
      _camera = null;
      // 保留上一帧画面（它已与自己的方向绑定），新帧到达前冻结显示，避免黑屏闪烁
      _init();
    }
    if (widget.enableSegmentation == oldWidget.enableSegmentation &&
        widget.keyColor == oldWidget.keyColor) {
      return;
    }
    // 实景 ↔ 抠像 / 换色布 切换：清空旧帧 + 重建或释放模型
    // ★用户主动重选（比如又点了「AI」）时给一次新机会：复位熔断计数与状态
    _aiFail = 0;
    _aiOff = false;
    _fallbackNotified = false;
    final old = _frame;
    _frame = null;
    old?.dispose();
    _prevAlpha = null; // 实景↔抠像 切换：清掉旧 alpha
    if (widget.enableSegmentation) {
      _status = widget.keyColor >= 0 ? '色键抠像' : 'AI 抠像';
      // 色布模式走纯色键，不需要分割模型
      if (_useAi) _loadEngine();
    } else {
      _status = '实景';
    }
  }

  @override
  void dispose() {
    BeautySettings.smooth.removeListener(_onBeautyChanged);
    BeautySettings.whiten.removeListener(_onBeautyChanged);
    _camera?.dispose();
    _engine?.dispose();
    _frame?.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    final gen = ++_camGen; // 本次初始化的代号（同步自增，立刻作废旧代）
    _prevAlpha = null; // 换摄像头/重建时清掉上一帧 alpha，避免时序串位
    final p = await Permission.camera.request();
    if (!p.isGranted) {
      if (mounted) setState(() => _status = '未授权相机权限');
      return;
    }
    if (gen != _camGen) return; // 期间用户又切了摄像头，放弃本次
    try {
      final cams = await availableCameras();
      if (cams.isEmpty) {
        if (mounted) setState(() => _status = '未检测到相机');
        return;
      }
      final lens = widget.useFront
          ? CameraLensDirection.front
          : CameraLensDirection.back;
      final cam = cams.firstWhere(
        (c) => c.lensDirection == lens,
        orElse: () => cams.first,
      );
      final orientation = cam.sensorOrientation; // ★方向随帧一起传递，不读共享字段
      final isFront = widget.useFront; // ★镜像也随帧一起传递（见 _frameMirror）
      if (gen != _camGen) return;
      _camera = CameraController(
        cam,
        // ★B 方案已上：合成搬到 GPU（相机纹理 + alpha 遮罩），分辨率不再拖帧率，
        //   所以这里回到 1080p —— 铺满全屏只需放大 ~1.2 倍，肉眼明显更清晰。
        //   ⚠️ 万一容器里 Texture 预览与图像流打架（画面卡住/不刷新），
        //      把 kGpuComposite 置 false 即回到老的 CPU 路径，那时再把这里改回 high。
        ResolutionPreset.veryHigh,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.nv21,
      );
      await _camera!.initialize();
      if (gen != _camGen) return;
      // 持续自动对焦（近距离拍摄时尤为关键；机型不支持就忽略）
      try {
        await _camera!.setFocusMode(FocusMode.auto);
      } catch (_) {}
      // 实景模式不抠像；色布模式走纯色键，两者都不需要分割模型
      if (widget.enableSegmentation && widget.keyColor < 0 && !_aiOff) {
        await _loadEngine();
      }
      await _camera!.startImageStream(
          (img) => _onFrame(img, gen, orientation, isFront));
      if (mounted && gen == _camGen) {
        setState(() => _status = !widget.enableSegmentation
            ? '实景'
            : (widget.keyColor >= 0
                ? '色键抠像'
                : (_engine == null ? 'AI 抠像不可用' : 'AI 抠像')));
      }
    } catch (e) {
      debugPrint('[SEG] 相机初始化失败: $e');
      if (mounted) setState(() => _status = '相机启动失败，请重试');
    }
  }

  /// 加载 AI 抠像引擎（MODNet + ONNX Runtime）。
  ///
  /// ★这条路**完全不碰谷歌组件**：模型是 Apache-2.0 的 MODNet（自带的 .onnx），
  ///   推理跑 App 自带的 `libonnxruntime.so`（由 sherpa_onnx 打包进来，纯 CPU），
  ///   所以在鸿蒙/卓易通容器里也能跑。
  ///
  /// ⚠️ 历史上这里用的是 ML Kit 的 SelfieSegmenter，容器里每帧抛
  ///   `InputImageConverterError: NullPointerException` → 已彻底移除。
  /// 加载端侧抠像引擎：MODNet + ONNX Runtime（CPU/XNNPACK，跑在独立 isolate）。
  ///
  /// ★这里踩过的坑都是这个容器里的真实现场，别再走回头路：
  ///   1) Google ML Kit SelfieSegmenter：容器里每帧 InputImageConverterError
  ///      （NullPointerException）→ 已彻底移除。
  ///   2) **tflite GPU delegate（OpenGL ES compute）**：容器 EGL 只报 "EGL 1.0"
  ///      （GLES 虽报 3.2，但 delegate 起不来/挂住不返回），一挂住就把整条管线
  ///      拖死——实测画面冻结、fps 归零、AI 永远出不来。**GPU 加速在鸿蒙容器里
  ///      不可用，已彻底摘掉**；真机 Android 上要不要重上，另行验证。
  ///   3) 加载没有超时：底层一挂住，AI 出不来、相机帧也一起丢。现在整条加载链
  ///      有硬超时，超时即判失败 → 降级实景（可用性优先）。
  Future<void> _loadEngine() async {
    if (_engine != null || _aiOff || _loadingEngine) return;
    _loadingEngine = true;
    final t0 = DateTime.now();
    try {
      DiagLog.instance.log('SEG', '开始加载引擎 ONNX/CPU（第 $_loadFails 次重试前）');
      final e = ModnetMattingEngine(threads: 4);
      final ok = await e.load().timeout(const Duration(seconds: 45));
      if (!mounted) {
        await e.dispose();
        return;
      }
      final ms = DateTime.now().difference(t0).inMilliseconds;
      if (ok) {
        _engine = e;
        _loadFails = 0;
        DiagLog.instance.log('SEG', 'MODNet 就绪 ${ms}ms · ${e.diag}');
      } else {
        await e.dispose();
        _noteLoadFailure('load() 返回 false（${ms}ms）');
      }
    } catch (e) {
      _noteLoadFailure('加载异常/超时: $e');
    } finally {
      _loadingEngine = false;
    }
  }

  /// 引擎**加载**失败——比"单帧推理失败"严重得多（加载不过就永远没有引擎）。
  /// 连续 2 次加载失败直接熔断，不让用户在"AI 正在加载"里干等好几分钟。
  void _noteLoadFailure(String why) {
    _loadFails++;
    DiagLog.instance.log('SEG', '引擎加载失败 $_loadFails 次: $why');
    _aiFail++;
    if (_loadFails >= 2 || _aiFail >= kAiFailLimit) _tripBreaker();
  }

  /// 记一次 AI 抠像失败；连续失败到阈值就熔断并降级。
  void _noteAiFailure() {
    _aiFail++;
    debugPrint('[SEG] AI 抠像失败 $_aiFail/$kAiFailLimit');
    if (_aiFail >= kAiFailLimit) _tripBreaker();
  }

  /// ★熔断：判定 AI 抠像在这台设备上不可用。
  /// 停掉整条管线（不再每帧调用模型 → 掐掉"每帧抛异常"的发热源），
  /// 并通知父层自动切到实景 + 用中文提示用户可改用色布模式。
  void _tripBreaker() {
    if (_aiOff) return;
    _aiOff = true;
    _engine?.dispose();
    _engine = null;
    _prevAlpha = null;
    _aiReqPending = false; // 引擎已停，清掉在途标记，否则会永久挡住后续重试
    _maskDbg = '';
    DiagLog.instance.log('SEG',
        'AI 抠像熔断（失败 ${_aiFail} 次 / 加载失败 ${_loadFails} 次）→ 降级实景');
    if (mounted) setState(() => _status = 'AI 抠像不可用，已切实景');
    if (!_fallbackNotified) {
      _fallbackNotified = true;
      widget.onSegmentationUnavailable?.call();
    }
  }

  /// 把 256² 的 alpha 发成一张小 `ui.Image` 交给 GPU 当遮罩。
  /// 256*256*4 = 256KB（对比原来每帧一张 1080p 大图 ≈ 8MB），而且只有 AI 出新 alpha
  /// 时才建（2~4 次/秒），对主线程几乎无感。
  void _publishAlpha(Float32List a, int size) {
    if (_alphaImgBusy) return;
    _alphaImgBusy = true;
    // 预乘白：RGB 与 A 同值，遮罩只看 alpha 通道，颜色无所谓
    final px = Uint8List(size * size * 4);
    for (int i = 0, o = 0; i < a.length; i++) {
      final v = (a[i] * 255.0).clamp(0.0, 255.0).toInt();
      px[o++] = v;
      px[o++] = v;
      px[o++] = v;
      px[o++] = v;
    }
    final seq = ++_alphaSeq;
    ui.decodeImageFromPixels(px, size, size, ui.PixelFormat.rgba8888, (img) {
      _alphaImgBusy = false;
      if (!mounted || seq != _alphaSeq) {
        img.dispose();
        return;
      }
      final oldA = _alphaImg;
      setState(() => _alphaImg = img);
      // ★必须等下一帧画完再释放：本帧的 Picture 可能还引用着旧图
      if (oldA != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) => oldA.dispose());
      }
    });
  }

  /// 遮罩矩阵：把 256² 的 alpha 摆到屏幕上"人像所在的那个方块"。
  ///
  /// 模型看到的是「转正后居中裁方」的画面，边长 S = min(转正宽, 转正高)；
  /// 屏幕上画面按 cover 比例 k 铺满控件，所以那个方块在屏幕上是边长 S*k 的居中正方形。
  /// 前置还要跟着镜像，否则遮罩和人像左右会差开。
  Matrix4 _maskMatrix(double viewW, double viewH, int rotDeg, bool mirror,
      int alphaSize) {
    final f = _frameSize;
    if (f.width <= 0 || f.height <= 0 || alphaSize <= 0) return Matrix4.identity();
    final swap = rotDeg == 90 || rotDeg == 270;
    final rw = swap ? f.height : f.width; // 转正后的宽
    final rh = swap ? f.width : f.height; // 转正后的高
    final k = math.max(viewW / rw, viewH / rh); // cover 比例
    final s = math.min(rw, rh) * k; // 人像方块在屏幕上的边长
    // 直接把矩阵写出来（不走 translate/scale 链，精确且无弃用告警）：
    // 把 alpha 图（alphaSize 见方）线性映射到屏幕上那个居中方块；
    // 前置镜像时 x 轴反向，原点挪到方块右边缘。
    final sc = s / alphaSize;
    final m = Matrix4.identity();
    m.setEntry(0, 0, mirror ? -sc : sc);
    m.setEntry(1, 1, sc);
    m.setEntry(0, 3, mirror ? viewW / 2 + s / 2 : viewW / 2 - s / 2);
    m.setEntry(1, 3, viewH / 2 - s / 2);
    return m;
  }

  /// 相机纹理层：GPU 零拷贝上屏。
  ///
  /// 几个已核实的细节（别再改回去）：
  /// * `CameraController.buildPreview()` 在 Android 上底层就是
  ///   `Texture(textureId: cameraId)` —— 纯 GPU 纹理，CPU 一点不碰。
  /// * camera 0.12 的 `buildPreview()` **自己已经处理转正与裁切**
  ///   （RotatedPreviewDelegate / camerax 原生），所以这里**不能再套 RotatedBox**，
  ///   否则会转两次。
  /// * 该插件**不自动镜像前置摄像头** —— 老 CPU 路径是在 `_CompositePainter` 里
  ///   `canvas.scale(-1, 1)` 翻的。GPU 层必须自己翻，否则画面与 alpha 遮罩左右错开。
  Widget _cameraTextureLayer(bool mirror) {
    final cam = _camera;
    if (cam == null || !cam.value.isInitialized) return const SizedBox.shrink();
    Widget p = CameraPreview(cam); // 官方预览：已转正、比例正确
    if (mirror) {
      p = Transform(
        alignment: Alignment.center,
        transform: Matrix4.diagonal3Values(-1.0, 1.0, 1.0),
        child: p,
      );
    }
    // cover 铺满：给 FittedBox 一个确定尺寸，它才能算缩放（AspectRatio 不能吃无界约束）
    final f = _frameSize;
    final rotDeg = (360 - _frameOrientation) % 360;
    final swap = rotDeg == 90 || rotDeg == 270;
    final rw = swap ? f.height : f.width;
    final rh = swap ? f.width : f.height;
    if (rw <= 0 || rh <= 0) return p;
    return ClipRect(
      child: SizedBox.expand(
        child: FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(width: rw, height: rh, child: p),
        ),
      ),
    );
  }

  /// 美颜（与 `_CompositePainter` 里的做法对齐：磨皮=模糊层 + 半透明原图，美白=颜色矩阵）
  Widget _beauty(Widget child) {
    final smooth = BeautySettings.smooth.value;
    final whiten = BeautySettings.whiten.value;
    if (smooth <= 0 && whiten <= 0) return child;
    Widget sharp = child;
    if (whiten > 0) {
      sharp = ColorFiltered(
          colorFilter: ColorFilter.matrix(whitenMatrix(whiten)), child: sharp);
    }
    if (smooth <= 0) return sharp;
    final sigma = 0.6 + smooth * 3.0;
    return Stack(fit: StackFit.expand, children: [
      ImageFiltered(
        imageFilter: ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
        child: child,
      ),
      Opacity(opacity: 1 - smooth * 0.55, child: sharp),
    ]);
  }

  /// 背景层（等价于 painter 里先铺的那层渐变/场景色）
  Widget _backgroundLayer() =>
      DecoratedBox(decoration: BoxDecoration(gradient: widget.background));

  /// ★B：GPU 合成的画面层
  Widget _gpuComposite() {
    final rotDeg = (360 - _frameOrientation) % 360;
    final mirror = widget.mirror && _frameMirror;
    final person = _beauty(_cameraTextureLayer(mirror));
    final alpha = _alphaImg;
    // 实景（不抠像）：纹理直出，CPU 一帧都不用碰
    if (!_useAi) {
      return _needBackground
          ? Stack(fit: StackFit.expand,
              children: [_backgroundLayer(), person])
          : person;
    }
    // AI 抠像：第一帧 alpha 还没出来时先原样显示（不黑屏），之后上遮罩
    if (alpha == null) return person;
    return Stack(fit: StackFit.expand, children: [
      if (_needBackground) _backgroundLayer(),
      ShaderMask(
        blendMode: BlendMode.dstIn,
        shaderCallback: (Rect bounds) => ui.ImageShader(
          alpha,
          TileMode.clamp,
          TileMode.clamp,
          _maskMatrix(bounds.width, bounds.height, rotDeg, mirror, alpha.width)
              .storage,
        ),
        child: person,
      ),
    ]);
  }

  /// 老路径（CPU 全分辨率合成）：合成、色布、以及 kGpuComposite=false 时用
  Widget _cpuComposite() => CustomPaint(
        painter: _CompositePainter(
          background: _needBackground ? widget.background : null,
          frame: _frame,
          // 镜像与帧绑定（前置镜像、后置不镜像）；切摄像头时旧帧不会被去镜像
          mirror: widget.mirror && _frameMirror,
          sensorOrientation: _frameOrientation,
          smooth: BeautySettings.smooth.value,
          whiten: BeautySettings.whiten.value,
        ),
      );

  /// 全分辨率 RGBA 缓冲（跨帧复用，尺寸变了才重建）
  Uint8List _rgbaOf(int w, int h) {
    final need = w * h * 4;
    final b = _rgbaBuf;
    if (b == null || b.length != need) {
      _rgbaBuf = Uint8List(need);
      return _rgbaBuf!;
    }
    return b;
  }

  /// 喂给模型的方形 RGB 缓冲（跨帧复用）
  Uint8List _aiRgbOf(int size) {
    final need = size * size * 3;
    final b = _aiRgbBuf;
    if (b == null || b.length != need) {
      _aiRgbBuf = Uint8List(need);
      return _aiRgbBuf!;
    }
    return b;
  }

  /// 诊断串：模型输出 alpha 的真实分布（排查"抠像没生效/抠太多"用）
  void _updateAiDiag(Float32List alpha, int size) {
    int bg = 0, sampled = 0;
    double sum = 0, mn = 1, mx = 0;
    for (int k = 0; k < alpha.length; k += 16) {
      final c = alpha[k];
      sum += c;
      sampled++;
      if (c < 0.5) bg++;
      if (c < mn) mn = c;
      if (c > mx) mx = c;
    }
    final n = sampled == 0 ? 1 : sampled;
    final prov = _engine?.diag ?? '';
    _maskDbg = '${prov.isEmpty ? '' : '$prov  '}'
        'AI ${size}x$size 背景${(bg * 100 / n).round()}% '
        '均值${(sum / n).toStringAsFixed(2)} '
        '最低${mn.toStringAsFixed(2)} 最高${mx.toStringAsFixed(2)}';
  }

  Future<void> _onFrame(
      CameraImage image, int gen, int orientation, bool isFront) async {
    if (gen != _camGen) return; // 旧摄像头的残留帧，直接丢
    if (_busy) {
      // ★卡死看门狗：底层（推理/解码/FFI）一旦挂住，_busy 会永远为 true ——
      //   现场表现就是「画面冻结 + fps 归零 + AI 一直出不来」，而且再也不会自愈。
      //   超过 12 秒强制复位，让管线自己活过来（宁可丢一帧，也不能整场冻住）。
      final since = _busySince;
      final stuck = since == null ? 0 : DateTime.now().difference(since).inSeconds;
      if (stuck > 12) {
        DiagLog.instance.log('SEG', '⚠️ 帧处理卡死 ${stuck}s，强制复位管线');
        _busy = false;
        _busySince = null;
        if (_aiReqPending) {
          _aiReqPending = false;
          DiagLog.instance.log('SEG', '⚠️ 同时清掉在途推理请求');
        }
        _noteLoadFailure('帧处理卡死被看门狗复位');
      } else {
        return;
      }
    }
    // 色布（绿/红/蓝）走**纯色键**，不跑 AI 模型：更快、边缘更锐、不留 AI 的糊边
    var useAi = _useAi;
    if (useAi && _engine == null) {
      await _loadEngine();
      if (gen != _camGen) return;
      // 加载失败/已熔断 → 本帧按实景出画（不黑屏、不透出英文报错）
      if (_engine == null) useAi = false;
    }
    _busy = true;
    _busySince = DateTime.now();
    final tStart = DateTime.now();
    int msRgb = 0, msSample = 0, msAlpha = 0, msDecode = 0;
    try {
      final w = image.width;
      final h = image.height;
      // camerax 输出的是 YUV_420_888 三平面，需拼接成 NV21 单缓冲（Y + VU 交错）
      // ★B：GPU 合成时，实景/色布（不跑模型）连 RGBA 都不用转 —— CPU 一帧都不碰
      final needRgba = useAi || widget.keyColor >= 0 || !kGpuComposite;
      final rgba = _rgbaOf(w, h);
      if (needRgba) {
        final nv21 = _yuvPlanesToNv21(image);
        _nv21ToRgbaInto(nv21, w, h, rgba);
      }
      msRgb = DateTime.now().difference(tStart).inMilliseconds;

      ui.Image? img;
      if (useAi) {
        final eng = _engine;
        if (eng == null) return;
        final size = eng.inputSize;
        // ---- 送给模型：转正 + 居中裁方 + 缩放到模型输入尺寸（一次采样搞定）----
        // ★相机给的是「传感器原始横版」buffer，必须按 sensorOrientation 转正，
        //   否则模型看到的是侧躺的人，抠像质量会明显变差。
        final rgb = _aiRgbOf(size);
        final rotDeg = (360 - orientation) % 360;
        _sampleSquareRgb(rgba, w, h, rotDeg, size, rgb);
        msSample = DateTime.now().difference(tStart).inMilliseconds - msRgb;

        // ---- ★★ 出画与推理解耦（不然手机端会掉成幻灯片）★★ ----
        // 反例：如果这里 `await eng.matting(...)`，那么一次推理 200~400ms 期间
        //   整个 _onFrame 都挂住，相机帧被丢弃 → 预览直接掉到 3~5fps。
        // 正解：**只在没有在途请求时发一帧出去，然后立刻用"上一帧 alpha"出画**。
        //   于是预览稳定走相机帧率（30fps），只有 alpha 按推理帧率（约 3~6fps）刷新
        //   —— 这就是方案里说的「跳帧插值」。人坐着直播时肉眼几乎看不出；
        //   快速走动时边缘会有轻微拖影（可接受，二期可加光流外推）。
        if (!_aiReqPending) {
          _aiReqPending = true;
          // rgb 是复用缓冲，请求在途时会被下一帧覆盖 → 拷一份交给后台
          final payload = Uint8List.fromList(rgb);
          final myGen = gen;
          eng.matting(payload, size, size).then((a) {
            _aiReqPending = false;
            if (!mounted || myGen != _camGen) return;
            if (a != null && a.length == size * size) {
              _aiFail = 0; // ★跑通了 → 连续失败计数清零
              // ★帧间平滑（EMA）：新帧 65% + 上一帧 35%。AI 只有 8fps，
              //   逐帧 alpha 抖动（边缘忽有忽无/闪烁）被明显压平；
              //   代价是边缘响应稍慢一拍，与"跳帧插值"的滞后同量级。
              final old = _prevAlpha;
              if (old != null && old.length == a.length) {
                for (int i = 0; i < a.length; i++) {
                  a[i] = a[i] * 0.65 + old[i] * 0.35;
                }
              }
              _prevAlpha = a;
              _aiFrames++; // AI 推理成功一帧（供 fps 角标结算）
              _updateAiDiag(a, size);
              // ★B：把 alpha 发成 256² 小图给 GPU 当遮罩
              if (kGpuComposite) _publishAlpha(a, size);
            } else if (eng.errorStreak > 0) {
              // 引擎「忙」不是错误；只有真的连续报错才计数 → 到阈值熔断
              _noteAiFailure();
            }
          }).catchError((Object _) {
            _aiReqPending = false;
          });
        }

        final tA = DateTime.now();
        if (!kGpuComposite) {
          // ---- 老路径：CPU 全分辨率合成 + 全屏 decode ----
          // 本帧用当前最新的 alpha 立刻出画（首帧还没 alpha 时按原图出，不黑屏）
          // ★预乘已合并进 _applySoftAlpha（省一遍全分辨率遍历）
          final a = _prevAlpha;
          if (a != null && a.length == size * size) {
            // ★alpha 是「转正+裁方」坐标系的，贴回必须做逆变换（同 rotDeg）
            _applySoftAlpha(rgba, a, size, size, widget.strength, w, h, rotDeg);
          }
          msAlpha = tA.difference(tStart).inMilliseconds - msRgb - msSample;
          img = await _decode(rgba, w, h);
          msDecode = DateTime.now().difference(tA).inMilliseconds;
        }
        // GPU 路径：什么都不用做 —— rgba 只用来喂模型，画面由 Texture + 遮罩在 GPU 合成
      } else {
        // 色布模式：只做真·色键；实景模式（不抠像）什么都不做
        if (widget.keyColor >= 0 || !kGpuComposite) {
          if (widget.keyColor >= 0) {
            _applyChromaKey(rgba, w, h, widget.keyColor, widget.strength);
            _premultiply(rgba, w, h);
          }
          final tA = DateTime.now();
          img = await _decode(rgba, w, h);
          msDecode = DateTime.now().difference(tA).inMilliseconds;
        }
        // GPU 路径的实景/色布（无遮罩）：画面直接来自 Texture，不必转码解码
      }
      if (!mounted || gen != _camGen) {
        img?.dispose();
        return;
      }

      final old = _frame;
      if (mounted) {
        setState(() {
          _frame = img;
          _frameOrientation = orientation; // 画面和「产生它的那台摄像头」的方向绑定
          // ★镜像也要跟着帧走：否则切到后置时，冻结中的旧前置帧瞬间被去镜像，
          //   而 90° 旋转 + 去镜像 = 视觉上转 180° → 就是"先倒立一下"的真正原因
          _frameMirror = isFront;
          // ★GPU 路径要这两样算 cover 比例：原始 buffer 尺寸 + 出过帧标记
          _frameSize = Size(w.toDouble(), h.toDouble());
          _hasFrame = true;
          _frames++;
          final now = DateTime.now();
          final dt = now.difference(_lastFps).inMilliseconds;
          if (dt >= 1000) {
            _fps = _frames * 1000 / dt;
            _frames = 0;
            _aiFps = _aiFrames * 1000 / dt;
            _aiFrames = 0;
            _lastFps = now;
            // 每秒结算一次耗时分解（本帧也计入）
            _tRgb += msRgb;
            _tSample += msSample;
            _tAlpha += msAlpha;
            _tDecode += msDecode;
            _tFrame += now.difference(tStart).inMilliseconds;
            _tN++;
            final n = _tN;
            _perfDbg = '耗时/帧(ms) 转RGBA ${_tRgb ~/ n} · 采样 ${_tSample ~/ n} · '
                '合成 ${_tAlpha ~/ n} · 解码 ${_tDecode ~/ n} · 合计 ${_tFrame ~/ n}';
            _tRgb = 0;
            _tSample = 0;
            _tAlpha = 0;
            _tDecode = 0;
            _tFrame = 0;
            _tN = 0;
          }
        });
      }
      old?.dispose();
    } catch (e) {
      // 技术细节只进日志；界面不显示英文异常
      debugPrint('[SEG] 单帧处理失败($_aiFail/$kAiFailLimit): $e');
      // ★连续失败到阈值 → 熔断并降级到实景：既止血画质，也掐掉每帧抛异常的发热源
      _noteAiFailure();
    } finally {
      _busy = false;
      _busySince = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    // 色布模式仍走 CPU 色键（遮罩那套只服务 AI 抠像）
    final onGpu = kGpuComposite && _camera != null &&
        _camera!.value.isInitialized && !(widget.keyColor >= 0);
    return Stack(fit: StackFit.expand, children: [
      if (onGpu) _gpuComposite() else _cpuComposite(),
      Positioned(
        // ★让开系统状态栏：之前 top:10 被状态栏时钟压住，关键诊断根本看不见
        top: MediaQuery.paddingOf(context).top + 6,
        left: 10,
        right: 10,
        child: Align(
          alignment: Alignment.topLeft,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: .45),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '${!_hasFrame ? _status : '$_status · ${_fps.toStringAsFixed(0)}fps'}${_maskDbg.isEmpty ? '' : '\n$_maskDbg'}${_perfDbg.isEmpty ? '' : '\n$_perfDbg'}',
              style: const TextStyle(color: Colors.white, fontSize: 11),
            ),
          ),
        ),
      ),
      // ★AI 抠像实时状态角标：只在 AI 抠像开启时显示，右上角不抢画面。
      // 每秒随现有 setState 结算一次 _aiFps（不额外 setState），供老板看"现在几帧"。
      if (_useAi && _engine != null)
        Positioned(
          top: MediaQuery.paddingOf(context).top + 6,
          right: 10,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: .38),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              'AI 抠像 ${_aiFps.toStringAsFixed(1)}fps · 输入${_engine!.inputSize}²',
              style: const TextStyle(
                  color: Colors.white70, fontSize: 9, height: 1.2),
            ),
          ),
        ),
    ]);
  }
}

/// YUV_420_888 三平面 → NV21 单缓冲（Y + VU 交错）
/// 兼容：单 plane（已是 NV21）直接用；3 plane 才拼接；否则退回 Y 平面避免越界崩溃
Uint8List _yuvPlanesToNv21(CameraImage image) {
  final w = image.width;
  final h = image.height;

  // 单 plane：已经是 NV21（Y + VU 交错），直接用
  if (image.planes.length == 1) {
    return image.planes[0].bytes;
  }
  // 不足 3 plane：退回 Y 平面（至少不崩溃，画面可能无色但能看到亮度）
  if (image.planes.length < 3) {
    return image.planes[0].bytes;
  }

  final yPlane = image.planes[0];
  final uPlane = image.planes[1];
  final vPlane = image.planes[2];

  final yRowStride = yPlane.bytesPerRow;
  final yPixStride = yPlane.bytesPerPixel ?? 1;
  final uvRowStride = uPlane.bytesPerRow;
  final uvPixStride = uPlane.bytesPerPixel ?? 1;

  final ySize = w * h;
  final nv21 = Uint8List(w * h * 3 ~/ 2);

  // Y 平面
  for (int row = 0; row < h; row++) {
    final srcOff = row * yRowStride;
    final dstOff = row * w;
    for (int col = 0; col < w; col++) {
      nv21[dstOff + col] = yPlane.bytes[srcOff + col * yPixStride];
    }
  }

  // UV 平面 → NV21 是 VU 交错（V 在前）
  for (int row = 0; row < h ~/ 2; row++) {
    for (int col = 0; col < w ~/ 2; col++) {
      final srcOff = row * uvRowStride + col * uvPixStride;
      final dstOff = ySize + (row * (w ~/ 2) + col) * 2;
      nv21[dstOff] = vPlane.bytes[srcOff];
      nv21[dstOff + 1] = uPlane.bytes[srcOff];
    }
  }

  return nv21;
}

/// NV21 → RGBA 写入调用方给的缓冲（每像素 4 字节，alpha 先置 255）。
/// 缓冲由 State 跨帧复用，避免每帧分配 w*h*4 字节触发 GC 抖动。
void _nv21ToRgbaInto(Uint8List nv21, int w, int h, Uint8List out) {
  final frameSize = w * h;
  for (int j = 0, yp = 0; j < h; j++) {
    int uvp = frameSize + (j >> 1) * w, u = 0, v = 0;
    for (int i = 0; i < w; i++, yp++) {
      int y = (nv21[yp] & 0xff) - 16;
      if (y < 0) y = 0;
      if ((i & 1) == 0) {
        v = (nv21[uvp++] & 0xff) - 128;
        u = (nv21[uvp++] & 0xff) - 128;
      }
      final y1192 = 1192 * y;
      final r = y1192 + 1634 * v;
      final g = y1192 - 833 * v - 400 * u;
      final b = y1192 + 2066 * u;
      final o = (j * w + i) * 4;
      out[o] = _clamp(r >> 10);
      out[o + 1] = _clamp(g >> 10);
      out[o + 2] = _clamp(b >> 10);
      out[o + 3] = 255;
    }
  }
}

/// 从全分辨率 RGBA 取一块「转正 + 居中裁方 + 缩放到 size×size」的 RGB，
/// 写入 [out]（长度 size*size*3）。这是喂给 MODNet 的输入。
///
/// ★为什么必须转正：相机给的是传感器原始横版 buffer，不转正模型看到的就是
///   「侧躺的人」，抠像质量明显下降（漏抠、把背景圈进人像）。
/// ★为什么居中裁方：MODNet 是方形输入，直接拉伸会把竖幅人像压扁变型；
///   居中裁方保住真实比例，代价是画面上下被裁（直播时人像本来居中，影响很小）。
void _sampleSquareRgb(
    Uint8List rgba, int w, int h, int rotDeg, int size, Uint8List out) {
  // 转正后的尺寸
  final swap = rotDeg == 90 || rotDeg == 270;
  final uw = swap ? h : w;
  final uh = swap ? w : h;
  final side = uw < uh ? uw : uh;
  final cropX = (uw - side) / 2.0;
  final cropY = (uh - side) / 2.0;
  final step = side / size;

  int o = 0;
  for (int oy = 0; oy < size; oy++) {
    final uy = cropY + oy * step;
    for (int ox = 0; ox < size; ox++) {
      final ux = cropX + ox * step;
      // 转正坐标 → 原始 buffer 坐标（90/180/270° 都是仿射变换，
      // 所以直接在原始坐标里做双线性采样，结果与"先转正再插值"等价）
      double rfx, rfy;
      switch (rotDeg) {
        case 90:
          rfx = uy;
          rfy = h - 1 - ux;
          break;
        case 180:
          rfx = w - 1 - ux;
          rfy = h - 1 - uy;
          break;
        case 270:
          rfx = w - 1 - uy;
          rfy = ux;
          break;
        default:
          rfx = ux;
          rfy = uy;
      }
      if (rfx < 0) rfx = 0;
      if (rfy < 0) rfy = 0;
      if (rfx > w - 1) rfx = (w - 1).toDouble();
      if (rfy > h - 1) rfy = (h - 1).toDouble();
      final x0 = rfx.floor();
      final y0 = rfy.floor();
      final x1 = x0 + 1 < w ? x0 + 1 : w - 1;
      final y1 = y0 + 1 < h ? y0 + 1 : h - 1;
      final tx = rfx - x0;
      final ty = rfy - y0;
      final i00 = (y0 * w + x0) * 4;
      final i01 = (y0 * w + x1) * 4;
      final i10 = (y1 * w + x0) * 4;
      final i11 = (y1 * w + x1) * 4;
      final b00 = (1 - tx) * (1 - ty);
      final b01 = tx * (1 - ty);
      final b10 = (1 - tx) * ty;
      final b11 = tx * ty;
      out[o++] = _clamp((rgba[i00] * b00 +
              rgba[i01] * b01 +
              rgba[i10] * b10 +
              rgba[i11] * b11)
          .round());
      out[o++] = _clamp((rgba[i00 + 1] * b00 +
              rgba[i01 + 1] * b01 +
              rgba[i10 + 1] * b10 +
              rgba[i11 + 1] * b11)
          .round());
      out[o++] = _clamp((rgba[i00 + 2] * b00 +
              rgba[i01 + 2] * b01 +
              rgba[i10 + 2] * b10 +
              rgba[i11 + 2] * b11)
          .round());
    }
  }
}

int _clamp(int v) => v < 0 ? 0 : (v > 255 ? 255 : v);

/// ★根因修复：`ui.decodeImageFromPixels(rgba8888)` 把数据按「预乘 alpha」解释。
/// 我们之前输出的是「非预乘」（alpha=0 但 RGB 仍是房间颜色），Skia 合成按
/// `dst = src + dst*(1-alpha)` 计算，alpha=0 时变成 `dst = src + dst` →
/// 把房间的颜色**直接加到背景上** → 表现就是「背景发白发亮 + 真实房间透出来」。
/// 这里把 RGB 按 alpha 预乘，alpha=0 的像素彻底归零，背景才会真正干净。
void _premultiply(Uint8List rgba, int w, int h) {
  final n = w * h;
  for (int p = 0; p < n; p++) {
    final o = p * 4;
    final a = rgba[o + 3];
    if (a == 255) continue;
    if (a == 0) {
      rgba[o] = 0;
      rgba[o + 1] = 0;
      rgba[o + 2] = 0;
      continue;
    }
    rgba[o] = rgba[o] * a ~/ 255;
    rgba[o + 1] = rgba[o + 1] * a ~/ 255;
    rgba[o + 2] = rgba[o + 2] * a ~/ 255;
  }
}

/// 形态学膨胀（3x3 方窗，迭代 r 次）
Uint8List _dilate(Uint8List src, int w, int h, int r) {
  var cur = src;
  for (int it = 0; it < r; it++) {
    final out = Uint8List(w * h);
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        int v = 0;
        for (int dy = -1; dy <= 1 && v == 0; dy++) {
          final yy = y + dy;
          if (yy < 0 || yy >= h) continue;
          final base = yy * w;
          for (int dx = -1; dx <= 1; dx++) {
            final xx = x + dx;
            if (xx < 0 || xx >= w) continue;
            if (cur[base + xx] != 0) {
              v = 1;
              break;
            }
          }
        }
        out[y * w + x] = v;
      }
    }
    cur = out;
  }
  return cur;
}

/// 形态学腐蚀（3x3 方窗，迭代 r 次）
Uint8List _erode(Uint8List src, int w, int h, int r) {
  var cur = src;
  for (int it = 0; it < r; it++) {
    final out = Uint8List(w * h);
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        int v = 1;
        for (int dy = -1; dy <= 1 && v == 1; dy++) {
          final yy = y + dy;
          if (yy < 0 || yy >= h) continue;
          final base = yy * w;
          for (int dx = -1; dx <= 1; dx++) {
            final xx = x + dx;
            if (xx < 0 || xx >= w) continue;
            if (cur[base + xx] == 0) {
              v = 0;
              break;
            }
          }
        }
        out[y * w + x] = v;
      }
    }
    cur = out;
  }
  return cur;
}

/// 去掉"贴在画面左/右边缘的细长条"。
///
/// ★为什么需要：房间里的书架/柜子/墙常被模型误判成"人"，
///   在画面边缘残留成一条窄条（而且往往和人像连在一起，连通域过滤也去不掉）。
///   启发式：人像总是**居中**的大块 → 逐行扫描，把"贴着左/右边缘、
///   且宽度 < 30% 画面宽"的前景段判为背景。人像若真的贴边，其连续段通常远宽于此。
Uint8List _stripEdgeBands(Uint8List bin, int w, int h) {
  final out = Uint8List.fromList(bin);
  final maxRun = (w * 0.30).round();
  for (int y = 0; y < h; y++) {
    final base = y * w;
    // 左边缘
    int i = 0;
    while (i < w && out[base + i] != 0) {
      i++;
    }
    if (i > 0 && i <= maxRun) {
      for (int k = 0; k < i; k++) {
        out[base + k] = 0;
      }
    }
    // 右边缘
    int j = w - 1;
    while (j >= 0 && out[base + j] != 0) {
      j--;
    }
    final run = (w - 1) - j;
    if (run > 0 && run <= maxRun) {
      for (int k = j + 1; k < w; k++) {
        out[base + k] = 0;
      }
    }
  }
  return out;
}

/// 连通域过滤：去掉"书架/墙"等被误判为人的**孤立小块**。
/// ★保留所有「面积 >= 最大块 50%」的块——只留最大块会把被切散的人像也丢掉
///   （上一版就是这样把脸/衣服切掉的）。用 4-邻域 BFS 标记，256x256 开销可忽略。
Uint8List _largestComponent(Uint8List bin, int w, int h) {
  final n = w * h;
  final label = Int32List(n);
  final stack = <int>[];
  final sizes = <int>[0];
  int cur = 0;
  for (int p = 0; p < n; p++) {
    if (bin[p] == 0 || label[p] != 0) continue;
    cur++;
    int size = 0;
    stack.add(p);
    label[p] = cur;
    while (stack.isNotEmpty) {
      final q = stack.removeLast();
      size++;
      final x = q % w, y = q ~/ w;
      if (x > 0) {
        final t = q - 1;
        if (bin[t] != 0 && label[t] == 0) {
          label[t] = cur;
          stack.add(t);
        }
      }
      if (x < w - 1) {
        final t = q + 1;
        if (bin[t] != 0 && label[t] == 0) {
          label[t] = cur;
          stack.add(t);
        }
      }
      if (y > 0) {
        final t = q - w;
        if (bin[t] != 0 && label[t] == 0) {
          label[t] = cur;
          stack.add(t);
        }
      }
      if (y < h - 1) {
        final t = q + w;
        if (bin[t] != 0 && label[t] == 0) {
          label[t] = cur;
          stack.add(t);
        }
      }
    }
    sizes.add(size);
  }
  int maxSize = 0;
  for (final s in sizes) {
    if (s > maxSize) maxSize = s;
  }
  final keepMin = (maxSize * 0.35).round();
  final out = Uint8List(n);
  for (int p = 0; p < n; p++) {
    final l = label[p];
    out[p] = (l != 0 && sizes[l] >= keepMin) ? 1 : 0;
  }
  return out;
}

/// 把 MODNet 的**软 alpha** 变成画面的 alpha 通道。
///
/// 与旧版（ML Kit 二值掩膜）的根本区别：这里是**软边保留**路线。
/// MODNet 输出的就是 0~1 连续 alpha，发丝/眼镜边/纱料正是靠这些中间值表现的，
/// 所以**绝不做二值化**，否则等于把新模型最值钱的能力扔掉。但纯软 alpha 也有风险：
/// 房间里的书架/柜子偶尔会被圈进前景。于是：
///   ① 在**半分辨率**上把软 alpha 二值化 → 闭运算填洞 → 去贴边细条 → 连通域过滤，
///      得到"哪些大区域算人"的 0/1 图（复用既有实现，开销极低）
///   ② 把这张图按比例映射回去，与原始软 alpha **相乘**
///      → 孤立误判块被干掉，而软边/发丝**原样保留**
///   ③ 按「抠像强度」做对比度映射：强度越大，越靠近 0 的 alpha 被压到 0，
///      背景越干净（代价是最淡的那几根发丝会少一点）
///   ④ 双线性上采样到全分辨率，写进 alpha 通道
///
/// ★★[rotDeg] = 送模型时的旋转角（与 `_sampleSquareRgb` 一致）。
/// alpha 描述的是「转正后画面（uw×uh）中央 side×side 裁方窗口」，
/// **不是**整幅原始帧 —— 之前直接把 alpha 当整幅缩略图铺满，
/// 竖屏时垂直被拉 1.78 倍 + 旋转 90° 错位 → 表现就是"只有脸中心一小块抠出来，
/// 四周全是糊的紫色渐变"。这里对每个原始像素做逆变换（原始→转正→裁方窗口→
/// alpha 坐标）再采样；窗口外的像素（裁方丢掉的上下/左右）直接算背景。
void _applySoftAlpha(Uint8List rgba, Float32List alpha, int aw, int ah,
    double strength, int w, int h, int rotDeg) {
  // ---- ① 半分辨率区域清理（去掉书架/墙等被误判为人的孤立块）----
  final hw = aw >> 1, hh = ah >> 1;
  Uint8List keep = Uint8List(0);
  if (hw >= 8 && hh >= 8) {
    final hn = hw * hh;
    final bin = Uint8List(hn);
    for (int j = 0; j < hh; j++) {
      final r0 = (j * 2) * aw;
      final r1 = (j * 2 + 1) * aw;
      for (int i = 0; i < hw; i++) {
        final s = (alpha[r0 + i * 2] +
                alpha[r0 + i * 2 + 1] +
                alpha[r1 + i * 2] +
                alpha[r1 + i * 2 + 1]) *
            0.25;
        bin[j * hw + i] = s >= 0.5 ? 1 : 0;
      }
    }
    var cleaned = _erode(_dilate(bin, hw, hh, 1), hw, hh, 1);
    cleaned = _stripEdgeBands(cleaned, hw, hh);
    keep = _largestComponent(cleaned, hw, hh);
    // 兜底：如果清理后一个前景块都没剩下（模型这帧没识别人），
    // 不要把整帧抠成透明（那会只剩背景），直接放弃这层过滤。
    var any = false;
    for (int k = 0; k < keep.length; k++) {
      if (keep[k] != 0) {
        any = true;
        break;
      }
    }
    if (!any) keep = Uint8List(0);
  }
  final useKeep = keep.isNotEmpty;

  // ---- ② 在模型分辨率（aw×ah）上合成：软 alpha × keep（硬切孤立误判块）----
  // ★关键减负：把"keep 分支、强度映射、羽化"全部下沉到 aw×ah（256×256 ≈ 6.5 万像素），
  //   全分辨率循环里只剩"双线性 + 预乘"，不再逐像素做 floor/keep 分支/映射运算。
  final n = aw * ah;
  final synth = Float32List(n);
  if (useKeep) {
    for (int j = 0; j < ah; j++) {
      var ky = (j * hh ~/ ah);
      if (ky > hh - 1) ky = hh - 1;
      final krow = ky * hw;
      final arow = j * aw;
      for (int i = 0; i < aw; i++) {
        var kx = (i * hw ~/ aw);
        if (kx > hw - 1) kx = hw - 1;
        synth[arow + i] = keep[krow + kx] != 0 ? alpha[arow + i] : 0.0;
      }
    }
  } else {
    synth.setAll(0, alpha);
  }

  // ---- ③ 3×3 盒式模糊：羽化 keep 硬边 + 压低软 alpha 帧间噪声 ----
  // 这一步是"锯齿/闪烁"的直接解药：256→1080p 放大 4 倍，硬边会被放大成 8px 台阶；
  // 模糊后边缘变成平滑过渡，闪烁明显减弱。在 256 上做，开销可忽略（约 6 万像素）。
  final blurred = _boxBlur3(synth, aw, ah);

  // ---- ④ 强度映射：强度越大，低 alpha 越容易被压到 0（抠得越狠）----
  final lo = strength * 0.22;
  final hi = 0.94 - strength * 0.10;
  final span = hi - lo;
  if (span > 0) {
    for (int p = 0; p < n; p++) {
      final v = (blurred[p] - lo) / span;
      blurred[p] = v <= 0 ? 0.0 : (v >= 1 ? 1.0 : v);
    }
  }

  // ---- ⑤ 逆变换贴回全分辨率：原始像素 → 转正坐标 → 裁方窗口 → alpha 坐标 ----
  // 与 _sampleSquareRgb 的正向变换互逆：
  //   rot 90 : ux = h-1-j（行常数）, uy = i（随 i 递增）
  //   rot 180: ux = w-1-i, uy = h-1-j
  //   rot 270: ux = j, uy = w-1-i（随 i 递减）
  //   rot 0  : ux = i, uy = j
  final swap = rotDeg == 90 || rotDeg == 270;
  final uw = swap ? h : w;
  final uh = swap ? w : h;
  final side = uw < uh ? uw : uh;
  final cropX = (uw - side) / 2.0;
  final cropY = (uh - side) / 2.0;
  final step = side / aw; // 与 _sampleSquareRgb 的 step 一致（aw == 模型 size）

  final awf = aw - 1, ahf = ah - 1;
  // 逐行预计算：ax/ay 在行内随 i 线性步进（步长 axD/ayD），免去逐像素乘除。
  for (int j = 0; j < h; j++) {
    double axRow, ayRow, axD, ayD;
    switch (rotDeg) {
      case 90: // ux = h-1-j, uy = i
        axRow = ((h - 1 - j) - cropX) / step;
        ayRow = 0 - cropY / step;
        axD = 0.0;
        ayD = 1.0 / step;
        break;
      case 180: // ux = w-1-i, uy = h-1-j
        axRow = ((w - 1) - cropX) / step;
        ayRow = ((h - 1 - j) - cropY) / step;
        axD = -1.0 / step;
        ayD = 0.0;
        break;
      case 270: // ux = j, uy = w-1-i
        axRow = (j - cropX) / step;
        ayRow = ((w - 1) - cropY) / step;
        axD = 0.0;
        ayD = -1.0 / step;
        break;
      default: // rot 0: ux = i, uy = j
        axRow = 0 - cropX / step;
        ayRow = (j - cropY) / step;
        axD = 1.0 / step;
        ayD = 0.0;
        break;
    }
    final orow = j * w * 4;
    double ax = axRow, ay = ayRow;
    for (int i = 0; i < w; i++, ax += axD, ay += ayD) {
      final o = orow + i * 4;
      // 窗口 = [0, aw)×[0, ah)（ax/ay 已含 crop/step 换算）；
      // 边缘小数部分靠 clamp 到最边像素（窗口宽 side = aw*step）。
      if (ax < 0 || ay < 0 || ax >= aw || ay >= ah) {
        // 裁方窗口外 = 模型没看过的区域 → 背景
        rgba[o] = 0;
        rgba[o + 1] = 0;
        rgba[o + 2] = 0;
        rgba[o + 3] = 0;
        continue;
      }
      int x0 = ax.floor(), y0 = ay.floor();
      final x1 = x0 + 1 <= awf ? x0 + 1 : awf;
      final y1 = y0 + 1 <= ahf ? y0 + 1 : ahf;
      final tx = ax - x0, ty = ay - y0;
      final row0 = y0 * aw, row1 = y1 * aw;
      final top =
          blurred[row0 + x0] + (blurred[row0 + x1] - blurred[row0 + x0]) * tx;
      final bottom =
          blurred[row1 + x0] + (blurred[row1 + x1] - blurred[row1 + x0]) * tx;
      var a = top + (bottom - top) * ty;
      if (a > 1) a = 1;
      if (a < 0) a = 0;
      final ab = (a * 255).round();
      rgba[o + 3] = ab;
      // 预乘（并入本循环，省一遍 200 万像素的单独遍历）
      if (ab == 255) continue;
      if (ab == 0) {
        rgba[o] = 0;
        rgba[o + 1] = 0;
        rgba[o + 2] = 0;
        continue;
      }
      rgba[o] = rgba[o] * ab ~/ 255;
      rgba[o + 1] = rgba[o + 1] * ab ~/ 255;
      rgba[o + 2] = rgba[o + 2] * ab ~/ 255;
    }
  }
}

/// 3×3 盒式模糊（边界复制边缘像素）。用于羽化抠像边缘、压低帧间 alpha 噪声。
/// 只在模型分辨率（≤256×256）上跑，开销可忽略。
Float32List _boxBlur3(Float32List src, int w, int h) {
  final out = Float32List(src.length);
  for (int y = 0; y < h; y++) {
    final up = y > 0 ? y - 1 : 0;
    final dn = y < h - 1 ? y + 1 : h - 1;
    for (int x = 0; x < w; x++) {
      final lf = x > 0 ? x - 1 : 0;
      final rt = x < w - 1 ? x + 1 : w - 1;
      out[y * w + x] = (src[up * w + lf] +
              src[up * w + x] +
              src[up * w + rt] +
              src[y * w + lf] +
              src[y * w + x] +
              src[y * w + rt] +
              src[dn * w + lf] +
              src[dn * w + x] +
              src[dn * w + rt]) /
          9.0;
    }
  }
  return out;
}

/// 真·色键抠像（chroma key）：把接近幕布颜色的像素抠成透明，并压掉边缘溢色。
///
/// [keyIdx]：0=绿幕 1=红幕 2=蓝幕。
/// 判据用"键色通道 减去 另两通道的最大值"（dominance），
/// 抗光照不均比直接比 RGB 距离稳。
void _applyChromaKey(
    Uint8List rgba, int w, int h, int keyIdx, double strength) {
  // strength 越大 → 阈值越低 → 抠得越狠
  final tLo = 15.0 + (1.0 - strength) * 30.0; // 低于此完全保留
  final tHi = tLo + 40.0; // 高于此完全抠掉
  final span = tHi - tLo;
  for (int p = 0; p < w * h; p++) {
    final o = p * 4;
    final r = rgba[o], g = rgba[o + 1], b = rgba[o + 2];
    int key, m1, m2;
    switch (keyIdx) {
      case 1: // 红幕
        key = r;
        m1 = g;
        m2 = b;
        break;
      case 2: // 蓝幕
        key = b;
        m1 = r;
        m2 = g;
        break;
      default: // 绿幕
        key = g;
        m1 = r;
        m2 = b;
    }
    final other = m1 > m2 ? m1 : m2;
    final d = (key - other).toDouble();
    if (d <= 0) continue; // 不是键色，原样保留
    if (d >= tHi) {
      rgba[o + 3] = 0; // 纯幕布 → 全透明
      continue;
    }
    // 过渡带：按比例降低不透明度（与 AI mask 取并集）
    final k = (d - tLo) / span;
    if (k > 0) {
      final a0 = rgba[o + 3];
      final a = (a0 * (1.0 - k)).round();
      rgba[o + 3] = a < 0 ? 0 : a;
    }
    // 溢色抑制：把偏键色的通道往另两通道均值拉，去掉边缘绿边/蓝边
    if (d > 0 && other + 12 < key) {
      final target = other + ((key - other) * (1.0 - k.clamp(0.0, 1.0)) * 0.5)
          .round();
      final v = target < 0 ? 0 : (target > 255 ? 255 : target);
      rgba[o + (keyIdx == 1 ? 0 : (keyIdx == 2 ? 2 : 1))] = v;
    }
  }
}

Future<ui.Image> _decode(Uint8List rgba, int w, int h) {
  final c = Completer<ui.Image>();
  ui.decodeImageFromPixels(rgba, w, h, ui.PixelFormat.rgba8888, c.complete);
  return c.future;
}

/// 美白颜色矩阵：通道增益提亮 + 轻微降蓝让肤色更暖（painter 与 GPU 合成层共用）
List<double> whitenMatrix(double whiten) {
  final g = whiten * 0.22;
  final o = whiten * 22;
  return <double>[
    1 + g, 0, 0, 0, o, //
    0, 1 + g, 0, 0, o, //
    0, 0, 1 + g * 0.85, 0, o * 0.85, //
    0, 0, 0, 1, 0, //
  ];
}

class _CompositePainter extends CustomPainter {
  final Gradient? background; // null = 不画背景（实景模式）
  final ui.Image? frame;
  final bool mirror;
  final int sensorOrientation;
  final double smooth; // 磨皮 0~1
  final double whiten; // 美白 0~1

  _CompositePainter({
    required this.background,
    required this.frame,
    required this.mirror,
    required this.sensorOrientation,
    this.smooth = 0,
    this.whiten = 0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (background != null) {
      canvas.drawRect(
        Offset.zero & size,
        Paint()..shader = background!.createShader(Offset.zero & size),
      );
    }

    final img = frame;
    if (img == null) return;

    // 前置摄像头 sensorOrientation=270°：需顺时针转 (360-270)=90° 才正立（之前直接转 270° 导致倒立）
    final rotationDeg = (360 - sensorOrientation) % 360;
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.rotate(rotationDeg * math.pi / 180);
    if (mirror) canvas.scale(-1, 1);

    // ★关键：dst 必须保持 img 原始宽高比（src 是原始坐标，不 swap）
    //   之前 swap 了 iw/ih，导致 dst 比例(3:4)和 src 比例(4:3)不匹配，drawImageRect 强行拉伸→脸拉宽
    final iw = img.width.toDouble();
    final ih = img.height.toDouble();

    // cover：旋转 90/270° 后，dst 宽(iw)覆盖屏幕高、dst 高(ih)覆盖屏幕宽，scale 目标互换
    final swap = rotationDeg == 90 || rotationDeg == 270;
    final scaleW = swap ? size.height / iw : size.width / iw;
    final scaleH = swap ? size.width / ih : size.height / ih;
    final scale = math.max(scaleW, scaleH);
    final dw = iw * scale;
    final dh = ih * scale;
    final rect = Rect.fromCenter(center: Offset.zero, width: dw, height: dh);
    final src = Rect.fromLTWH(0, 0, iw, ih);

    // ===== 美颜 =====
    if (smooth > 0) {
      // 磨皮：先画整体模糊层，再半透明叠原图（保留五官，smooth 越大越平滑）
      final sigma = 0.6 + smooth * 3.0;
      canvas.drawImageRect(
        img,
        src,
        rect,
        Paint()
          ..filterQuality = FilterQuality.high
          ..imageFilter = ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
      );
      final p = Paint()
        ..filterQuality = FilterQuality.high
        ..color = Color.fromRGBO(255, 255, 255, 1 - smooth * 0.55);
      if (whiten > 0) p.colorFilter = ColorFilter.matrix(whitenMatrix(whiten));
      canvas.drawImageRect(img, src, rect, p);
    } else {
      final p = Paint()..filterQuality = FilterQuality.high;
      if (whiten > 0) p.colorFilter = ColorFilter.matrix(whitenMatrix(whiten));
      canvas.drawImageRect(img, src, rect, p);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_CompositePainter old) =>
      old.frame != frame ||
      old.mirror != mirror ||
      old.background != background ||
      old.sensorOrientation != sensorOrientation ||
      old.smooth != smooth ||
      old.whiten != whiten;
}