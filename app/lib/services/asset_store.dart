import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 素材的唯一键：**哪句话（话术第几行）× 一个形象 × 一种语言** = 一份产物。
///
/// 之所以不做自增 id：素材天生是多维组合（以后要"换形象重新生成"、
/// "英语一份西语一份"），用这个组合当键，同一组合重复生成就是覆盖，
/// 不会越攒越多、也不会出现两条"同一句话同一个形象"的记录。
///
/// ★[lineIdx] 单独一个维度、**不要把它并进 scriptId**：scriptId 是外键，
///   `listFor(scriptId)` 要能按话术聚合（统计完成度、整条删素材）。
///   一旦掺成 `id#3`，以后每次聚合都得先拆字符串。
String assetKey(String scriptId, int lineIdx, int avatarId, String lang) =>
    '$scriptId|$lineIdx|$avatarId|$lang';

/// 中文版素材的语言取值。外文版用 `LangStore` 里 `LangOption.code`
/// （en / es / pt）——和话术库里"中文稿 / 外文稿"的口径保持一致。
const String kAssetLangZh = 'zh';

/// FAQ 答案产物的行号约定：**-1 表示"这是 FAQ 的答案，不是话术的某一行"**。
///
/// 话术行的 lineIdx 一律 >= 0，FAQ 一律 -1，**两种产物靠正负天然分开**，
/// 即使 Script.id 和 Faq.id 万一同一个字符串也不会撞键。
/// （`lineIdx == kAssetLineFaq` 时，`scriptId` 里放的是 `Faq.id`。）
const int kAssetLineFaq = -1;

/// 一条生成产物：某句话、某个形象、某种语言对应的那份素材。
///
/// 单独建表而不是往 `Script` / `Faq` 里加字段，是因为这里存的东西
/// **不属于"话术"本身**：同一句话 × 不同形象 × 不同语言各是一份产物，
/// 还要记生成状态与时长。塞进话术模型里，第二个维度一来就爆。
class AssetInfo {
  /// 生成状态：未生成 / 生成中 / 完成 / 失败
  static const String statusPending = 'pending';
  static const String statusGenerating = 'generating';
  static const String statusDone = 'done';
  static const String statusFailed = 'failed';

  final String scriptId; // 话术产物 = Script.id；FAQ 产物 = Faq.id（见 kAssetLineFaq）
  final int lineIdx; // 话术里第几行（从 0 起）；FAQ 用 kAssetLineFaq(-1)
  /// ★生成当时这一行的**原文**。用来判断素材有没有失效，见 [isStale]。
  /// FAQ 产物这里存的是当时的 `Faq.answer`，同样能判失效。
  final String lineText;
  final int avatarId; // 数字人形象下标（kDigitalAvatarImages / kDigitalAvatarNames）
  final String lang; // kAssetLangZh 或 LangOption.code
  final String path; // 产物文件路径；未生成/失败时为空
  final int durationMs; // 时长（毫秒），没生成出来时为 0
  final String status; // 见上面 4 个状态常量
  final DateTime createdAt;

  const AssetInfo({
    required this.scriptId,
    required this.lineIdx,
    this.lineText = '',
    required this.avatarId,
    required this.lang,
    this.path = '',
    this.durationMs = 0,
    this.status = statusPending,
    required this.createdAt,
  });

  /// 唯一键，见 [assetKey]
  String get key => assetKey(scriptId, lineIdx, avatarId, lang);

  /// 这条产物是 FAQ 的答案（不是话术的某一行）
  bool get isFaq => lineIdx == kAssetLineFaq;

  /// 素材是否已经**失效**：话术改过，素材和文本对不上了。
  ///
  /// 判定就用最直白的字符串比较（改一个字也该判失效），**不算 hash** ——
  /// 好读、好调试，出错时一眼能看出是哪句对不上。
  ///
  /// ★为什么非要存 `lineText`、光比行号不行：**行号会在用户编辑话术后错位**。
  ///   用户在中间插一行，原来的"第 5 行"就变成"第 4 行"，素材和新文本静默错配，
  ///   而且**不报错**，只表现为"数字人讲的内容和画面/语音不符"——最难查的那种 bug。
  ///   所以**以文本为准，行号只用来定位**。
  ///
  /// 调用方拿到 stale 的素材时，应把它当作未生成（`status` 降回 [statusPending]），
  /// 界面上提示"话术改过，需要重新生成"。
  bool isStale(String currentLineText) =>
      lineText.trim() != currentLineText.trim();

  Map<String, dynamic> toJson() => {
        'scriptId': scriptId,
        'lineIdx': lineIdx,
        'lineText': lineText,
        'avatarId': avatarId,
        'lang': lang,
        'path': path,
        'durationMs': durationMs,
        'status': status,
        'createdAt': createdAt.toIso8601String(),
      };

  factory AssetInfo.fromJson(Map<String, dynamic> json) => AssetInfo(
        scriptId: json['scriptId'] as String? ?? '',
        lineIdx: json['lineIdx'] as int? ?? 0,
        // 老记录/缺字段时留空 → isStale 会判成失效，逼一次重新生成（宁可重做，不可错配）
        lineText: json['lineText'] as String? ?? '',
        avatarId: json['avatarId'] as int? ?? 0,
        lang: json['lang'] as String? ?? '',
        path: json['path'] as String? ?? '',
        durationMs: json['durationMs'] as int? ?? 0,
        status: json['status'] as String? ?? statusPending,
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
            DateTime.now(),
      );

  /// 键（scriptId / lineIdx / avatarId / lang）即身份，不参与 copyWith
  AssetInfo copyWith({
    String? lineText,
    String? path,
    int? durationMs,
    String? status,
    DateTime? createdAt,
  }) =>
      AssetInfo(
        scriptId: scriptId,
        lineIdx: lineIdx,
        lineText: lineText ?? this.lineText,
        avatarId: avatarId,
        lang: lang,
        path: path ?? this.path,
        durationMs: durationMs ?? this.durationMs,
        status: status ?? this.status,
        createdAt: createdAt ?? this.createdAt,
      );
}

/// 素材库：生成产物的登记表（哪句话 / 哪个形象 / 哪种语言有没有、什么状态）。
///
/// 持久化文件：getApplicationDocumentsDirectory()/assets.json
/// 与 ScriptStore 一样走「懒加载 + 内存缓存 + 写操作全量落盘」，
/// 不引入新依赖。**只存登记信息，不搬产物文件本身。**
class AssetStore {
  AssetStore._();
  static final AssetStore instance = AssetStore._();

  static const String _fileName = 'assets.json';

  List<AssetInfo> _cache = [];

  /// 与 ScriptStore 一致：懒加载，读一次就不再读盘
  bool _loaded = false;

  /// 取某句话 × 某个形象 × 某种语言的产物；没有则 null。
  /// 这里做成异步（不像 ScriptStore.get 那样同步）是为了先 `_ensureLoaded()`，
  /// 否则冷启动时第一次取会"明明有却查不到"。
  ///
  /// ★拿到之后**记得用 `asset.isStale(当前这一行的文本)` 判一下**：
  ///   话术被改过的话，这份素材已经和文本对不上了，要当未生成处理。
  Future<AssetInfo?> get(
      String scriptId, int lineIdx, int avatarId, String lang) async {
    await _ensureLoaded();
    final key = assetKey(scriptId, lineIdx, avatarId, lang);
    for (final a in _cache) {
      if (a.key == key) return a;
    }
    return null;
  }

  /// 登记/更新一份产物（同键覆盖，不会重复累积）
  Future<void> save(AssetInfo info) async {
    await _ensureLoaded();
    final idx = _cache.indexWhere((a) => a.key == info.key);
    if (idx >= 0) {
      _cache[idx] = info;
    } else {
      _cache.add(info);
    }
    await _persist();
  }

  /// 删除某个组合的产物登记
  Future<void> remove(
      String scriptId, int lineIdx, int avatarId, String lang) async {
    await _ensureLoaded();
    final key = assetKey(scriptId, lineIdx, avatarId, lang);
    _cache.removeWhere((a) => a.key == key);
    await _persist();
  }

  /// 某条话术的全部产物（各形象 / 各语言 / 各行），按登记顺序返回。
  /// ★FAQ 的产物 lineIdx = [kAssetLineFaq]，与话术行天然不同键，不会混进来。
  Future<List<AssetInfo>> listFor(String scriptId) async {
    await _ensureLoaded();
    return _cache.where((a) => a.scriptId == scriptId).toList();
  }

  /// 标记生成失败。
  /// ★已有记录只改状态、**不清 path**：失败的是"重新生成"那一次，
  ///   上一次生成好的旧产物可能还有用，别顺手删掉。
  Future<void> markFailed(String scriptId, int lineIdx, int avatarId, String lang,
      {String lineText = ''}) async {
    await _ensureLoaded();
    final key = assetKey(scriptId, lineIdx, avatarId, lang);
    final idx = _cache.indexWhere((a) => a.key == key);
    if (idx >= 0) {
      _cache[idx] = _cache[idx].copyWith(status: AssetInfo.statusFailed);
    } else {
      _cache.add(AssetInfo(
        scriptId: scriptId,
        lineIdx: lineIdx,
        lineText: lineText,
        avatarId: avatarId,
        lang: lang,
        status: AssetInfo.statusFailed,
        createdAt: DateTime.now(),
      ));
    }
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
          .map((e) => AssetInfo.fromJson(e as Map<String, dynamic>))
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
    final list = _cache.map((a) => a.toJson()).toList();
    await file.writeAsString(jsonEncode(list));
  }
}
