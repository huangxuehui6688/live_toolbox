import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

/// 数字人可选形象
const List<String> kDigitalAvatarImages = [
  'assets/avatar/avatar_0_v2.png',
  'assets/avatar/avatar_1_v2.png',
  'assets/avatar/avatar_2_v2.png',
  'assets/avatar/avatar_3_v2.png',
];

const List<String> kDigitalAvatarNames = ['知性主播', '元气带货', '美妆主播', '数码讲师'];

/// 可选背景（场景视频）——「背景」按钮里选，和顶部"幕布"（绿布/红布/AI）是两件事
const List<String> kSceneVideos = [
  'assets/scenes/video_supermarket.mp4',
  'assets/scenes/video_produce.mp4',
  'assets/scenes/video_warehouse.mp4',
  'assets/scenes/video_bookstore.mp4',
  'assets/scenes/video_electronics.mp4',
  'assets/scenes/video_bazaar.mp4',
];

const List<String> kSceneNames = ['超市货架', '生鲜市集', '仓储发货', '书店', '数码店', '百货市场'];

/// 素材库实景图（「背景」里和视频场景并列可选）。
/// 老板已删掉不好看的几张，剩下 7 张重新编号。
const List<String> kBgImages = [
  'assets/backgrounds_v2/bg_01.jpeg',
  'assets/backgrounds_v2/bg_02.jpeg',
  'assets/backgrounds_v2/bg_03.jpeg',
  'assets/backgrounds_v2/bg_04.jpeg',
  'assets/backgrounds_v2/bg_05.jpeg',
  'assets/backgrounds_v2/bg_06.jpeg',
  'assets/backgrounds_v2/bg_07.jpeg',
];

const List<String> kBgImageNames = [
  '实景1', '实景2', '实景3', '实景4', '实景5', '实景6', '实景7',
];

/// 背景总表（0..5 = 视频场景，之后 = 实景图）——「背景」弹窗按这个顺序平铺
const List<String> kAllBgNames = [...kSceneNames, ...kBgImageNames];

/// 挂件贴纸：**全部是"完全抠像、无背景"的素材**
/// （6 个透明 GIF 动图 + 14 个透明 PNG 静图，都已逐帧实测透明占比）
const List<String> kStickers = [
  'assets/stickers_v2/sticker_01.gif',
  'assets/stickers_v2/sticker_02.gif',
  'assets/stickers_v2/sticker_03.gif',
  'assets/stickers_v2/sticker_04.gif',
  'assets/stickers_v2/sticker_05.gif',
  'assets/stickers_v2/sticker_06.gif',
  'assets/stickers_v2/sticker_07.png',
  'assets/stickers_v2/sticker_08.png',
  'assets/stickers_v2/sticker_09.png',
  'assets/stickers_v2/sticker_10.png',
  'assets/stickers_v2/sticker_11.png',
  'assets/stickers_v2/sticker_12.png',
  'assets/stickers_v2/sticker_13.png',
  'assets/stickers_v2/sticker_14.png',
  'assets/stickers_v2/sticker_15.png',
  'assets/stickers_v2/sticker_16.png',
  'assets/stickers_v2/sticker_17.png',
  'assets/stickers_v2/sticker_18.png',
  'assets/stickers_v2/sticker_19.png',
  'assets/stickers_v2/sticker_20.png',
];

/// 背景层：视频场景 或 实景图；未选/加载失败 → AI 渐变兜底。
/// 只负责背景，人（真人/数字人）由上层单独叠。
class SceneBackground extends StatefulWidget {
  /// 背景下标：0..kSceneVideos.length-1 = 视频场景；之后 = kBgImages 实景图；<0 = 渐变兜底
  final int index;
  final List<String> sceneVideos;
  final List<String> bgImages;

  const SceneBackground({
    super.key,
    required this.index,
    this.sceneVideos = kSceneVideos,
    this.bgImages = kBgImages,
  });

  @override
  State<SceneBackground> createState() => _SceneBackgroundState();
}

class _SceneBackgroundState extends State<SceneBackground> {
  VideoPlayerController? _c;
  bool _ready = false;

  static const _fallback = DecoratedBox(
    decoration: BoxDecoration(
        gradient: LinearGradient(colors: [Color(0xff2a1a4a), Color(0xff7c5cff)])),
  );

  /// 当前背景下标是不是"视频场景"
  bool get _isVideo =>
      widget.index >= 0 && widget.index < widget.sceneVideos.length;

  @override
  void initState() {
    super.initState();
    if (_isVideo) _load();
  }

  @override
  void didUpdateWidget(SceneBackground old) {
    super.didUpdateWidget(old);
    if (old.index == widget.index) return;
    if (_isVideo) {
      _load();
    } else if (_c != null) {
      _stopVideo();
    }
  }

  @override
  void dispose() {
    _c?.dispose();
    super.dispose();
  }

  void _stopVideo() {
    final old = _c;
    _c = null;
    old?.dispose();
    if (mounted) setState(() => _ready = false);
  }

  Future<void> _load() async {
    _stopVideo();

    final c = VideoPlayerController.asset(widget.sceneVideos[widget.index]);
    _c = c;
    try {
      await c.initialize();
      await c.setLooping(true);
      await c.setVolume(0);
      await c.play();
      if (mounted && _c == c) setState(() => _ready = true);
    } catch (_) {
      // 视频加载失败保持渐变兜底
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isVideo) {
      // 实景图背景（素材库图片）
      final i = widget.index - widget.sceneVideos.length;
      if (i >= 0 && i < widget.bgImages.length) {
        return Image.asset(widget.bgImages[i], fit: BoxFit.cover);
      }
      return _fallback; // 未选背景
    }
    final c = _c;
    if (c == null || !_ready) return _fallback;
    return FittedBox(
      fit: BoxFit.cover,
      child: SizedBox(
        width: c.value.size.width,
        height: c.value.size.height,
        child: VideoPlayer(c),
      ),
    );
  }
}

/// 数字人图层：**只有数字人本体**（透明背景）。
/// 支持**单指拖动 + 双指缩放**，双击复位。
/// 背景不在这里画——由宿主页叠 SceneVideoView / 色布渐变，这样"幕布"和"背景"是两个独立概念。
class DigitalAvatarLayer extends StatefulWidget {
  final int avatarIndex;
  final bool mirror;
  final List<String> avatarImages;

  const DigitalAvatarLayer({
    super.key,
    this.avatarIndex = 0,
    this.mirror = false,
    this.avatarImages = kDigitalAvatarImages,
  });

  @override
  State<DigitalAvatarLayer> createState() => _DigitalAvatarLayerState();
}

class _DigitalAvatarLayerState extends State<DigitalAvatarLayer> {
  List<ui.Image>? _frames;
  int _frameIdx = 0;
  Timer? _timer;
  int _loadGen = 0;

  // 拖动 / 缩放
  double _scale = 1.0;
  Offset _offset = Offset.zero;
  double _startScale = 1.0;
  Offset _startOffset = Offset.zero;
  Offset _startFocal = Offset.zero;

  static const double _baseW = 300;
  static const double _baseH = 400;

  @override
  void initState() {
    super.initState();
    _loadFrames(widget.avatarIndex);
  }

  @override
  void didUpdateWidget(DigitalAvatarLayer old) {
    super.didUpdateWidget(old);
    if (old.avatarIndex != widget.avatarIndex) _loadFrames(widget.avatarIndex);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _frames?.clear();
    super.dispose();
  }

  Future<void> _loadFrames(int avatar) async {
    final gen = ++_loadGen;
    _timer?.cancel();
    _frames?.clear();
    _frames = null;
    _frameIdx = 0;
    if (mounted) setState(() {});

    final frames = <ui.Image>[];
    for (int i = 0; i < 20; i++) {
      final name = 'assets/avatar_frames_v2/avatar_$avatar/'
          'f${i.toString().padLeft(2, '0')}.png';
      try {
        final data = await rootBundle.load(name);
        final codec = await ui.instantiateImageCodec(
            data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
        final frame = await codec.getNextFrame();
        frames.add(frame.image);
      } catch (_) {
        break; // 帧缺失就用已加载的部分
      }
    }
    if (!mounted || gen != _loadGen) return;
    setState(() {
      _frames = frames;
      _frameIdx = 0;
    });
    if (frames.isNotEmpty) {
      _timer = Timer.periodic(const Duration(milliseconds: 125), (_) {
        if (mounted && _frames != null && _frames!.isNotEmpty) {
          setState(() => _frameIdx = (_frameIdx + 1) % _frames!.length);
        }
      });
    }
  }

  void _onScaleStart(ScaleStartDetails d) {
    _startScale = _scale;
    _startOffset = _offset;
    _startFocal = d.focalPoint;
  }

  void _onScaleUpdate(ScaleUpdateDetails d) {
    setState(() {
      _scale = (_startScale * d.scale).clamp(0.35, 3.5);
      _offset = _startOffset + (d.focalPoint - _startFocal);
    });
  }

  void _reset() => setState(() {
        _scale = 1.0;
        _offset = Offset.zero;
      });

  @override
  Widget build(BuildContext context) {
    final frames = _frames;
    final idx = frames == null || frames.isEmpty
        ? -1
        : _frameIdx.clamp(0, frames.length - 1);

    Widget person;
    if (idx < 0) {
      // 帧序列缺失 → 回退静态图（仍可拖动缩放）
      final i = widget.avatarIndex.clamp(0, widget.avatarImages.length - 1);
      person = Image.asset(widget.avatarImages[i], fit: BoxFit.contain);
    } else {
      person = RawImage(image: frames![idx], fit: BoxFit.contain);
    }

    // 镜像（数字人的"翻转"）
    if (widget.mirror) {
      person = Transform(
        alignment: Alignment.center,
        transform: Matrix4.diagonal3Values(-1, 1, 1),
        child: person,
      );
    }

    return Align(
      alignment: const Alignment(0, 0.05),
      child: Transform.translate(
        offset: _offset,
        child: Transform.scale(
          scale: _scale,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onScaleStart: _onScaleStart,
            onScaleUpdate: _onScaleUpdate,
            onDoubleTap: _reset,
            child: SizedBox(width: _baseW, height: _baseH, child: person),
          ),
        ),
      ),
    );
  }
}
