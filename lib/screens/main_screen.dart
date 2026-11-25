import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../models/card_style.dart';
import '../models/vocab_card.dart';
import '../services/overlay_service.dart';
import '../widgets/vocab_card_view.dart';

/// 主界面：
///  * 全屏透明；
///  * 在其他应用之上（置顶）；
///  * 除右上角“设置”按钮外，其他区域鼠标 / 触摸事件全部穿透给下层应用。
///
/// 实现方式（桌面端）：
///  * 系统级整窗“穿透”会连“设置”按钮一起穿透，导致按钮也不可点。
///    因此这里用光标轮询代替普通的事件监听：
///      - 定时查询全局光标位置；
///      - 当光标落在“设置”按钮热区内时，临时关闭穿透，让按钮可点击；
///      - 光标离开后立即恢复穿透。
///  * 这样既保证“除按钮外全部穿透”，又保证按钮可用。
///
/// 移动端无法做到系统级穿透（见 README），此处仅保持透明并正常显示按钮。
class MainScreen extends StatefulWidget {
  final List<VocabCard> cards;

  /// 词汇卡整体样式（有边框 / 无边框仅字体）。
  final CardStyle cardStyle;

  final VoidCallback onOpenSettings;

  const MainScreen({
    super.key,
    required this.cards,
    required this.onOpenSettings,
    this.cardStyle = CardStyle.bordered,
  });

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  /// 当前是否处于“设置按钮热区”内（用于驱动视觉高亮与穿透切换）。
  bool _inButtonHotZone = false;

  /// “设置”按钮的热区（逻辑像素，屏幕坐标）。
  Rect? _buttonHotZone;

  Timer? _cursorTimer;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // 默认整体穿透。
      OverlayService.instance.setClickThrough(true);
      // 桌面端靠全局光标轮询来临时关闭穿透，让“设置”按钮可点；
      // 移动端没有全局光标（轮询恒为 null），必须关闭穿透才能点到按钮 ——
      // 否则按钮永远点不动，也就进不了设置界面。
      _startCursorWatch();
    });
  }

  void _startCursorWatch() {
    _cursorTimer?.cancel();
    // 约 60ms 轮询一次：按钮悬停态表现自然，开销也很低。
    _cursorTimer = Timer.periodic(const Duration(milliseconds: 60), (_) {
      _pollCursor();
    });
  }

  Future<void> _pollCursor() async {
    if (_busy) return;

    final cursor = await OverlayService.instance.getGlobalCursorPos();
    if (!mounted) return;
    if (cursor == null) {
      // 不支持全局光标的平台（Android / iOS / macOS / Linux）：
      // 无法检测光标是否进入热区，只能让主界面可交互，否则“设置”按钮
      // 永远收不到点击。卡片区域本身仍是 IgnorePointer，不会拦截事件。
      if (_inButtonHotZone) return;
      _busy = true;
      try {
        setState(() => _inButtonHotZone = true);
        await OverlayService.instance.setClickThrough(false);
      } finally {
        _busy = false;
      }
      return;
    }

    final hotZone = _buttonHotZone;
    if (hotZone == null) return;

    // 原生返回的是物理像素（屏幕坐标）；而热区 _buttonHotZone 是 Flutter
    // 逻辑坐标。这里用 devicePixelRatio 把光标换算到逻辑坐标再比较，
    // 保证在高 DPI 屏幕上按钮热区位置正确。
    final dpr = View.of(context).devicePixelRatio;
    final logicalCursor = dpr > 0 ? cursor / dpr : cursor;

    final inside = hotZone.inflate(6).contains(logicalCursor);

    if (inside == _inButtonHotZone) return;
    _busy = true;
    try {
      setState(() => _inButtonHotZone = inside);
      // 在按钮热区内时关闭穿透，其余时间保持穿透。
      await OverlayService.instance.setClickThrough(!inside);
    } finally {
      _busy = false;
    }
  }

  @override
  void dispose() {
    _cursorTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Stack(
        children: [
          // 词汇卡区域：完全穿透，不拦截任何键鼠 / 触摸事件。
          Positioned.fill(
            child: IgnorePointer(
              child: Stack(
                children: [
                  for (final card in widget.cards)
                    Positioned(
                      left: card.x,
                      top: card.y,
                      child: IgnorePointer(
                        child: VocabCardView(
                          card: card,
                          style: widget.cardStyle,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),

          // 右上角“设置”按钮：唯一可交互区域。
          Positioned(
            top: 16,
            right: 16,
            child: _HotZoneReporter(
              onBounds: (rect) => _buttonHotZone = rect,
              child: _SettingsButton(
                active: _inButtonHotZone,
                onTap: () async {
                  _cursorTimer?.cancel();
                  await OverlayService.instance.setClickThrough(false);
                  widget.onOpenSettings();
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 把子组件的全局矩形（逻辑像素，屏幕坐标）上报给父级。
class _HotZoneReporter extends StatefulWidget {
  final ValueChanged<Rect> onBounds;
  final Widget child;

  const _HotZoneReporter({required this.onBounds, required this.child});

  @override
  State<_HotZoneReporter> createState() => _HotZoneReporterState();
}

class _HotZoneReporterState extends State<_HotZoneReporter> {
  final GlobalKey _key = GlobalKey();

  void _report() {
    final box = _key.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final topLeft = box.localToGlobal(Offset.zero);
    widget.onBounds(topLeft & box.size);
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) => _report());
    return KeyedSubtree(key: _key, child: widget.child);
  }
}

class _SettingsButton extends StatelessWidget {
  final bool active;
  final VoidCallback onTap;

  const _SettingsButton({required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: active ? 0.75 : 0.55),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.settings, size: 16, color: Colors.white),
              SizedBox(width: 6),
              Text('设置', style: TextStyle(color: Colors.white, fontSize: 13)),
            ],
          ),
        ),
      ),
    );
  }
}
