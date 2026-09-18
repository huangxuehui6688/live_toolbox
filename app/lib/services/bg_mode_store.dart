import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 「幕布 / 识别方式」档位 + 本机 AI 抠像可用性的本地持久化。
///
/// 存两个值：
///   bgIdx         —— 上次用的档位（0=实景 1=绿布 2=红布 3=蓝布 4=AI）
///   aiUnavailable —— 本机 AI 抠像是否已判定不可用（端侧分割熔断过）
///
/// ★为什么必须落盘（默认档位不能写死 AI）：
///   1) 容器里 ML Kit 起不来 → 每次进直播间第一帧都要熔断一次、弹一次
///      "AI 抠像在这台设备上用不了"，用户每次都被打扰一次；
///   2) AI 真能用的机型，上次选了 AI，下次进来应该还是 AI；
///   3) 降级过一次后就不再自动选 AI，直到用户自己主动点「AI」重试。
///   → 无记录时默认 `0`（实景）：保底、零处理、不发烫。
///
/// 持久化文件：getApplicationDocumentsDirectory()/bg_mode.json
/// 与 ScriptStore 同一套 `path_provider + dart:io` 套路（不引入新依赖）。
class BgModeStore {
  BgModeStore._();
  static final BgModeStore instance = BgModeStore._();

  static const String _fileName = 'bg_mode.json';

  int _bgIdx = 0; // 无记录时默认实景
  bool _aiUnavailable = false;
  Future<void>? _loading;

  int get bgIdx => _bgIdx;
  bool get aiUnavailable => _aiUnavailable;

  /// 读盘（幂等；并发调用共享同一个 Future；失败按"无记录"处理，不影响启动）
  Future<void> load() => _loading ??= _doLoad();

  Future<void> _doLoad() async {
    try {
      final file = await _file();
      if (!await file.exists()) return;
      final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      final idx = json['bgIdx'];
      if (idx is int && idx >= 0 && idx <= 4) _bgIdx = idx;
      _aiUnavailable = json['aiUnavailable'] == true;
    } catch (e) {
      // 文件损坏/无权限：回退默认值，不阻塞进入直播间
      debugPrint('[BG] 档位记录读取失败: $e');
    }
  }

  /// 记下用户选的档位。
  /// ★传 4（AI）表示用户**主动**要用 AI → 同时清掉"不可用"标记，让它再试一轮
  ///   （真机可用的人不该被一次失败永久禁掉）。
  Future<void> saveBgIdx(int idx) async {
    await load();
    _bgIdx = idx;
    if (idx == 4) _aiUnavailable = false;
    await _persist();
  }

  /// AI 抠像熔断：标记本机不可用，并把档位落回实景，一次落盘。
  Future<void> markAiUnavailable() async {
    await load();
    _aiUnavailable = true;
    if (_bgIdx == 4) _bgIdx = 0;
    await _persist();
  }

  Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File(p.join(dir.path, _fileName));
  }

  Future<void> _persist() async {
    try {
      final file = await _file();
      await file.writeAsString(jsonEncode({
        'bgIdx': _bgIdx,
        'aiUnavailable': _aiUnavailable,
      }));
    } catch (e) {
      debugPrint('[BG] 档位记录写入失败: $e');
    }
  }
}
