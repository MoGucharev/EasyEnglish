import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';

import '../models/card_style.dart';
import '../models/vocab_card.dart';
import 'overlay_platform.dart';

/// 移动端（Android）的 [OverlayPlatform] 实现。
///
/// 用 `flutter_overlay_window` 在系统层创建 `TYPE_APPLICATION_OVERLAY`
/// 悬浮窗，里面跑第二个 Flutter 引擎（入口见 lib/overlay_main.dart）渲染
/// 词汇卡，从而让卡片显示在其他应用之上。
///
/// 关键点：
///  * 浏览（主界面）模式：悬浮窗用 [OverlayFlag.clickThrough] → 整窗穿透，
///    除原生控件外不拦截下层应用；
///  * 调整模式：切到 [OverlayFlag.defaultFlag] 让卡片可触摸拖动；
///  * 卡片数据通过 [FlutterOverlayWindow.shareData] 推送到悬浮窗引擎；
///  * 悬浮窗引擎把拖动后的位置回传，主应用据此持久化。
///
/// iOS 不支持跨应用悬浮窗，此处所有方法为 no-op。
/// 原生侧是否存在运行中的悬浮窗（**不**修改任何本地缓存）。
///
/// 供各界面判断“该由谁来画卡片”。之所以暴露成顶层函数：
///  * `NativeOverlay.isActive()` 是无副作用的；
///  * 与 `MobileOverlayPlatform.isActive()`（会同步 `_showing`）区分开，
///    避免界面层无意中修改平台层的显示状态。
class NativeOverlay {
  NativeOverlay._();

  static bool get _isAndroid => !kIsWeb && Platform.isAndroid;

  /// 原生悬浮窗当前是否真的在显示。
  static Future<bool> isActive() async {
    if (!_isAndroid) return false;
    try {
      return await FlutterOverlayWindow.isActive();
    } catch (e) {
      // 不静默吞异常：至少留下一次痕迹，否则「悬浮窗到底在不在」这种
      // 关键状态完全不可见。
      debugPrint('[overlay] isActive failed: $e');
      return false;
    }
  }

  /// 向原生查询屏幕尺寸（dp）。
  ///
  /// 仅作为**兜底**：`OverlayService.getScreenSize()` 的 density 取自
  /// `getApplicationContext()`，不跟随横竖屏切换，横屏下可能与 Flutter 视图
  /// 尺寸不一致。调用方必须先用 `ScreenMetrics.isPlausible()` 校验。
  static Future<Size?> screenSize() async {
    if (!_isAndroid) return null;
    try {
      final pos = await FlutterOverlayWindow.getScreenSize();
      final size = Size(pos.x, pos.y);
      if (size.width <= 0 || size.height <= 0) return null;
      return size;
    } catch (e) {
      debugPrint('[overlay] getScreenSize failed: $e');
      return null;
    }
  }

  /// 显示 / 隐藏悬浮窗窗口本身（不销毁服务与引擎）。
  ///
  /// 与「推送 visible:false」不同：后者只是让悬浮窗引擎不画内容，原生窗口
  /// 仍是全屏尺寸（可触摸模式下还会拦截触摸）。这里把原生窗口缩成 0×0，
  /// 彻底不占任何触摸区域，用于设置 / 调整界面打开期间。
  static Future<void> setWindowVisible(bool visible) async {
    if (!_isAndroid) return;
    try {
      await FlutterOverlayWindow.setOverlayVisible(visible: visible);
    } catch (e) {
      debugPrint('[overlay] setOverlayVisible($visible) failed: $e');
    }
  }
}

class MobileOverlayPlatform implements OverlayPlatform {
  bool _showing = false;

  /// Dart 侧记录的显示状态（是否真的还在显示请看 [isActive]）。
  bool get showing => _showing;

  /// 期望的触摸标志：true = 整窗穿透（浏览模式），false = 可触摸。
  ///
  /// 不能依赖 `updateFlag` 的调用结果 —— 它可能被静默丢弃或抛异常，
  /// 所以这里记住「应该是哪种模式」，在引擎就绪时统一下发。
  bool _clickThrough = true;

  /// 悬浮窗引擎是否已就绪（收到 ready 握手）。
  bool get engineReady => _engineReady;
  bool _engineReady = false;

  /// 最近一次推送给悬浮窗的卡片 / 样式（引擎就绪后补发）。
  List<VocabCard> _lastCards = <VocabCard>[];
  CardStyle _lastStyle = CardStyle.bordered;

  /// 主应用是否正在显示自己的界面（设置 / 调整）。
  ///
  /// 为 true 时悬浮窗内容应隐藏，避免与本应用界面里的卡片重复显示。
  bool get pageVisible => _pageVisible;
  bool _pageVisible = false;

  /// 当前卡片坐标所属的屏幕（宽 / 高，逻辑像素）。
  ///
  /// 卡片坐标是绝对坐标，**必须**连同它所属的屏幕尺寸一起下发，悬浮窗引擎
  /// 才能正确地把它旋转到当前的屏幕方向上。缺失时引擎只能靠猜 —— 旋转后
  /// 卡片位置错乱的根源就在这里。
  Size? _sourceScreen;

  /// 更新卡片坐标所属的屏幕（主应用在加载 / 保存卡片时同步过来）。
  void setSourceScreen(Size? screen) {
    _sourceScreen = screen;
  }

  static bool get _isAndroid => !kIsWeb && Platform.isAndroid;

  /// 原生侧是否存在运行中的悬浮窗。
  ///
  /// 主界面被销毁重建、或进程被系统回收后，Dart 侧缓存的 [_showing]
  /// 可能与真实状态不一致，因此以原生 `isActive()` 为准，并同步本地缓存。
  Future<bool> isActive() async {
    if (!_isAndroid) return false;
    try {
      final active = await FlutterOverlayWindow.isActive();
      if (active) _showing = true;
      return active;
    } catch (e) {
      // 平台调用失败时退回本地缓存，但必须留下日志：
      // 否则「窗口到底在不在」这个判断完全是黑箱。
      debugPrint('[overlay] isActive failed, fallback to cached '
          'showing=$_showing: $e');
      return _showing;
    }
  }

  @override
  Future<void> initWindowForOverlay() async {
    // 移动端没有桌面窗口需要初始化。
  }

  @override
  Future<void> ensureCoverScreen() async {
    // 移动端不需要（也无法）铺满整个屏幕。
  }

  /// 是否已获得“显示在其他应用上层”权限。
  Future<bool> isPermissionGranted() async {
    if (!_isAndroid) return true;
    try {
      return await FlutterOverlayWindow.isPermissionGranted();
    } catch (e) {
      debugPrint('[overlay] isPermissionGranted failed: $e');
      return false;
    }
  }

  /// 请求悬浮窗权限（跳转系统设置页）。返回用户归来后的授权状态。
  Future<bool> requestPermission() async {
    if (!_isAndroid) return true;
    try {
      if (await FlutterOverlayWindow.isPermissionGranted()) return true;
      final ok = await FlutterOverlayWindow.requestPermission();
      return ok ?? false;
    } catch (e) {
      debugPrint('[overlay] requestPermission failed: $e');
      return false;
    }
  }

  /// 主应用界面（设置 / 调整）是否正在显示。
  ///
  /// 由 [MobileController.setPageVisible] 同步过来。
  ///
  /// 除了记录意图（引擎就绪时重放 [visible]），还会**同时收缩原生窗口**：
  /// 主应用显示设置界面时必须关闭悬浮窗的可触摸性才能输入文字，而此时一个
  /// 全屏的可触摸悬浮窗会挡住主应用自己的按钮。把窗口缩成 0×0 后，悬浮窗
  /// 既不可见也不占用任何触摸区域，横竖屏下都不会「吞掉」界面上的控件。
  void setPageVisible(bool visible) {
    if (_pageVisible == visible) return;
    _pageVisible = visible;
    // 立刻把可见性意图同步给悬浮窗（如果它存在）；否则等引擎就绪时补发。
    setCardsVisible(!visible);
    unawaited(NativeOverlay.setWindowVisible(!visible));
  }

  /// 悬浮窗引擎已就绪：把缓存下来的「期望状态」一次性补齐。
  ///
  /// 这是「第一次点应用生效、之后都不生效」与「没点应用就不显示」的修复关键：
  /// 首次 `showOverlay` 后插件会「创建窗口 → 销毁 → 重建」，引擎重启后原生
  /// 窗口的触摸标志回到 `showOverlay` 时的默认值，而 Dart 侧后续的
  /// `updateFlag` 打在了刚被销毁的引擎上 → 标志永远不正确、卡片也收不到。
  Future<void> onEngineReady() async {
    if (!_isAndroid) return;
    _engineReady = true;

    // 0) 原生窗口的显示 / 尺寸：按「页面可见性」重放。引擎重建后窗口可能
    //    已经被 setOverlayVisible(false) 收缩成 0×0，必须恢复回来。
    await NativeOverlay.setWindowVisible(!_pageVisible);

    // 1) 触摸标志：按期望值重新下发。
    await _applyFlag(adjustMode: !_clickThrough);

    // 2) 卡片 + 可见性：推送一次完整状态。
    //
    // 这里原本连推两次，加上 showOverlay 里的三次、以及 main.dart 里
    // `_syncMobileOverlay` / `_ensureFloatingOnBackground` 各自再推一遍，
    // 一次「点应用」会下发七八条完全相同的消息（日志里就是这么刷屏的）。
    // 重放本身就是幂等的，重复推送没有正确性收益，只会掩盖「到底哪条生效」。
    // 一次推送即可：`ready` 握手是悬浮窗引擎注册好消息监听之后才发出的。
    await _pushCards(
      _lastCards,
      adjustMode: !_clickThrough,
      visible: !_pageVisible,
      cardStyle: _lastStyle,
    );
  }

  /// 显示系统悬浮窗（若尚未显示）。
  ///
  /// [adjustMode] 为 true 时悬浮窗可触摸（用于拖动卡片），否则整窗穿透。
  Future<void> showOverlay({
    required List<VocabCard> cards,
    bool adjustMode = false,
    CardStyle cardStyle = CardStyle.bordered,
  }) async {
    if (!_isAndroid) return;
    if (!await isPermissionGranted()) return;

    _lastCards = cards;
    _lastStyle = cardStyle;
    _clickThrough = !adjustMode;

    // 以原生状态为准：Dart 侧 _showing 可能已经过期（比如主界面被系统销毁
    // 重建过）。此时必须重新 showOverlay，否则只是 updateFlag，
    // 而原生侧根本没有窗口 → 卡片永远不显示。
    final active = await isActive();

    if (!active) {
      // 窗口不存在 → 让悬浮窗引擎重新走一遍「就绪 → 补发状态」的流程。
      _engineReady = false;
      await _createWindow(adjustMode: adjustMode);
      _showing = true;
    } else {
      // 已显示：仅更新触摸行为。
      await _applyFlag(adjustMode: adjustMode);
    }

    // 窗口刚创建时，悬浮窗引擎会先握手再收数据；`onEngineReady()` 已经负责
    // 「就绪后重放完整状态」，这里只需要推一次，不必再循环三遍
    // （三遍会让日志里同一条消息出现三次，掩盖真正的时序问题）。
    await _pushCards(cards, adjustMode: adjustMode, cardStyle: cardStyle);
  }

  /// 创建（或重建）原生悬浮窗。
  Future<void> _createWindow({required bool adjustMode}) async {
    // ★ 高度用 fullCover（而不是 matchParent）★
    //
    // matchParent 的高度会被插件按「可用区」夹取：它在 `onStartCommand` 里
    // 用 `screenHeight()` 计算高度，而这个值缓存在 `mScreenHeight` 里，
    // 只在第一次取用时按当时的方向算一次（竖屏还要额外加上导航栏高度）。
    // 横屏后窗口仍是竖屏算出来的尺寸 → 可用区比屏幕小，卡片坐标靠下 / 靠右
    // 的部分「放不进去」，表现为下面那张卡被夹到边界甚至被覆盖。
    //
    // fullCover（-1999）让插件把边界直接设成整块屏幕（含状态栏、导航栏），
    // 横竖屏下都与真实屏幕一致，卡片坐标才可以按整屏计算。
    await FlutterOverlayWindow.showOverlay(
      height: WindowSize.fullCover,
      width: WindowSize.matchParent,
      alignment: OverlayAlignment.topLeft,
      flag: adjustMode ? OverlayFlag.defaultFlag : OverlayFlag.clickThrough,
      overlayTitle: '词汇悬浮卡',
      overlayContent: '词汇卡正在显示',
      enableDrag: false,
      positionGravity: PositionGravity.none,
    );
  }

  /// 更新悬浮窗内的卡片内容（不改变显示 / 触摸状态）。
  ///
  /// [visible] 为 null 时不改变可见性；否则一并切换。
  Future<void> updateCards(
    List<VocabCard> cards, {
    bool? visible,
    CardStyle cardStyle = CardStyle.bordered,
  }) async {
    if (!_isAndroid) return;
    _lastCards = cards;
    _lastStyle = cardStyle;
    if (!await isActive()) return;
    await _pushCards(
      cards,
      adjustMode: !_clickThrough,
      visible: visible,
      cardStyle: cardStyle,
    );
  }

  /// 切换调整模式（可触摸拖动 vs 穿透）。
  Future<void> setAdjustMode({
    required bool adjustMode,
    required List<VocabCard> cards,
  }) async {
    if (!_isAndroid) return;
    _lastCards = cards;
    _clickThrough = !adjustMode;
    // 未显示时直接按“显示悬浮窗”处理，避免静默失败。
    if (!await isActive()) {
      await showOverlay(cards: cards, adjustMode: adjustMode);
      return;
    }
    await _applyFlag(adjustMode: adjustMode);
    await _pushCards(cards, adjustMode: adjustMode, cardStyle: _lastStyle);
  }

  static const MethodChannel _appChannel = MethodChannel('vocab_overlay/app');

  /// 把主应用移到后台，让系统悬浮窗显示在其他应用之上。
  Future<void> moveToBackground() async {
    if (!_isAndroid) return;
    try {
      await _appChannel.invokeMethod<void>('moveToBackground');
    } catch (e) {
      // 某些 ROM 可能不支持；记日志，便于排查「点了应用却没切后台」。
      debugPrint('[overlay] moveToBackground failed: $e');
    }
  }

  /// 下发触摸标志（仅在悬浮窗存在时调用）。
  ///
  /// ★ 不要用 `FlutterOverlayWindow.updateFlag` ★
  ///
  /// 插件 1.0.2 原生侧把 `updateFlag` 注册在 **`OverlayService` 里那个
  /// `x-slayer/overlay` 通道**上（见 OverlayService.onStartCommand 里的
  /// `flutterChannel.setMethodCallHandler`），而这个 channel 属于**悬浮窗引擎**：
  /// 窗口还没 addView / 引擎还没就绪时调用，只会得到
  /// `MissingPluginException: No implementation found for method updateFlag`，
  /// 而且它**不记住意图** —— 等窗口晚点建好，标志又回到 showOverlay 时传的值。
  ///
  /// 真正可靠的是主引擎通道上的 `updateOverlay(x, y, width, height,
  /// enableDrag)`：原生 `updateOverlay` 会一次性替换 flags，但**同时会替换
  /// 位置与尺寸**，所以这里必须把当前位置 / 整屏尺寸一起带上，否则窗口会被
  /// 缩成 0×0 或挪到屏幕外。
  Future<void> _applyFlag({required bool adjustMode}) async {
    final flag = adjustMode ? OverlayFlag.defaultFlag : OverlayFlag.clickThrough;
    // 位置：保持与创建时一致（topLeft + 整屏 fullCover）。
    final pos = await _currentWindowPosition();
    debugPrint(
      '[overlay] apply flag adjust=$adjustMode at '
      '${pos.dx.toStringAsFixed(1)},${pos.dy.toStringAsFixed(1)}',
    );
    try {
      final ok = await FlutterOverlayWindow.updateOverlay(
        x: pos.dx.round(),
        y: pos.dy.round(),
        width: WindowSize.matchParent,
        height: WindowSize.fullCover,
        enableDrag: false,
      );
      debugPrint('[overlay] updateOverlay(adjust=$adjustMode) → $ok');
      if (ok == true) return;
    } catch (e) {
      // 换通道后仍可能失败（引擎/窗口未就绪）；继续尝试降级路径并记录原因。
      debugPrint('[overlay] updateOverlay(adjust=$adjustMode) failed: $e');
    }
    // 降级：至少让窗口内部（悬浮窗引擎）也切到期望标志。走不通就只留日志，
    // 由 onEngineReady() 在引擎就绪时重放。
    try {
      await FlutterOverlayWindow.updateFlag(flag);
      debugPrint('[overlay] updateFlag fallback(adjust=$adjustMode) ok');
    } catch (e) {
      debugPrint('[overlay] updateFlag fallback(adjust=$adjustMode) failed: $e');
    }
  }

  /// 查询当前悬浮窗窗口位置（dp）；查不到时退回 (0, 0)。
  ///
  /// 只用于「保持窗口不动地更新 flags」，失败不影响主流程，但必须留日志。
  Future<Offset> _currentWindowPosition() async {
    try {
      final p = await FlutterOverlayWindow.getOverlayPosition();
      return Offset(p.x, p.y);
    } catch (e) {
      debugPrint('[overlay] getOverlayPosition failed, use (0,0): $e');
      return Offset.zero;
    }
  }

  Future<void> _pushCards(
    List<VocabCard> cards, {
    required bool adjustMode,
    bool? visible,
    CardStyle cardStyle = CardStyle.bordered,
  }) async {
    final map = <String, dynamic>{
      'cards': cards.map((c) => c.toJson()).toList(),
      'adjust': adjustMode,
      'cardStyle': cardStyle.id,
    };
    // 卡片坐标所属的屏幕：引擎据此把坐标正向旋转到当前方向。
    final source = _sourceScreen;
    if (source != null && source.width > 0 && source.height > 0) {
      map['sourceScreen'] = {'w': source.width, 'h': source.height};
    }
    if (visible != null) map['visible'] = visible;
    try {
      await FlutterOverlayWindow.shareData(jsonEncode(map));
    } catch (e) {
      // 引擎尚未就绪时可能抛异常，会在 onEngineReady 时重新推送。
      debugPrint(
        '[overlay] pushCards failed (cards=${cards.length}, '
        'adjust=$adjustMode, visible=$visible): $e',
      );
    }
  }

  /// 只切换悬浮窗内容的可见性（不重建 / 不移动卡片）。
  ///
  /// 用于主应用显示设置 / 调整界面时：此时主应用自己会显示卡片，
  /// 悬浮窗内容先隐藏，避免重复显示与同步间隙里的错位。
  Future<void> setCardsVisible(bool visible) async {
    if (!_isAndroid || !await isActive()) return;
    try {
      await FlutterOverlayWindow.shareData(jsonEncode({'visible': visible}));
    } catch (e) {
      debugPrint('[overlay] setCardsVisible($visible) failed: $e');
    }
  }

  /// 关闭悬浮窗。
  Future<void> hideOverlay() async {
    if (!_isAndroid) return;
    try {
      if (await isActive()) await FlutterOverlayWindow.closeOverlay();
    } catch (e) {
      debugPrint('[overlay] hideOverlay failed: $e');
    }
    _showing = false;
    _engineReady = false;
  }

  /// 横竖屏切换后调用：把原生窗口重新贴回整块屏幕，并补发一次卡片。
  ///
  /// 为什么需要：插件的窗口尺寸 / 有效区在 `onStartCommand` 里算好后就缓存了
  /// （`mScreenHeight` 只在第一次取用时按当时的方向计算），旋转后不会自己
  /// 跟着变。窗口如果比屏幕矮，卡片坐标系与可视区就会错位。
  ///
  /// 做法是重建窗口（`showOverlay` 在 `windowManager != null` 时会先
  /// cleanup 再 addView），引擎随后重新握手 → [onEngineReady] 会重放
  /// 触摸标志与卡片。卡片坐标系的方向映射由悬浮窗引擎自己按新视图尺寸完成。
  Future<void> refreshWindowForOrientation() async {
    if (!_isAndroid) return;
    if (!await isActive()) return;
    if (!_engineReady) {
      // 引擎还没握手，说明窗口正在创建中，等 onEngineReady 重放即可。
      return;
    }
    debugPrint('[overlay] refresh window for orientation change');
    try {
      await _createWindow(adjustMode: !_clickThrough);
    } catch (e) {
      debugPrint('[overlay] refreshWindowForOrientation failed: $e');
    }
  }

  // ---- OverlayPlatform 接口实现 ----

  /// 移动端的“穿透”映射到悬浮窗是否可触摸。
  ///
  /// 这里既记录期望值，也在悬浮窗存在时立刻下发。记录是必要的：
  /// 悬浮窗不存在时调用 `updateFlag` 会抛异常，而且那次调用本身也无法
  /// “记住”意图，等窗口创建后自然也就没有生效。
  @override
  Future<void> setClickThrough(bool clickThrough) async {
    if (!_isAndroid) return;
    _clickThrough = clickThrough;
    if (!await isActive()) return;
    await _applyFlag(adjustMode: !clickThrough);
  }

  @override
  Future<void> setInteractive(bool interactive) =>
      setClickThrough(!interactive);

  @override
  Future<void> setAlwaysOnTop(bool value) async {
    // 悬浮窗天然置顶，无需额外处理。
  }

  @override
  Future<void> closeApp() async {
    await hideOverlay();
    exit(0);
  }

  @override
  Future<Offset?> getGlobalCursorPos() async {
    // 移动端没有全局光标。
    return null;
  }
}
