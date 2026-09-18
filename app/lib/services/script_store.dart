import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 一套话术草稿
///
/// 一条话术同时存两份文字：
///   content —— 中文稿（主播自己讲 / 国内用）
///   foreign —— 外文稿（给境外观众看和听的，如英文）
/// 两份都可留空，留空表示这条只服务一边。
class Script {
  final String id;
  final String title; // 如"零食专场"
  final String content; // 中文稿，按 \n 拆行传给悬浮窗
  final String foreign; // 外文稿（英文/西文/葡文，取决于目标语言设置）
  final DateTime updatedAt;

  const Script({
    required this.id,
    required this.title,
    required this.content,
    this.foreign = '',
    required this.updatedAt,
  });

  /// 是否有外文稿（决定这条话术能不能给境外观众用）
  bool get hasForeign => foreign.trim().isNotEmpty;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'content': content,
        'foreign': foreign,
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory Script.fromJson(Map<String, dynamic> json) => Script(
        id: json['id'] as String,
        title: json['title'] as String? ?? '',
        content: json['content'] as String? ?? '',
        foreign: json['foreign'] as String? ?? '',
        updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
            DateTime.now(),
      );

  Script copyWith({
    String? title,
    String? content,
    String? foreign,
    DateTime? updatedAt,
  }) =>
      Script(
        id: id,
        title: title ?? this.title,
        content: content ?? this.content,
        foreign: foreign ?? this.foreign,
        updatedAt: updatedAt ?? this.updatedAt,
      );
}

/// 台词库：多套话术草稿的 CRUD + 本地文件 JSON 持久化。
///
/// 持久化文件：getApplicationDocumentsDirectory()/scripts.json
/// 采用「懒加载 + 内存缓存 + 每次写操作全量落盘」的简单方案。
class ScriptStore {
  ScriptStore._();
  static final ScriptStore instance = ScriptStore._();

  static const String _fileName = 'scripts.json';

  List<Script> _cache = [];
  bool _loaded = false;
  int _seq = 0;

  /// 按 updatedAt 倒序返回所有草稿
  Future<List<Script>> list() async {
    await _ensureLoaded();
    final list = List<Script>.from(_cache);
    list.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return list;
  }

  /// 按 id 查找（可能返回 null）
  Script? get(String id) {
    for (final s in _cache) {
      if (s.id == id) return s;
    }
    return null;
  }

  Future<Script> create(String title, String content,
      {String foreign = ''}) async {
    await _ensureLoaded();
    final script = Script(
      id: _newId(),
      title: title,
      content: content,
      foreign: foreign,
      updatedAt: DateTime.now(),
    );
    _cache.add(script);
    await _persist();
    return script;
  }

  /// 更新已有草稿（id 不变，updatedAt 由调用方决定，通常传 DateTime.now()）
  Future<void> update(Script script) async {
    await _ensureLoaded();
    final idx = _cache.indexWhere((s) => s.id == script.id);
    if (idx >= 0) {
      _cache[idx] = script;
    } else {
      _cache.add(script);
    }
    await _persist();
  }

  Future<void> delete(String id) async {
    await _ensureLoaded();
    _cache.removeWhere((s) => s.id == id);
    await _persist();
  }

  Future<void> _ensureLoaded() async {
    if (_loaded) return;
    _loaded = true;
    final file = await _file();
    if (!await file.exists()) {
      _cache = [];
      return;
    }
    try {
      final raw = await file.readAsString();
      final list = (jsonDecode(raw) as List<dynamic>)
          .map((e) => Script.fromJson(e as Map<String, dynamic>))
          .toList();
      _cache = list;
    } catch (_) {
      // 文件损坏时回退为空库，避免影响启动
      _cache = [];
    }
  }

  Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File(p.join(dir.path, _fileName));
  }

  Future<void> _persist() async {
    final file = await _file();
    final list = _cache.map((s) => s.toJson()).toList();
    await file.writeAsString(jsonEncode(list));
  }

  String _newId() =>
      '${DateTime.now().microsecondsSinceEpoch}_${_seq++}';
}
