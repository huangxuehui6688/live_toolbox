import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'pages/live_room_page.dart';
import 'pages/material_page.dart';
import 'pages/mine_page.dart';
import 'pages/my_avatar_page.dart';
import 'pages/preparation_page.dart';
import 'pages/script_library_page.dart';
import 'pages/subtitle_settings_page.dart';
import 'pages/teleprompter_page.dart';
import 'pages/tutorial_page.dart';
import 'services/diag_log.dart';
// 提供 TeleprompterOverlayApp（下方 overlayMain 入口使用）
import 'widgets/teleprompter_overlay.dart';

/// 悬浮窗独立 engine 的入口，flutter_overlay_window 按 "overlayMain" 名字调用。
/// 必须放在 main.dart（入口文件）并用 @pragma 保住，否则会被 tree-shake，
/// 表现为悬浮窗不浮起来 + logcat "Could not resolve main entrypoint function"。
@pragma('vm:entry-point')
void overlayMain() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const TeleprompterOverlayApp());
}

void main() {
  // ★排障日志必须最先起：鸿蒙容器里没有 logcat，出了问题只能靠它把现场带出来
  DiagLog.instance.start();
  // 未捕获异常也记一笔（端侧 FFI/插件异常最容易"静默失败"，没日志就查不动）
  FlutterError.onError = (FlutterErrorDetails d) {
    DiagLog.instance.log('ERR', 'FlutterError: ${d.exception}');
    FlutterError.presentError(d);
  };
  runZonedGuarded(_boot, (Object e, StackTrace s) {
    DiagLog.instance.log('ERR', '未捕获异常: $e');
    debugPrint('$s');
  });
}

void _boot() {
  WidgetsFlutterBinding.ensureInitialized();
  // v2 为竖屏设计(390×844)，锁定竖屏，避免横屏拉伸布局
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  // 边到边：系统栏透明、内容绘制到底，消除与 App 的颜色断层
  // (MIUI 会忽略导航栏纯色设置，只能用透明方式让 App 自己的底色透出来)
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
    statusBarBrightness: Brightness.light,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarIconBrightness: Brightness.dark,
    systemNavigationBarContrastEnforced: false,
  ));
  DiagLog.instance.logNow('BOOT', 'App 启动 (build: A-720p+perf / 2026-09-18)');
  runApp(const LiveToolboxApp());
}

const _bg = Color(0xfff6f7fb);
const _pink = Color(0xffff2d7a);
const _purple = Color(0xff7c5cff);
const _sub = Color(0xff9aa0b0);
const _grad = LinearGradient(colors: [_pink, _purple]);

class LiveToolboxApp extends StatelessWidget {
  const LiveToolboxApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AI直播副驾驶',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(scaffoldBackgroundColor: _bg, useMaterial3: true),
      home: const MainShell(),
    );
  }
}

class MainShell extends StatefulWidget {
  const MainShell({super.key});
  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _tab = 0;
  static const List<Widget> _pages = [
    HomePage(),
    MaterialLibraryPage(),
    // 「开播」tab 直接进开播准备台（原来是「开发中」占位，等于没入口）
    PreparationPage(),
    TutorialPage(),
    MinePage(),
  ];
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _pages[_tab],
      bottomNavigationBar:
          _BottomBar(current: _tab, onTap: (i) => setState(() => _tab = i)),
    );
  }
}

class _BottomBar extends StatelessWidget {
  final int current;
  final ValueChanged<int> onTap;
  const _BottomBar({required this.current, required this.onTap});
  @override
  Widget build(BuildContext context) {
    // edge-to-edge 下，底部系统导航栏区域内缩由 App 自己补，白色底可无缝铺满
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;
    return Container(
      height: 74 + bottomInset,
      padding: EdgeInsets.only(bottom: bottomInset),
      decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Color(0xffeef0f5)))),
      child: Row(children: [
        _tabItem(0, Icons.home_outlined, '首页'),
        _tabItem(1, Icons.grid_view_outlined, '素材'),
        _center(context),
        _tabItem(3, Icons.menu_book_outlined, '教程'),
        _tabItem(4, Icons.person_outline, '我的'),
      ]),
    );
  }

  Widget _tabItem(int i, IconData icon, String label) {
    final on = current == i;
    return Expanded(
      child: GestureDetector(
        onTap: () => onTap(i),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, size: 22, color: on ? _purple : const Color(0xff9ba1af)),
          const SizedBox(height: 4),
          Text(label,
              style: TextStyle(
                  fontSize: 10,
                  color: on ? _purple : const Color(0xff9ba1af),
                  fontWeight: on ? FontWeight.w600 : FontWeight.normal)),
        ]),
      ),
    );
  }

  Widget _center(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const LiveRoomPage())),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Container(
            width: 54,
            height: 54,
            margin: const EdgeInsets.only(bottom: 4),
            decoration: BoxDecoration(
                gradient: _grad,
                borderRadius: BorderRadius.circular(27),
                boxShadow: [
                  BoxShadow(
                      color: const Color(0xffb23df0).withValues(alpha:.42),
                      blurRadius: 12,
                      offset: const Offset(0, 4))
                ]),
            child: const Icon(Icons.add, color: Colors.white, size: 28),
          ),
        ]),
      ),
    );
  }
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});
  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                    gradient: _grad, borderRadius: BorderRadius.circular(9)),
                child: const Center(child: Text('🎙', style: TextStyle(fontSize: 15)))),
            const SizedBox(width: 8),
            const Text('AI直播副驾驶',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            const Spacer(),
            Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
                decoration: const BoxDecoration(
                    gradient: LinearGradient(
                        colors: [Color(0xffeaf4ff), Color(0xffdceaff)]),
                    borderRadius: BorderRadius.all(Radius.circular(14))),
                child: const Row(children: [
                  Text('●',
                      style:
                          TextStyle(color: Color(0xff3b82f6), fontSize: 8)),
                  SizedBox(width: 5),
                  Text('AI客服',
                      style: TextStyle(
                          color: Color(0xff3b82f6),
                          fontSize: 11,
                          fontWeight: FontWeight.w600)),
                ])),
          ]),
          const SizedBox(height: 14),
          GestureDetector(
            onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const LiveRoomPage())),
            child: Container(
              decoration: BoxDecoration(
                  gradient: _grad,
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                        color: const Color(0xffb23df0).withValues(alpha: .25),
                        blurRadius: 16,
                        offset: const Offset(0, 6))
                  ]),
              padding: const EdgeInsets.all(18),
              child: const Row(children: [
                Icon(Icons.videocam, color: Colors.white, size: 24),
                SizedBox(width: 14),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text('开始直播',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 17,
                              fontWeight: FontWeight.w800)),
                      Text('真人 / 数字人，一键开播',
                          style: TextStyle(
                              color: Colors.white70, fontSize: 11.5)),
                    ])),
                Icon(Icons.chevron_right, color: Colors.white),
              ]),
            ),
          ),
          const SizedBox(height: 18),
          GestureDetector(
            onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const LiveRoomPage())),
            child: Container(
              decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withValues(alpha:.05),
                        blurRadius: 8,
                        offset: const Offset(0, 2))
                  ]),
              padding: const EdgeInsets.all(13),
              child: const Row(children: [
                SizedBox(
                    width: 36,
                    height: 36,
                    child: DecoratedBox(
                        decoration: BoxDecoration(
                            gradient: _grad,
                            borderRadius:
                                BorderRadius.all(Radius.circular(11))))),
                SizedBox(width: 12),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text('双机开播',
                          style: TextStyle(
                              fontSize: 13.5, fontWeight: FontWeight.w600)),
                      Text('手机A直播 · 手机B控场看弹幕',
                          style: TextStyle(fontSize: 11, color: _sub)),
                    ])),
                Icon(Icons.chevron_right, color: _sub),
              ]),
            ),
          ),
          const SizedBox(height: 18),
          Container(
              decoration: const BoxDecoration(
                  gradient: LinearGradient(
                      colors: [Color(0xffff9a1a), Color(0xffff7a2d)]),
                  borderRadius: BorderRadius.all(Radius.circular(12)),
                  boxShadow: [
                    BoxShadow(
                        color: Color(0xffff7a2d),
                        blurRadius: 8,
                        offset: Offset(0, 3))
                  ]),
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              child: const Row(children: [
                Text('📢', style: TextStyle(fontSize: 13)),
                SizedBox(width: 9),
                Expanded(
                    child: Text('主播实战课:3 步做出高转化虚拟直播间',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700))),
                Icon(Icons.chevron_right, color: Colors.white),
              ])),
          const SizedBox(height: 18),
          Row(children: [
            const _Quick(icon: '🤖', label: 'AI 回复', c: Color(0xffffeadf)),
            _Quick(
                icon: '🎙',
                label: '提词器',
                c: const Color(0xffe1f4ed),
                onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const TeleprompterPage()))),
            _Quick(
                icon: '💬',
                label: '字幕',
                c: const Color(0xffece4ff),
                onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const SubtitleSettingsPage()))),
            const _Quick(icon: '📦', label: '素材库', c: Color(0xfffff4d4)),
          ]),
          const SizedBox(height: 18),
          const Text('主要功能',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 11,
            crossAxisSpacing: 11,
            childAspectRatio: 1.5,
            children: [
              _Cell(
                  emoji: '🧑',
                  title: '我的数字人',
                  sub: '选一个 AI 形象',
                  ic: const Color(0xffece4ff),
                  icC: const Color(0xff7c5cff),
                  onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const MyAvatarPage()))),
              _Cell(
                  emoji: '📝',
                  title: '话术库',
                  sub: '写话术 · 备常见问题',
                  ic: const Color(0xffe6faf1),
                  icC: const Color(0xff16c07a),
                  onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const ScriptLibraryPage()))),
              // ★合并为一张（老板：数字人直播和虚拟直播间是同一个直播间，
              //   数字人也可以在虚拟直播间里选）→ 只留「虚拟直播间」这张主推卡，
              //   副标题走数字人口径，让用户一眼知道里面有数字人。
              _Cell(
                  emoji: '🎭',
                  title: '虚拟直播间',
                  sub: '数字人讲品 · 一键搭虚拟场景',
                  hero: true,
                  onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const LiveRoomPage()))),
              _Cell(
                  emoji: '📊',
                  title: '直播数据',
                  sub: '即将上线 · 复盘报告 · 弹幕热词',
                  ic: const Color(0xffe6faf1),
                  icC: const Color(0xff16c07a),
                  onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const LiveDataPage()))),
              // 「新手教程」卡片已删除：底部导航已有「教程」tab，入口只留一个
            ],
          ),
          const SizedBox(height: 10),
        ]),
      ),
    );
  }
}

class _Quick extends StatelessWidget {
  final String icon;
  final String label;
  final Color c;
  final VoidCallback? onTap;
  const _Quick(
      {required this.icon, required this.label, required this.c, this.onTap});
  @override
  Widget build(BuildContext context) => Expanded(
        child: GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: Column(children: [
            Container(
                width: 54,
                height: 54,
                decoration:
                    BoxDecoration(color: c, borderRadius: BorderRadius.circular(27)),
                child: Center(child: Text(icon, style: const TextStyle(fontSize: 24)))),
            const SizedBox(height: 7),
            Text(label, style: const TextStyle(fontSize: 11.5, color: Color(0xff2c2e36))),
          ]),
        ),
      );
}

class _Cell extends StatelessWidget {
  final String emoji;
  final String title;
  final String sub;
  final bool hero;
  final Color? ic;
  final Color? icC;
  final VoidCallback? onTap;
  const _Cell(
      {required this.emoji,
      required this.title,
      required this.sub,
      this.hero = false,
      this.ic,
      this.icC,
      this.onTap});
  @override
  Widget build(BuildContext context) {
    final isHero = hero;
    return GestureDetector(
      onTap: onTap,
      child: Container(
      decoration: BoxDecoration(
        gradient: isHero
            ? const LinearGradient(colors: [Color(0xff1a1233), Color(0xff3b2a8e)])
            : null,
        color: isHero ? null : Colors.white,
        borderRadius: BorderRadius.circular(17),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha:isHero ? .12 : .05),
              blurRadius: 8,
              offset: const Offset(0, 3))
        ],
      ),
      padding: const EdgeInsets.fromLTRB(16, 13, 16, 11),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
                color: isHero
                    ? Colors.white.withValues(alpha:.16)
                    : (ic ?? Colors.grey.shade100),
                borderRadius: BorderRadius.circular(12)),
            child: Center(
                child: Text(emoji,
                    style: TextStyle(
                        fontSize: 21,
                        color: isHero ? Colors.white : (icC ?? Colors.black))))),
        const Spacer(),
        Text(title,
            style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: isHero ? Colors.white : const Color(0xff14151c))),
        const SizedBox(height: 4),
        Text(sub,
            style: TextStyle(
                fontSize: 11, color: isHero ? Colors.white70 : _sub)),
      ]),
      ),
    );
  }
}

/// 直播数据（功能还没做）
///
/// 首页那张卡点了要有反馈，又不能留死路，所以这里如实说明：
/// 将来会展示什么、数据从哪来、为什么现在还是空的。
class LiveDataPage extends StatelessWidget {
  const LiveDataPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: const Color(0xff1a1a1a),
        title: const Text('直播数据',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
        children: [
          _hero(),
          const SizedBox(height: 16),
          const Text('上线后会看到',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          const _PendingItem(
              emoji: '📈',
              title: '观看与留存',
              sub: '进场人数、最高在线、平均停留时长'),
          const _PendingItem(
              emoji: '💬',
              title: '弹幕热词',
              sub: '观众反复在问什么、哪句话带来成交'),
          const _PendingItem(
              emoji: '🛒',
              title: '转化与成交',
              sub: '讲解到下单的转化、爆单时段复盘'),
          const SizedBox(height: 6),
          _whereFrom(context),
        ],
      ),
    );
  }

  Widget _hero() => Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
            gradient: _grad,
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                  color: const Color(0xffb23df0).withValues(alpha: .25),
                  blurRadius: 16,
                  offset: const Offset(0, 6))
            ]),
        child: const Row(children: [
          Text('📊', style: TextStyle(fontSize: 22)),
          SizedBox(width: 12),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text('即将上线',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w800)),
                SizedBox(height: 3),
                Text('每场直播的复盘报告 · 弹幕热词 · 转化分析',
                    style: TextStyle(color: Colors.white70, fontSize: 11.5)),
              ])),
        ]),
      );

  Widget _whereFrom(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xffeeeef4)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('数据从哪来？',
              style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xff1a1a1a))),
          const SizedBox(height: 7),
          const Text(
              '这些数据要从直播平台取，需要先完成平台连接和数据授权。'
              '当前版本还没接入平台，所以这里暂时没有真实数据 —— 等接好了，'
              '这个页面会自动显示你每场的复盘结果。',
              style: TextStyle(
                  fontSize: 12, height: 1.6, color: Color(0xff6b6b7b))),
          const SizedBox(height: 10),
          GestureDetector(
            onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const PreparationPage())),
            child: const Text('去开播准备台看看 ›',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: _purple)),
          ),
        ]),
      );
}

/// 「待接入」的数据条目
class _PendingItem extends StatelessWidget {
  final String emoji;
  final String title;
  final String sub;
  const _PendingItem(
      {required this.emoji, required this.title, required this.sub});

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xffeeeef4)),
        ),
        child: Row(children: [
          Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                  color: const Color(0xfff4f5f9),
                  borderRadius: BorderRadius.circular(12)),
              child: Center(
                  child: Text(emoji, style: const TextStyle(fontSize: 19)))),
          const SizedBox(width: 12),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: Color(0xff1a1a1a))),
                const SizedBox(height: 3),
                Text(sub,
                    style: const TextStyle(fontSize: 11.5, color: _sub)),
              ])),
          Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                  color: const Color(0xfff4f5f9),
                  borderRadius: BorderRadius.circular(6)),
              child: const Text('待接入',
                  style: TextStyle(fontSize: 10, color: Color(0xff9a9aae)))),
        ]),
      );
}
