import 'dart:math' as math;

/// 把 ASR 流式文本对齐到提词稿行号（跟读核心）。
///
/// 思路：主播按顺序读稿。归一化（去标点空格）后，判断 ASR 累计文本
/// 已经"覆盖"到了稿子的第几行，覆盖到哪一行，当前就滚到哪一行。
/// 用「下一行核心片段是否已出现在 ASR 文本里」做前进判定，容错 ASR 的错字。
class AsrAligner {
  AsrAligner(this.scriptLines) {
    _normLines = scriptLines.map(_norm).toList();
  }

  /// 原始稿子行
  final List<String> scriptLines;

  late final List<String> _normLines;

  int _cur = 0;

  /// 跨句累计识别文本（关键：ASR 端点断句会 reset 累计文本，
  /// 但主播是连续读稿，必须跨句累计才能正确判断"念到第几行"）。
  String _accumulated = '';

  /// 当前对齐到的行号（0-based）
  int get current => _cur;

  /// 归一化后的当前行（供调试/展示）
  String get currentNorm => _cur < _normLines.length ? _normLines[_cur] : '';

  /// 喂入新的 ASR 文本，返回最新行号
  int feed(String asrText) {
    if (asrText.isEmpty || _normLines.isEmpty) return _cur;
    final a = _norm(asrText);
    if (a.isEmpty) return _cur;

    // 跨句累计：getResult 返回句内累计文本。若本次文本比历史长（句内延续）则
    // 直接替换；若变短说明端点断句 reset 了，把本次追加到历史尾部。
    final acc = _norm(_accumulated);
    if (a.length >= acc.length) {
      _accumulated = asrText;
    } else {
      _accumulated = _accumulated + asrText;
    }
    final accumulated = _norm(_accumulated);

    // 找累计文本覆盖到的最远行。允许跳过「识别不准」的行（最多连续跳 1 行），
    // 避免某一行识别错字导致后续全部卡住不动。
    var farthest = _cur;
    var skip = 0;
    for (var i = _cur + 1; i < _normLines.length; i++) {
      final line = _normLines[i];
      if (line.isEmpty || _matched(accumulated, line)) {
        farthest = i;
        skip = 0;
      } else {
        skip++;
        if (skip > 1) break; // 连续 2 行没匹配上，说明真没念到，停止
      }
    }
    _cur = farthest;
    return _cur;
  }

  /// 判断 ASR 累计文本 a 是否已覆盖「下一行」next：
  /// 依次尝试 next 的前 8/6/4/2 字前缀，任一出现在 a 里即算覆盖。
  bool _matched(String a, String next) {
    for (final n in const [8, 6, 4, 2]) {
      if (next.length <= n) {
        if (a.contains(next)) return true;
      } else if (a.contains(next.substring(0, n))) {
        return true;
      }
    }
    return false;
  }

  /// 归一化：去空白与常见中英文标点，只留字符
  String _norm(String s) => s.replaceAll(
      RegExp(r'[\s，。！？、；：""''（）《》〈〉,.!?;:…—·~`]'), '');

  /// 重置到开头
  void reset() {
    _cur = 0;
    _accumulated = '';
  }

  /// 试算一个"进度"（0~1），给 UI 显示滚动进度
  double get progress => _normLines.isEmpty
      ? 0
      : (_cur / math.max(1, _normLines.length - 1)).clamp(0.0, 1.0);
}
