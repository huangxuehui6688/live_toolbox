import 'package:flutter/material.dart';

import '../services/avatar_store.dart';
import '../services/lang_store.dart';
import '../services/script_store.dart';
import '../widgets/flow_steps.dart';
import 'live_room_page.dart';
import 'my_avatar_page.dart';
import 'script_library_page.dart';

const _kAccent = Color(0xff7c5cff);
const _kPageBg = Color(0xfff6f7fb);
const _kInk = Color(0xff1a1a1a);
const _kBody = Color(0xff6b6b7b);
const _kSub = Color(0xff8a8a99);
const _kBorder = Color(0xffeeeef4);

/// 数字人 2D 流程 · 第 3 步「生成视频」
///
/// 把前两步准备好的东西汇总在一页：已选形象 + 话术条数。
/// ⚠️ 口型合成必须在电脑端离线跑（桌面端工具还在开发中），
///    所以「开始生成」目前只做说明与引导，不是死路：
///    页面本身是完整的，并明确告诉用户"生成好之后回直播间使用"。
class GenerateVideoPage extends StatefulWidget {
  const GenerateVideoPage({super.key});

  @override
  State<GenerateVideoPage> createState() => _GenerateVideoPageState();
}

class _GenerateVideoPageState extends State<GenerateVideoPage> {
  List<Script> _scripts = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    // 读一次目标语言：这一页的"外文稿"措辞跟着它变
    LangStore.instance.ensureLoaded().then((_) {
      if (mounted) setState(() {});
    });
    _reload();
  }

  /// 当前目标语言（英语 / 西班牙语 / 葡萄牙语）
  LangOption get _lang => LangStore.instance.current.value;

  Future<void> _reload() async {
    final s = await ScriptStore.instance.list();
    if (!mounted) return;
    setState(() {
      _scripts = s;
      _loading = false;
    });
  }

  bool get _hasScript => _scripts.isNotEmpty;
  int get _missingForeign =>
      _scripts.where((s) => !s.hasForeign).length;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kPageBg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: _kInk,
        title: const Text('生成数字人视频',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              children: [
                const FlowSteps(current: 2),
                const SizedBox(height: 16),
                _avatarCard(),
                const SizedBox(height: 14),
                _scriptCard(),
                const SizedBox(height: 14),
                _howCard(),
                const SizedBox(height: 14),
                _nextCard(),
              ],
            ),
      bottomNavigationBar: _loading ? null : _bottomBar(),
    );
  }

  // ---------------- 已选形象 ----------------

  Widget _avatarCard() {
    final a = AvatarStore.current;
    return _card(
      children: [
        _rowTitle('第 1 步 · 已选形象', a == null ? '还没选' : a.name),
        const SizedBox(height: 12),
        if (a == null)
          _tip('你还没有选形象。先挑一个 AI 形象，再回来生成。',
              actionLabel: '去选形象', onAction: _openAvatar)
        else
          Row(
            children: [
              Container(
                width: 62,
                height: 62,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xffe7e3ff), Color(0xffcfc6ff)],
                  ),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Image.asset(
                      AvatarStore.assetPath(a),
                      fit: BoxFit.contain,
                      filterQuality: FilterQuality.high,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(a.name,
                        style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: _kInk)),
                    const SizedBox(height: 4),
                    Text(a.tag,
                        style: const TextStyle(fontSize: 12, color: _kSub)),
                  ],
                ),
              ),
              TextButton(
                onPressed: _openAvatar,
                child: const Text('更换',
                    style: TextStyle(fontSize: 13, color: _kAccent)),
              ),
            ],
          ),
      ],
    );
  }

  Future<void> _openAvatar() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const MyAvatarPage()),
    );
    if (mounted) setState(() {});
  }

  // ---------------- 话术统计 ----------------

  Widget _scriptCard() {
    final total = _scripts.length;
    final miss = _missingForeign;
    return _card(
      children: [
        _rowTitle('第 2 步 · 话术准备', total == 0 ? '还没有' : '$total 条'),
        const SizedBox(height: 12),
        if (total == 0)
          _tip('还没有话术，数字人就没有可讲的内容。先写一条再来生成。',
              actionLabel: '去写话术', onAction: _openScriptLibrary)
        else ...[
          _stat('共 $total 条话术', '数字人会按顺序讲这些内容'),
          const SizedBox(height: 8),
          if (miss == 0)
            _stat('${_lang.scriptName}齐全', '境外版的画面和声音都能直接用',
                ok: true)
          else
            _stat('$miss 条缺${_lang.short}稿', '不影响生成，但境外观众那版会少这几段',
                warn: true),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: _openScriptLibrary,
              style: TextButton.styleFrom(
                  padding: EdgeInsets.zero, minimumSize: const Size(0, 32)),
              child: const Text('去话术库继续补充 ›',
                  style: TextStyle(fontSize: 13, color: _kAccent)),
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _openScriptLibrary() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ScriptLibraryPage()),
    );
    if (mounted) await _reload();
  }

  // ---------------- 说明：口型合成在电脑上 ----------------

  Widget _howCard() {
    return _card(
      bg: const Color(0xfff0edff),
      borderColor: const Color(0xffe2dcff),
      children: [
        Row(
          children: [
            const Text('🖥', style: TextStyle(fontSize: 17)),
            const SizedBox(width: 8),
            const Expanded(
              child: Text('口型合成要在电脑上完成',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Color(0xff2c2c3a))),
            ),
          ],
        ),
        const SizedBox(height: 8),
        const Text(
          '让数字人跟着你的话术张嘴，这一步算力比较大，手机端做不了。'
          '桌面端工具正在开发中——上线后在这一页就能一键生成。',
          style: TextStyle(fontSize: 12, height: 1.65, color: _kBody),
        ),
        const SizedBox(height: 12),
        _mini('① 手机上：选形象 + 写话术（已完成）'),
        const SizedBox(height: 6),
        _mini('② 电脑上：工具离线合成口型视频（开发中）'),
        const SizedBox(height: 6),
        _mini('③ 手机上：回到直播间，直接用它开播'),
      ],
    );
  }

  Widget _mini(String text) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 5),
            child: Text('•',
                style: TextStyle(fontSize: 12, color: Color(0xff9a9aae))),
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Text(text,
                style: const TextStyle(
                    fontSize: 12, height: 1.5, color: _kBody)),
          ),
        ],
      );

  // ---------------- 下一步：开播 ----------------

  Widget _nextCard() {
    return _card(
      children: [
        _rowTitle('第 4 步 · 去开播', '生成好就能用'),
        const SizedBox(height: 8),
        const Text(
          '视频生成好之后，回到直播间，数字人就会按你写的话术出镜开讲；'
          '弹幕问到常见问题里的内容，会自动插播对应回答。',
          style: TextStyle(fontSize: 12.5, height: 1.65, color: _kBody),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          height: 46,
          child: OutlinedButton(
            style: OutlinedButton.styleFrom(
              foregroundColor: _kAccent,
              side: const BorderSide(color: Color(0xffd8d0ff)),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: _openLiveRoom,
            child: const Text('下一步：去直播间开播',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          ),
        ),
      ],
    );
  }

  void _openLiveRoom() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const LiveRoomPage(initialPerson: 1)),
    );
  }

  // ---------------- 底部主按钮 ----------------

  Widget _bottomBar() {
    final can = _hasScript;
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xffeef0f5))),
      ),
      child: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 10, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              can
                  ? '形象和话术都齐了，可以开始生成'
                  : '先写一条话术，才能生成视频',
              style: const TextStyle(fontSize: 11.5, color: _kSub),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: can ? _kAccent : const Color(0xffdcdce6),
                  foregroundColor:
                      can ? Colors.white : const Color(0xff9a9aae),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: can ? _showGenerateSheet : _warnNoScript,
                child: Text(can ? '开始生成数字人视频' : '先写一条话术',
                    style: const TextStyle(
                        fontSize: 15.5, fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _warnNoScript() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('先写一条话术，再回来生成'),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        action: SnackBarAction(label: '去写话术', onPressed: _openScriptLibrary),
      ),
    );
  }

  /// 生成说明面板：明确告知"这一步在电脑上做"，并给出不堵死的出口
  Future<void> _showGenerateSheet() async {
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
                        color: Color(0xfff0edff), shape: BoxShape.circle),
                    child: const Center(
                        child: Text('🖥', style: TextStyle(fontSize: 16))),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text('生成需要在电脑上完成',
                        style: TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Text(
                '口型合成要跑在电脑上，桌面端工具正在开发中，'
                '手机端暂时没法直接出片。',
                style: TextStyle(
                    fontSize: 12.5, height: 1.65, color: _kBody),
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xfff6f7fb),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('已经备好的内容',
                        style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Color(0xff2c2c3a))),
                    const SizedBox(height: 6),
                    Text(
                      '形象：${AvatarStore.current?.name ?? '未选'}'
                      '\n话术：${_scripts.length} 条'
                      '${_missingForeign > 0 ? '（$_missingForeign 条缺${_lang.short}稿）' : ''}',
                      style: const TextStyle(
                          fontSize: 12, height: 1.6, color: _kBody),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: _kAccent,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('知道了',
                      style: TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w600)),
                ),
              ),
              const SizedBox(height: 6),
              SizedBox(
                width: double.infinity,
                height: 42,
                child: TextButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('先去直播间看看',
                      style: TextStyle(fontSize: 13.5, color: _kAccent)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted) return;
    if (go == true) _openLiveRoom();
  }

  // ---------------- 通用组件 ----------------

  Widget _card({
    required List<Widget> children,
    Color bg = Colors.white,
    Color borderColor = _kBorder,
  }) =>
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: borderColor),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: children,
        ),
      );

  Widget _rowTitle(String title, String right) => Row(
        children: [
          Expanded(
            child: Text(title,
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w600, color: _kInk)),
          ),
          Text(right,
              style: const TextStyle(fontSize: 12, color: _kSub)),
        ],
      );

  Widget _stat(String title, String sub, {bool ok = false, bool warn = false}) {
    final color = ok
        ? const Color(0xff20b26b)
        : (warn ? const Color(0xffe08a2e) : const Color(0xff2c2c3a));
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 5),
          child: Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: color)),
              const SizedBox(height: 2),
              Text(sub,
                  style: const TextStyle(
                      fontSize: 11.5, height: 1.5, color: _kSub)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _tip(String text,
      {required String actionLabel, required VoidCallback onAction}) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(text,
              style: const TextStyle(fontSize: 12.5, height: 1.6, color: _kBody)),
          const SizedBox(height: 10),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: _kAccent,
              padding:
                  const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: onAction,
            child: Text(actionLabel,
                style: const TextStyle(
                    fontSize: 13.5, fontWeight: FontWeight.w600)),
          ),
        ],
      );
}
