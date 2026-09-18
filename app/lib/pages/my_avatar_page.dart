import 'package:flutter/material.dart';

import '../services/avatar_store.dart';
import '../widgets/flow_steps.dart';
import 'script_library_page.dart';

const _kAccent = Color(0xff7c5cff);
const _kPageBg = Color(0xfff6f7fb);

/// 我的数字人：从预置的 AI 形象库里选一个
///
/// 用户不需要自己拍摄——形象全部由 AI 预先生成，规格统一。
class MyAvatarPage extends StatefulWidget {
  const MyAvatarPage({super.key});

  @override
  State<MyAvatarPage> createState() => _MyAvatarPageState();
}

class _MyAvatarPageState extends State<MyAvatarPage> {
  String? _pick;

  @override
  void initState() {
    super.initState();
    _pick = AvatarStore.selected.value;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kPageBg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: const Color(0xff1a1a1a),
        title: const Text('我的数字人',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
        children: [
          const FlowSteps(current: 0),
          const SizedBox(height: 16),
          _specCard(),
          const SizedBox(height: 16),
          const Text('挑一个形象',
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Color(0xff1a1a1a))),
          const SizedBox(height: 4),
          const Text('形象已预置好，选完就能用，不需要自己拍',
              style: TextStyle(fontSize: 12.5, color: Color(0xff8a8a99))),
          const SizedBox(height: 14),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 14,
            crossAxisSpacing: 14,
            childAspectRatio: 0.72,
            children: AvatarStore.library.map((a) => _card(a)).toList(),
          ),
          const SizedBox(height: 18),
          _comingSoon(),
        ],
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: SizedBox(
          height: 50,
          child: FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: _kAccent,
              disabledBackgroundColor: const Color(0xffdcdce6),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
            onPressed: _pick == null
                ? null
                : () async {
                    AvatarStore.selected.value = _pick;
                    if (!mounted) return;
                    await _showNextStep();
                  },
            child: Text(
              _pick == null ? '请先选一个形象' : '使用这个形象',
              style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600),
            ),
          ),
        ),
      ),
    );
  }

  /// 选完形象后引导进入下一步（写话术），而不是直接退回首页
  Future<void> _showNextStep() async {
    final go = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: const BoxDecoration(
                        color: Color(0xffe9f9ef), shape: BoxShape.circle),
                    child: const Icon(Icons.check,
                        size: 19, color: Color(0xff20b26b)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '已选用「${AvatarStore.current?.name ?? ''}」形象',
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              const Text('下一步：写下你要讲的话术',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Color(0xff1a1a1a))),
              const SizedBox(height: 6),
              const Text(
                '数字人讲什么，由你的话术决定。这一步也顺手把「常见问题」准备好——'
                '弹幕问到就自动插播。',
                style: TextStyle(
                    fontSize: 12.5, height: 1.6, color: Color(0xff6b6b7b)),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: _kAccent,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('去写话术',
                      style: TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w600)),
                ),
              ),
              const SizedBox(height: 6),
              SizedBox(
                width: double.infinity,
                height: 42,
                child: TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('稍后再说',
                      style: TextStyle(
                          fontSize: 13.5, color: Color(0xff8a8a99))),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted) return;
    if (go == true) {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const ScriptLibraryPage()),
      );
    }
    if (mounted) Navigator.pop(context);
  }

  Widget _specCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xfff0edff),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('💡', style: TextStyle(fontSize: 18)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text('形象已经按直播要求做好了',
                    style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: Color(0xff2c2c3a))),
                SizedBox(height: 5),
                Text('透明背景 · 正面 · 半身 · 嘴部无遮挡\n选完即可直接放进直播间画面',
                    style: TextStyle(
                        fontSize: 12, height: 1.6, color: Color(0xff6b6b7b))),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _card(AiAvatar a) {
    final on = _pick == a.asset;
    return GestureDetector(
      onTap: () => setState(() => _pick = a.asset),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: on ? _kAccent : const Color(0xffeeeef4),
            width: on ? 2 : 1,
          ),
          boxShadow: on
              ? [
                  BoxShadow(
                      color: _kAccent.withValues(alpha: 0.22),
                      blurRadius: 14,
                      offset: const Offset(0, 4))
                ]
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                children: [
                  // 人像底：给透明 PNG 一个场景化背景，贴近直播间观感
                  Positioned.fill(
                    child: ClipRRect(
                      borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(15)),
                      child: Container(
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Color(0xffe7e3ff), Color(0xffcfc6ff)],
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Image.asset(
                        AvatarStore.assetPath(a),
                        fit: BoxFit.contain,
                        filterQuality: FilterQuality.high,
                      ),
                    ),
                  ),
                  if (on)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        width: 22,
                        height: 22,
                        decoration: const BoxDecoration(
                            color: _kAccent, shape: BoxShape.circle),
                        child: const Icon(Icons.check,
                            size: 14, color: Colors.white),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 9, 10, 11),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(a.name,
                      style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Color(0xff1a1a1a))),
                  const SizedBox(height: 3),
                  Text(a.tag,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 11.5, color: Color(0xff8a8a99))),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _comingSoon() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xffeeeef4)),
      ),
      child: Row(
        children: [
          const Text('🧩', style: TextStyle(fontSize: 18)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text('更多形象陆续上线',
                    style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: Color(0xff2c2c3a))),
                SizedBox(height: 4),
                Text('计划共 6 个形象，覆盖不同性别与气质，适配不同品类',
                    style: TextStyle(
                        fontSize: 12, height: 1.5, color: Color(0xff6b6b7b))),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
