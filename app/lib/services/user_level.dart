import 'package:flutter/foundation.dart';

/// 当前用户会员等级（本地模拟，后续接真实账号体系）。
///
/// 取值：'free'（免费）/ 'vip'（超级会员）/ 'svip'（运营商）。
/// 角标显示规则：功能所需等级 >= 当前等级时**不显示角标**（已开通），
/// 只有未开通时才显示，提示用户"这是付费功能"。
class UserLevel {
  UserLevel._();

  static final ValueNotifier<String> current = ValueNotifier<String>('free');

  static bool get isVip => current.value == 'vip' || current.value == 'svip';
  static bool get isSvip => current.value == 'svip';
}
