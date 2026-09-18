import 'package:flutter/material.dart';

import '../services/lang_store.dart';

const _purple = Color(0xff7c5cff);
const _bg = Color(0xfff6f7fb);
const _sub = Color(0xff9aa0b0);

/// 目标语言设置（单选）
///
/// 决定话术库里"外文稿"那一栏该写哪国语言，也决定生成境外版视频时用哪一版稿。
/// 首版一次只输出一种语言，所以这里做单选、不做多选。
class LangSettingsPage extends StatefulWidget {
  const LangSettingsPage({super.key});

  @override
  State<LangSettingsPage> createState() => _LangSettingsPageState();
}

class _LangSettingsPageState extends State<LangSettingsPage> {
  LangOption _selected = LangStore.instance.current.value;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await LangStore.instance.ensureLoaded();
    if (!mounted) return;
    setState(() => _selected = LangStore.instance.current.value);
  }

  Future<void> _pick(LangOption o) async {
    setState(() => _selected = o);
    await LangStore.instance.setLang(o);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: const Color(0xff1a1a1a),
        title: const Text('目标语言',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
        children: [
          _hint(),
          const SizedBox(height: 14),
          for (final o in kLangOptions) ...[
            _optionTile(o),
            const SizedBox(height: 10),
          ],
          const SizedBox(height: 6),
          _note(),
        ],
      ),
    );
  }

  Widget _hint() => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xfff0edff),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Text(
            '境外版直播一次只说一种语言，所以这里只选一种。'
            '选好之后，话术库里的"外文稿"就按这个语言写，列表上的角标也会跟着变。',
            style: TextStyle(
                fontSize: 12, height: 1.6, color: Color(0xff6b6b7b))),
      );

  Widget _optionTile(LangOption o) {
    final on = o.code == _selected.code;
    return GestureDetector(
      onTap: () => _pick(o),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: on ? _purple : const Color(0xffeeeef4),
              width: on ? 1.5 : 1),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: .04),
                blurRadius: 8,
                offset: const Offset(0, 2))
          ],
        ),
        child: Row(children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
                color: on ? _purple : const Color(0xfff0edff),
                borderRadius: BorderRadius.circular(12)),
            child: Center(
                child: Text(o.badge,
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: on ? Colors.white : _purple))),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(o.name,
                      style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Color(0xff1a1a1a))),
                  const SizedBox(height: 4),
                  Text('外文稿写成：${o.scriptName}',
                      style: const TextStyle(fontSize: 11.5, color: _sub)),
                ]),
          ),
          Icon(on ? Icons.radio_button_checked : Icons.radio_button_off,
              size: 20, color: on ? _purple : const Color(0xffc8c8d4)),
        ]),
      ),
    );
  }

  Widget _note() => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xffeeeef4)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${_selected.name}示例',
              style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: Color(0xff2c2c3a))),
          const SizedBox(height: 6),
          Text(_selected.example,
              style: const TextStyle(
                  fontSize: 12,
                  height: 1.5,
                  color: Color(0xff6b6b7b))),
        ]),
      );
}
