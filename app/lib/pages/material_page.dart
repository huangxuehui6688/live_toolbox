import 'dart:math' as math;

import 'package:flutter/material.dart';

const _bgc = Color(0xfff6f7fb);
const _pink = Color(0xffff2d7a);
const _purple = Color(0xff7c5cff);
const _sub = Color(0xff9aa0b0);
const _grad = LinearGradient(colors: [_pink, _purple]);
const _gradWide = LinearGradient(colors: [Color(0xffff5aa0), Color(0xffa878ff)]);

class _WidgetItem {
  final String title, meta, cat;
  final int stage;
  final String? badge; // 'hot' | 'vip'
  const _WidgetItem(this.title, this.meta, this.cat, this.stage, [this.badge]);
}

class _Script {
  final String title, meta;
  const _Script(this.title, this.meta);
}

class MaterialLibraryPage extends StatefulWidget {
  const MaterialLibraryPage({super.key});
  @override
  State<MaterialLibraryPage> createState() => _MaterialPageState();
}

class _MaterialPageState extends State<MaterialLibraryPage> {
  int _seg = 0; // 0 贴片 / 1 提词话术

  // 贴片
  int _cat = 0;
  int _sel = -1;
  static const _cats = ['推荐', '贴片', '文字', '时钟', '跑马灯', '特效'];
  static const _items = [
    _WidgetItem('价格标签', '8.2万人使用', '贴片', 0),
    _WidgetItem('秒杀标', '7.5万人使用', '贴片', 1, 'hot'),
    _WidgetItem('热卖标', '6.1万人使用', '贴片', 2),
    _WidgetItem('新品标', '5.3万人使用', '贴片', 3),
    _WidgetItem('倒计时', '4.8万人使用', '时钟', 4, 'vip'),
    _WidgetItem('时钟', '4.2万人使用', '时钟', 5),
    _WidgetItem('跑马灯', '3.6万人使用', '跑马灯', 6),
    _WidgetItem('欢迎语', '3.1万人使用', '文字', 7),
    _WidgetItem('烟花特效', '2.8万人使用', '特效', 8),
    _WidgetItem('爱心飘屏', '2.3万人使用', '特效', 9),
  ];
  static const _stageGrads = [
    LinearGradient(colors: [Color(0xfffff1f6), Color(0xffffe2ee)]),
    LinearGradient(colors: [Color(0xfffff6e8), Color(0xffffe7cd)]),
    LinearGradient(colors: [Color(0xfffff0f8), Color(0xfff6e0ff)]),
    LinearGradient(colors: [Color(0xffeefaf3), Color(0xffd9f5e6)]),
    LinearGradient(colors: [Color(0xfff1f3f9), Color(0xffe1e5f1)]),
    LinearGradient(colors: [Color(0xffeef8fb), Color(0xffd9eef5)]),
    LinearGradient(colors: [Color(0xfff2eefc), Color(0xffe6ddfb)]),
    LinearGradient(colors: [Color(0xffeef0fc), Color(0xffdce0fa)]),
    LinearGradient(colors: [Color(0xfff6eefc), Color(0xffe9ddfb)]),
    LinearGradient(colors: [Color(0xfffff1f6), Color(0xffffe2ee)]),
  ];

  // 提词话术
  int _scriptSel = 0;
  final List<_Script> _scripts = [
    const _Script('追剧零食大礼包 · 带货话术', '8 段 · 约 4 分钟 · 用过 12 次'),
    const _Script('服装专场 · 开场 + 逼单', '6 段 · 约 3 分钟 · 用过 5 次'),
    const _Script('美妆护肤 · 产品讲解', '7 段 · 约 4 分钟 · 用过 3 次'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgc,
      body: SafeArea(
        child: Column(children: [
          _topBar(),
          _segBar(),
          Expanded(child: _seg == 0 ? _patchBody() : _scriptBody()),
          if (_seg == 0) _patchFoot(),
        ]),
      ),
    );
  }

  Widget _topBar() => Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
        child: Row(children: [
          const Text('素材库',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          const Spacer(),
          Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withValues(alpha: .05),
                        blurRadius: 6,
                        offset: const Offset(0, 2))
                  ]),
              child: const Icon(Icons.search, size: 18, color: Color(0xff2c2e36))),
        ]),
      );

  Widget _segBar() => Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        padding: const EdgeInsets.all(4),
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
          _segItem(0, '贴片'),
          _segItem(1, '提词话术'),
        ]),
      );

  Widget _segItem(int i, String label) => Expanded(
        child: GestureDetector(
          onTap: () => setState(() => _seg = i),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(vertical: 9),
            decoration: BoxDecoration(
                gradient: _seg == i ? _grad : null,
                borderRadius: BorderRadius.circular(11)),
            child: Center(
                child: Text(label,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: _seg == i ? Colors.white : const Color(0xff6b7280)))),
          ),
        ),
      );

  // ===== 贴片 =====
  Widget _patchBody() {
    final list = _cat == 0
        ? _items
        : _items.where((e) => e.cat == _cats[_cat]).toList();
    return Column(children: [
      SizedBox(
        height: 42,
        child: Stack(children: [
          ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            itemCount: _cats.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (_, i) => _patchCatChip(i),
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
      ),
      Expanded(
        child: GridView.count(
          crossAxisCount: 2,
          padding: const EdgeInsets.fromLTRB(16, 2, 16, 12),
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 1.08,
          children: [
            for (int i = 0; i < list.length; i++) _patchCard(_items.indexOf(list[i])),
          ],
        ),
      ),
    ]);
  }

  Widget _patchCatChip(int i) {
    final on = _cat == i;
    return GestureDetector(
      onTap: () => setState(() => _cat = i),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
        decoration: BoxDecoration(
            gradient: on ? _grad : null,
            color: on ? null : Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withValues(alpha: .04),
                  blurRadius: 6,
                  offset: const Offset(0, 2))
            ]),
        child: Text(_cats[i],
            style: TextStyle(
                fontSize: 13,
                fontWeight: on ? FontWeight.w700 : FontWeight.w500,
                color: on ? Colors.white : const Color(0xff6b7280))),
      ),
    );
  }

  Widget _patchCard(int idx) {
    final item = _items[idx];
    final on = _sel == idx;
    return GestureDetector(
      onTap: () => setState(() => _sel = idx),
      child: Container(
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
                color: on ? _purple : Colors.transparent, width: 2),
            boxShadow: on
                ? [
                    BoxShadow(
                        color: _purple.withValues(alpha: .18),
                        spreadRadius: 3)
                  ]
                : [
                    BoxShadow(
                        color: Colors.black.withValues(alpha: .05),
                        blurRadius: 10,
                        offset: const Offset(0, 3))
                  ]),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
            height: 104,
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(15)),
              child: Stack(children: [
                Positioned.fill(
                    child: Container(
                        decoration: BoxDecoration(
                            gradient: _stageGrads[item.stage]))),
                Positioned(
                    top: -26,
                    right: -22,
                    child: Container(
                        width: 90,
                        height: 90,
                        decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: .45),
                            shape: BoxShape.circle))),
                Center(child: _mock(item.stage)),
                if (item.badge != null)
                  Positioned(
                      top: 8,
                      left: 8,
                      child: _badge(item.badge!)),
                if (on)
                  Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                          width: 22,
                          height: 22,
                          decoration: const BoxDecoration(
                              color: Colors.white, shape: BoxShape.circle),
                          child: const Icon(Icons.check,
                              size: 14, color: _purple))),
              ]),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(11, 9, 11, 11),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.title,
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 3),
                  Text(item.meta,
                      style: const TextStyle(fontSize: 10, color: _sub)),
                ]),
          ),
        ]),
      ),
    );
  }

  Widget _badge(String kind) {
    final isVip = kind == 'vip';
    return Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
            gradient: isVip
                ? const LinearGradient(
                    colors: [Color(0xffffb347), Color(0xffff7a2d)])
                : const LinearGradient(
                    colors: [Color(0xffff2d7a), Color(0xffff5e3a)]),
            borderRadius: BorderRadius.circular(9)),
        child: Text(isVip ? 'VIP' : '热门',
            style: const TextStyle(
                fontSize: 9, fontWeight: FontWeight.w700, color: Colors.white)));
  }

  Widget _mock(int stage) {
    switch (stage) {
      case 0:
        return Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
                gradient:
                    const LinearGradient(colors: [Color(0xffff4d4d), Color(0xffff2d5a)]),
                borderRadius: BorderRadius.circular(10),
                boxShadow: [
                  BoxShadow(
                      color: const Color(0xffff2d5a).withValues(alpha: .3),
                      blurRadius: 12,
                      offset: const Offset(0, 4))
                ]),
            // 「价格标签」贴片的样式预览：这里只演示版式，
            // 真实价格由用户在使用该贴片时自行填写，故用占位符而非具体数字。
            child: const Text.rich(TextSpan(children: [
              TextSpan(text: '¥ ', style: TextStyle(fontSize: 11)),
              TextSpan(text: 'X.XX'),
            ], style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 20))));
      case 1:
        return _pill('⚡ 限时秒杀', const [Color(0xffff9f2e), Color(0xffff6a2d)], 20);
      case 2:
        return _pill('🔥 热卖中', const [Color(0xffff2d7a), Color(0xffb23df0)], 20);
      case 3:
        return Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
            decoration: BoxDecoration(
                gradient: const LinearGradient(
                    colors: [Color(0xff16c07a), Color(0xff0ea06a)]),
                borderRadius: BorderRadius.circular(8)),
            child: const Text('NEW',
                style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                    letterSpacing: 2)));
      case 4:
        return Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
                color: const Color(0xff14151c),
                borderRadius: BorderRadius.circular(10)),
            child: const Text('00:59:59',
                style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                    letterSpacing: 1,
                    fontFamily: 'monospace')));
      case 5:
        return _clockMock();
      case 6:
        return Container(
            width: 130,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(
                color: _purple, borderRadius: BorderRadius.circular(8)),
            child: const Text('今日下单买一送一 🎁',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 13)));
      case 7:
        return Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: const Color(0xffc9c4ff), width: 1.5),
                borderRadius: BorderRadius.circular(8)),
            child: const Text('欢迎来到直播间~',
                style: TextStyle(
                    color: Color(0xff5a3ad0),
                    fontWeight: FontWeight.w700,
                    fontSize: 14)));
      case 8:
        return const Text('🎆', style: TextStyle(fontSize: 40));
      default:
        return const Text('❤️', style: TextStyle(fontSize: 36));
    }
  }

  Widget _pill(String text, List<Color> colors, double size) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
            gradient: LinearGradient(colors: colors),
            borderRadius: BorderRadius.circular(20)),
        child: Text(text,
            style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: size - 5)),
      );

  Widget _clockMock() => SizedBox(
        width: 52,
        height: 52,
        child: Stack(alignment: Alignment.center, children: [
          Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xff333333), width: 3))),
          Transform.translate(
              offset: const Offset(0, -4),
              child: Container(
                  width: 2, height: 14, color: const Color(0xff333333))),
          Transform.rotate(
              angle: 80 * math.pi / 180,
              child: Transform.translate(
                  offset: const Offset(0, -4),
                  child: Container(
                      width: 2, height: 11, color: const Color(0xffff2d5a)))),
        ]),
      );

  Widget _patchFoot() => Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
        color: _bgc,
        child: Row(children: [
          GestureDetector(
            onTap: () {},
            child: Container(
              width: 70,
              height: 56,
              decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: const Color(0xffc9c4ff), width: 1.5),
                  borderRadius: BorderRadius.circular(16)),
              child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                        width: 26,
                        height: 26,
                        decoration: BoxDecoration(
                            gradient: _grad, shape: BoxShape.circle),
                        child: const Center(
                            child: Text('＋',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    height: 1)))),
                    const SizedBox(height: 4),
                    const Text('上传',
                        style: TextStyle(fontSize: 10, color: _sub)),
                  ]),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: GestureDetector(
              onTap: _sel < 0
                  ? null
                  : () {},
              child: Container(
                height: 56,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                    gradient: _sel < 0 ? null : _gradWide,
                    color: _sel < 0 ? const Color(0xffffb8d3) : null,
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: _sel < 0
                        ? null
                        : [
                            BoxShadow(
                                color: const Color(0xffff5aa0)
                                    .withValues(alpha: .42),
                                blurRadius: 24,
                                offset: const Offset(0, 10))
                          ]),
                child: const Text('使用此贴片',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w800)),
              ),
            ),
          ),
        ]),
      );

  // ===== 提词话术 =====
  Widget _scriptBody() => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
        child: Column(children: [
          _genCard(),
          const SizedBox(height: 12),
          Row(children: [
            _quickBtn('✍️', '手动写稿'),
            const SizedBox(width: 10),
            _quickBtn('📋', '从模板选'),
          ]),
          Padding(
            padding: const EdgeInsets.fromLTRB(2, 20, 2, 10),
            child: Row(children: [
              const Text('我的话术',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
              const Spacer(),
              const Text('点选即可切换当前提词',
                  style: TextStyle(fontSize: 11.5, color: _sub)),
            ]),
          ),
          for (int i = 0; i < _scripts.length; i++) _scriptItem(i),
          const SizedBox(height: 12),
          GestureDetector(
            onTap: _openGenSheet,
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: const Color(0xffd6d9e4), width: 1.5),
                  borderRadius: BorderRadius.circular(15)),
              child: const Center(
                  child: Text('＋ 新建话术',
                      style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: Color(0xff8b90a2)))),
            ),
          ),
        ]),
      );

  Widget _genCard() => GestureDetector(
        onTap: _openGenSheet,
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
              gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [_pink, _purple]),
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                    color: const Color(0xff963cdc).withValues(alpha: .3),
                    blurRadius: 26,
                    offset: const Offset(0, 12))
              ]),
          child: Stack(children: [
            Positioned(
                top: -50,
                left: -30,
                child: Container(
                    width: 170,
                    height: 170,
                    decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: .16),
                        shape: BoxShape.circle))),
            Padding(
              padding: const EdgeInsets.fromLTRB(17, 16, 17, 16),
              child: Column(children: [
                Row(children: [
                  Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: .22),
                          borderRadius: BorderRadius.circular(12)),
                      child: const Center(
                          child: Text('✨', style: TextStyle(fontSize: 19)))),
                  const SizedBox(width: 11),
                  const Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('AI 一键生成话术',
                              style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white)),
                          SizedBox(height: 3),
                          Text('输入商品名 + 卖点,自动写整套直播话术',
                              style: TextStyle(
                                  fontSize: 11.5, color: Color(0xd9ffffff))),
                        ]),
                  ),
                ]),
                const SizedBox(height: 12),
                Container(
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12)),
                    child: const Center(
                        child: Text('立即生成 ›',
                            style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w800,
                                color: Color(0xff7c2fd8))))),
              ]),
            ),
          ]),
        ),
      );

  Widget _quickBtn(String icon, String label) => Expanded(
        child: GestureDetector(
          onTap: () {},
          child: Container(
            padding: const EdgeInsets.all(13),
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
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                      color: const Color(0xfff2f3f8),
                      borderRadius: BorderRadius.circular(10)),
                  child: Center(
                      child: Text(icon, style: const TextStyle(fontSize: 15)))),
              const SizedBox(width: 9),
              Text(label,
                  style: const TextStyle(
                      fontSize: 12.5, fontWeight: FontWeight.w600)),
            ]),
          ),
        ),
      );

  Widget _scriptItem(int i) {
    final on = _scriptSel == i;
    final s = _scripts[i];
    return GestureDetector(
      onTap: () => setState(() => _scriptSel = i),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
            gradient: on
                ? const LinearGradient(
                    colors: [Color(0xfffaf7ff), Color(0xfff3f0ff)])
                : null,
            color: on ? null : Colors.white,
            borderRadius: BorderRadius.circular(15),
            border: Border.all(
                color: on ? _purple : Colors.transparent, width: 1.5),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withValues(alpha: .04),
                  blurRadius: 9,
                  offset: const Offset(0, 2))
            ]),
        child: Row(children: [
          Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                  gradient: on ? _gradWide : null,
                  color: on ? null : const Color(0xfff2f3f8),
                  borderRadius: BorderRadius.circular(11)),
              child: Center(
                  child: Text('📖',
                      style: TextStyle(
                          fontSize: 18,
                          color: on ? Colors.white : null)))),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(s.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 13.5, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 3),
                  Text(s.meta,
                      style: const TextStyle(fontSize: 11, color: _sub)),
                ]),
          ),
          const SizedBox(width: 8),
          on
              ? Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                      gradient: _grad, borderRadius: BorderRadius.circular(9)),
                  child: const Text('使用中',
                      style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                          color: Colors.white)))
              : const Icon(Icons.radio_button_unchecked,
                  size: 16, color: Color(0xffc9ccd8)),
        ]),
      ),
    );
  }

  Future<void> _openGenSheet() async {
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _GenSheet(),
    );
    if (ok == true && mounted) {
      setState(() {
        _scripts.insert(
            0, const _Script('追剧零食大礼包 · AI新话术', '7 段 · 约 4 分钟 · 刚刚生成'));
        _scriptSel = 0;
      });
    }
  }
}

class _GenSheet extends StatefulWidget {
  const _GenSheet();
  @override
  State<_GenSheet> createState() => _GenSheetState();
}

class _GenSheetState extends State<_GenSheet> {
  final _name = TextEditingController(text: '追剧零食大礼包');
  final _point = TextEditingController(text: '20包混合装 · 好吃不贵');
  // 预填的是话术模板，价格位故意留成 XX 占位：真实价格由用户按自己的商品填写。
  final _price = TextEditingController(text: '原价XX · 直播价XX · 买一送一');
  int _style = 0;
  bool _busy = false;
  static const _styles = ['亲切萌妹', '专业讲师', '幽默段子手'];

  @override
  void dispose() {
    _name.dispose();
    _point.dispose();
    _price.dispose();
    super.dispose();
  }

  Future<void> _doGen() async {
    if (_busy) return;
    setState(() => _busy = true);
    await Future.delayed(const Duration(milliseconds: 1300));
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      padding: EdgeInsets.fromLTRB(
          18, 18, 18, 22 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          const Text('✨ AI 生成话术',
              style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800)),
          const Spacer(),
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                    color: const Color(0xfff2f3f8),
                    borderRadius: BorderRadius.circular(9)),
                child: const Icon(Icons.close,
                    size: 15, color: Color(0xff6b7080))),
          ),
        ]),
        const SizedBox(height: 14),
        _field('商品名称', _name),
        _field('核心卖点', _point),
        _field('价格 / 优惠', _price),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('话术风格',
              style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: Color(0xff6b7080))),
          const SizedBox(height: 6),
          Row(children: [
            for (int i = 0; i < _styles.length; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _style = i),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    decoration: BoxDecoration(
                        color: _style == i
                            ? const Color(0xfff3efff)
                            : const Color(0xfff4f5fa),
                        border: Border.all(
                            color: _style == i
                                ? _purple
                                : Colors.transparent,
                            width: 1.5),
                        borderRadius: BorderRadius.circular(11)),
                    child: Center(
                        child: Text(_styles[i],
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: _style == i
                                    ? const Color(0xff6a3ad0)
                                    : const Color(0xff6b7080)))),
                  ),
                ),
              ),
            ],
          ]),
        ]),
        const SizedBox(height: 18),
        GestureDetector(
          onTap: _doGen,
          child: Opacity(
            opacity: _busy ? .75 : 1,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 14),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                  gradient: const LinearGradient(
                      colors: [Color(0xffff3d7f), Color(0xff7c5cff)]),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                        color: const Color(0xffb23df0).withValues(alpha: .3),
                        blurRadius: 22,
                        offset: const Offset(0, 10))
                  ]),
              child: Text(_busy ? 'AI 生成中…' : '✨ 开始生成',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14.5,
                      fontWeight: FontWeight.w800)),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _field(String label, TextEditingController c) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label,
              style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: Color(0xff6b7080))),
          const SizedBox(height: 6),
          TextField(
            controller: c,
            style: const TextStyle(fontSize: 13.5),
            decoration: InputDecoration(
              filled: true,
              fillColor: const Color(0xfffafbfd),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(
                      color: Color(0xffeceef5), width: 1.5)),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: _purple, width: 1.5)),
            ),
          ),
        ]),
      );
}
