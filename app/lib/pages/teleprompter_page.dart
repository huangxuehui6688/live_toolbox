import 'dart:async';
import 'dart:developer' show log;

import 'package:flutter/material.dart';

import '../services/asr_aligner.dart';
import '../services/asr_service.dart';
import '../services/overlay_service.dart';
import '../services/script_store.dart';

const _bgc = Color(0xfff6f7fb);
const _purple = Color(0xff7c5cff);
const _sub = Color(0xff9aa0b0);

/// 把话术全文按行拆分（去空行），既用于跟读，也用于传给悬浮窗
List<String> _splitLines(String content) => content
    .split('\n')
    .map((l) => l.trim())
    .where((l) => l.isNotEmpty)
    .toList();

String _fmtTime(DateTime t) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${t.year}-${two(t.month)}-${two(t.day)} '
      '${two(t.hour)}:${two(t.minute)}';
}

/// 提词器首页：台词库列表 + 新建台词
class TeleprompterPage extends StatefulWidget {
  const TeleprompterPage({super.key});
  @override
  State<TeleprompterPage> createState() => _TeleprompterPageState();
}

class _TeleprompterPageState extends State<TeleprompterPage>
    with WidgetsBindingObserver {
  List<Script> _scripts = [];
  bool _loading = true;

  String? _activeScriptId; // 当前开启悬浮窗的台词 id
  AsrAligner? _aligner;
  StreamSubscription<AsrResult>? _asrSub;

  /// 是否已获得「显示在其他应用上层」权限（null=还没查到，用于顶部提示条）
  bool? _overlayGranted;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
    _refreshOverlayPermission();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopFollow();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 用户去系统设置里授权后切回 App，重新查一次，状态实时刷新
    if (state == AppLifecycleState.resumed) _refreshOverlayPermission();
  }

  Future<void> _refreshOverlayPermission() async {
    final ok = await OverlayService.instance.hasPermission();
    if (!mounted || ok == _overlayGranted) return;
    setState(() => _overlayGranted = ok);
  }

  Future<void> _load() async {
    final list = await ScriptStore.instance.list();
    if (!mounted) return;
    setState(() {
      _scripts = list;
      _loading = false;
    });
  }

  Future<void> _openEditor([Script? existing]) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => _ScriptEditorPage(existing: existing)),
    );
    _load();
  }

  /// 开启/关闭悬浮窗（悬浮窗就是跟读窗口，开启后同步启动智能跟读）
  Future<void> _toggleOverlay(Script script) async {
    if (_activeScriptId == script.id) {
      await _stopFollow();
      await OverlayService.instance.hide();
      if (mounted) setState(() => _activeScriptId = null);
      _snack('悬浮窗已关闭');
      return;
    }
    final lines = _splitLines(script.content);
    if (lines.isEmpty) {
      _snack('话术内容为空，请先填写内容');
      return;
    }
    final svc = OverlayService.instance;
    if (!await svc.hasPermission()) {
      final r = await svc.requestPermission();
      if (!mounted) return;
      switch (r) {
        case OverlayPermResult.granted:
          break; // 拿到权限，继续往下开悬浮窗
        case OverlayPermResult.needGuide:
        case OverlayPermResult.guideOnly:
          // 自动弹已发生过一次 / 本会话手动重开已达上限：改为弹中文指引层
          _showPermissionGuide(script, lines);
          return;
        case OverlayPermResult.denied:
          _snack('未获得悬浮窗权限，请按指引手动开启后再试');
          _refreshOverlayPermission();
          return;
        case OverlayPermResult.unavailable:
          _snack('系统里找不到悬浮窗授权入口，请手动到系统设置里开启');
          _refreshOverlayPermission();
          return;
      }
    }
    await _doShow(script, lines);
  }

  /// 真正开悬浮窗 + 启动智能跟读（权限已就绪后调用）
  Future<void> _doShow(Script script, List<String> lines) async {
    try {
      final ok = await OverlayService.instance.show(lines);
      if (ok) {
        await _startFollow(lines);
        if (mounted) {
          setState(() {
            _activeScriptId = script.id;
            _overlayGranted = true;
          });
        }
        _snack('悬浮窗已开启');
      } else {
        _snack('开启悬浮窗失败');
      }
    } catch (e) {
      // 技术细节只进日志；界面一律中文，不暴露英文异常/堆栈
      debugPrint('[ASR] 开启悬浮窗失败: $e');
      _snack('开启悬浮窗失败，请重试');
    }
  }

  /// 中文指引层：自动跳转只发生一次，之后让用户按两条路径手动开启。
  Future<void> _showPermissionGuide(Script script, List<String> lines) async {
    final svc = OverlayService.instance;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _PermissionGuideSheet(
        onCheck: () async {
          Navigator.pop(ctx);
          if (!mounted) return;
          if (await svc.hasPermission()) {
            await _doShow(script, lines);
          } else {
            _snack('仍未开启，请按上面两条路径操作后再试');
            _refreshOverlayPermission();
          }
        },
        onOpenManual: () async {
          Navigator.pop(ctx);
          if (!mounted) return;
          final r = await svc.openManualPermission();
          if (!mounted) return;
          switch (r) {
            case OverlayPermResult.granted:
              await _doShow(script, lines);
              break;
            case OverlayPermResult.guideOnly:
              _snack('本会话已手动打开过一次，请按上面路径操作');
              break;
            case OverlayPermResult.denied:
              _snack('未获得悬浮窗权限，请按路径开启后再试');
              _refreshOverlayPermission();
              break;
            case OverlayPermResult.needGuide:
            case OverlayPermResult.unavailable:
              _snack('系统里找不到悬浮窗授权入口，请手动到系统设置里开启');
              _refreshOverlayPermission();
              break;
          }
        },
      ),
    );
  }

  /// 启动智能跟读：ASR 识别 → 对齐行号 → 同步悬浮窗高亮
  Future<void> _startFollow(List<String> lines) async {
    await _stopFollow();
    _aligner = AsrAligner(lines);
    try {
      await AsrService.instance.start();
      await _asrSub?.cancel();
      _asrSub = AsrService.instance.results.listen((r) {
        final line = _aligner?.feed(r.text) ?? 0;
        OverlayService.instance.updateLine(line);
      });
    } catch (e) {
      log('跟读启动失败: $e', name: 'ASR');
    }
  }

  Future<void> _stopFollow() async {
    await _asrSub?.cancel();
    _asrSub = null;
    _aligner = null;
    await AsrService.instance.stop();
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _confirmDelete(Script script) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除话术'),
        content: Text('确定删除「${script.title}」吗？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('删除',
                  style: TextStyle(color: Color(0xffe0523f)))),
        ],
      ),
    );
    if (ok == true) {
      await ScriptStore.instance.delete(script.id);
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgc,
      body: SafeArea(
        child: Column(children: [
          _topBar(context),
          if (_overlayGranted == false) _overlayPermHint(),
          _newBtn(),
          Expanded(child: _body()),
        ]),
      ),
    );
  }

  /// 未授权时的中文提示条（不出现任何英文权限名）
  Widget _overlayPermHint() => Padding(
        padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xfffff4e5),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Row(children: [
            Icon(Icons.info_outline, size: 16, color: Color(0xffe08a1e)),
            SizedBox(width: 7),
            Expanded(
              child: Text(
                '悬浮窗还需要「显示在其他应用上层」权限。点「开启悬浮窗」按提示开启一次'
                '即可在所有应用上显示',
                style: TextStyle(
                    fontSize: 11.5, color: Color(0xffb06a10), height: 1.45),
              ),
            ),
          ]),
        ),
      );

  Widget _topBar(BuildContext ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
        child: Row(children: [
          _iconBtn(Icons.arrow_back_ios_new, () => Navigator.pop(ctx)),
          const Expanded(
              child: Center(
                  child: Text('台词库',
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w800)))),
          _iconBtn(Icons.history_outlined, () {}),
        ]),
      );

  Widget _newBtn() => Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
        child: GestureDetector(
          onTap: () => _openEditor(),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 13),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                  colors: [Color(0xff7c5cff), Color(0xff9a6bff)]),
              borderRadius: BorderRadius.circular(14),
              boxShadow: const [
                BoxShadow(
                    color: Color(0x337c5cff),
                    blurRadius: 10,
                    offset: Offset(0, 4))
              ],
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.add, color: Colors.white, size: 20),
                SizedBox(width: 6),
                Text('新建台词',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w700)),
              ],
            ),
          ),
        ),
      );

  Widget _body() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_scripts.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('📝', style: TextStyle(fontSize: 42)),
            SizedBox(height: 12),
            Text('还没有台词，点上方「新建台词」写一篇吧',
                style: TextStyle(fontSize: 12.5, color: _sub)),
          ],
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 24),
      itemCount: _scripts.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (ctx, i) => _scriptCard(_scripts[i]),
    );
  }

  Widget _scriptCard(Script s) {
    final lines = _splitLines(s.content);
    final preview = lines.isNotEmpty ? lines.first : '（空话术）';
    return Container(
      decoration: _card(),
      padding: const EdgeInsets.fromLTRB(14, 13, 12, 13),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text(s.title.isEmpty ? '未命名话术' : s.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 14.5, fontWeight: FontWeight.w800)),
          ),
          IconButton(
            icon: const Icon(Icons.edit_outlined,
                size: 18, color: Color(0xff5b6070)),
            onPressed: () => _openEditor(s),
            visualDensity: VisualDensity.compact,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline,
                size: 18, color: Color(0xff5b6070)),
            onPressed: () => _confirmDelete(s),
            visualDensity: VisualDensity.compact,
          ),
        ]),
        const SizedBox(height: 2),
        Text('更新于 ${_fmtTime(s.updatedAt)}',
            style: const TextStyle(fontSize: 10.5, color: _sub)),
        const SizedBox(height: 6),
        Text(preview,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                fontSize: 12, color: Color(0xff5b6070), height: 1.4)),
        const SizedBox(height: 11),
        Row(children: [
          Expanded(
            child: GestureDetector(
              onTap: () => _toggleOverlay(s),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 9),
                decoration: BoxDecoration(
                    gradient: _activeScriptId == s.id
                        ? const LinearGradient(
                            colors: [Color(0xffff5f6d), Color(0xffff2d55)])
                        : const LinearGradient(
                            colors: [Color(0xff7c5cff), Color(0xff9a6bff)]),
                    borderRadius: BorderRadius.circular(11)),
                child: Center(
                    child: Text(
                        _activeScriptId == s.id ? '关闭悬浮窗' : '开启悬浮窗',
                        style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: Colors.white))),
              ),
            ),
          ),
        ]),
      ]),
    );
  }

  Widget _iconBtn(IconData ic, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(11),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withValues(alpha: .05),
                    blurRadius: 5,
                    offset: const Offset(0, 1))
              ]),
          child: Icon(ic, size: 18, color: const Color(0xff5b6070)),
        ),
      );

  BoxDecoration _card() => BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: .05),
              blurRadius: 10,
              offset: const Offset(0, 3))
        ],
      );
}

/// 悬浮窗权限中文指引层：两条路径都写清楚，不猜用户看到的是哪个入口。
class _PermissionGuideSheet extends StatelessWidget {
  final Future<void> Function() onCheck;
  final Future<void> Function() onOpenManual;
  const _PermissionGuideSheet({
    required this.onCheck,
    required this.onOpenManual,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('需要手动开启悬浮窗权限',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            const Text('自动跳转已关闭（避免反复打扰），请按下面任意一条路径手动打开一次即可',
                style: TextStyle(fontSize: 12, color: _sub, height: 1.4)),
            const SizedBox(height: 14),
            _path('路径一（卓易通内）',
                '打开「卓易通」App → 我的 → 应用管理 → 选择「直播工具箱」→ 应用信息 → 权限 → 打开「显示在其他应用上层」'),
            const SizedBox(height: 10),
            _path('路径二（华为系统设置）',
                '打开华为系统设置 → 应用和服务 → 应用管理 → 直播工具箱 → 权限 → 打开「显示在其他应用上层」'),
            const SizedBox(height: 10),
            _path('如果已开启但仍提示未开启',
                '请检查卓易通容器的权限设置，容器内的悬浮窗权限可能无法盖住鸿蒙原生应用'),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: _gradientBtn('我已开启，去检查', onCheck),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: onOpenManual,
                style: OutlinedButton.styleFrom(
                  foregroundColor: _purple,
                  side: const BorderSide(color: _purple),
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(13)),
                ),
                child: const Text('仍然不行？手动打开系统设置页',
                    style: TextStyle(
                        fontSize: 13.5, fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _path(String title, String body) => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xfff6f7fb),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    color: Color(0xff5b6070))),
            const SizedBox(height: 4),
            Text(body,
                style: const TextStyle(
                    fontSize: 12, color: _sub, height: 1.5)),
          ],
        ),
      );

  Widget _gradientBtn(String label, Future<void> Function() onTap) =>
      GestureDetector(
        onTap: () => onTap(),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 13),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
                colors: [Color(0xff7c5cff), Color(0xff9a6bff)]),
            borderRadius: BorderRadius.circular(13),
          ),
          child: Center(
            child: Text(label,
                style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: Colors.white)),
          ),
        ),
      );
}

/// 新建 / 编辑话术
class _ScriptEditorPage extends StatefulWidget {
  final Script? existing;
  const _ScriptEditorPage({this.existing});
  @override
  State<_ScriptEditorPage> createState() => _ScriptEditorPageState();
}

class _ScriptEditorPageState extends State<_ScriptEditorPage> {
  late final TextEditingController _titleCtrl;
  late final TextEditingController _contentCtrl;

  bool get _isNew => widget.existing == null;

  @override
  void initState() {
    super.initState();
    _titleCtrl = TextEditingController(text: widget.existing?.title ?? '');
    _contentCtrl =
        TextEditingController(text: widget.existing?.content ?? '');
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _contentCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final title = _titleCtrl.text.trim();
    final content = _contentCtrl.text.trim();
    if (title.isEmpty && content.isEmpty) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('标题和内容不能都为空')));
      return;
    }
    if (_isNew) {
      await ScriptStore.instance.create(title, content);
    } else {
      await ScriptStore.instance.update(widget.existing!
          .copyWith(title: title, content: content, updatedAt: DateTime.now()));
    }
    if (!mounted) return;
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgc,
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
            child: Row(children: [
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: const Icon(Icons.arrow_back_ios_new,
                    size: 18, color: Color(0xff5b6070)),
              ),
              Expanded(
                child: Center(
                    child: Text(_isNew ? '新建台词' : '编辑台词',
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w800))),
              ),
              TextButton(
                  onPressed: _save,
                  child: const Text('保存',
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: _purple))),
            ]),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                TextField(
                  controller: _titleCtrl,
                  maxLines: 1,
                  decoration: _inputDeco('话术标题', '如：零食专场', Icons.title_outlined),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _contentCtrl,
                  minLines: 10,
                  maxLines: null,
                  textAlignVertical: TextAlignVertical.top,
                  decoration: _inputDeco(
                      '话术内容', '每行一句，按回车换行；开启悬浮窗时按行滚动', Icons.notes_outlined),
                ),
              ],
            ),
          ),
        ]),
      ),
    );
  }

  InputDecoration _inputDeco(String label, String hint, IconData icon) =>
      InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, size: 20, color: _sub),
        filled: true,
        fillColor: Colors.white,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xffeef0f5))),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: _purple, width: 1.2)),
      );
}
