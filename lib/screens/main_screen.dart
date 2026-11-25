import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:material_ui/material_ui.dart';

import '../models/card_style.dart';
import '../models/vocab_card.dart';
import '../services/overlay_mobile.dart' show NativeOverlay;
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
/// 移动端（Android / iOS）没有“全局光标”这个概念：主应用窗口默认保持穿透，
/// 卡片永远浮在其他应用之上，且不会拦截下层应用的触摸。
///
/// 卡片由谁绘制：
///  * 移动端：系统悬浮窗存在时由**悬浮窗引擎**绘制（本界面不画，避免出现
///    “两份卡片”）；悬浮窗不存在时才由本界面兜底绘制；
///  * 桌面端：没有系统悬浮窗，始终由本界面绘制。
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

  /// 移动端：低频核对原生悬浮窗状态的计时器。
  Timer? _overlayStateTimer;

  bool _busy = false;

  /// 系统悬浮窗是否正在显示。
  ///
  /// ★ 移动端主界面**不再**自己绘制词汇卡：只要系统悬浮窗还在显示，卡片就由
  /// 悬浮窗引擎（第二个 Flutter 引擎，渲染在 `TYPE_APPLICATION_OVERLAY` 上）
  /// 负责画。否则会出现“两份卡片”重叠显示 —— 悬浮窗里一份、主界面里一份，
  /// 而且两份的位置 / 拖动结果还会不一致。
  ///
  /// 悬浮窗不存在时（首次启动、还没来得及切后台、或用户主动关闭）才由本界面
  /// 兜底显示主界面自己的卡片，保证“打开软件就能看到卡片”。
  bool _overlayActive = false;

  /// 是否为移动平台（Android / iOS）：这类平台没有全局光标。
  static bool get _isMobile => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshOverlayActive();
      // 默认整体穿透。
      OverlayService.instance.setClickThrough(true);
      // 桌面端靠全局光标轮询来临时关闭穿透，让“设置”按钮可点；
      // 移动端没有全局光标（轮询恒为 null），必须关闭穿透才能点到按钮 ——
      // 否则按钮永远点不动，也就进不了设置界面。
      //
      // ★ 但移动端**不能**在一进来就把主应用窗口设成“可触摸”：那样用户切到
      // 后台后会有一个透明的全屏 Activity 覆盖在其他应用之上拦截触摸
      // （表现为“浮上去的卡片点不动 / 下层应用没反应”）。移动端这里只在
      // 用户真正点“设置”按钮时才临时关闭穿透（见 [_SettingsButton.onTap]）。
      if (!_isMobile) _startCursorWatch();
    });
    // 移动端：进入主界面时（从设置 / 调整界面返回、从后台切回、或悬浮窗刚
    // 被创建 / 关闭）重新判断是否需要本界面兜底显示卡片。
    if (_isMobile) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _refreshOverlayActive();
      });
      // 悬浮窗的创建 / 销毁可能发生在稍后（切后台 → 创建悬浮窗 → 回前台），
      // 低频轮询一次原生状态，保证“该隐藏时隐藏、该兜底时兜底”。
      _overlayStateTimer = Timer.periodic(
        const Duration(milliseconds: 700),
        (_) => _refreshOverlayActive(),
      );
    }
  }

  /// 查询原生悬浮窗是否在显示，用于决定本界面是否绘制卡片。
  ///
  /// 只在结果变化时 `setState`，避免无谓重建（也避免打断按钮热区状态）。
  Future<void> _refreshOverlayActive() async {
    if (!mounted) return;
    final active = await NativeOverlay.isActive();
    if (!mounted || active == _overlayActive) return;
    setState(() => _overlayActive = active);
  }

  @override
  void didUpdateWidget(covariant MainScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 卡片 / 样式变了（例如从设置界面点“应用”返回），重新核对一次。
    if (_isMobile &&
        (oldWidget.cards != widget.cards ||
            oldWidget.cardStyle != widget.cardStyle)) {
      _refreshOverlayActive();
    }
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
      // 不支持全局光标的平台（macOS / Linux 等）：无法检测光标是否进入热区。
      // 这里**不动**穿透状态，避免在移动端把主应用窗口切成“可触摸”
      // （那样切到后台后会有一个透明 Activity 拦截其他应用的触摸）。
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
    _overlayStateTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 移动端：系统悬浮窗正在显示时，卡片由悬浮窗引擎负责绘制，
    // 本界面不再重复绘制（否则会出现“两份卡片”）。
    // 桌面端没有系统悬浮窗，始终由本界面绘制。
    final showLocalCards = !_isMobile || !_overlayActive;

    return Material(
      color: Colors.transparent,
      child: Stack(
        children: [
          // 词汇卡区域：完全穿透，不拦截任何键鼠 / 触摸事件。
          Positioned.fill(
            child: IgnorePointer(
              child: Stack(
                children: [
                  if (showLocalCards)
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
                  // 进入设置界面才需要主应用窗口接收触摸（否则输入框点不了）。
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
