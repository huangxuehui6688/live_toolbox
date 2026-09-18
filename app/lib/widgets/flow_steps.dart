import 'package:flutter/material.dart';

const _kAccent = Color(0xff7c5cff);

/// 数字人 2D 流程的步骤指示条
///
/// 选形象 → 写话术 → 生成视频 → 开播
/// 放在各步骤页顶部，让用户随时知道"我在哪一步、下一步是什么"。
class FlowSteps extends StatelessWidget {
  const FlowSteps({super.key, required this.current});

  /// 0-based：0=选形象 1=写话术 2=生成视频 3=开播
  final int current;

  static const _labels = ['选形象', '写话术', '生成', '开播'];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xffeeeef4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < _labels.length; i++) ...[
            Expanded(child: _step(i)),
            if (i != _labels.length - 1)
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Icon(
                  Icons.chevron_right,
                  size: 14,
                  color: i < current ? _kAccent : const Color(0xffd5d5e0),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _step(int i) {
    final done = i < current;
    final now = i == current;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 20,
          height: 20,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: now
                ? _kAccent
                : (done ? const Color(0xffe9f9ef) : const Color(0xfff2f2f7)),
            shape: BoxShape.circle,
          ),
          child: done
              ? const Icon(Icons.check, size: 12, color: Color(0xff20b26b))
              : Text(
                  '${i + 1}',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: now ? Colors.white : const Color(0xff8a8a99),
                  ),
                ),
        ),
        const SizedBox(height: 4),
        Text(
          _labels[i],
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 10.5,
            fontWeight: now ? FontWeight.w600 : FontWeight.w400,
            color: now ? _kAccent : const Color(0xff8a8a99),
          ),
        ),
      ],
    );
  }
}
