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
    } catch (_) {
      return false;
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
    } catch (_) {
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
    } catch (_) {
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
    } catch (_) {
      return false;
    }
  }

  /// 主应用界面（设置 / 调整）是否正在显示。
  ///
  /// 由 [MobileController.setPageVisible] 同步过来。
  void setPageVisible(bool visible) {
    if (_pageVisible == visible) return;
    _pageVisible = visible;
    // 立刻把可见性意图同步给悬浮窗（如果它存在）；否则等引擎就绪时补发。
    setCardsVisible(!visible);
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

    // 1) 触摸标志：按期望值重新下发。
    await _applyFlag(adjustMode: !_clickThrough);

    // 2) 卡片 + 可见性：重新推送一次完整状态。
    final visible = !_pageVisible;
    final cards = _lastCards;
    for (var i = 0; i < 2; i++) {
      await _pushCards(
        cards,
        adjustMode: !_clickThrough,
        visible: visible,
        cardStyle: _lastStyle,
      );
      if (i == 0) {
        await Future<void>.delayed(const Duration(milliseconds: 120));
      }
    }
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
      await FlutterOverlayWindow.showOverlay(
        height: WindowSize.matchParent,
        width: WindowSize.matchParent,
        alignment: OverlayAlignment.topLeft,
        flag: adjustMode ? OverlayFlag.defaultFlag : OverlayFlag.clickThrough,
        overlayTitle: '词汇悬浮卡',
        overlayContent: '词汇卡正在显示',
        enableDrag: false,
        positionGravity: PositionGravity.none,
      );
      _showing = true;
    } else {
      // 已显示：仅更新触摸行为。
      await _applyFlag(adjustMode: adjustMode);
    }

    // 悬浮窗引擎是懒创建的（首次 attach 时才启动 Dart 入口并注册消息监听），
    // 刚显示时立刻发送的数据有极小概率丢失。这里连续推送几次，保证卡片一定
    // 到达悬浮窗引擎；同时也覆盖“窗口刚被重建”的情况。
    for (var i = 0; i < 3; i++) {
      await _pushCards(cards, adjustMode: adjustMode, cardStyle: cardStyle);
      if (i < 2) {
        await Future<void>.delayed(const Duration(milliseconds: 120));
      }
    }
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
    } catch (_) {
      // 忽略：某些 ROM 可能不支持。
    }
  }

  /// 下发触摸标志（仅在悬浮窗存在时调用）。
  Future<void> _applyFlag({required bool adjustMode}) async {
    try {
      await FlutterOverlayWindow.updateFlag(
        adjustMode ? OverlayFlag.defaultFlag : OverlayFlag.clickThrough,
      );
    } catch (_) {
      // 忽略：引擎尚未就绪时可能抛 MissingPluginException，
      // 会在 onEngineReady 时重新下发。
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
    if (visible != null) map['visible'] = visible;
    try {
      await FlutterOverlayWindow.shareData(jsonEncode(map));
    } catch (_) {
      // 忽略：引擎尚未就绪时可能抛异常，会在 onEngineReady 时重新推送。
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
    } catch (_) {
      // 忽略。
    }
  }

  /// 关闭悬浮窗。
  Future<void> hideOverlay() async {
    if (!_isAndroid) return;
    try {
      if (await isActive()) await FlutterOverlayWindow.closeOverlay();
    } catch (_) {
      // 忽略。
    }
    _showing = false;
    _engineReady = false;
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
