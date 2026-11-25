import 'dart:convert';

import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:material_ui/material_ui.dart';

import 'models/card_style.dart';
import 'models/vocab_card.dart';
import 'widgets/vocab_card_view.dart';

/// 系统悬浮窗（Android `TYPE_APPLICATION_OVERLAY`）里的独立 Flutter 入口。
///
/// 这个入口运行在**第二个 Flutter 引擎**中，渲染到系统悬浮窗上，因此卡片可以
/// 显示在其他应用之上。它通过 [FlutterOverlayWindow.overlayListener] 接收
/// 主应用推送的卡片数据。
///
/// 悬浮窗的“穿透”由原生 `FLAG_NOT_TOUCHABLE` 控制（见 MobileOverlayPlatform），
/// 因此：
///  * 浏览模式（adjust=false）：整窗穿透，卡片不拦截下层应用；
///  * 调整模式（adjust=true）：可触摸拖动卡片（此时不穿透）。
///
/// 这个入口必须带 `@pragma("vm:entry-point")`，否则 release 构建会被 tree-shake。
///
/// 消息格式：`{"cards": [...], "adjust": bool, "visible": bool}`。
///  * 带 `cards`：整体替换卡片（并同步 adjust / visible）；
///  * 只带 `visible`：仅切换可见性，保留现有卡片。
/// 启动悬浮窗 UI（运行在**第二个 Flutter 引擎**里）。
///
/// 注意：真正的引擎入口 `overlayMain` **定义在 main.dart 中**，它委托到这里。
/// 原因见 main.dart 顶部注释：原生 `DartEntrypoint(appBundlePath, "overlayMain")`
/// 只在 main 库的根命名空间里按名字查找，所以 `overlayMain` 必须是 main.dart
/// 的顶层函数，否则报 `Could not resolve main entrypoint function`。
@pragma("vm:entry-point")
void runOverlayApp() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const _OverlayApp());
}

class _OverlayApp extends StatefulWidget {
  const _OverlayApp();

  @override
  State<_OverlayApp> createState() => _OverlayAppState();
}

class _OverlayAppState extends State<_OverlayApp> {
  List<VocabCard> _cards = <VocabCard>[];
  bool _adjustMode = false;

  /// 词汇卡整体样式（由主应用随消息推送）。
  CardStyle _cardStyle = CardStyle.bordered;

  /// 主应用正在显示设置 / 调整界面时为 false：此时由主应用自己显示卡片，
  /// 悬浮窗内容先隐藏，避免重复显示、也避免数据同步间隙里的错位。
  bool _visible = true;

  /// 屏幕尺寸（逻辑像素）。
  ///
  /// 悬浮窗里的 `MediaQuery` 不一定可靠（窗口由插件以全屏方式 addView，
  /// 且带 FLAG_LAYOUT_NO_LIMITS），因此显式向插件查询真实屏幕尺寸（dp），
  /// 查询失败时再退回 MediaQuery。
  Size? _screenSize;

  /// 拖动时卡片左上角相对指针的偏移。
  final Map<int, Offset> _grabOffsets = {};

  @override
  void initState() {
    super.initState();
    FlutterOverlayWindow.overlayListener.listen(_onMessage);
    _loadScreenSize();
    // 握手：引擎一启动就通知主应用“我准备好了”，让主应用立刻回推卡片。
    // 这样即使 showOverlay 后立刻推送的数据因时序丢失，也能在引擎就绪后补上。
    _announceReady();
  }

  Future<void> _announceReady() async {
    // 稍等一帧，确保监听与首帧渲染就绪后再报告。
    await Future<void>.delayed(const Duration(milliseconds: 80));
    if (!mounted) return;
    try {
      await FlutterOverlayWindow.shareData(jsonEncode({'ready': true}));
      debugPrint('[overlay] ready sent');
    } catch (e) {
      debugPrint('[overlay] ready failed: $e');
    }
  }

  Future<void> _loadScreenSize() async {
    try {
      final pos = await FlutterOverlayWindow.getScreenSize();
      final size = Size(pos.x, pos.y);
      if (size.width > 0 && size.height > 0 && mounted) {
        setState(() => _screenSize = size);
      }
    } catch (_) {
      // 忽略：退回 MediaQuery。
    }
  }

  void _onMessage(dynamic message) {
    if (!mounted) return;
    if (message is! String) return;
    debugPrint('[overlay] recv: $message');
    try {
      final decoded = jsonDecode(message);
      if (decoded is! Map) return;
      final map = Map<String, dynamic>.from(decoded);

      // 支持两种消息：
      //  * {"cards": [...], "adjust": bool, "visible": bool}：完整状态；
      //  * {"visible": bool}：只切换可见性（不重置卡片）。
      final rawCards = map['cards'];
      final cards = <VocabCard>[];
      if (rawCards is List) {
        for (final e in rawCards) {
          if (e is Map) {
            cards.add(VocabCard.fromJson(Map<String, dynamic>.from(e)));
          }
        }
      }

      setState(() {
        if (rawCards is List) {
          _cards = cards;
          _adjustMode = map['adjust'] == true;
          _grabOffsets.clear();
        }
        // 样式可随任意消息携带；缺失时保持当前样式。
        final rawStyle = map['cardStyle'];
        if (rawStyle != null) {
          _cardStyle = CardStyle.fromId(rawStyle);
        }
        final visible = map['visible'];
        if (visible is bool) _visible = visible;
      });
      // 把卡片位置 / 拖动结果回传给主应用，用于持久化。
      if (map['requestSave'] == true) {
        _sendCards();
      }
    } catch (_) {
      // 忽略非法消息。
    }
  }

  Future<void> _sendCards() async {
    final payload = jsonEncode({
      'cards': _cards.map((c) => c.toJson()).toList(),
    });
    await FlutterOverlayWindow.shareData(payload);
  }

  @override
  Widget build(BuildContext context) {
    // 悬浮窗坐标使用 dp（逻辑像素），与卡片模型一致。
    final screen = _screenSize ?? MediaQuery.of(context).size;

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      // 悬浮窗本体必须透明：不要额外铺背景色。
      color: Colors.transparent,
      home: Material(
        color: Colors.transparent,
        child: Stack(
          children: [
            if (_visible)
              for (var i = 0; i < _cards.length; i++)
                _adjustMode
                    ? _DraggableCard(
                        key: ValueKey('overlay_card_$i'),
                        card: _cards[i],
                        style: _cardStyle,
                        screen: screen,
                        onDragStart: (pointer) {
                          _grabOffsets[i] =
                              Offset(_cards[i].x, _cards[i].y) - pointer;
                        },
                        onDragUpdate: (pointer) {
                          if (!_grabOffsets.containsKey(i)) return;
                          final target = pointer + _grabOffsets[i]!;
                          setState(() {
                            _cards[i] = _cards[i].movedTo(
                              _clamp(target, _cards[i], screen),
                            );
                          });
                          _grabOffsets[i] =
                              Offset(_cards[i].x, _cards[i].y) - pointer;
                        },
                        onDragEnd: () {
                          _grabOffsets.remove(i);
                          // 拖动结束后把最新位置回传主应用保存。
                          _sendCards();
                        },
                      )
                    : Positioned(
                        left: _cards[i].x,
                        top: _cards[i].y,
                        child: VocabCardView(
                          card: _cards[i],
                          style: _cardStyle,
                        ),
                      ),
          ],
        ),
      ),
    );
  }

  Offset _clamp(Offset pos, VocabCard card, Size screen) {
    final maxX = (screen.width - card.width)
        .clamp(0.0, double.infinity)
        .toDouble();
    final maxY = (screen.height - card.height)
        .clamp(0.0, double.infinity)
        .toDouble();
    return Offset(
      pos.dx.clamp(0.0, maxX).toDouble(),
      pos.dy.clamp(0.0, maxY).toDouble(),
    );
  }
}

/// 调整模式下可拖动的卡片。
class _DraggableCard extends StatefulWidget {
  final VocabCard card;
  final CardStyle style;
  final Size screen;
  final ValueChanged<Offset> onDragStart;
  final ValueChanged<Offset> onDragUpdate;
  final VoidCallback onDragEnd;

  const _DraggableCard({
    super.key,
    required this.card,
    this.style = CardStyle.bordered,
    required this.screen,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
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
        dragStartBehavior: DragStartBehavior.down,
        onPanStart: (d) => widget.onDragStart(d.globalPosition),
        onPanUpdate: (d) => widget.onDragUpdate(d.globalPosition),
        onPanEnd: (_) => widget.onDragEnd(),
        onPanCancel: widget.onDragEnd,
        child: VocabCardView(
          card: widget.card,
          style: widget.style,
          highlight: true,
        ),
      ),
    );
  }
}
