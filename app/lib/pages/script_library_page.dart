import 'package:flutter/material.dart';

import '../services/faq_store.dart';
import '../services/lang_store.dart';
import '../services/script_store.dart';
import 'lang_settings_page.dart';

const _kAccent = Color(0xff7c5cff);
const _kPageBg = Color(0xfff6f7fb);

/// 话术库 + 常见问题（FAQ）
///
/// 这是用户唯一需要"提前准备"的地方：
///   话术 → 数字人按顺序讲；常见问题 → 弹幕命中时插播对应回答。
class ScriptLibraryPage extends StatefulWidget {
  const ScriptLibraryPage({super.key});

  @override
  State<ScriptLibraryPage> createState() => _ScriptLibraryPageState();
}

class _ScriptLibraryPageState extends State<ScriptLibraryPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tab = TabController(length: 2, vsync: this);
  int _tabIndex = 0;

  List<Script> _scripts = [];
  List<Faq> _faqs = [];
  bool _loading = true;

  /// 当前目标语言：外文稿的标签、角标都跟着它变
  LangOption get _lang => LangStore.instance.current.value;

  @override
  void initState() {
    super.initState();
    _tab.addListener(_onTabChanged);
    LangStore.instance.current.addListener(_onLangChanged);
    // 读一次已保存的目标语言，再刷新界面
    LangStore.instance.ensureLoaded().then((_) {
      if (mounted) setState(() {});
    });
    _reload();
  }

  void _onLangChanged() {
    if (mounted) setState(() {});
  }

  void _onTabChanged() {
    if (!mounted) return;
    if (_tabIndex != _tab.index) setState(() => _tabIndex = _tab.index);
  }

  @override
  void dispose() {
    _tab.removeListener(_onTabChanged);
    LangStore.instance.current.removeListener(_onLangChanged);
    _tab.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    final s = await ScriptStore.instance.list();
    final f = await FaqStore.instance.list();
    if (!mounted) return;
    setState(() {
      _scripts = s;
      _faqs = f;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kPageBg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: const Color(0xff1a1a1a),
        title: const Text('话术库',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
        actions: [
          // 目标语言决定"外文稿"该写哪国语言，所以入口就放在话术库
          GestureDetector(
            onTap: _openLangSettings,
            behavior: HitTestBehavior.opaque,
            child: Container(
              margin: const EdgeInsets.only(right: 14),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                  color: const Color(0xfff0edff),
                  borderRadius: BorderRadius.circular(14)),
              child: Row(children: [
                const Text('🌐', style: TextStyle(fontSize: 12)),
                const SizedBox(width: 5),
                Text('目标语言：${_lang.name}',
                    style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: _kAccent)),
              ]),
            ),
          ),
        ],
        bottom: TabBar(
          controller: _tab,
          labelColor: _kAccent,
          unselectedLabelColor: const Color(0xff8a8a99),
          indicatorColor: _kAccent,
          indicatorSize: TabBarIndicatorSize.label,
          labelStyle:
              const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          tabs: const [Tab(text: '话术'), Tab(text: '常见问题')],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(
                  child: TabBarView(
                    controller: _tab,
                    children: [_scriptTab(), _faqTab()],
                  ),
                ),
              ],
            ),
      floatingActionButton: _loading
          ? null
          : FloatingActionButton.extended(
              onPressed: () =>
                  _tabIndex == 0 ? _editScript(null) : _editFaq(null),
              backgroundColor: _kAccent,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add),
              label: Text(
                _tabIndex == 0 ? '新增话术' : '新增问题',
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w600),
              ),
            ),
    );
  }

  /// 打开目标语言设置
  Future<void> _openLangSettings() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const LangSettingsPage()),
    );
    if (mounted) setState(() {});
  }

  // ---------------- 话术 ----------------

  Widget _scriptTab() {
    return Column(
      children: [
        _hint('每条话术存两份：中文稿（你自己讲的）+ ${_lang.scriptName}（境外观众看/听的）。'
            '按商品/段落分开写，一段讲一件事。目标语言可在右上角更换。'),
        Expanded(
          child: _scripts.isEmpty
              ? _empty('还没有话术', '把你直播要讲的话写进来，数字人照着讲',
                  actionLabel: '写下第一条话术',
                  onAction: () => _editScript(null))
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
                  itemCount: _scripts.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (_, i) {
                    final s = _scripts[i];
                    return _tile(
                      title: s.title.isEmpty ? '(未命名话术)' : s.title,
                      body: s.content.isEmpty ? '(还没写中文稿)' : s.content,
                      bodyForeign: s.foreign,
                      warn: !s.hasForeign,
                      badge:
                          '${s.content.split('\n').where((e) => e.trim().isNotEmpty).length} 句',
                      onEdit: () => _editScript(s),
                      onDelete: () async {
                        await ScriptStore.instance.delete(s.id);
                        await _reload();
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }

  Future<void> _editScript(Script? old) async {
    final title = TextEditingController(text: old?.title ?? '');
    final body = TextEditingController(text: old?.content ?? '');
    final foreign = TextEditingController(text: old?.foreign ?? '');
    final ok = await _editDialog(
      title: old == null ? '新增话术' : '编辑话术',
      fields: [
        _Field(
            label: '名称',
            hint: '给这段起个名，如「零食开场」',
            ctrl: title),
        _Field(
            label: '中文稿（你自己讲的）',
            hint: '一段一行。例：\n家人们，今天这个价格是真的压到底了\n只剩最后三十单，手慢就没了',
            ctrl: body,
            minLines: 4,
            maxLines: 8),
        _Field(
            label: '${_lang.scriptName}（给境外观众）',
            hint: '这段中文对应的${_lang.name}，例：\n${_lang.example}\n'
                '境外版直播时，观众看到和听到的就是这里的内容',
            ctrl: foreign,
            minLines: 3,
            maxLines: 8),
      ],
    );
    if (ok != true) return;
    if (old == null) {
      await ScriptStore.instance.create(title.text.trim(), body.text.trim(),
          foreign: foreign.text.trim());
    } else {
      await ScriptStore.instance.update(old.copyWith(
        title: title.text.trim(),
        content: body.text.trim(),
        foreign: foreign.text.trim(),
        updatedAt: DateTime.now(),
      ));
    }
    await _reload();
  }

  // ---------------- 常见问题 ----------------

  Widget _faqTab() {
    return Column(
      children: [
        _hint('弹幕问到的问题，命中这里就插播对应回答。每一条也存两份——'
            '中文一份、${_lang.scriptName}一份，境外版用${_lang.name}那份。'),
        Expanded(
          child: _faqs.isEmpty
              ? _empty('还没有常见问题', '把观众最常问的问题和你的回答写进来',
                  actionLabel: '添加第一条常见问题',
                  onAction: () => _editFaq(null))
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
                  itemCount: _faqs.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (_, i) {
                    final f = _faqs[i];
                    return _tile(
                      title: 'Q：${f.question}',
                      body: 'A：${f.answer}',
                      bodyForeign: f.answerForeign.isEmpty
                          ? f.questionForeign
                          : 'Q：${f.questionForeign}\nA：${f.answerForeign}',
                      warn: !f.hasForeign,
                      badge: null,
                      onEdit: () => _editFaq(f),
                      onDelete: () async {
                        await FaqStore.instance.delete(f.id);
                        await _reload();
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }

  Future<void> _editFaq(Faq? old) async {
    final q = TextEditingController(text: old?.question ?? '');
    final a = TextEditingController(text: old?.answer ?? '');
    final qf = TextEditingController(text: old?.questionForeign ?? '');
    final af = TextEditingController(text: old?.answerForeign ?? '');
    final ok = await _editDialog(
      title: old == null ? '新增常见问题' : '编辑常见问题',
      fields: [
        _Field(
            label: '问题（中文）',
            hint: '观众会怎么问（例：包邮吗）',
            ctrl: q),
        _Field(
            label: '回答（中文）',
            hint: '你希望数字人怎么回答（例：全国包邮，偏远地区也可以发）',
            ctrl: a,
            minLines: 2,
            maxLines: 4),
        _Field(
            label: '问题（${_lang.name}）',
            hint: '把上面的问题翻成${_lang.short}（例：Do you ship for free?）',
            ctrl: qf),
        _Field(
            label: '回答（${_lang.name}）',
            hint: '把上面的回答翻成${_lang.short}',
            ctrl: af,
            minLines: 2,
            maxLines: 4),
      ],
    );
    if (ok != true) return;
    if (old == null) {
      await FaqStore.instance.create(q.text.trim(), a.text.trim(),
          questionForeign: qf.text.trim(), answerForeign: af.text.trim());
    } else {
      await FaqStore.instance.update(old.copyWith(
        question: q.text.trim(),
        answer: a.text.trim(),
        questionForeign: qf.text.trim(),
        answerForeign: af.text.trim(),
        updatedAt: DateTime.now(),
      ));
    }
    await _reload();
  }

  // ---------------- 通用组件 ----------------

  Widget _hint(String text) => Container(
        width: double.infinity,
        margin: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xfff0edff),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(text,
            style: const TextStyle(
                fontSize: 12, height: 1.6, color: Color(0xff6b6b7b))),
      );

  Widget _empty(String title, String sub,
          {String? actionLabel, VoidCallback? onAction}) =>
      Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('📝', style: TextStyle(fontSize: 38)),
            const SizedBox(height: 12),
            Text(title,
                style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Color(0xff2c2c3a))),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 48),
              child: Text(sub,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 12.5, height: 1.6, color: Color(0xff8a8a99))),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 18),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: _kAccent,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 22, vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: onAction,
                child: Text(actionLabel,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600)),
              ),
            ],
          ],
        ),
      );

  Widget _tile({
    required String title,
    required String body,
    String? bodyForeign,
    bool warn = false,
    String? badge,
    required VoidCallback onEdit,
    required VoidCallback onDelete,
  }) {
    final hasForeign = (bodyForeign ?? '').trim().isNotEmpty;
    return Dismissible(
      key: ValueKey('$title|$body|${bodyForeign ?? ''}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: const Color(0xffff5a5a),
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Icon(Icons.delete_outline, color: Colors.white),
      ),
      onDismissed: (_) => onDelete(),
      child: InkWell(
        onTap: onEdit,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xffeeeef4)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Color(0xff1a1a1a))),
                  ),
                  if (warn && !hasForeign)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                          color: const Color(0xfffff3e6),
                          borderRadius: BorderRadius.circular(6)),
                      child: Text('缺${_lang.short}稿',
                          style: const TextStyle(
                              fontSize: 10, color: Color(0xffe08a2e))),
                    ),
                  if (badge != null) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                          color: const Color(0xfff0edff),
                          borderRadius: BorderRadius.circular(6)),
                      child: Text(badge,
                          style: const TextStyle(
                              fontSize: 10.5, color: _kAccent)),
                    ),
                  ],
                  const SizedBox(width: 6),
                  const Icon(Icons.edit_outlined,
                      size: 15, color: Color(0xffb0b0c0)),
                ],
              ),
              const SizedBox(height: 6),
              Text(body,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 12.5, height: 1.55, color: Color(0xff6b6b7b))),
              if (hasForeign) ...[
                const SizedBox(height: 9),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(
                    color: const Color(0xfff6f4ff),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                                color: _kAccent.withValues(alpha: 0.13),
                                borderRadius: BorderRadius.circular(4)),
                            child: Text(_lang.badge,
                                style: const TextStyle(
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.w700,
                                    color: _kAccent)),
                          ),
                          const SizedBox(width: 6),
                          const Text('境外版用这版',
                              style: TextStyle(
                                  fontSize: 10, color: Color(0xff9a9aae))),
                        ],
                      ),
                      const SizedBox(height: 5),
                      Text(bodyForeign!,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 12.5,
                              height: 1.5,
                              color: Color(0xff5b5b70))),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<bool?> _editDialog({
    required String title,
    required List<_Field> fields,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(title, style: const TextStyle(fontSize: 16)),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < fields.length; i++) ...[
                  if (i > 0) const SizedBox(height: 14),
                  Text(fields[i].label,
                      style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: Color(0xff2c2c3a))),
                  const SizedBox(height: 6),
                  TextField(
                    controller: fields[i].ctrl,
                    minLines: fields[i].minLines,
                    maxLines: fields[i].maxLines,
                    decoration: InputDecoration(
                      hintText: fields[i].hint,
                      hintStyle: const TextStyle(fontSize: 12),
                      border: const OutlineInputBorder(),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 10),
                    ),
                    style: const TextStyle(fontSize: 13.5, height: 1.45),
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _kAccent),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }
}

/// 编辑弹窗里的一栏（带标签的多行输入）
class _Field {
  final String label;
  final String hint;
  final TextEditingController ctrl;
  final int minLines;
  final int maxLines;

  const _Field({
    required this.label,
    required this.hint,
    required this.ctrl,
    this.minLines = 1,
    this.maxLines = 1,
  });
}
