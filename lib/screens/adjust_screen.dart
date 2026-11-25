import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:material_ui/material_ui.dart';

import '../models/card_style.dart';
import '../models/vocab_card.dart';
import '../services/overlay_service.dart';
import '../widgets/vocab_card_view.dart';

/// 调整界面：
///  * 与主界面一样大（全屏）；
///  * 背景半透明且稍微变暗，卡片可拖动（鼠标 / 触摸）；
///  * 右上角“上一步”会把所有卡片恢复到本次调整之前的位置；
///  * 右上角“完成”会记录当前位置并返回设置界面。
///
/// 返回：
///  * 返回调整后的卡片列表：表示“完成”，携带调整后的卡片；
///  * 返回 null：表示“上一步”，放弃本次调整。
class AdjustScreen extends StatefulWidget {
  final List<VocabCard> initialCards;

  /// 当前词汇卡整体样式（仅用于显示，不影响位置）。
  final CardStyle style;

  const AdjustScreen({
    super.key,
    required this.initialCards,
    this.style = CardStyle.bordered,
  });

  @override
  State<AdjustScreen> createState() => _AdjustScreenState();
}

class _AdjustScreenState extends State<AdjustScreen> {
  /// 当前显示的卡片（会被拖动）。
  late List<VocabCard> _cards;

  /// 进入调整界面时的快照，用于“上一步”回退。
  late final List<VocabCard> _original;

  /// 拖动卡片时，卡片左上角相对光标的偏移（按下时记录，松开时清除）。
  final Map<int, Offset> _grabOffsets = {};

  @override
  void initState() {
    super.initState();
    _cards = List<VocabCard>.from(widget.initialCards);
    _original = List<VocabCard>.from(widget.initialCards);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // 调整界面需要可拖动：关闭穿透、置顶（避免遮挡操作）。
      OverlayService.instance.setClickThrough(false);
      OverlayService.instance.setAlwaysOnTop(false);
      // 确保窗口铺满整个屏幕；否则可拖动范围会被限制在窗口内，
      // 看起来就像“词汇卡无法放到屏幕上的任意位置”。
      // 铺满后窗口尺寸可能变化，需要触发一次重建让可拖动范围同步刷新。
      OverlayService.instance.ensureCoverScreen().then((_) {
        if (mounted) setState(() {});
      });
    });
  }

  /// 整个屏幕的尺寸（词汇卡坐标系，逻辑像素）。
  ///
  /// 窗口已铺满屏幕时，`MediaQuery.size` 即等于整个屏幕的逻辑尺寸；
  /// 卡片坐标与拖动坐标也统一使用逻辑像素，保证可以放到屏幕任意位置。
  Size get _screenSize => MediaQuery.of(context).size;

  /// 把卡片位置限制在屏幕范围内（允许贴边，但不允许拖出屏幕）。
  Offset _clampToScreen(Offset pos, VocabCard card) {
    final size = _screenSize;
    final maxX = (size.width - card.width)
        .clamp(0.0, double.infinity)
        .toDouble();
    final maxY = (size.height - card.height)
        .clamp(0.0, double.infinity)
        .toDouble();
    return Offset(
      pos.dx.clamp(0.0, maxX).toDouble(),
      pos.dy.clamp(0.0, maxY).toDouble(),
    );
  }

  void _onStepBack() {
    // 上一步：所有卡片回到本次调整之前的位置。
    setState(() {
      _grabOffsets.clear();
      for (var i = 0; i < _cards.length && i < _original.length; i++) {
        _cards[i] = _cards[i].copyWith(
          x: _original[i].x,
          y: _original[i].y,
          width: _original[i].width,
          height: _original[i].height,
        );
      }
    });
  }

  void _onFinish() {
    // 完成：记录位置并返回设置界面。
    Navigator.of(context).pop(_cards);
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Stack(
        children: [
          // 半透明、稍微变暗的背景层。
          Positioned.fill(
            child: Container(color: Colors.black.withValues(alpha: 0.35)),
          ),

          // 可拖动的词汇卡。
          for (var i = 0; i < _cards.length; i++)
            _DraggableCard(
              key: ValueKey('adjust_card_$i'),
              card: _cards[i],
              style: widget.style,
              onDragStart: (pointer) {
                _grabOffsets[i] = Offset(_cards[i].x, _cards[i].y) - pointer;
              },
              onDragUpdate: (pointer) {
                if (_grabOffsets.containsKey(i)) {
                  final target = pointer + _grabOffsets[i]!;
                  final nearest = _clampToScreen(target, _cards[i]);
                  setState(() {
                    _cards[i] = _cards[i].movedTo(nearest);
                  });
                  // 卡片被夹在屏幕边缘时会停在边界上。此时重新以“卡片实际
                  // 位置”为基准更新抓取偏移，保证反向拖动时立即跟手，
                  // 而不会先“追回”被夹住的位移，从而能贴边放到任意位置。
                  _grabOffsets[i] = nearest - pointer;
                } else {
                  // 防御：拖动开始事件丢失时，退化为按位移移动。
                  setState(() {
                    final target = Offset(_cards[i].x, _cards[i].y) + pointer;
                    _cards[i] = _cards[i].movedTo(
                      _clampToScreen(target, _cards[i]),
                    );
                  });
                }
              },
              onDragEnd: () => _grabOffsets.remove(i),
            ),

          // 右上角按钮。
          Positioned(
            top: 16,
            right: 16,
            child: Row(
              children: [
                _PillButton(
                  icon: Icons.undo,
                  label: '上一步',
                  onPressed: _onStepBack,
                ),
                const SizedBox(width: 10),
                _PillButton(
                  icon: Icons.check,
                  label: '完成',
                  filled: true,
                  onPressed: _onFinish,
                ),
              ],
            ),
          ),

          // 提示文字。
          Positioned(
            left: 0,
            right: 0,
            bottom: 24,
            child: IgnorePointer(
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    '拖动卡片调整位置',
                    style: TextStyle(color: Colors.white, fontSize: 13),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 可拖动的卡片：使用拖拽手势同时支持鼠标与触摸。
///
/// 用“光标位置 + 抓取偏移”计算新位置，不依赖累加位移，
/// 因此卡片可以精确地放到屏幕上的任意位置。
class _DraggableCard extends StatefulWidget {
  final VocabCard card;
  final CardStyle style;
  final ValueChanged<Offset> onDragStart;
  final ValueChanged<Offset> onDragUpdate;
  final VoidCallback? onDragEnd;

  const _DraggableCard({
    super.key,
    required this.card,
    this.style = CardStyle.bordered,
    required this.onDragStart,
    required this.onDragUpdate,
    this.onDragEnd,
  });

  @override
  State<_DraggableCard> createState() => _DraggableCardState();
}

class _DraggableCardState extends State<_DraggableCard> {
  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: widget.card.x,
      top: widget.card.y,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        // 按下即开始拖动（鼠标 / 触摸都支持）。
        dragStartBehavior: DragStartBehavior.down,
        // 直接用指针的全局坐标驱动拖动，避免“卡片被限制在屏幕内后、
        // 局部坐标与全局坐标脱节”导致的拖动不跟手 / 放不到边缘。
        onPanStart: (details) {
          widget.onDragStart(details.globalPosition);
        },
        onPanUpdate: (details) {
          widget.onDragUpdate(details.globalPosition);
        },
        onPanEnd: (_) => widget.onDragEnd?.call(),
        onPanCancel: () => widget.onDragEnd?.call(),
        child: MouseRegion(
          cursor: SystemMouseCursors.grab,
          child: VocabCardView(
            card: widget.card,
            style: widget.style,
            highlight: true,
          ),
        ),
      ),
    );
  }
}

class _PillButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final bool filled;

  const _PillButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.filled = false,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: filled
          ? Theme.of(context).colorScheme.primary
          : Colors.black.withValues(alpha: 0.55),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: Colors.white),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(color: Colors.white, fontSize: 13),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
