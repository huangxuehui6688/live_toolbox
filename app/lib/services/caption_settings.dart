import 'package:flutter/material.dart';

/// 字幕样式（字号/位置/背景）
class CaptionStyle {
  final double fontSize;
  final Alignment alignment;
  final bool withBackground;

  const CaptionStyle({
    this.fontSize = 18,
    this.alignment = Alignment.bottomCenter,
    this.withBackground = true,
  });

  CaptionStyle copyWith({
    double? fontSize,
    Alignment? alignment,
    bool? withBackground,
  }) =>
      CaptionStyle(
        fontSize: fontSize ?? this.fontSize,
        alignment: alignment ?? this.alignment,
        withBackground: withBackground ?? this.withBackground,
      );
}

/// 字幕全局设置（内存态，首版不落盘）
class CaptionSettings {
  CaptionSettings._();
  static final ValueNotifier<CaptionStyle> style =
      ValueNotifier(const CaptionStyle());
}
