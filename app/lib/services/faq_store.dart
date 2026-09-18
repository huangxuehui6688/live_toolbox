import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 一条常见问题（弹幕命中时插播对应答案的预生成视频）
///
/// 同样存两份文字：中文（主播/国内）+ 外文（境外观众）。
class Faq {
  final String id;
  final String question; // 观众可能问的问题（中文）
  final String answer; // 数字人要回答的内容（中文）
  final String questionForeign; // 外文问题（英文等）
  final String answerForeign; // 外文回答
  final DateTime updatedAt;

  const Faq({
    required this.id,
    required this.question,
    required this.answer,
    this.questionForeign = '',
    this.answerForeign = '',
    required this.updatedAt,
  });

  /// 是否有外文问答（决定这条能不能给境外观众用）
  bool get hasForeign =>
      questionForeign.trim().isNotEmpty || answerForeign.trim().isNotEmpty;

  Map<String, dynamic> toJson() => {
        'id': id,
        'question': question,
        'answer': answer,
        'questionForeign': questionForeign,
        'answerForeign': answerForeign,
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory Faq.fromJson(Map<String, dynamic> json) => Faq(
        id: json['id'] as String,
        question: json['question'] as String? ?? '',
        answer: json['answer'] as String? ?? '',
        questionForeign: json['questionForeign'] as String? ?? '',
        answerForeign: json['answerForeign'] as String? ?? '',
        updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
            DateTime.now(),
      );

  Faq copyWith({
    String? question,
    String? answer,
    String? questionForeign,
    String? answerForeign,
    DateTime? updatedAt,
  }) =>
      Faq(
        id: id,
        question: question ?? this.question,
        answer: answer ?? this.answer,
        questionForeign: questionForeign ?? this.questionForeign,
        answerForeign: answerForeign ?? this.answerForeign,
        updatedAt: updatedAt ?? this.updatedAt,
      );
}

/// 常见问题库：CRUD + 本地 JSON 持久化（与 ScriptStore 同款方案）。
class FaqStore {
  FaqStore._();
  static final FaqStore instance = FaqStore._();

  static const String _fileName = 'faqs.json';

  List<Faq> _cache = [];
  bool _loaded = false;
  int _seq = 0;

  Future<List<Faq>> list() async {
    await _ensureLoaded();
    final list = List<Faq>.from(_cache);
    list.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return list;
  }

  Future<Faq> create(String question, String answer,
      {String questionForeign = '', String answerForeign = ''}) async {
    await _ensureLoaded();
    final faq = Faq(
      id: _newId(),
      question: question,
      answer: answer,
      questionForeign: questionForeign,
      answerForeign: answerForeign,
      updatedAt: DateTime.now(),
    );
    _cache.add(faq);
    await _persist();
    return faq;
  }

  Future<void> update(Faq faq) async {
    await _ensureLoaded();
    final idx = _cache.indexWhere((f) => f.id == faq.id);
    if (idx >= 0) {
      _cache[idx] = faq;
    } else {
      _cache.add(faq);
    }
    await _persist();
  }

  Future<void> delete(String id) async {
    await _ensureLoaded();
    _cache.removeWhere((f) => f.id == id);
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
      _cache = (jsonDecode(raw) as List<dynamic>)
          .map((e) => Faq.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      _cache = [];
    }
  }

  Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File(p.join(dir.path, _fileName));
  }

  Future<void> _persist() async {
    final file = await _file();
    await file.writeAsString(jsonEncode(_cache.map((f) => f.toJson()).toList()));
  }

  String _newId() => '${DateTime.now().microsecondsSinceEpoch}_${_seq++}';
}
