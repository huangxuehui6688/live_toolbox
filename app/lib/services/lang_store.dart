import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 一种可选的目标语言（境外观众看/听的那一版文案用什么语言写）。
///
/// 首版口径：一次只输出一种目标语言，由用户在「目标语言」里单选。
class LangOption {
  final String code; // 落盘用的稳定标识：en / es / pt
  final String name; // 界面上的完整名：英语 / 西班牙语 / 葡萄牙语
  final String short; // 短名，用于"缺英文稿"这类文案：英文 / 西语 / 葡语
  final String badge; // 列表卡片角标：EN / ES / PT
  final String scriptName; // 外文稿的称呼：英文稿 / 西班牙文稿 / 葡萄牙文稿

  const LangOption({
    required this.code,
    required this.name,
    required this.short,
    required this.badge,
    required this.scriptName,
  });

  /// 写稿时给用户的示例，省得不知道该写哪种语言
  String get example => switch (code) {
        'es' => '¡Hola a todos! Hoy tenemos una oferta increíble.',
        'pt' => 'Olá pessoal! Hoje temos uma oferta incrível.',
        _ => 'Welcome, everyone! We have an amazing deal today.',
      };
}

/// 全部候选语言（首版就这三种）
const List<LangOption> kLangOptions = [
  LangOption(
      code: 'en',
      name: '英语',
      short: '英文',
      badge: 'EN',
      scriptName: '英文稿'),
  LangOption(
      code: 'es',
      name: '西班牙语',
      short: '西语',
      badge: 'ES',
      scriptName: '西班牙文稿'),
  LangOption(
      code: 'pt',
      name: '葡萄牙语',
      short: '葡语',
      badge: 'PT',
      scriptName: '葡萄牙文稿'),
];

/// 目标语言设置：本地文件 JSON 持久化的单选状态。
///
/// 持久化文件：getApplicationDocumentsDirectory()/live_lang.json
/// 与 ScriptStore 一样走「懒加载 + 内存缓存 + 写操作全量落盘」，
/// 不引入新依赖。current 是 ValueNotifier，话术库等页面监听它实时刷新。
class LangStore {
  LangStore._();
  static final LangStore instance = LangStore._();

  static const String _fileName = 'live_lang.json';

  /// 当前目标语言，默认英语
  final ValueNotifier<LangOption> current =
      ValueNotifier<LangOption>(kLangOptions.first);

  bool _loaded = false;
  bool _userPicked = false; // 用户已经手动选过，就别被慢一拍的读盘结果覆盖

  /// 读一次本地设置；重复调用只会真正读一次
  Future<void> ensureLoaded() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final file = await _file();
      if (!await file.exists()) return;
      final raw = await file.readAsString();
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final code = map['code'] as String? ?? '';
      final hit = kLangOptions.where((o) => o.code == code);
      if (hit.isNotEmpty && !_userPicked) current.value = hit.first;
    } catch (_) {
      // 文件损坏时保持默认英语，不影响启动
    }
  }

  /// 单选切换目标语言：先更新界面状态，再落盘
  Future<void> setLang(LangOption option) async {
    _loaded = true;
    _userPicked = true;
    current.value = option;
    try {
      final file = await _file();
      await file.writeAsString(jsonEncode({'code': option.code}));
    } catch (e) {
      // 技术细节只进日志；设置页一律中文提示
      debugPrint('[LangStore] 保存目标语言失败: $e');
    }
  }

  Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File(p.join(dir.path, _fileName));
  }
}
