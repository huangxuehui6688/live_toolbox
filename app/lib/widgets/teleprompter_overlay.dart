import 'dart:developer' as dev;
import 'dart:isolate';
import 'dart:ui';

import 'package:flutter/material.dart';

import '../services/overlay_service.dart';

class TeleprompterOverlayApp extends StatelessWidget {
  const TeleprompterOverlayApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: TeleprompterOverlay(),
    );
  }
}

/// 悬浮窗里的提词 UI：窄条、大字号、当前行高亮、可拖动、可调透明度。
class TeleprompterOverlay extends StatefulWidget {
  const TeleprompterOverlay({super.key});

  @override
  State<TeleprompterOverlay> createState() => _TeleprompterOverlayState();
}

class _TeleprompterOverlayState extends State<TeleprompterOverlay> {
  final ReceivePort _receivePort = ReceivePort();
  SendPort? _homePort;

  List<String> _lines = const [];
  int _current = -1; // 0-based 当前行，-1 = 未开始
  double _opacity = 0.55; // 背景透明度 0.15~0.95

  @override
  void initState() {
    super.initState();
    dev.log('TeleprompterOverlay initState 开始', name: 'OverlayService');
    IsolateNameServer.registerPortWithName(
      _receivePort.sendPort,
      kOverlayPort,
    );
    _receivePort.listen(_onMessage);
    dev.log('TeleprompterOverlay initState 完成，端口已注册', name: 'OverlayService');
  }

  @override
  void dispose() {
    IsolateNameServer.removePortNameMapping(kOverlayPort);
    _receivePort.close();
    super.dispose();
  }

  void _onMessage(dynamic message) {
    if (message is! Map) return;
    final Object? type = message['type'];
    if (type == 'lines') {
      final List<String> lines = _asStringList(message['lines']);
      final int index = (message['index'] as num?)?.toInt() ?? -1;
      setState(() {
        _lines = lines;
        _current = index;
      });
    } else if (type == 'index') {
      final int index = (message['index'] as num?)?.toInt() ?? -1;
      setState(() => _current = index);
    }
  }

  static List<String> _asStringList(Object? raw) {
    if (raw is! List) return const [];
    return raw.map((e) => e.toString()).toList(growable: false);
  }

  void _requestClose() {
    _homePort ??= IsolateNameServer.lookupPortByName(kOverlayHomePort);
    _homePort?.send({'type': 'close'});
  }

  @override
  Widget build(BuildContext context) {
    final bool hasContent = _lines.isNotEmpty;
    final int cur = hasContent ? _current.clamp(0, _lines.length - 1) : -1;
    final bool started = _current >= 0 && hasContent;
    final int prev = cur > 0 ? cur - 1 : -1;
    final int next = cur >= 0 && cur < _lines.length - 1 ? cur + 1 : -1;

    return Material(
      color: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: _opacity),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildHeader(),
            const Divider(height: 1, color: Colors.white12),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!hasContent)
                    const Text(
                      '暂无台词',
                      style: TextStyle(fontSize: 22, color: Colors.white70),
                    ),
                  if (prev >= 0) _lineText(_lines[prev], false, 20, 1),
                  if (hasContent) _lineText(_lines[cur], started, 30, 2),
                  if (next >= 0) _lineText(_lines[next], false, 20, 1),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _lineText(String text, bool highlight, double fontSize, int maxLines) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 3),
      padding: const EdgeInsets.only(left: 8),
      decoration: highlight
          ? BoxDecoration(
              border: Border(
                left: BorderSide(color: Colors.amberAccent, width: 4),
              ),
            )
          : null,
      child: Text(
        text,
        maxLines: maxLines,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: fontSize,
          height: 1.25,
          fontWeight: highlight ? FontWeight.bold : FontWeight.normal,
          color: highlight ? Colors.white : Colors.white60,
          shadows: const [
            Shadow(color: Colors.black54, blurRadius: 4, offset: Offset(0, 1)),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      child: Row(
        children: [
          const Icon(Icons.drag_indicator, size: 18, color: Colors.white38),
          const SizedBox(width: 6),
          const Text(
            '提词器',
            style: TextStyle(fontSize: 12, color: Colors.white54),
          ),
          const Spacer(),
          _iconButton(
            Icons.remove,
            onTap: () =>
                setState(() => _opacity = _stepOpacity(-0.1)),
          ),
          Text(
            '${(_opacity * 100).round()}%',
            style: const TextStyle(fontSize: 11, color: Colors.white54),
          ),
          _iconButton(
            Icons.add,
            onTap: () =>
                setState(() => _opacity = _stepOpacity(0.1)),
          ),
          _iconButton(Icons.close, onTap: _requestClose),
        ],
      ),
    );
  }

  double _stepOpacity(double delta) {
    return (_opacity + delta).clamp(0.15, 0.95).toDouble();
  }

  Widget _iconButton(IconData icon, {required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Icon(icon, size: 18, color: Colors.white70),
      ),
    );
  }
}
