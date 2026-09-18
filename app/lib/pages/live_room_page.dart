import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/asr_service.dart';
import '../services/bg_mode_store.dart';
import '../services/faq_store.dart';
import '../services/script_store.dart';
import '../services/tts_service.dart';
import '../services/user_level.dart';
import '../widgets/digital_avatar_view.dart';
import '../widgets/live_caption_overlay.dart';
import '../widgets/sticker_layer.dart';
import '../widgets/virtual_background_view.dart';
import 'beauty_sheet.dart';

/// 直播间主界面（完全照搬绿幕助手布局）：满屏真人相机。
/// 顶部 X+5 个背景 tabs+眼睛；左右各 8/11 个浮窗功能键；左下角绿色 ▶ 开播按钮。
/// 轻点画面切换控件显隐。
///
/// ★「真人 / 数字人」都在同一个直播间里选（统一路径），而且**可以同时开**：
///   真人层 + 数字人层 + 挂件层 叠在所选背景上。
///
/// ★原「AI 数字人直播」独立页已并入本页（老板要求：数字人直播与虚拟直播间是同一个直播间）。
///   所以数字人出镜时，这里还提供它原来的能力：形象用同一套帧动画（DigitalAvatarLayer）、
///   场景一键切换、当前话术字幕条、话术循环播报开关。
class LiveRoomPage extends StatefulWidget {
  /// 0 = 只出真人；1~4 = 进来就直接出对应数字人（对应 kDigitalAvatarImages 下标 0~3）
  final int initialPerson;

  /// 进来就选中的背景：-1=默认（渐变兜底，不换背景）；0~5=场景视频；6+=实景图
  final int initialScene;

  const LiveRoomPage({
    super.key,
    this.initialPerson = 0,
    this.initialScene = -1,
  });
  @override
  State<LiveRoomPage> createState() => _LiveRoomPageState();
}

class _LiveRoomPageState extends State<LiveRoomPage> {
  // 0=实景（不抠像）/ 1=绿布 / 2=红布 / 3=蓝布 / 4=AI
  /// ★初值由 `BgModeStore` 从本地文件恢复（见 _restoreBgMode）。
  /// 不写死 AI：容器里 AI 抠像起不来，写死 AI 会让用户每次进来都被
  /// "熔断 + 提示"打扰一次。无记录时默认 0=实景（保底、零处理、不发烫）。
  int _bgIdx = 0;
  bool _realOn = true; // 真人（摄像头）出镜开关——可与数字人同时开
  int _personIdx = 0; // 数字人：0=不用；1~4 = kDigitalAvatarImages 下标 0~3
  int _sceneIdx = -1; // 背景：-1=默认（渐变兜底）；0~5=场景视频；6+=实景图
  double _strength = 0.7; // 抠像强度（越大抠得越狠，背景越干净）
  /// ★本机 AI 抠像已判定不可用（端侧分割熔断后置位，并落盘）。
  /// 置位后不再自动切回 AI，避免"选背景 → 又切 AI → 又失败"来回弹。
  bool _aiUnavailable = false;
  final List<StickerItem> _stickers = []; // 已放置的挂件
  int _stickerSeq = 0;
  bool _useFront = true; // 前置/后置摄像头（前置镜像、后置不镜像）
  bool _avatarMirror = false; // 数字人左右翻转
  bool _ctrlVisible = true;
  bool _clockOn = false;
  bool _captionOn = false;
  /// ★播报期间由本页主动把 ASR 麦停掉了，讲完要负责开回来（见 _resumeCaptionAfterSpeak）
  bool _captionPausedBySpeak = false;
  String _clockText = '';
  Timer? _clockTimer;

  // ===== 数字人播报：话术队列 + 循环 + FAQ 插播（并入自原「AI 数字人直播」页）=====
  /// 话术拆成的句子队列。既有约定：`Script.content` 按 \n 拆行（见 script_store.dart），
  /// 过滤掉空行——"一段一行、一行 10~15 秒"，队列天然就是句子粒度。
  List<String> _lines = const [];

  /// 正在讲第几句（-1 = 还没开讲）。
  /// ★插播期间**不动它**，所以插播完自然接着原来的位置往下讲。
  int _idx = -1;

  /// 正在讲的那一句（字幕条显示它，而不是整条话术）
  String _nowLine = '';

  /// 待插播的 FAQ 答案：只在"当前句讲完"这个队列边界生效，不打断半句
  String? _pendingFaq;

  /// 现在播的是 FAQ 插播（进度区显示"插播中"，不显示句号）
  bool _inserting = false;

  /// 20 秒看门狗：只兜"TTS 卡住不出 onComplete"，正常情况走不到
  Timer? _watchdog;

  bool _speaking = false;
  StreamSubscription<void>? _completeSub;

  bool get _isDigital => _personIdx > 0;

  @override
  void initState() {
    super.initState();
    _personIdx = widget.initialPerson;
    if (widget.initialPerson > 0) _realOn = false; // 从「数字人直播」进来：默认只出数字人
    _sceneIdx = widget.initialScene;
    _restoreBgMode().then((_) => _applyInitialSceneBg());
    _loadLines();
    // 播报讲完一句自动接着讲下一句（循环），和合并前完全一致
    _completeSub = TtsService.instance.onComplete.listen((_) => _onSpeakComplete());
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final n = DateTime.now();
      if (mounted) {
        setState(() => _clockText =
            '${_fmt(n.hour)}:${_fmt(n.minute)}:${_fmt(n.second)}');
      }
    });
  }

  /// ★恢复上次用的档位 + 本机 AI 抠像可用性（都落盘，见 BgModeStore）。
  /// 已判定 AI 不可用的机型：即使上次记录是 AI，也落回实景（不再自动选 AI）。
  Future<void> _restoreBgMode() async {
    final store = BgModeStore.instance;
    await store.load();
    if (!mounted) return;
    final idx = store.bgIdx;
    setState(() {
      _aiUnavailable = store.aiUnavailable;
      _bgIdx = (_aiUnavailable && idx == 4) ? 0 : idx;
    });
  }

  /// 档位变化 → 落盘（异步、不阻塞 UI）
  void _persistBgMode() {
    BgModeStore.instance.saveBgIdx(_bgIdx);
  }

  /// 带着场景进来（开播准备台「开始直播」透传的 initialScene）：
  /// 档位还停在"实景"时自动切 AI，否则用户之后打开真人出镜会"看不到背景"。
  /// 与「背景」里选场景（_applyScene）保持一致；
  /// ★放在 _restoreBgMode 之后执行——AI 已熔断的机型不走这条路，不会来回弹提示。
  void _applyInitialSceneBg() {
    if (!mounted) return;
    if (widget.initialScene < 0 || _bgIdx != 0 || _aiUnavailable) return;
    setState(() => _bgIdx = 4);
    _persistBgMode();
  }

  static String _fmt(int x) => x.toString().padLeft(2, '0');

  @override
  void dispose() {
    _clockTimer?.cancel();
    _watchdog?.cancel();
    _completeSub?.cancel();
    TtsService.instance.stop(); // 离开直播间就别再出声
    AsrService.instance.stop(); // 也别留着麦克风在后台采集（字幕）
    super.dispose();
  }

  // ===== 数字人播报：话术队列 + 循环 + FAQ 插播 =====

  /// 取话术库里最新更新的一条，按 \n 拆成句子队列（list 已按更新时间倒序）
  Future<void> _loadLines() async {
    final list = await ScriptStore.instance.list();
    if (!mounted) return;
    final raw = list.isEmpty ? '' : list.first.content;
    setState(() {
      _lines = raw
          .split('\n')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
    });
    // 从「开播准备台」带着数字人进来的 → 自动开讲（合并前 DigitalLivePage 就是这个行为）
    if (widget.initialPerson > 0 && _lines.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _startSpeak());
    }
  }

  /// 下一句该念什么 —— **队列推进的唯一出口**。
  /// ★"多套话术轮换"的口子就留在这里：将来一套循环要升级成多套轮换，
  ///   只改这一个方法（比如走到某套末尾就换下一套），
  ///   别把"该讲哪句"的分支散到调用处。**现在只实现一套循环。**
  String _nextLine() {
    // ① FAQ 插播：只在队列边界生效（不在句子中间打断），
    //   且不推进 _idx → 插播完自然回到原来的位置
    final faq = _pendingFaq;
    if (faq != null) {
      _pendingFaq = null;
      _inserting = true;
      return faq;
    }
    _inserting = false;
    if (_lines.isEmpty) return '';
    // ② 一套话术循环：-1+1=0（首次正好第一句），末尾 (n-1+1)%n 回到第一句
    _idx = (_idx + 1) % _lines.length;
    return _lines[_idx];
  }

  /// 讲下一句
  Future<void> _speakNext() async {
    if (!_speaking) return;
    final line = _nextLine();
    if (line.isEmpty) {
      await _stopSpeak(); // 没有可讲的了（没话术、也没有待插播）
      return;
    }
    setState(() => _nowLine = line); // 字幕条 + 进度一起刷新

    // ★底膜接入点（等"说话态底膜"素材到位后改这一段）：
    //   现在这一句是下面这行 TTS 现场合成语音播的。
    //   素材到位后改成：先看这一句有没有产物 ——
    //   `AssetStore.instance.get(scriptId, lineIdx, avatarId, lang)`，
    //   有 path 就播视频、没有仍然用 TTS 兜底。
    //   三个参数怎么取：scriptId = _loadLines 里 list.first.id，
    //   lineIdx = `_inserting ? kAssetLineFaq : _idx`（正常播报时 _idx 就是当前句下标，
    //   插播那一条是 FAQ 答案、用 -1），avatarId = _personIdx - 1，lang 用 kAssetLangZh。
    //   ⚠️拿到素材要用 `asset.isStale(_lines[lineIdx])` 判一下：话术被改过就失效了
    //     （行号会错位，所以以 lineText 为准），失效就当未生成、提示重新生成。
    //   ⚠️现在**故意不写**任何视频播放逻辑：素材形态还没定，提前写会白做。
    try {
      await TtsService.instance.speak(line);
    } catch (e) {
      // 技术细节只进日志；界面一律中文，不暴露英文异常/堆栈
      debugPrint('[TTS] 播报失败: $e');
      if (mounted) {
        setState(() => _speaking = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('播报失败，请重试')),
        );
        await _resumeCaptionAfterSpeak();
      }
      return;
    }
    if (!mounted || !_speaking) return;
    _armWatchdog(); // 播放已经开始了，这句从这时候起算 20 秒
    _prefetchAhead(); // ★这句已在播、worker 空着 → 趁现在把后面几句先合成好
  }

  /// 预取用的"从现在起第 n 句"——**只看不推进**，纯粹给预取用。
  /// 真正推进仍然只有 _nextLine() 一处。
  /// ★猜错了也没关系：预取命中要求**文本一字不差地相同**，
  ///   估错最多是白生成一份、被自动清掉，绝不会把别的句子播出来。
  String _peekAhead(int n) {
    // FAQ 待插播：第 1 句就是它，之后的从原进度继续数
    final faq = _pendingFaq;
    if (faq != null) {
      if (n == 1) return faq;
      n -= 1;
    }
    if (_lines.isEmpty) return '';
    return _lines[(_idx + n) % _lines.length];
  }

  /// 趁当前句在播时，把后面几句提前合成好（边播边合成流水线）。
  /// ★一次预取 [depth] 句：长句播放时 worker 能提前多合成几句攒下缓冲，
  ///   短句连发（播放 <1s、合成 >1s）时才不会"这句播完了、下一句还没好"。
  /// ★仍放在 speak() 返回之后再发：worker 串行，别把正在播这句的生成挤掉。
  /// 不 await：它只是优化，失败也不影响播报。
  static const int _prefetchDepth = 3;

  void _prefetchAhead() {
    for (int n = 1; n <= _prefetchDepth; n++) {
      final peek = _peekAhead(n);
      if (peek.isEmpty) break;
      TtsService.instance.prefetch(peek);
    }
  }

  /// 20 秒看门狗：**只用来兜"TTS 卡住不出 onComplete"**。
  /// 正常情况 onComplete 就是句尾，走不到这里；超时则强制推进下一句 + 中文提示，
  /// 免得整场直播卡死在同一句上。
  /// ★不管"生成阶段就卡死"（那时 `await speak` 永不返回、看门狗也装不上）；
  ///   那种情况用户点一下「停止播报」就能脱身（TtsService.stop 会作废在途结果）。
  void _armWatchdog() {
    _watchdog?.cancel();
    _watchdog = Timer(const Duration(seconds: 20), () async {
      if (!mounted || !_speaking) return;
      debugPrint('[TTS] 这句超过 20 秒还没播完，强制推进下一句');
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('这一句卡住了，已跳到下一句'),
        duration: Duration(seconds: 2),
      ));
      await TtsService.instance.stop(); // 停掉卡住的这句，并作废在途生成
      if (!mounted || !_speaking) return;
      await _speakNext();
    });
  }

  void _onSpeakComplete() {
    if (!mounted || !_speaking) return;
    _watchdog?.cancel(); // 正常句尾：撤掉看门狗
    _speakNext(); // 下一句（循环 / 插播都从 _nextLine 走）
  }

  Future<void> _startSpeak() async {
    if (_speaking) return;
    // 没话术但有待插播的答疑也要能讲（插播入口在没开播时点了就得有反应）
    if (_lines.isEmpty && _pendingFaq == null) return;
    setState(() => _speaking = true);
    await _pauseCaptionForSpeak(); // ★先停麦再开口，别把数字人自己的声音当主播说话
    try {
      await TtsService.instance.init();
    } catch (e) {
      debugPrint('[TTS] 语音初始化失败: $e');
      if (mounted) {
        setState(() => _speaking = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('语音功能初始化失败，请重试')),
        );
        await _resumeCaptionAfterSpeak();
      }
      return;
    }
    await _speakNext();
  }

  Future<void> _stopSpeak() async {
    _watchdog?.cancel();
    if (mounted) setState(() => _speaking = false);
    await TtsService.instance.stop();
    await _resumeCaptionAfterSpeak(); // ★讲完了，把字幕麦开回来
  }

  /// ★播报期间暂停 ASR 采集。
  /// 不停会出大问题：数字人的声音被麦克风采到 → 识别成"主播在说话" →
  /// 字幕全是乱码；等弹幕自动回复接上，更会变成
  /// "AI 听到自己讲的话 → 当成观众提问 → 又回答一次"的自问自答死循环。
  /// 产品上也站得住：数字人在讲的时候，主播本来就不该同时说话。
  Future<void> _pauseCaptionForSpeak() async {
    if (!_captionOn) return;
    _captionPausedBySpeak = true;
    await AsrService.instance.stop(); // 未在运行则内部直接返回
  }

  /// 播报结束/失败 → 把刚才主动停掉的字幕识别恢复回来
  Future<void> _resumeCaptionAfterSpeak() async {
    if (!_captionPausedBySpeak) return;
    _captionPausedBySpeak = false;
    if (!mounted || !_captionOn) return;
    try {
      await AsrService.instance.start();
    } catch (e) {
      // 技术细节只进日志；界面一律中文
      debugPrint('[CAP] 字幕恢复失败: $e');
      if (mounted) setState(() => _captionOn = false);
    }
  }

  Future<void> _toggleSpeak() async {
    if (_speaking) {
      await _stopSpeak();
      return;
    }
    // 没有话术就别让数字人干站着：给明确引导，不静默
    if (_lines.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('还没有话术：数字人没有可讲的内容，先去话术库里写一条'),
        duration: Duration(seconds: 3),
      ));
      return;
    }
    await _startSpeak();
  }

  /// 排一条答疑等插播 / 直接开讲。
  /// 规则：**等当前这句讲完再插，不在句子中间打断**（_nextLine 只在队列边界消费它），
  /// 插播完 _idx 没动，所以自然回到原来的位置继续。
  void _insertFaq(String answer) {
    final text = answer.trim();
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('这条答疑还没有写回答')));
      return;
    }
    _pendingFaq = text;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('已排队：这句讲完就插播这条答疑'),
      duration: Duration(seconds: 2),
    ));
    if (!_speaking) _startSpeak(); // 没在播就顺便开讲，别点了没反应
  }

  /// 「插播答疑」：弹幕自动触发还没接（弹幕 API 完全没做），
  /// 所以这里先给**手动触发入口**——点一条常见问题就真的会插播，
  /// 等功能可验证；等弹幕接进来，把触发源换成命中弹幕即可，插播逻辑不用改。
  void _faqSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: Color(0xff1c1c22),
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        ),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
        child: FutureBuilder<List<Faq>>(
          future: FaqStore.instance.list(),
          builder: (ctx2, snap) {
            // 读盘期间先显示"读取中"——别把"还没读出来"显示成"还没有常见问题"
            if (snap.connectionState != ConnectionState.done) {
              return const SizedBox(
                height: 120,
                child: Center(
                    child: CircularProgressIndicator(color: Colors.white24)),
              );
            }
            final faqs = snap.data ?? const <Faq>[];
            return Column(mainAxisSize: MainAxisSize.min, children: [
              const Text('插播答疑',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              const Text('点一条就插播它的回答：这句讲完才插，不打断半句，插完接着原来的进度讲',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white54, fontSize: 11)),
              const SizedBox(height: 12),
              if (faqs.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Text('还没有常见问题：先去话术库的「常见问题」里写几条',
                      style: TextStyle(color: Colors.white70, fontSize: 12.5)),
                )
              else
                SizedBox(
                  height: 260,
                  child: ListView.separated(
                    itemCount: faqs.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (_, i) {
                      final f = faqs[i];
                      return GestureDetector(
                        onTap: () {
                          Navigator.pop(ctx);
                          _insertFaq(f.answer);
                        },
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: .07),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(f.question,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600)),
                              const SizedBox(height: 4),
                              Text(
                                  f.answer.trim().isEmpty
                                      ? '（还没写回答）'
                                      : f.answer,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      color: Colors.white60,
                                      fontSize: 11.5,
                                      height: 1.4)),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
            ]);
          },
        ),
      ),
    );
  }

  /// 选数字人形象：关掉数字人时同步停止播报（避免"看不见人还在念"）
  void _setPerson(int idx) {
    setState(() => _personIdx = idx);
    if (idx == 0 && _speaking) _stopSpeak();
  }

  /// 选背景（场景视频/实景图）：顶部「场景」快捷切换与「背景」弹窗共用同一份状态
  void _applyScene(int idx) {
    setState(() {
      _sceneIdx = idx;
      // 选了背景却还在"实景"（不抠像）→ 自动切到 AI，保证"换背景就看不到实景"。
      // ★但本机 AI 抠像已熔断时不再自动切（否则来回弹、还费电）
      if (idx >= 0 && _bgIdx == 0 && !_aiUnavailable) _bgIdx = 4;
    });
    _persistBgMode();
  }

  /// 未实现功能的占位提示（按会员等级区分文案）
  void _todo(String label, {String? badge}) {
    final hint = badge == 'S'
        ? '（运营商专属 · 开发中）'
        : badge == 'V'
            ? '（超级会员专属 · 开发中）'
            : '（开发中）';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text('$label$hint'), duration: const Duration(seconds: 1)),
    );
  }

  /// ★AI 抠像在本机不可用（端侧分割连续失败已熔断）→ 自动降级到实景 + 中文提示。
  /// 不显示任何英文异常；给出下一步动作（改用色布模式）。
  void _onSegmentationUnavailable() {
    if (!mounted) return;
    setState(() {
      _aiUnavailable = true;
      if (_bgIdx == 4) _bgIdx = 0; // AI 抠像 → 实景
    });
    // ★落盘：下次进直播间直接是实景，不会再自动选 AI、不会再弹这次提示
    BgModeStore.instance.markAiUnavailable();
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('AI 抠像在这台设备上用不了，已自动切到实景。'
          '想抠像可以挂一块绿布，再点顶部「绿布」，效果更快更干净。'),
      duration: Duration(seconds: 6),
    ));
  }

  /// 字幕开关：开启时启动端侧 ASR（麦克风识别），实时字幕叠在画面上
  Future<void> _toggleCaption() async {
    final on = !_captionOn;
    if (on) {
      setState(() => _captionOn = true);
      // ★数字人正在播报：先记下"用户要开字幕"，等它讲完再真正开麦。
      //   否则麦克风立刻会把数字人的声音识别成字幕（见 _pauseCaptionForSpeak）
      if (_speaking) {
        _captionPausedBySpeak = true;
        return;
      }
      try {
        await AsrService.instance.start();
      } catch (e) {
        // 技术细节只进日志；界面一律中文，不暴露英文异常/堆栈
        debugPrint('[CAP] 字幕启动失败: $e');
        if (mounted) {
          setState(() => _captionOn = false);
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('字幕启动失败，请重试')));
        }
      }
    } else {
      setState(() => _captionOn = false);
      _captionPausedBySpeak = false;
      await AsrService.instance.stop();
    }
  }

  static const _bgNames = ['实景', '绿布', '红布', '蓝布', 'AI'];
  /// 全透明背景：选了场景视频时，人像层不画自己的背景，让下层视频透出来
  static const _clear = LinearGradient(
      colors: [Color(0x00000000), Color(0x00000000)]);
  /// 默认背景（没选场景时的兜底渐变）。
  /// ★绿/红/蓝幕布不再当作背景色——幕布只影响"识别方式"，背景一律用用户选的。
  static const _fallbackBg = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xff2a1a4a), Color(0xff7c5cff)]);

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: Colors.black,
        body: GestureDetector(
          onTap: () => setState(() => _ctrlVisible = !_ctrlVisible),
          behavior: HitTestBehavior.opaque,
          child: Stack(children: [
            // ===== 1. 主画面 =====
            //  图层顺序：背景 → 真人（抠像）→ 数字人（可与真人**同框**并存）
            Positioned.fill(
              child: Stack(fit: StackFit.expand, children: [
                // ① 背景层：选了就用（视频/实景图）；只出数字人时用兜底渐变
                //   ★顶部那行幕布（实景/绿布/红布/蓝布/AI）只决定"识别方式"，
                //     不再决定背景颜色——背景永远来自「背景」里选的内容
                if (_sceneIdx >= 0)
                  SceneBackground(index: _sceneIdx)
                else if (!_realOn)
                  const DecoratedBox(
                      decoration: BoxDecoration(gradient: _fallbackBg)),
                // ② 真人层（可单独关掉）
                if (_realOn)
                  VirtualBackgroundView(
                    // 选了背景 → 真人层不画背景（透明），让下层背景清晰透出来
                    background: _sceneIdx >= 0 ? _clear : _fallbackBg,
                    useFront: _useFront,
                    strength: _strength,
                    enableSegmentation: _bgIdx != 0,
                    // 绿布/红布/蓝布 → 真·色键抠像（AI=4 不做色键）
                    keyColor: _bgIdx >= 1 && _bgIdx <= 3 ? _bgIdx - 1 : -1,
                    // ★AI 抠像失败熔断时自动降级到实景（并中文提示）
                    onSegmentationUnavailable: _onSegmentationUnavailable,
                  ),
                // ③ 数字人层（独立开关，可与真人同时出现）
                if (_isDigital)
                  DigitalAvatarLayer(
                      avatarIndex: _personIdx - 1, mirror: _avatarMirror),
                // ④ 挂件层（贴纸，可拖动缩放；删除在「挂件」弹窗里做）
                if (_stickers.isNotEmpty)
                  Positioned.fill(child: StickerLayer(items: _stickers)),
              ]),
            ),

            // ===== 2. 顶部：X + 5 个背景 tabs + 眼睛 =====
            //   ★数字人出镜时，下面多一行：「AI 数字人直播」角标 + 场景一键切换
            _bar(
              child: Align(
                alignment: Alignment.topCenter,
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      SizedBox(
                        height: 38,
                        child: Row(children: [
                          // X 关闭（磨砂半透明圆形）
                          _roundIcon(Icons.close, () => Navigator.pop(context),
                              size: 32, iconSize: 18),
                          const SizedBox(width: 6),
                          // 幕布/识别方式（实景/绿布/红布/蓝布/AI）——始终不变；
                          // 「背景」内容在左侧「背景」按钮里选（两件事，别混）
                          Expanded(child: _bgTabs()),
                          const SizedBox(width: 6),
                          // 眼睛隐藏
                          _roundIcon(
                              Icons.visibility_off_outlined,
                              () => setState(() => _ctrlVisible = !_ctrlVisible),
                              size: 32,
                              iconSize: 18),
                        ]),
                      ),
                      if (_isDigital) ...[
                        const SizedBox(height: 10),
                        Row(children: [
                          _liveBadge(),
                          const SizedBox(width: 8),
                          Expanded(child: _sceneTabs()),
                        ]),
                      ],
                    ]),
                  ),
                ),
              ),
            ),

            // ===== 3. 左侧 8 个浮窗功能键（无背景）=====
            _bar(
              child: Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    // ★「人物」：真人 / 数字人 统一入口。
                    //   标签固定叫"人物"——之前显示人名会把旁边功能键的位置顶掉/混淆
                    _floating(
                        _isDigital
                            ? Icons.smart_toy_outlined
                            : Icons.person_outline,
                        '人物',
                        _personSheet),
                    const SizedBox(height: 12),
                    // 翻转：有真人就切前后摄像头；只有数字人时翻转数字人（常驻，不被顶掉）
                    _floating(Icons.cameraswitch_outlined, '翻转', () {
                      setState(() {
                        if (_realOn) {
                          _useFront = !_useFront;
                        } else {
                          _avatarMirror = !_avatarMirror;
                        }
                      });
                    }),
                    const SizedBox(height: 12),
                    // 美颜只对摄像头画面有意义
                    if (_realOn) ...[
                      _floating(Icons.face_retouching_natural_outlined, '美颜',
                          () => showModalBottomSheet(
                              context: context,
                              backgroundColor: Colors.transparent,
                              builder: (_) => const BeautySheet()),
                          badge: 'V'),
                      const SizedBox(height: 12),
                    ],
                    // ★背景：实际画面背景（场景库）——与顶部"幕布"（绿布/红布/AI）是两件事
                    _floating(Icons.wallpaper_outlined, '背景', _bgSheet),
                    const SizedBox(height: 12),
                    _floating(Icons.my_location_outlined, '轨选',
                        () => _todo('轨选', badge: 'S'),
                        badge: 'S'),
                    const SizedBox(height: 14),
                    _floating(Icons.auto_awesome_outlined, '幻影',
                        () => _todo('幻影', badge: 'S'),
                        badge: 'S'),
                    const SizedBox(height: 14),
                    _floating(Icons.filter_center_focus_outlined, '运镜',
                        () => _todo('运镜', badge: 'S'),
                        badge: 'S'),
                    const SizedBox(height: 14),
                    _floating(Icons.tune_outlined, '调色', () => _todo('调色')),
                    const SizedBox(height: 14),
                    _floating(Icons.layers_outlined, '图层',
                        () => _todo('图层', badge: 'S'),
                        badge: 'S'),
                    const SizedBox(height: 14),
                    _floating(Icons.settings_remote_outlined, '遥控',
                        () => _todo('遥控', badge: 'S'),
                        badge: 'S'),
                  ]),
                ),
              ),
            ),

            // ===== 4. 右侧 11 个浮窗功能键 =====
            _bar(
              child: Align(
                alignment: Alignment.centerRight,
                child: Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    _floating(Icons.widgets_outlined, '挂件', _stickerSheet,
                        badge: 'V'),
                    const SizedBox(height: 14),
                    _floating(Icons.subtitles_outlined, '字幕', _toggleCaption),
                    const SizedBox(height: 14),
                    _floating(Icons.music_note_outlined, '音乐',
                        () => _todo('音乐', badge: 'V'),
                        badge: 'V'),
                    const SizedBox(height: 14),
                    _floating(Icons.surround_sound_outlined, '音效',
                        () => _todo('音效', badge: 'V'),
                        badge: 'V'),
                    const SizedBox(height: 14),
                    _floating(Icons.videocam_outlined, '机位',
                        () => _todo('机位', badge: 'V'),
                        badge: 'V'),
                    const SizedBox(height: 14),
                    _floating(Icons.sports_esports_outlined, '小游戏',
                        () => _todo('小游戏', badge: 'S'),
                        badge: 'S'),
                    const SizedBox(height: 14),
                    _floating(Icons.access_time_outlined, '时钟',
                        () => setState(() => _clockOn = !_clockOn)),
                    const SizedBox(height: 14),
                    _floating(Icons.star_outline, '特效',
                        () => _todo('特效', badge: 'V'),
                        badge: 'V'),
                    const SizedBox(height: 14),
                    _floating(Icons.smart_toy_outlined, 'AI',
                        () => _todo('AI', badge: 'S'),
                        badge: 'S'),
                    const SizedBox(height: 14),
                    _floating(Icons.fiber_manual_record_outlined, '录制',
                        () => _todo('录制')),
                    const SizedBox(height: 14),
                    _floating(Icons.sort_outlined, '排序', () => _todo('排序')),
                  ]),
                ),
              ),
            ),

            // ===== 5. 左下角：绿色圆形 ▶ 开播按钮 =====
            _bar(
              child: Align(
                alignment: Alignment.bottomLeft,
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 0, 24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _goButton(),
                        const SizedBox(height: 6),
                        const Text('开播',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                shadows: [
                                  Shadow(
                                      color: Color(0xcc000000), blurRadius: 4)
                                ])),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // ===== 6. 右下角：数字人播报 + 插播答疑（只在数字人出镜时出现）=====
            //   与左下角「开播」左右对称；返回/切形象不重复放——顶部 X 和「人物」里已有
            if (_isDigital)
              _bar(
                child: Align(
                  alignment: Alignment.bottomRight,
                  child: SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(0, 0, 16, 24),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _insertFaqEntry(),
                          const SizedBox(width: 8),
                          _speakButton(),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

            // ===== 7. 数字人正在讲的那一句 + 进度（念到哪了，观众也看得见）=====
            if (_isDigital && _nowLine.isNotEmpty) _subtitleStrip(),

            // ===== 8. 时钟叠加 =====
            if (_clockOn)
              _bar(
                child: Align(
                  alignment: Alignment.topCenter,
                  child: Padding(
                    // 数字人出镜时顶部多了一行「角标 + 场景」，时钟顺势下移避免压在一起
                    padding: EdgeInsets.only(top: _isDigital ? 118 : 70),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: .45),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(
                        _clockText.isEmpty ? '00:00:00' : _clockText,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  ),
                ),
              ),

            // ===== 9. 实时字幕叠加（ASR 识别结果，随推流出去）=====
            //   播报中不显示：此时 ASR 已被主动停掉，留着只会定格上一句旧字幕
            //   （这几句由数字人话术字幕条顶上，见 _subtitleStrip）
            if (_captionOn && !_speaking)
              const IgnorePointer(child: LiveCaptionOverlay()),
          ]),
        ),
      ),
    );
  }

  /// 控件容器（受 _ctrlVisible 控制淡入淡出 + 暂停点击）
  Widget _bar({required Widget child}) => AnimatedOpacity(
        duration: const Duration(milliseconds: 250),
        opacity: _ctrlVisible ? 1 : 0,
        child: IgnorePointer(ignoring: !_ctrlVisible, child: child),
      );

  /// 顶部圆形图标按钮（X、眼睛等）
  Widget _roundIcon(IconData icon, VoidCallback onTap,
      {double size = 32, double iconSize = 18}) {
    return GestureDetector(
      onTap: onTap,
      child: ClipOval(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: .35),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: Colors.white, size: iconSize),
          ),
        ),
      ),
    );
  }

  /// 5 个背景类型 tabs（黑色半透明胶囊，文字白色，选中态黑色高亮）
  Widget _bgTabs() => ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _bgNames.length,
        separatorBuilder: (_, _) => const SizedBox(width: 4),
        itemBuilder: (_, i) {
          final on = _bgIdx == i;
          return GestureDetector(
            onTap: () {
              setState(() {
                _bgIdx = i;
                // 手动再点「AI」= 用户主动重试，清掉"不可用"标记，让它再试一轮
                if (i == 4) _aiUnavailable = false;
              });
              _persistBgMode(); // 记住用户的选择（saveBgIdx(4) 会一并清掉"不可用"标记）
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                  color: on ? Colors.black : Colors.black.withValues(alpha: .4),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: Colors.white.withValues(alpha: .15), width: 0.5)),
              child: Center(
                child: Text(_bgNames[i],
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: on ? FontWeight.w800 : FontWeight.w500,
                        color: Colors.white)),
              ),
            ),
          );
        },
      );

  /// 「数字人直播」角标（并入自原独立页）：一眼看出"现在数字人正在出镜"
  Widget _liveBadge() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: .35),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
                color: Color(0xffff4d5e), shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          const Text('AI 数字人直播',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w700)),
        ]),
      );

  /// 场景一键切换（并入自原独立页）：「默认」+ 6 个视频场景。
  /// ★和左侧「背景」弹窗是**同一份状态**（_sceneIdx），弹窗里还有实景图更全的一套，
  ///   这里只做直播中最常用的"一秒换场景"。
  Widget _sceneTabs() => SizedBox(
        height: 34,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: kSceneNames.length + 1,
          separatorBuilder: (_, _) => const SizedBox(width: 8),
          itemBuilder: (_, i) {
            final idx = i - 1; // i=0 → 默认（-1）
            final on = _sceneIdx == idx;
            return GestureDetector(
              onTap: () => _applyScene(idx),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: on ? Colors.white : Colors.black.withValues(alpha: .3),
                  borderRadius: BorderRadius.circular(17),
                  border: Border.all(
                      color: Colors.white.withValues(alpha: on ? 0 : .18),
                      width: .6),
                ),
                child: Text(
                  idx < 0 ? '默认' : kSceneNames[idx],
                  style: TextStyle(
                    color: on ? const Color(0xff4a3a8a) : Colors.white,
                    fontSize: 12,
                    fontWeight: on ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ),
            );
          },
        ),
      );

  /// 数字人正在讲的那一句 + 轻量进度（并入自原独立页，进度为队列化后新增）。
  /// ★不另设"字幕"开关：右侧那颗「字幕」是**端侧 ASR 实时识别字幕**，两回事；
  ///   再放一个同名开关只会让人分不清。这里随"有没有正在讲的话"自动出现/消失。
  Widget _subtitleStrip() => Positioned(
        left: 20,
        right: 20,
        bottom: 112,
        child: IgnorePointer(
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: .45),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(children: [
              // 进度：主播一眼知道讲到哪了（插播时显示"插播中"）
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .18),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Text(
                  _progressLabel,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _nowLine,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: Colors.white, fontSize: 13, height: 1.5),
                ),
              ),
            ]),
          ),
        ),
      );

  /// 进度文案：`3/30`；插播时显示"插播中"；还没开讲显示 `—`
  String get _progressLabel {
    if (_inserting) return '插播中';
    if (_idx < 0 || _lines.isEmpty) return '—';
    return '${_idx + 1}/${_lines.length}';
  }

  /// 「插播答疑」入口（横幅第二颗按钮，只在数字人出镜时出现）。
  /// 让它和「开始播报」并排放在一起：它是播报的附属动作，放这里最好找。
  Widget _insertFaqEntry() => GestureDetector(
        onTap: _faqSheet,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: .35),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
                color: Colors.white.withValues(alpha: .3), width: .8),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.forum_outlined, color: Colors.white, size: 18),
            const SizedBox(width: 5),
            Text(_pendingFaq == null ? '插播答疑' : '插播待播',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700)),
          ]),
        ),
      );

  /// 数字人播报开关（并入自原独立页的底部主按钮）
  Widget _speakButton() => GestureDetector(
        onTap: _toggleSpeak,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          decoration: BoxDecoration(
            gradient: _speaking
                ? const LinearGradient(
                    colors: [Color(0xffff5f6d), Color(0xffff2d55)])
                : const LinearGradient(
                    colors: [Color(0xffff2d7a), Color(0xff7c5cff)]),
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                  color: const Color(0xffb23df0).withValues(alpha: .35),
                  blurRadius: 14,
                  offset: const Offset(0, 4)),
            ],
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(_speaking ? Icons.stop_rounded : Icons.play_arrow_rounded,
                color: Colors.white, size: 20),
            const SizedBox(width: 5),
            Text(_speaking ? '停止播报' : '开始播报',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800)),
          ]),
        ),
      );

  /// 「背景」面板：画面实际背景（场景库）。
  /// 与顶部那一行「幕布/识别方式」（实景/绿布/红布/蓝布/AI）是**两件事**。
  void _bgSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: Color(0xff1c1c22),
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        ),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
        child: StatefulBuilder(
          builder: (ctx2, setSheet) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('选择背景',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                const Text(
                    '顶部那行是「幕布/识别方式」，这里才是画面换成什么背景（背景会清晰铺满，不会被幕布颜色盖住）',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white54, fontSize: 11)),
                const SizedBox(height: 14),
                SizedBox(
                  height: 116,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      _bgCard(ctx, -1, '默认'),
                      for (int i = 0; i < kAllBgNames.length; i++)
                        _bgCard(ctx, i, kAllBgNames[i]),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text('抠像强度（背景发虚/人像有洞都调这里）',
                      style: TextStyle(color: Colors.white70, fontSize: 12)),
                ),
                const SizedBox(height: 8),
                Row(children: [
                  _strengthChip('柔和', 0.55, setSheet),
                  const SizedBox(width: 8),
                  _strengthChip('标准', 0.7, setSheet),
                  const SizedBox(width: 8),
                  _strengthChip('强力', 0.9, setSheet),
                ]),
              ]),
        ),
      ),
    );
  }

  /// 抠像强度档位
  Widget _strengthChip(String label, double v, StateSetter refresh) {
    final on = (_strength - v).abs() < 0.01;
    return GestureDetector(
      onTap: () {
        setState(() => _strength = v);
        refresh(() {});
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color:
              on ? const Color(0xff7c5cff) : Colors.white.withValues(alpha: .08),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Text(label,
            style: const TextStyle(color: Colors.white, fontSize: 12.5)),
      ),
    );
  }

  /// 背景卡片：idx = -1 默认（紫渐变兜底）；0~5 视频场景；6+ 实景图
  Widget _bgCard(BuildContext ctx, int idx, String name) {
    final selected = _sceneIdx == idx;
    final imgIdx = idx - kSceneVideos.length;
    final isImage = imgIdx >= 0 && imgIdx < kBgImages.length;
    return GestureDetector(
      onTap: () {
        Navigator.pop(ctx);
        _applyScene(idx);
      },
      child: Container(
        width: 104,
        margin: const EdgeInsets.only(right: 10),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: selected
              ? const Color(0xff7c5cff).withValues(alpha: .28)
              : Colors.white.withValues(alpha: .06),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: selected ? const Color(0xff9d7bff) : Colors.white24,
              width: selected ? 1.6 : 1),
        ),
        child: Column(children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: idx < 0
                  ? Container(
                      color: Colors.white10,
                      child: const Icon(Icons.gradient_outlined,
                          color: Colors.white70, size: 24),
                    )
                  : isImage
                      ? Image.asset(kBgImages[imgIdx],
                          fit: BoxFit.cover, width: double.infinity)
                      : Container(
                          color: Colors.white10,
                          child: const Icon(Icons.videocam_outlined,
                              color: Colors.white70, size: 24),
                        ),
            ),
          ),
          const SizedBox(height: 6),
          Text(name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontSize: 11)),
        ]),
      ),
    );
  }

  /// 「挂件」面板：素材库透明 GIF 贴纸。点一下加到画面上；
  /// 画面上的挂件可拖动/双指缩放，点它右上角 ✕ 即删除。
  void _stickerSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx2, setSheet) => Container(
          decoration: const BoxDecoration(
            color: Color(0xff1c1c22),
            borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
          ),
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('挂件',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            const Text('点一下加到画面；画面上可拖动/双指缩放；删不掉就在这里点 ✕',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white54, fontSize: 11)),
            const SizedBox(height: 12),
            SizedBox(
              height: 226,
              child: GridView.builder(
                gridDelegate:
                    const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 4,
                        mainAxisSpacing: 8,
                        crossAxisSpacing: 8),
                itemCount: kStickers.length,
                itemBuilder: (_, i) => GestureDetector(
                  onTap: () {
                    setState(() =>
                        _stickers.add(StickerItem(_stickerSeq++, kStickers[i])));
                    setSheet(() {});
                  },
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: .07),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    padding: const EdgeInsets.all(6),
                    child: Image.asset(kStickers[i], fit: BoxFit.contain),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: Text('已放置 ${_stickers.length} 个',
                    style:
                        const TextStyle(color: Colors.white54, fontSize: 11.5)),
              ),
              TextButton(
                onPressed: _stickers.isEmpty
                    ? null
                    : () {
                        setState(() => _stickers.clear());
                        setSheet(() {});
                      },
                child: const Text('全部清空',
                    style: TextStyle(color: Color(0xffff8a80))),
              ),
            ]),
            // ★在弹窗里直接删：不受画面手势干扰，一定能删掉
            if (_stickers.isNotEmpty)
              SizedBox(
                height: 58,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    for (final s in _stickers)
                      Container(
                        width: 58,
                        margin: const EdgeInsets.only(right: 8),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: .07),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Stack(clipBehavior: Clip.none, children: [
                          Positioned.fill(
                            child: Padding(
                              padding: const EdgeInsets.all(6),
                              child:
                                  Image.asset(s.asset, fit: BoxFit.contain),
                            ),
                          ),
                          Positioned(
                            right: -8,
                            top: -8,
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () {
                                setState(() => _stickers
                                    .removeWhere((x) => x.id == s.id));
                                setSheet(() {});
                              },
                              child: Container(
                                width: 32,
                                height: 32,
                                alignment: Alignment.center,
                                child: Container(
                                  width: 22,
                                  height: 22,
                                  decoration: const BoxDecoration(
                                      color: Color(0xffff3b30),
                                      shape: BoxShape.circle),
                                  child: const Icon(Icons.close,
                                      size: 14, color: Colors.white),
                                ),
                              ),
                            ),
                          ),
                        ]),
                      ),
                  ],
                ),
              ),
          ]),
        ),
      ),
    );
  }

  /// 「人物」面板：真人（开关）+ 数字人（单选，可选"不用"）。
  /// ★真人与数字人**可以同时开**（同框），不是二选一。
  void _personSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Container(
          decoration: const BoxDecoration(
            color: Color(0xff1c1c22),
            borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
          ),
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('出镜人物',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            const Text('真人 + 数字人可以同时开（同框）；数字人可在画面上拖动、双指缩放，双击复位',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white54, fontSize: 11)),
            const SizedBox(height: 12),
            // 真人开关（可与数字人并存）
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: .06),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(children: [
                const Icon(Icons.person_outline,
                    color: Colors.white70, size: 20),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text('真人出镜（摄像头）',
                      style: TextStyle(color: Colors.white, fontSize: 13)),
                ),
                Switch(
                  value: _realOn,
                  onChanged: (v) {
                    setState(() => _realOn = v);
                    setSheet(() {});
                  },
                ),
              ]),
            ),
            const SizedBox(height: 12),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text('数字人',
                  style: TextStyle(color: Colors.white70, fontSize: 12)),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 132,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  _personCard('不用', Icons.block, null, _personIdx == 0, () {
                    _setPerson(0);
                    setSheet(() {});
                  }),
                  for (int i = 0; i < kDigitalAvatarImages.length; i++)
                    _personCard(kDigitalAvatarNames[i], null,
                        kDigitalAvatarImages[i], _personIdx == i + 1, () {
                      _setPerson(i + 1);
                      setSheet(() {});
                    }),
                ],
              ),
            ),
          ]),
        ),
      ),
    );
  }

  /// 人物卡片（数字人形象 / "不用"）
  Widget _personCard(String name, IconData? icon, String? image, bool selected,
      VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 92,
        margin: const EdgeInsets.only(right: 10),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: selected
              ? const Color(0xff7c5cff).withValues(alpha: .28)
              : Colors.white.withValues(alpha: .06),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: selected ? const Color(0xff9d7bff) : Colors.white24,
              width: selected ? 1.6 : 1),
        ),
        child: Column(children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: image == null
                  ? Container(
                      color: Colors.white10,
                      child: Icon(icon ?? Icons.person,
                          color: Colors.white70, size: 32),
                    )
                  : Image.asset(image,
                      fit: BoxFit.cover, width: double.infinity),
            ),
          ),
          const SizedBox(height: 6),
          Text(name,
              style: const TextStyle(color: Colors.white, fontSize: 11.5)),
        ]),
      ),
    );
  }

  /// 浮窗功能键（无背景，纯图标 + 文字标签，绿幕助手原版样式）
  /// 文字白色 + 黑色阴影，在亮背景（实景相机）和渐变背景上都清晰。
  /// [badge]：角标——'V'=超级会员专属（金色），'S'=运营商专属（紫色），null=免费。
  Widget _floating(IconData icon, String label, VoidCallback onTap,
      {String? badge}) {
    return GestureDetector(
      onTap: onTap,
      child: Column(children: [
        Stack(clipBehavior: Clip.none, children: [
          Icon(icon, color: Colors.white, size: 22),
          if (_showBadge(badge))
            Positioned(
              top: -6,
              right: -12,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: badge == 'V'
                        ? const [Color(0xffffd54a), Color(0xffffa726)]
                        : const [Color(0xffc77dff), Color(0xff9d4edd)],
                  ),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(badge!,
                    style: const TextStyle(
                        fontSize: 9,
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        height: 1.2)),
              ),
            ),
        ]),
        const SizedBox(height: 4),
        Text(label,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                shadows: [Shadow(color: Color(0xdd000000), blurRadius: 4)])),
      ]),
    );
  }

  /// 角标显示逻辑：功能所需等级已开通则不显示角标
  bool _showBadge(String? badge) {
    if (badge == null) return false;
    if (badge == 'V') return !UserLevel.isVip; // 未开通超级会员才显示 V
    if (badge == 'S') return !UserLevel.isSvip; // 未开通运营商才显示 S
    return false;
  }

  /// 左下角：绿色圆形 ▶ 开播按钮（绿幕助手原版样式）
  Widget _goButton() => GestureDetector(
        onTap: () {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('开播入口正在开发中：即将支持在这里一键推流开播'),
              duration: Duration(seconds: 2),
            ),
          );
        },
        child: Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xff3aff8a), Color(0xff16c07a)]),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                  color: const Color(0x6616c07a),
                  blurRadius: 14,
                  offset: const Offset(0, 3))
            ],
          ),
          child: const Center(
            child: Icon(Icons.play_arrow_rounded,
                color: Colors.white, size: 34),
          ),
        ),
      );
}