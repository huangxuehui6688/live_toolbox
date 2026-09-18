import 'package:flutter/material.dart';

const _bgc = Color(0xfff6f7fb);
const _purple = Color(0xff7c5cff);
const _sub = Color(0xff9aa0b0);

class MinePage extends StatelessWidget {
  const MinePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgc,
      body: SafeArea(
        child: Column(children: [
          _nav(),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              child: Column(children: [
                _userCard(),
                _vipCard(),
                _quads(),
                _inviteBanner(),
                _mentor(),
                _logout(),
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
          const Text('我的',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const Spacer(),
          Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: .04),
                  shape: BoxShape.circle),
              child: const Center(
                  child: Text('⚙️', style: TextStyle(fontSize: 14)))),
        ]),
      );

  Widget _userCard() => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        decoration: _card(radius: 20),
        child: Row(children: [
          Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                  gradient: const LinearGradient(
                      colors: [Color(0xffff9a5a), Color(0xffff6a3a)]),
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                        color: const Color(0xffff7a2d).withValues(alpha: .25),
                        blurRadius: 12,
                        offset: const Offset(0, 4))
                  ]),
              child: const Center(
                  child: Text('🙋', style: TextStyle(fontSize: 26)))),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Text('元气小美',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                const SizedBox(width: 8),
                Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 9, vertical: 2),
                    decoration: BoxDecoration(
                        gradient: const LinearGradient(
                            colors: [Color(0xffff7a2d), Color(0xffff4d6a)]),
                        borderRadius: BorderRadius.circular(9)),
                    child: const Text('👑 运营商',
                        style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: Colors.white))),
              ]),
              const SizedBox(height: 5),
              Row(children: [
                const Text('ID: 886520',
                    style: TextStyle(fontSize: 12, color: _sub)),
                const SizedBox(width: 6),
                GestureDetector(
                    onTap: () {},
                    child: const Text('复制',
                        style: TextStyle(
                            fontSize: 10,
                            color: _purple,
                            fontWeight: FontWeight.w600))),
              ]),
            ]),
          ),
        ]),
      );

  Widget _vipCard() => GestureDetector(
        onTap: () {},
        child: Container(
          margin: const EdgeInsets.only(bottom: 14),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
          decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [
                Color(0xfff7da7f),
                Color(0xffeac45e),
                Color(0xffd0a744),
              ]),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                    color: const Color(0xffbf8f28).withValues(alpha: .3),
                    blurRadius: 20,
                    offset: const Offset(0, 8))
              ]),
          child: Row(children: [
            Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: .28),
                    borderRadius: BorderRadius.circular(12)),
                child: const Center(
                    child: Text('👑', style: TextStyle(fontSize: 21)))),
            const SizedBox(width: 12),
            const Expanded(
                child: Text('您已解锁全部运营商特权',
                    style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w800,
                        color: Color(0xff6b4a12)))),
            Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 13, vertical: 6),
                decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14)),
                child: const Text('权益 ›',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: Color(0xff6b4a12)))),
          ]),
        ),
      );

  Widget _quads() => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(children: [
          _quad('我的团队', Icons.groups_rounded, const Color(0xff0fb97c),
              const Color(0xffe6f7f0)),
          const SizedBox(width: 8),
          _quad('邀请好友', Icons.card_giftcard_rounded, const Color(0xffff4d6a),
              const Color(0xffffeaf0)),
          const SizedBox(width: 8),
          _quad('推广中心', Icons.campaign_rounded, const Color(0xffff9a1a),
              const Color(0xfffff3e0)),
          const SizedBox(width: 8),
          _quad('我的订单', Icons.receipt_long_rounded, const Color(0xff3b82f6),
              const Color(0xffe8f1ff)),
        ]),
      );

  Widget _quad(String label, IconData ic, Color color, Color bg) =>
      Expanded(
        child: GestureDetector(
          onTap: () {},
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 15),
            decoration: _card(radius: 16),
            child: Column(children: [
              Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                      color: bg, borderRadius: BorderRadius.circular(12)),
                  child: Icon(ic, size: 22, color: color)),
              const SizedBox(height: 8),
              Text(label,
                  style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: Color(0xff3a3d4a))),
            ]),
          ),
        ),
      );

  Widget _inviteBanner() => GestureDetector(
        onTap: () {},
        child: Container(
          margin: const EdgeInsets.only(bottom: 14),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
          decoration: BoxDecoration(
              gradient: const LinearGradient(
                  colors: [Color(0xffa878ff), Color(0xff5b8df0)]),
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                    color: _purple.withValues(alpha: .3),
                    blurRadius: 22,
                    offset: const Offset(0, 10))
              ]),
          child: Row(children: [
            const Text('🎁', style: TextStyle(fontSize: 40)),
            const SizedBox(width: 14),
            const Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('邀请好友赚佣金',
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: Colors.white)),
                    SizedBox(height: 4),
                    Text('好友消费你赚佣金 · 多邀多得无上限',
                        style: TextStyle(
                            fontSize: 11.5, color: Color(0xeaffffff))),
                  ]),
            ),
            Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16)),
                child: const Text('立即邀请',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: _purple))),
          ]),
        ),
      );

  Widget _mentor() => GestureDetector(
        onTap: () {},
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: _card(radius: 18),
          child: Row(children: [
            Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                    gradient: const LinearGradient(
                        colors: [Color(0xffffb347), Color(0xffff7a2d)]),
                    borderRadius: BorderRadius.circular(13),
                    boxShadow: [
                      BoxShadow(
                          color: const Color(0xffff7a2d).withValues(alpha: .25),
                          blurRadius: 10,
                          offset: const Offset(0, 4))
                    ]),
                child: const Center(
                    child: Text('👩‍🏫', style: TextStyle(fontSize: 20)))),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('加入导师团队',
                        style: TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w700)),
                    SizedBox(height: 3),
                    Text('跟着导师学直播 · 免费领教程资料',
                        style: TextStyle(fontSize: 11, color: _sub)),
                  ]),
            ),
            const Text('立即加入 ›',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Color(0xffff7a2d))),
          ]),
        ),
      );

  Widget _logout() => GestureDetector(
        onTap: () {},
        child: const Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: Center(
              child: Text('退出登录',
                  style: TextStyle(fontSize: 13, color: _sub))),
        ),
      );

  BoxDecoration _card({double radius = 16}) => BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(radius),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: .05),
              blurRadius: 12,
              offset: const Offset(0, 3))
        ],
      );
}
