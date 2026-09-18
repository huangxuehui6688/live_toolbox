import 'package:flutter/foundation.dart';

/// 美颜参数（全局单例，直播间和设置页共用）。
///
/// 三个维度都是 0~1，0=关闭。用 [ValueNotifier] 便于渲染层直接监听重绘。
class BeautySettings {
  BeautySettings._();

  /// 磨皮强度（0~1）：越大皮肤越平滑，1 会明显失真
  static final ValueNotifier<double> smooth = ValueNotifier<double>(0);

  /// 美白强度（0~1）：提亮肤色
  static final ValueNotifier<double> whiten = ValueNotifier<double>(0);

  /// 瘦脸强度（0~1）：目前仅记录，需 FaceMesh 关键点 warp 实现
  static final ValueNotifier<double> slimFace = ValueNotifier<double>(0);

  /// 是否开启（任一维度 > 0）
  static bool get isOn =>
      smooth.value > 0 || whiten.value > 0 || slimFace.value > 0;

  /// 一键重置
  static void reset() {
    smooth.value = 0;
    whiten.value = 0;
    slimFace.value = 0;
  }
}
