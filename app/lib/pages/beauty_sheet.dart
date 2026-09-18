import 'package:flutter/material.dart';

import '../services/beauty_settings.dart';

/// 美颜面板（底部弹出）：磨皮 / 美白 / 瘦脸。
///
/// 改动即时生效（BeautySettings 是 ValueNotifier，相机渲染层直接监听重绘），
/// 不需要「保存」按钮，关闭即完成。
class BeautySheet extends StatelessWidget {
  const BeautySheet({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
      decoration: const BoxDecoration(
        color: Color(0xff1a1b2e),
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Text('美颜',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w800)),
            const Spacer(),
            GestureDetector(
              onTap: BeautySettings.reset,
              child: const Text('重置',
                  style: TextStyle(color: Color(0xff9aa0b0), fontSize: 13)),
            ),
            const SizedBox(width: 16),
            GestureDetector(
              onTap: () => Navigator.pop(context),
              child: const Icon(Icons.close, color: Colors.white70, size: 20),
            ),
          ]),
          const SizedBox(height: 10),
          _slider('磨皮', BeautySettings.smooth),
          _slider('美白', BeautySettings.whiten),
          _sliderTodo('瘦脸', BeautySettings.slimFace),
        ],
      ),
    );
  }

  Widget _slider(String label, ValueNotifier<double> v) =>
      ValueListenableBuilder<double>(
        valueListenable: v,
        builder: (_, val, _) => Row(children: [
          SizedBox(
              width: 44,
              child: Text(label,
                  style: const TextStyle(color: Colors.white70, fontSize: 13))),
          Expanded(
            child: Slider(
              value: val,
              onChanged: (x) => v.value = x,
              activeColor: const Color(0xff7c5cff),
              inactiveColor: const Color(0xff3a3b52),
            ),
          ),
          SizedBox(
              width: 40,
              child: Text('${(val * 100).round()}%',
                  textAlign: TextAlign.right,
                  style: const TextStyle(color: Colors.white54, fontSize: 12))),
        ]),
      );

  Widget _sliderTodo(String label, ValueNotifier<double> v) => Row(children: [
        SizedBox(
            width: 44,
            child: Text(label,
                style: const TextStyle(color: Colors.white24, fontSize: 13))),
        const Expanded(child: Slider(value: 0, onChanged: null)),
        const SizedBox(
            width: 40,
            child: Text('开发中',
                textAlign: TextAlign.right,
                style: TextStyle(color: Colors.white24, fontSize: 11))),
      ]);
}
