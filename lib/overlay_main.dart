import 'dart:async';
import 'dart:convert';

import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:material_ui/material_ui.dart';

import 'models/card_style.dart';
import 'models/vocab_card.dart';
import 'services/overlay_mobile.dart' show NativeOverlay;
import 'utils/screen_metrics.dart';
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
  /// 主应用下发的**配置坐标**（持久化的那份，属于 [sourceSize] 方向）。
  List<VocabCard> _sourceCards = <VocabCard>[];

  /// [_sourceCards] 所属的坐标系方向（通常是「竖屏时的屏幕尺寸」）。
  ///
  /// 旋转后不清理它：它是绝对参考，坐标映射 [ScreenMetrics.mapPosition]
  /// 以它为基准算出来才稳定、幂等。
  Size? _sourceSize;

  /// 实际渲染用的卡片（= 配置坐标按当前视图尺寸映射后的结果）。
  List<VocabCard> _cards = <VocabCard>[];

  /// [_cards] 对应的视图尺寸，用于判断「旋转了需要重算」。
  Size _layoutSize = Size.zero;

  bool _adjustMode = false;

  /// 词汇卡整体样式（由主应用随消息推送）。
  CardStyle _cardStyle = CardStyle.bordered;

  /// 主应用正在显示设置 / 调整界面时为 false：此时由主应用自己显示卡片，
  /// 悬浮窗内容先隐藏，避免重复显示、也避免数据同步间隙里的错位。
  bool _visible = true;

  /// 屏幕尺寸（逻辑像素）。
  ///
  /// ★ 横屏适配的关键 ★
  ///
  /// 卡片坐标系 = 「逻辑像素，屏幕坐标，原点在屏幕左上角」。这个坐标系的主人是
  /// **Flutter 视图本身**，所以首选 [MediaQuery.sizeOf]（= 视图尺寸），
  /// 从原生查到的 dp 尺寸只在视图尺寸不可用时兜底。
  Size? _nativeScreenSize;

  /// 拖动时卡片左上角相对指针的偏移。
  final Map<int, Offset> _grabOffsets = {};

  /// 最近一次记录的视图尺寸（用于日志去重）。
  Size _lastLoggedSize = Size.zero;

  @override
  void initState() {
    super.initState();
    FlutterOverlayWindow.overlayListener.listen(_onMessage);
    _loadScreenSize();
    // 握手：引擎一启动就通知主应用“我准备好了”，让主应用立刻回推卡片。
    // 这样即使 showOverlay 后立刻推送的数据因时序丢失，也能在引擎就绪后补上。
    _announceReady();
  }

  /// 引擎重建计数：用于让主应用区分“首次就绪”与“重建后就绪”。
  ///
  /// 悬浮窗引擎可能被重建（插件在 onStartCommand 里会先 cleanup 再 addView），
  /// 重建后状态全部丢失，主应用必须重新下发触摸标志与卡片。
  static int _readyCount = 0;

  Future<void> _announceReady() async {
    // 稍等一帧，确保监听与首帧渲染就绪后再报告。
    await Future<void>.delayed(const Duration(milliseconds: 80));
    if (!mounted) return;
    _readyCount++;
    try {
      await FlutterOverlayWindow.shareData(
        jsonEncode({'ready': true, 'count': _readyCount}),
      );
      debugPrint('[overlay] ready sent (#$_readyCount)');
    } catch (e) {
      debugPrint('[overlay] ready failed: $e');
    }
  }

  Future<void> _loadScreenSize() async {
    // 仅作为兜底缓存；真正的坐标系以视图尺寸（MediaQuery.sizeOf）为准，
    // 见 [_effectiveScreenSize]。
    final size = await NativeOverlay.screenSize();
    if (size == null || !mounted) return;
    setState(() => _nativeScreenSize = size);
  }

  /// 当前应使用的屏幕尺寸（卡片坐标系）。
  ///
  /// 规则：**视图尺寸优先**；只有视图尺寸不可用（<= 0）时才退回原生查询结果。
  /// 横竖屏切换时视图尺寸会立即更新，绝不会被旧方向的 dp 尺寸拖住 —— 这是
  /// 「横屏后卡片跑偏 / 下半部分被吞掉」的核心修复点。
  Size _effectiveScreenSize(BuildContext context) {
    final view = ScreenMetrics.of(context);
    if (view.width > 0 && view.height > 0) return view;
    return _nativeScreenSize ?? Size.zero;
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

      // ★ 不要把收到的坐标按当前屏幕「夹一下」就用 ★
      //
      // 收到的坐标是**配置坐标**，它属于主应用下发的那个方向（竖屏）。
      // 悬浮窗视图切到横屏后，视图本身已经是横屏尺寸、但布局不会自动旋转，
      // 若在这里用横屏尺寸去 clamp，下面那张卡片的 y 会被夹到屏幕底部
      // （正是「下方词汇卡被覆盖」的直接来源）。正确做法是把它记为配置坐标，
      // 渲染时再按 [ScreenMetrics.mapPosition] 随方向旋转。
      final screen = _effectiveScreenSize(context);

      setState(() {
        if (rawCards is List) {
          _sourceCards = cards;
          // 配置坐标的方向由**主应用明确告知**；只有旧版本消息缺失该字段时
          // 才退回推断。
          //
          // ★ 绝不能在「配置没变」时重新猜测参考方向 ★
          // 旧实现每次收到消息都用当前视图方向去验算：旋转之后，横屏坐标
          // 同样「放得下」，于是参考方向被改写成横屏 —— 下一帧又按横屏
          // 映射一次，卡片被反复旋转、越转越偏。
          final announced = _parseScreen(map['sourceScreen']);
          if (announced != null) {
            _sourceSize = announced;
          } else {
            _sourceSize ??= _pickSourceSize(cards, screen);
          }
          _layoutSize = Size.zero; // 强制下一帧按新参考重算布局
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
      if (rawCards is List) {
        _relayout(screen);
        debugPrint(
          '[overlay] cards=${cards.length} source='
          '${_sourceSize == null ? '?' : ScreenMetrics.describe(_sourceSize!)} '
          'view=${ScreenMetrics.describe(screen)}',
        );
      }
      // 主应用要求回传卡片（requestSave）：只回应，不再二次触发保存，
      // 否则会和主应用形成「推 → 回传 → 再推」的循环。
      if (map['requestSave'] == true) {
        _requestSendCards();
      }
    } catch (e) {
      // 不静默吞异常：非法消息 / 解析失败都要在日志里可见，
      // 否则「卡片收不到 / 解析失败」无从排查。
      debugPrint('[overlay] message handling failed: $e');
    }
  }

  /// 解析主应用下发的「配置坐标所属屏幕」。
  ///
  /// 消息格式：`"sourceScreen": {"w": 366.4, "h": 813.4}`。缺失 / 非法时返回
  /// null，由调用方决定是否退回推断。
  static Size? _parseScreen(Object? raw) {
    if (raw is! Map) return null;
    final w = (raw['w'] as num?)?.toDouble();
    final h = (raw['h'] as num?)?.toDouble();
    if (w == null || h == null || w <= 0 || h <= 0) return null;
    return Size(w, h);
  }

  /// 选择配置坐标所属的「参考方向」。
  ///
  /// 只有在参考方向与当前视图方向一致、且坐标确实放得下时才沿用旧参考；
  /// 否则（例如用户就是在横屏下摆的卡片）直接用当前视图尺寸做参考。
  Size _pickSourceSize(List<VocabCard> cards, Size screen) {
    final previous = _sourceSize;
    if (previous != null &&
        previous.width > 0 &&
        previous.height > 0 &&
        (previous.width > previous.height) == (screen.width > screen.height) &&
        cards.every(
          (c) =>
              c.x >= 0 &&
              c.y >= 0 &&
              c.x + c.width <= previous.width + 0.5 &&
              c.y + c.height <= previous.height + 0.5,
        )) {
      return previous;
    }
    return screen;
  }

  /// 按当前视图尺寸重算渲染坐标（旋转后自动跟随）。
  ///
  /// 幂等：以配置坐标（[_sourceCards]）为唯一来源重新算，不做增量改动，
  /// 因此在任意时刻重复调用都不会让卡片位置漂移。
  void _relayout(Size screen) {
    if (screen.width <= 0 || screen.height <= 0) return;
    final source = _sourceSize;
    final sourceSize = source ?? screen;
    final mapped = <VocabCard>[];
    for (var i = 0; i < _sourceCards.length; i++) {
      final c = _sourceCards[i];
      final pos = ScreenMetrics.mapPosition(
        pos: c.position,
        source: sourceSize,
        screen: screen,
        cardWidth: c.width,
        cardHeight: c.height,
      );
      _logMapping(i, c.position, pos, sourceSize, screen);
      mapped.add(c.movedTo(pos));
    }
    if (mapped.length != _cards.length) {
      _grabOffsets.clear();
    } else {
      for (var i = 0; i < mapped.length; i++) {
        if (mapped[i].position != _cards[i].position) {
          // 旋转后旧的抓取偏移已失效（坐标系变了）。
          _grabOffsets.remove(i);
        }
      }
    }
    _cards = mapped;
    _layoutSize = screen;
  }

  void _logMapping(
    int index,
    Offset before,
    Offset after,
    Size source,
    Size screen,
  ) {
    final key = '${ScreenMetrics.describe(source)}->'
        '${ScreenMetrics.describe(screen)}';
    if (key == _lastMappingKey) return;
    _lastMappingKey = key;
    debugPrint('[overlay] map card $index $key: $before -> $after');
  }

  String? _lastMappingKey;

  /// 上一次真正回传的时间戳（用于节流）。
  DateTime? _lastSendAt;

  /// 待发送标记：节流窗口内收到的多次请求合并成窗口结束后的一次。
  bool _sendScheduled = false;

  /// 回传卡片位置给主应用保存（**节流**）。
  ///
  /// 拖动过程中 `onPanUpdate` 每帧都会走到这里，而一次拖动可能持续数秒、
  /// 产生几百帧。之前是「每次拖动都 `_sendCards`」，主应用每帧都要
  /// `jsonEncode` + 写 SharedPreferences + `setState`，会明显掉帧。
  ///
  /// 现在：距上次回传不足 [_sendInterval] 时，只登记「窗口结束后再发一次」，
  /// 保证最终位置一定会被保存，又不会在拖动途中疯狂落地。
  static const Duration _sendInterval = Duration(milliseconds: 400);

  void _requestSendCards() {
    final now = DateTime.now();
    final last = _lastSendAt;
    if (last != null && now.difference(last) < _sendInterval) {
      if (_sendScheduled) return;
      _sendScheduled = true;
      final wait = _sendInterval - now.difference(last);
      Future<void>.delayed(wait, () {
        _sendScheduled = false;
        if (!mounted) return;
        // 节流窗口结束时补发最终位置（拖动可能已经结束，这里是最新值）。
        unawaited(_sendCards());
      });
      return;
    }
    unawaited(_sendCards());
  }

  Future<void> _sendCards() async {
    _lastSendAt = DateTime.now();
    // 回传**配置坐标**（已逆映射回 [_sourceSize] 方向），并附上它所属的屏幕
    // 尺寸，主应用可直接持久化 —— 下次启动 / 旋转时才能正确地正向映射。
    final source = _sourceSize;
    final payload = jsonEncode({
      // ★ requestSave 必须带上 ★
      //
      // 主应用（MobileController._onMessage）只在看到 `requestSave == true`
      // 时才把回传的卡片交给 `onCardsUpdated` 持久化。之前这里没有这个字段，
      // 于是「拖动卡片 → 位置被保存」这条链路**从来没有生效过**：悬浮窗引擎
      // 本地改完坐标、回传了，主应用却当成普通消息丢掉，重启后位置又回到旧值。
      'requestSave': true,
      'cards': _sourceCards.map((c) => c.toJson()).toList(),
      if (source != null && source != Size.zero)
        'sourceScreen': {'w': source.width, 'h': source.height},
      // 兼容字段：本次渲染所用的坐标系尺寸。
      'screen': {
        'w': _layoutSize.width,
        'h': _layoutSize.height,
      },
    });
    try {
      await FlutterOverlayWindow.shareData(payload);
    } catch (e) {
      // 回传失败会让主应用丢掉拖动结果，必须留日志。
      debugPrint('[overlay] sendCards failed: $e');
    }
  }

  /// 把 [_cards]（当前方向下）旋转回配置坐标所属方向后写入 [_sourceCards]。
  ///
  /// 拖动 / 重置发生在**当前方向**，而持久化的是**配置坐标**。必须先逆映射
  /// 回 [_sourceSize]，否则横屏下保存的坐标下次会被当成竖屏坐标再旋转一次，
  /// 卡片位置逐步漂移。
  void _commitRenderedToSource() {
    final source = _sourceSize;
    if (source == null || source == Size.zero) return;
    final from = _layoutSize == Size.zero ? source : _layoutSize;
    for (var i = 0; i < _cards.length && i < _sourceCards.length; i++) {
      final card = _cards[i];
      final pos = ScreenMetrics.mapPosition(
        pos: card.position,
        source: from,
        screen: source,
        cardWidth: card.width,
        cardHeight: card.height,
      );
      _sourceCards[i] = card.movedTo(pos);
    }
  }

  @override
  Widget build(BuildContext context) {
    // 悬浮窗坐标使用 dp（逻辑像素），与卡片模型一致。
    final screen = _effectiveScreenSize(context);
    // 视图尺寸变化（旋转 / 窗口重建）时重新映射「为什么」：
    // 悬浮窗视图不会随系统方向重新布局，必须自己跟着坐标系转。
    if (screen != _layoutSize && screen.width > 0 && screen.height > 0) {
      _relayout(screen);
      if (_lastLoggedSize != screen) {
        _lastLoggedSize = screen;
        debugPrint('[overlay] view size -> ${ScreenMetrics.describe(screen)}');
      }
    }
    final size = _layoutSize == Size.zero ? screen : _layoutSize;

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
                        onDragStart: (pointer) {
                          _grabOffsets[i] =
                              Offset(_cards[i].x, _cards[i].y) - pointer;
                        },
                        onDragUpdate: (pointer) {
                          if (!_grabOffsets.containsKey(i)) return;
                          final target = pointer + _grabOffsets[i]!;
                          setState(() {
                            _cards[i] = _cards[i].movedTo(
                              _clamp(target, _cards[i], size),
                            );
                          });
                          _grabOffsets[i] =
                              Offset(_cards[i].x, _cards[i].y) - pointer;
                        },
                        onDragEnd: () {
                          _grabOffsets.remove(i);
                          // 拖动结束后写回配置坐标并回传主应用保存。
                          // 这里立即发送（忽略节流）：松手时的最终位置必须落地。
                          _commitRenderedToSource();
                          _lastSendAt = null;
                          _requestSendCards();
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

  Offset _clamp(Offset pos, VocabCard card, Size screen) =>
      ScreenMetrics.clampPosition(
        pos: pos,
        screen: screen,
        cardWidth: card.width,
        cardHeight: card.height,
      );
}

/// 调整模式下可拖动的卡片。
class _DraggableCard extends StatefulWidget {
  final VocabCard card;
  final CardStyle style;
  final ValueChanged<Offset> onDragStart;
  final ValueChanged<Offset> onDragUpdate;
  final VoidCallback onDragEnd;

  const _DraggableCard({
    super.key,
    required this.card,
    this.style = CardStyle.bordered,
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
