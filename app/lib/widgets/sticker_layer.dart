import 'package:flutter/material.dart';

/// 画面上已放置的一个挂件
class StickerItem {
  final int id;
  final String asset;
  StickerItem(this.id, this.asset);
}

/// 挂件层：每个挂件可**单指拖动、双指缩放、双击复位**。
///
/// ★画面上**不显示删除按钮**——老板反馈 ✕ 经常点不中（手势冲突，体验差），
/// 删除统一放到「挂件」弹窗里的"已放置"列表里做。
class StickerLayer extends StatelessWidget {
  final List<StickerItem> items;

  const StickerLayer({super.key, required this.items});

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        for (final it in items)
          DraggableSticker(key: ValueKey(it.id), asset: it.asset),
      ],
    );
  }
}

class DraggableSticker extends StatefulWidget {
  final String asset;

  const DraggableSticker({super.key, required this.asset});

  @override
  State<DraggableSticker> createState() => _DraggableStickerState();
}

class _DraggableStickerState extends State<DraggableSticker> {
  double _scale = 1.0;
  Offset _offset = Offset.zero;
  double _startScale = 1.0;
  Offset _startOffset = Offset.zero;
  Offset _startFocal = Offset.zero;
  static const double _base = 130;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.center,
      child: Transform.translate(
        offset: _offset,
        child: Transform.scale(
          scale: _scale,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onScaleStart: (d) {
              _startScale = _scale;
              _startOffset = _offset;
              _startFocal = d.focalPoint;
            },
            onScaleUpdate: (d) {
              setState(() {
                _scale = (_startScale * d.scale).clamp(0.3, 3.0);
                _offset = _startOffset + (d.focalPoint - _startFocal);
              });
            },
            // 空 onTap：让贴纸"吃掉"点击，避免触发整页的控件显隐
            onTap: () {},
            onDoubleTap: () => setState(() {
              _scale = 1.0;
              _offset = Offset.zero;
            }),
            child: Image.asset(widget.asset, width: _base, fit: BoxFit.contain),
          ),
        ),
      ),
    );
  }
}
