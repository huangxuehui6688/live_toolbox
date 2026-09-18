import 'dart:async';

import 'package:flutter/material.dart';

import '../services/asr_service.dart';
import '../services/caption_settings.dart';

/// 直播间实时字幕叠加层：订阅 ASR 流，把主播说的话显示在画面上。
/// 叠在相机预览之上（观众能看到的那一层），随推流一起出去。
/// 样式由 [CaptionSettings.style] 全局控制，设置页改动实时生效。
class LiveCaptionOverlay extends StatefulWidget {
  const LiveCaptionOverlay({super.key});

  @override
  State<LiveCaptionOverlay> createState() => _LiveCaptionOverlayState();
}

class _LiveCaptionOverlayState extends State<LiveCaptionOverlay> {
  String _text = '';
  StreamSubscription<AsrResult>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = AsrService.instance.results.listen((r) {
      if (!mounted) return;
      if (r.text != _text) setState(() => _text = r.text);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_text.isEmpty) return const SizedBox.shrink();

    return ValueListenableBuilder<CaptionStyle>(
      valueListenable: CaptionSettings.style,
      builder: (context, style, _) {
        final text = Text(
          _text,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white,
            fontSize: style.fontSize,
            fontWeight: FontWeight.w600,
            shadows: const [
              Shadow(
                  color: Colors.black87,
                  blurRadius: 4,
                  offset: Offset(0, 1)),
            ],
          ),
        );

        return Align(
          alignment: style.alignment,
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 70),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: style.withBackground
                ? BoxDecoration(
                    color: Colors.black.withValues(alpha: .45),
                    borderRadius: BorderRadius.circular(10),
                  )
                : null,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: text,
            ),
          ),
        );
      },
    );
  }
}
