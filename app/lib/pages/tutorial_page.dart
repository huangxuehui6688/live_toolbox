import 'package:flutter/material.dart';

const _bgc = Color(0xfff6f7fb);
const _purple = Color(0xff7c5cff);
const _sub = Color(0xff9aa0b0);

const _gDy = LinearGradient(colors: [Color(0xff000000), Color(0xff1a1a1a)]);
const _gXhs = LinearGradient(colors: [Color(0xffff2442), Color(0xffff5a7a)]);
const _gSph = LinearGradient(colors: [Color(0xff07c160), Color(0xff3adf7c)]);
const _gKs = LinearGradient(colors: [Color(0xffff6633), Color(0xffff8855)]);
const _gTb = LinearGradient(colors: [Color(0xffff5000), Color(0xffff7733)]);
const _gPush = LinearGradient(colors: [Color(0xff7c5cff), Color(0xffa878ff)]);
const _gBarrage = LinearGradient(colors: [Color(0xff3acf8e), Color(0xff16c07a)]);

class _Howto {
  final String emoji, title, sub;
  final LinearGradient g;
  const _Howto(this.emoji, this.title, this.sub, this.g);
}

class _Vid {
  final String cat, cover, s1, s2, info, plays, dur;
  final bool isNew;
  const _Vid(this.cat, this.cover, this.s1, this.s2, this.info, this.plays,
      this.dur, this.isNew);
}

class TutorialPage extends StatefulWidget {
  const TutorialPage({super.key});
  @override
  State<TutorialPage> createState() => _TutorialPageState();
}

class _TutorialPageState extends State<TutorialPage> {
  String _cat = 'all';

  static const _cats = [
    ('all', '全部'),
    ('howto', '怎么直播'),
    ('newbie', '新手入门'),
    ('digital', '数字人'),
    ('bg', '换背景'),
    ('ai', 'AI 回复'),
    ('telep', '提词器'),
    ('3d', '3D 场景'),
  ];

  static const _howtos = [
    _Howto('🎵', '手机-抖音-投屏开播', '手机怎么用 AI 直播在抖音开播', _gDy),
    _Howto('🎵', '手机-抖音-推流开播', '手机抖音怎么用推流地址开播', _gDy),
    _Howto('📕', '电脑-小红书-投屏开播', '电脑怎么用 AI 直播在小红书开播', _gXhs),
    _Howto('📕', '手机-小红书-直播', '手机小红书怎么用 AI 直播开播', _gXhs),
    _Howto('💬', '电脑-视频号-投屏开播', '电脑怎么用微信视频号配合 AI 直播开播', _gSph),
    _Howto('💬', '手机-视频号-推流开播', '手机怎么用视频号推流开播', _gSph),
    _Howto('📷', '手机-快手-录屏开播', '手机怎么用 AI 直播在快手开播', _gKs),
    _Howto('🛒', '手机-淘宝-录屏开播', '手机怎么用 AI 直播在淘宝开播', _gTb),
    _Howto('🔗', '电脑-小鹅通-推流开播', '电脑怎么用 AI 直播在小鹅通平台推流', _gPush),
    _Howto('🌏', '手机-TikTok-海外开播', '手机怎么用 AI 直播在 TikTok 海外开播', _gDy),
    _Howto('💬', '各平台弹幕接口对接', '怎么从抖音/快手拉取弹幕,AI 自动回复', _gBarrage),
  ];

  static const _vids = [
    _Vid('newbie', '新手速学课', 'AI直播官方教学', '实际运用和功能讲解',
        '3分钟学会开播:从选数字人到推流', '1.2万播放 · 新手', '03:12', true),
    _Vid('newbie', '双机开播课', '手机A直播+手机B控场', '一台手机也能操作',
        '双机开播:手机A直播+手机B控场', '7200播放 · 新手', '06:22', true),
    _Vid('digital', 'AI数字人', '数字人形象设置', '口型+语音同步',
        '数字人主播怎么设置?形象+声音', '9800播放 · 数字人', '05:47', true),
    _Vid('digital', '智能托管', 'AI全自动直播', '真人开口智能让话',
        '智能托管:全自动直播设置', '5800播放 · 数字人', '07:30', true),
    _Vid('bg', '调色', '绿幕助手官方教学', '实际运用和功能讲解',
        '一键换背景:不用绿幕也能换场景', '2.1万播放 · 换背景', '02:35', false),
    _Vid('bg', '导入模板', '模板教学', '实际运用和功能讲解',
        '3D 场景:打造沉浸式直播间', '6400播放 · 换背景', '05:05', false),
    _Vid('ai', '导出模板', '模板教学', '实际运用和功能讲解',
        'AI 自动回复:让数字人接住每条弹幕', '1.5万播放 · AI回复', '04:18', false),
    _Vid('telep', '提词技巧', '提词器使用', '实际运用和功能讲解',
        '提词器使用技巧:悬浮提词+AI跟读', '8600播放 · 提词器', '03:56', false),
    _Vid('3d', '3D场景', '3D场景教学', '实际运用和功能讲解',
        '3D 场景:打造沉浸式直播间', '6400播放 · 3D场景', '05:05', false),
  ];

  @override
  Widget build(BuildContext context) {
    final showHowto = _cat == 'all' || _cat == 'howto';
    final showGrid = _cat != 'howto';
    final vids =
        _cat == 'all' ? _vids : _vids.where((v) => v.cat == _cat).toList();
    return Scaffold(
      backgroundColor: _bgc,
      body: SafeArea(
        child: Column(children: [
          _nav(),
          _searchBar(),
          _catBar(),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
              child: Column(children: [
                if (showHowto) ...[
                  for (final h in _howtos) _howtoItem(h),
                  const SizedBox(height: 2),
                ],
                if (showGrid) _grid(vids),
              ]),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _nav() => Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
        child: Row(children: [
          const Text('教程中心',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          const Spacer(),
          Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: .04),
                  shape: BoxShape.circle),
              child: const Center(
                  child: Text('🔍', style: TextStyle(fontSize: 14)))),
        ]),
      );

  Widget _searchBar() => Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withValues(alpha: .04),
                  blurRadius: 8,
                  offset: const Offset(0, 2))
            ]),
        child: Row(children: [
          const Text('🔍', style: TextStyle(fontSize: 13)),
          const SizedBox(width: 8),
          const Text('请输入搜索关键词',
              style: TextStyle(fontSize: 12, color: _sub)),
        ]),
      );

  Widget _catBar() => SizedBox(
        height: 42,
        child: Stack(children: [
          ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            itemCount: _cats.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (_, i) {
              final (key, label) = _cats[i];
              return _catChip(key, label);
            },
          ),
          // 右侧渐隐，提示可横滑
          const Positioned(
            right: 0,
            top: 0,
            bottom: 12,
            width: 28,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [Color(0x00f6f7fb), _bgc],
                  ),
                ),
              ),
            ),
          ),
        ]),
      );

  Widget _catChip(String key, String label) {
    final on = _cat == key;
    return GestureDetector(
      onTap: () => setState(() => _cat = key),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
            color: on ? _purple : Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withValues(alpha: .04),
                  blurRadius: 6,
                  offset: const Offset(0, 2))
            ]),
        child: Text(label,
            style: TextStyle(
                fontSize: 12,
                fontWeight: on ? FontWeight.w800 : FontWeight.w600,
                color: on ? Colors.white : _sub)),
      ),
    );
  }

  Widget _howtoItem(_Howto h) => GestureDetector(
        onTap: () {},
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withValues(alpha: .04),
                    blurRadius: 8,
                    offset: const Offset(0, 2))
              ]),
          child: Row(children: [
            Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                    gradient: h.g, borderRadius: BorderRadius.circular(12)),
                child: Center(
                    child: Text(h.emoji, style: const TextStyle(fontSize: 22)))),
            const SizedBox(width: 12),
            Expanded(
                child:
                    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(h.title,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w700)),
              const SizedBox(height: 3),
              Text(h.sub, style: const TextStyle(fontSize: 11, color: _sub)),
            ])),
            const Icon(Icons.chevron_right, color: Color(0xffc8ccd6), size: 18),
          ]),
        ),
      );

  Widget _grid(List<_Vid> vids) => GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 0.78,
        children: [for (final v in vids) _videoCard(v)],
      );

  Widget _videoCard(_Vid v) => GestureDetector(
        onTap: () {},
        child: Container(
          decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withValues(alpha: .05),
                    blurRadius: 10,
                    offset: const Offset(0, 3))
              ]),
          clipBehavior: Clip.antiAlias,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(
              height: 150,
              child: Stack(children: [
                Positioned.fill(
                    child: Container(
                        decoration: const BoxDecoration(
                            gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                      Color(0xff1a1c2b),
                      Color(0xff2a2c3e),
                      Color(0xff3a3a55),
                    ])))),
                Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(children: [
                    const Spacer(),
                    Text(v.cover,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                            letterSpacing: .5)),
                    const SizedBox(height: 6),
                    Text('● ${v.s1}',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 9.5,
                            color: Colors.white.withValues(alpha: .7))),
                    const SizedBox(height: 1),
                    Text('● ${v.s2}',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 9.5,
                            color: Colors.white.withValues(alpha: .7))),
                    const Spacer(),
                  ]),
                ),
                if (v.isNew)
                  Positioned(
                      top: 0,
                      right: 0,
                      child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: const BoxDecoration(
                              color: Color(0xffff4d4a),
                              borderRadius: BorderRadius.only(
                                  bottomLeft: Radius.circular(8))),
                          child: const Text('最新',
                              style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: .5,
                                  color: Colors.white)))),
                Positioned(
                    left: 8,
                    bottom: 6,
                    child: Row(children: [
                      Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 4, vertical: 1),
                          decoration: BoxDecoration(
                              color: const Color(0xff3acf8e),
                              borderRadius: BorderRadius.circular(3)),
                          child: const Text('AI直播',
                              style: TextStyle(
                                  fontSize: 8,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xff1a1c2b)))),
                      const SizedBox(width: 3),
                      Text('基础课',
                          style: TextStyle(
                              fontSize: 8,
                              color: Colors.white.withValues(alpha: .6))),
                    ])),
                Positioned(
                    right: 6,
                    bottom: 28,
                    child: Container(
                        width: 26,
                        height: 26,
                        decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: .3),
                            shape: BoxShape.circle,
                            border: Border.all(
                                color: Colors.white.withValues(alpha: .4))),
                        child: const Icon(Icons.play_arrow,
                            size: 13, color: Colors.white))),
                Positioned(
                    right: 6,
                    bottom: 6,
                    child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: .5),
                            borderRadius: BorderRadius.circular(6)),
                        child: Text(v.dur,
                            style: const TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                                color: Colors.white)))),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 9, 12, 11),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(v.info,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            height: 1.4)),
                    const SizedBox(height: 3),
                    Text(v.plays,
                        style: const TextStyle(fontSize: 10, color: _sub)),
                  ]),
            ),
          ]),
        ),
      );
}
