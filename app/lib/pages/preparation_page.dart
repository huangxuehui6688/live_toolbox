import 'dart:async';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../services/lang_store.dart';
import '../services/script_store.dart';
import '../services/tts_service.dart';
import '../widgets/digital_avatar_view.dart'
    show kDigitalAvatarImages, kDigitalAvatarNames, kSceneNames, kSceneVideos;
import '../widgets/digital_human_avatar.dart';
import 'lang_settings_page.dart';
import 'live_room_page.dart';
import 'script_library_page.dart';

const _pink = Color(0xffff2d7a);
const _purple = Color(0xff7c5cff);
const _sub = Color(0xff9aa0b0);
const _grad = LinearGradient(colors: [_pink, _purple]);

class PreparationPage extends StatefulWidget {
  const PreparationPage({super.key});
  @override
  State<PreparationPage> createState() => _PreparationPageState();
}

class _PreparationPageState extends State<PreparationPage> {
  int _avatar = 0;
  int _scene = 0;
  bool _speaking = false;
  StreamSubscription<void>? _completeSub;

  /// 要讲的话术：取话术库里最新更新的一条，没有就为空（不再写死假数据）
  Script? _script;
  String get _scriptText => _script?.content.trim() ?? '';
  bool get _hasScript => _scriptText.isNotEmpty;

  /// ★形象/场景只用全工程**同一套**数据源（digital_avatar_view.dart）：
  ///   直播间的「人物」面板、数字人图层帧动画都取自这里，避免两处各有一份对不上。
  final _sceneNames = kSceneNames;
  final _sceneVideos = kSceneVideos;
  final _avatarImages = kDigitalAvatarImages;
  final _avatarNames = kDigitalAvatarNames;

  VideoPlayerController? _bgController;
  bool _bgReady = false;

  @override
  void initState() {
    super.initState();
    _completeSub = TtsService.instance.onComplete.listen((_) {
      if (mounted) setState(() => _speaking = false);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadSceneVideo());
    _loadScript();
    // 读一次已保存的目标语言
    LangStore.instance.ensureLoaded().then((_) {
      if (mounted) setState(() {});
    });
  }

  /// 取话术库里最新更新的一条当"这次要讲的话"（list 已按更新时间倒序）
  Future<void> _loadScript() async {
    final list = await ScriptStore.instance.list();
    if (!mounted) return;
    setState(() => _script = list.isEmpty ? null : list.first);
  }

  Future<void> _openScriptLibrary() async {
    await Navigator.push(context,
        MaterialPageRoute(builder: (_) => const ScriptLibraryPage()));
    if (mounted) await _loadScript();
  }

  @override
  void dispose() {
    _completeSub?.cancel();
    _bgController?.dispose();
    super.dispose();
  }

  /// 加载/切换预览场景视频（循环、静音）
  Future<void> _loadSceneVideo() async {
    final old = _bgController;
    _bgController = null;
    old?.dispose();
    if (mounted) setState(() => _bgReady = false);
    if (_scene >= _sceneVideos.length) return;
    final c = VideoPlayerController.asset(_sceneVideos[_scene]);
    _bgController = c;
    try {
      await c.initialize();
      await c.setLooping(true);
      await c.setVolume(0);
      await c.play();
      if (mounted && _bgController == c) setState(() => _bgReady = true);
    } catch (_) {
      // 视频加载失败则保持占位背景
    }
  }

  void _switchScene(int i) {
    if (i == _scene) return;
    setState(() => _scene = i);
    _loadSceneVideo();
  }

  Future<void> _tryListen() async {
    if (_speaking) {
      await TtsService.instance.stop();
      if (mounted) setState(() => _speaking = false);
      return;
    }
    if (!_hasScript) {
      _promptNoScript();
      return;
    }
    await _speak('试听失败，请重试');
  }

  /// 重新生成：把当前这条话术重新合成/播一遍（点了必须听到声音，不能静默）
  Future<void> _regenerate() async {
    if (!_hasScript) {
      _promptNoScript();
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('正在重新生成这条话术的语音…'),
      duration: Duration(seconds: 2),
    ));
    await _speak('重新生成失败，请重试');
  }

  /// 试听与重新生成共用的出语音动作
  Future<void> _speak(String failMsg) async {
    if (!mounted) return;
    setState(() => _speaking = true);
    try {
      await TtsService.instance.stop();
      await TtsService.instance.init();
      await TtsService.instance.speak(_scriptText);
    } catch (e) {
      // 技术细节只进日志；界面一律中文，不暴露英文异常/堆栈
      debugPrint('[TTS] 语音生成失败: $e');
      if (!mounted) return;
      setState(() => _speaking = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(failMsg)));
    }
  }

  /// 没有话术时的统一引导：不能点了没反应，也不能让数字人空着讲
  void _promptNoScript() {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: const Text('还没有话术：先在话术库里写一条'),
      duration: const Duration(seconds: 3),
      behavior: SnackBarBehavior.floating,
      action: SnackBarAction(label: '去写话术', onPressed: _openScriptLibrary),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xfff6f7fb),
      body: SafeArea(
        child: Column(children: [
          _navBar(context),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(children: [
                _preview(),
                const SizedBox(height: 14),
                _sectionTitle('选择数字人形象', 1),
                _avatars(),
                const SizedBox(height: 12),
                _sectionTitle('选择虚拟场景', 2),
                _scenesRow(),
                const SizedBox(height: 12),
                _sectionTitle('目标语言（境外观众听/看的版本）', 3),
                _langRow(),
                const SizedBox(height: 12),
                _sectionTitle('直播话术（取自话术库最新一条）', 4),
                _scriptCard(),
                const SizedBox(height: 12),
              ]),
            ),
          ),
          _startBtn(),
        ]),
      ),
    );
  }

  Widget _navBar(BuildContext ctx) => Padding(
        padding: EdgeInsets.fromLTRB(Navigator.canPop(ctx) ? 8 : 16, 4, 16, 8),
        child: Row(children: [
          // 这个页面同时被「开播」tab 直接当页面用，那时没有上一页，不显示返回键
          if (Navigator.canPop(ctx))
            IconButton(
                icon: const Icon(Icons.arrow_back_ios_new, size: 18),
                onPressed: () => Navigator.pop(ctx)),
          const Text('开播准备',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          const Spacer(),
        ]),
      );

  /// 目标语言入口：话术库里的"外文稿"按这个语言写
  Widget _langRow() {
    final lang = LangStore.instance.current.value;
    return GestureDetector(
      onTap: () async {
        await Navigator.push(context,
            MaterialPageRoute(builder: (_) => const LangSettingsPage()));
        if (mounted) setState(() {});
      },
      child: Container(
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withValues(alpha: .05),
                  blurRadius: 8,
                  offset: const Offset(0, 2))
            ]),
        child: Row(children: [
          Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                  color: const Color(0xfff0edff),
                  borderRadius: BorderRadius.circular(11)),
              child: const Center(
                  child: Text('🌐', style: TextStyle(fontSize: 17)))),
          const SizedBox(width: 12),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text('${lang.name} · 外文稿用${lang.short}',
                    style: const TextStyle(
                        fontSize: 13.5, fontWeight: FontWeight.w600)),
                const SizedBox(height: 3),
                Text('境外版一次只说一种语言，点这里更换',
                    style: const TextStyle(fontSize: 11, color: _sub)),
              ])),
          const Text('更换 ›',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: _purple)),
        ]),
      ),
    );
  }

  Widget _preview() => Container(
        height: 300,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: .15),
                blurRadius: 16,
                offset: const Offset(0, 6))
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Stack(children: [
            Positioned.fill(child: _previewVideo()),
            Align(
            alignment: Alignment.bottomCenter,
            child: DigitalHumanAvatar(
              imagePath: _avatarImages[_avatar],
              speaking: _speaking,
              width: 150,
              height: 232,
            ),
          ),
          Positioned(
              top: 12,
              left: 12,
              child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: .25),
                      borderRadius: BorderRadius.circular(12)),
                  child: const Text('AI 直播',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w700)))),
          Positioned(
              bottom: 12,
              left: 0,
              right: 0,
              child: Center(
                  child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: .3),
                          borderRadius: BorderRadius.circular(12)),
                      child: const Text('预览效果',
                          style:
                              TextStyle(color: Colors.white, fontSize: 10))))),
          ]),
        ),
      );

  Widget _previewVideo() {
    final c = _bgController;
    if (c == null || !_bgReady) {
      return const DecoratedBox(
        decoration: BoxDecoration(
            gradient: LinearGradient(
                colors: [Color(0xff2a1a4a), Color(0xff7c5cff)])),
      );
    }
    return FittedBox(
      fit: BoxFit.cover,
      child: SizedBox(
        width: c.value.size.width,
        height: c.value.size.height,
        child: VideoPlayer(c),
      ),
    );
  }

  Widget _sectionTitle(String t, int step) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(children: [
          Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                  gradient: _grad, borderRadius: BorderRadius.circular(9)),
              child: Center(
                  child: Text('$step',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w700)))),
          const SizedBox(width: 6),
          Text(t,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
        ]),
      );

  Widget _avatars() => SizedBox(
        height: 86,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: _avatarNames.length,
          separatorBuilder: (_, _) => const SizedBox(width: 10),
          itemBuilder: (_, i) => GestureDetector(
            onTap: () => setState(() => _avatar = i),
            child: Column(children: [
              Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                      border: Border.all(
                          color: _avatar == i ? _purple : const Color(0xffe8eaf0),
                          width: 2),
                      borderRadius: BorderRadius.circular(18)),
                  child: ClipRRect(
                      borderRadius: BorderRadius.circular(15),
                      child: Image.asset(
                        _avatarImages[i],
                        width: 60,
                        height: 60,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => Container(
                            color: const Color(0xfff6d9b8),
                            child: const Icon(Icons.person, color: Colors.white)),
                      ))),
              const SizedBox(height: 5),
              Text(_avatarNames[i],
                  style: TextStyle(
                      fontSize: 10,
                      color: _avatar == i ? _purple : _sub,
                      fontWeight: _avatar == i
                          ? FontWeight.w600
                          : FontWeight.normal)),
            ]),
          ),
        ),
      );

  Widget _scenesRow() => SizedBox(
        height: 60,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: 7,
          separatorBuilder: (_, _) => const SizedBox(width: 10),
          itemBuilder: (_, i) {
            if (i == 6) return _uploadCard();
            final sel = _scene == i;
            return GestureDetector(
              onTap: () => _switchScene(i),
              child: Container(
                  width: 88,
                  height: 60,
                  decoration: BoxDecoration(
                      gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: sel
                              ? const [Color(0xff7c5cff), Color(0xff9a6bff)]
                              : const [Color(0xff3a3550), Color(0xff2a2740)]),
                      border: Border.all(
                          color: sel ? _purple : Colors.transparent, width: 2),
                      borderRadius: BorderRadius.circular(14)),
                  child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                            sel
                                ? Icons.play_circle_fill
                                : Icons.play_circle_outline,
                            color: Colors.white,
                            size: 20),
                        const SizedBox(height: 3),
                        Text(_sceneNames[i],
                            style: const TextStyle(
                                color: Colors.white, fontSize: 9)),
                      ])),
            );
          },
        ),
      );

  Widget _uploadCard() => GestureDetector(
        onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const LiveRoomPage())),
        child: Container(
          width: 88,
          height: 60,
          decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(
                  color: const Color(0xffc9c4ff),
                  width: 1.5),
              borderRadius: BorderRadius.circular(14)),
          child: const Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.add, color: _purple, size: 18),
                Text('上传', style: TextStyle(fontSize: 10, color: _sub))
              ]),
        ),
      );

  Widget _scriptCard() => Container(
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withValues(alpha: .05),
                  blurRadius: 8,
                  offset: const Offset(0, 2))
            ]),
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Text(
                  _hasScript
                      ? '话术库 · ${_script!.title.isEmpty ? '(未命名话术)' : _script!.title}'
                      : '话术库 · 还没有话术',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w700)),
            ),
            const SizedBox(width: 8),
            GestureDetector(
                onTap: _tryListen,
                child: Text(
                    _speaking ? '⏹ 停止' : '▶ 试听',
                    style: const TextStyle(
                        fontSize: 11,
                        color: _purple,
                        fontWeight: FontWeight.w600))),
            const SizedBox(width: 12),
            GestureDetector(
                onTap: _regenerate,
                child: const Text('🔄 重新生成语音',
                    style: TextStyle(fontSize: 11, color: _purple))),
          ]),
          const SizedBox(height: 8),
          if (_hasScript)
            Text(_scriptText,
                style: const TextStyle(
                    fontSize: 12, color: Color(0xff555b68), height: 1.6))
          else
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('还没有话术，数字人没有可讲的内容。先去话术库写一条。',
                  style: TextStyle(
                      fontSize: 12, color: Color(0xff8a8a99), height: 1.6)),
              const SizedBox(height: 10),
              SizedBox(
                height: 38,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: _purple,
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: _openScriptLibrary,
                  child: const Text('去话术库写一条',
                      style: TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600)),
                ),
              ),
            ]),
        ]),
      );

  Widget _startBtn() => Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: GestureDetector(
          onTap: () {
            // 没有话术就别进直播间（数字人没内容可播），给明确引导
            if (!_hasScript) {
              _promptNoScript();
              return;
            }
            // ★「数字人直播」已并入虚拟直播间（同一个直播间，数字人在里面选）：
            //   这里把选好的形象与场景透传过去，直接以数字人出镜 + 该场景开播。
            //   话术由直播间自己从话术库取最新一条（和本页同一份数据）。
            Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => LiveRoomPage(
                          initialPerson: _avatar + 1,
                          initialScene: _scene,
                        )));
          },
          child: Container(
            decoration: BoxDecoration(
                gradient: _grad,
                borderRadius: BorderRadius.circular(18),
                boxShadow: [
                  BoxShadow(
                      color: const Color(0xffb23df0).withValues(alpha: .3),
                      blurRadius: 16,
                      offset: const Offset(0, 6))
                ]),
            padding: const EdgeInsets.all(16),
            child: const Center(
                child: Text('🚀 开始直播',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w800))),
          ),
        ),
      );
}
