import 'package:flutter/foundation.dart';

/// AI 数字人形象库 + 当前选中的形象。
///
/// 形象素材统一规格（见 直播/方案-数字人2D完整流程.md）：
///   透明背景、正面正对镜头、半身、28~32 岁、嘴部与下巴无遮挡。
/// 素材全部预置在 assets/avatars_ai/，用户只需选一个，不需要自己拍。
class AiAvatar {
  final String asset; // assets/avatars_ai/ 下的文件名
  final String name; // 展示名
  final String tag; // 一句话标签

  const AiAvatar({required this.asset, required this.name, required this.tag});
}

class AvatarStore {
  AvatarStore._();

  /// 形象库（首版 2 个，最终计划 6 个）
  static const List<AiAvatar> library = <AiAvatar>[
    AiAvatar(asset: 'ai_avatar_f1.png', name: '小雅', tag: '女 · 28~32岁 · 亲和可信'),
    AiAvatar(asset: 'ai_avatar_m1.png', name: '阿泽', tag: '男 · 28~32岁 · 踏实实在'),
  ];

  /// 当前选中的形象（null = 还没选）
  static final ValueNotifier<String?> selected =
      ValueNotifier<String?>(null);

  static AiAvatar? get current {
    final id = selected.value;
    if (id == null) return null;
    for (final a in library) {
      if (a.asset == id) return a;
    }
    return null;
  }

  static String assetPath(AiAvatar a) => 'assets/avatars_ai/${a.asset}';
}
