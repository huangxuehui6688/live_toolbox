import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 数字人形象组件：插画 + 说话呼吸动画 + 音波指示 + 气泡。
///
/// [speaking]=true 时，插画做轻微呼吸缩放、底部音波条跳动，
/// 用于表达"数字人在开口说话"。真实口型开合需分层素材（闭嘴/张嘴图），
/// 当前先用呼吸 + 音波 + 气泡兜底，后续可换口型贴图。
class DigitalHumanAvatar extends StatefulWidget {
  final String imagePath; // asset 路径，如 assets/avatar/digital_host.png
  final bool speaking;
  final String? bubbleText; // 当前播报的文字（可选，显示为气泡）
  final double width;
  final double height;

  const DigitalHumanAvatar({
    super.key,
    required this.imagePath,
    this.speaking = false,
    this.bubbleText,
    this.width = 260,
    this.height = 300,
  });

  @override
  State<DigitalHumanAvatar> createState() => _DigitalHumanAvatarState();
}

class _DigitalHumanAvatarState extends State<DigitalHumanAvatar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 760));
    _scale = Tween<double>(begin: 1.0, end: 1.03).animate(
      CurvedAnimation(parent: _c, curve: Curves.easeInOut),
    );
    _sync();
  }

  void _sync() {
    if (widget.speaking) {
      _c.repeat(reverse: true);
    } else {
      _c.stop();
      _c.animateTo(0, duration: const Duration(milliseconds: 200));
    }
  }

  @override
  void didUpdateWidget(covariant DigitalHumanAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.speaking != widget.speaking) _sync();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: Stack(alignment: Alignment.bottomCenter, children: [
        // ===== 数字人插画卡片 =====
        AnimatedBuilder(
          animation: _c,
          builder: (context, _) => Transform.scale(
            scale: _scale.value,
            child: Container(
              width: widget.width,
              height: widget.height,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xfffdf0f6), Color(0xfff3ecff)],
                ),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: const Color(0xffefe7ff), width: 1.5),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xffb23df0).withValues(alpha: .16),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(23),
                child: Image.asset(
                  widget.imagePath,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => const Center(
                    child: Text('👩‍💼', style: TextStyle(fontSize: 72)),
                  ),
                ),
              ),
            ),
          ),
        ),

        // ===== 说话气泡 =====
        if (widget.bubbleText != null && widget.bubbleText!.isNotEmpty)
          Positioned(
            bottom: widget.height + 12,
            left: 0,
            right: 0,
            child: IgnorePointer(
              child: Center(
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 280),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: .08),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Text(
                    widget.bubbleText!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xff3a3f4d),
                      height: 1.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ),
          ),

        // ===== 底部音波指示器 =====
        Positioned(
          bottom: 10,
          child: _SoundWave(animating: widget.speaking, controller: _c),
        ),
      ]),
    );
  }
}

/// 3 根跳动的音波竖条，模拟"正在说话"。
class _SoundWave extends StatelessWidget {
  final bool animating;
  final AnimationController controller;
  const _SoundWave({required this.animating, required this.controller});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final phase = controller.value * math.pi * 2;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: .45),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: List.generate(3, (i) {
              final h = animating
                  ? 8.0 + 10.0 * (0.5 + 0.5 * math.sin(phase - i * 1.1))
                  : 5.0;
              return Container(
                width: 4,
                height: h,
                margin: const EdgeInsets.symmetric(horizontal: 2.5),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(2),
                ),
              );
            }),
          ),
        );
      },
    );
  }
}
