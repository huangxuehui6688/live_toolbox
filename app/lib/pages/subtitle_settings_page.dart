import 'package:flutter/material.dart';

import '../services/caption_settings.dart';

const _purple = Color(0xff7c5cff);
const _pink = Color(0xffff2d7a);
const _grad = LinearGradient(colors: [_pink, _purple]);
const _sub = Color(0xff9aa0b0);
const _bg = Color(0xfff6f7fb);

class SubtitleSettingsPage extends StatefulWidget {
  const SubtitleSettingsPage({super.key});
  @override
  State<SubtitleSettingsPage> createState() => _SubtitleSettingsPageState();
}

class _SubtitleSettingsPageState extends State<SubtitleSettingsPage> {
  static const _fontOptions = [14.0, 18.0, 24.0];
  static const _posOptions = <Alignment>[
    Alignment.topCenter,
    Alignment.center,
    Alignment.bottomCenter,
  ];
  static const _posLabels = ['顶部', '中部', '底部'];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Column(children: [
          _topBar(context),
          Expanded(
            child: ValueListenableBuilder<CaptionStyle>(
              valueListenable: CaptionSettings.style,
              builder: (context, style, _) => ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                children: [
                  _preview(style),
                  const SizedBox(height: 18),
                  _section('字号'),
                  _segmented(
                    ['小', '中', '大'],
                    _fontOptions.indexOf(style.fontSize).clamp(0, 2),
                    (i) => _update(fontSize: _fontOptions[i]),
                  ),
                  _section('位置'),
                  _segmented(
                    _posLabels,
                    _posOptions.indexOf(style.alignment).clamp(0, 2),
                    (i) => _update(alignment: _posOptions[i]),
                  ),
                  _section('背景'),
                  _switchRow(style),
                  const SizedBox(height: 8),
                  const Text(
                    '字幕叠在直播画面上，随推流一起给观众看。首版仅支持中文识别。',
                    style: TextStyle(fontSize: 11, color: _sub, height: 1.5),
                  ),
                ],
              ),
            ),
          ),
        ]),
      ),
    );
  }

  void _update({double? fontSize, Alignment? alignment, bool? withBackground}) {
    CaptionSettings.style.value = CaptionSettings.style.value
        .copyWith(
            fontSize: fontSize,
            alignment: alignment,
            withBackground: withBackground);
  }

  Widget _topBar(BuildContext ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
        child: Row(children: [
          GestureDetector(
            onTap: () => Navigator.pop(ctx),
            child: Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(11)),
              child: const Icon(Icons.arrow_back_ios_new,
                  size: 18, color: Color(0xff5b6070)),
            ),
          ),
          const Expanded(
              child: Center(
                  child: Text('字幕设置',
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w800)))),
          const SizedBox(width: 34),
        ]),
      );

  Widget _preview(CaptionStyle style) => Container(
        height: 150,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
              colors: [Color(0xff3b3358), Color(0xff7c5cff)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(16),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(children: [
          Align(
            alignment: style.alignment,
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: style.withBackground
                  ? BoxDecoration(
                      color: Colors.black.withValues(alpha: .45),
                      borderRadius: BorderRadius.circular(10),
                    )
                  : null,
              child: Text(
                '欢迎来到直播间',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: style.fontSize,
                  fontWeight: FontWeight.w600,
                  shadows: const [
                    Shadow(color: Colors.black87, blurRadius: 4),
                  ],
                ),
              ),
            ),
          ),
        ]),
      );

  Widget _section(String title) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(title,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
      );

  Widget _segmented(List<String> labels, int selected, ValueChanged<int> onTap) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          for (int i = 0; i < labels.length; i++)
            Expanded(
              child: GestureDetector(
                onTap: () => onTap(i),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    gradient: selected == i ? _grad : null,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Center(
                    child: Text(
                      labels[i],
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: selected == i ? Colors.white : _sub,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _switchRow(CaptionStyle style) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
            color: Colors.white, borderRadius: BorderRadius.circular(12)),
        child: Row(children: [
          const Text('半透明黑底',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          const Spacer(),
          GestureDetector(
            onTap: () => _update(withBackground: !style.withBackground),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 46,
              height: 27,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                gradient: style.withBackground ? _grad : null,
                color: style.withBackground ? null : const Color(0xffe3e6ef),
              ),
              child: AnimatedAlign(
                duration: const Duration(milliseconds: 200),
                alignment: style.withBackground
                    ? Alignment.centerRight
                    : Alignment.centerLeft,
                child: const Padding(
                  padding: EdgeInsets.all(3),
                  child: SizedBox(
                    width: 21,
                    height: 21,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                          shape: BoxShape.circle, color: Colors.white),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ]),
      );
}
