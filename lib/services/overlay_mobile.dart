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
class MobileOverlayPlatform implements OverlayPlatform {
  bool _showing = false;

  /// Dart 侧记录的显示状态（是否真的还在显示请看 [isActive]）。
  bool get showing => _showing;

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

    // 以原生状态为准：Dart 侧 _showing 可能已经过期（比如主界面被系统销毁
    // 重建过）。此时必须重新 showOverlay，否则只是 updateFlag，
    // 而原生侧根本没有窗口 → 卡片永远不显示。
    final active = await isActive();

    if (!active) {
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
      await FlutterOverlayWindow.updateFlag(
        adjustMode ? OverlayFlag.defaultFlag : OverlayFlag.clickThrough,
      );
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
    if (!_isAndroid || !await isActive()) return;
    await _pushCards(
      cards,
      adjustMode: false,
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
    // 未显示时直接按“显示悬浮窗”处理，避免静默失败。
    if (!await isActive()) {
      await showOverlay(cards: cards, adjustMode: adjustMode);
      return;
    }
    await FlutterOverlayWindow.updateFlag(
      adjustMode ? OverlayFlag.defaultFlag : OverlayFlag.clickThrough,
    );
    await _pushCards(cards, adjustMode: adjustMode);
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
    await FlutterOverlayWindow.shareData(jsonEncode(map));
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
  }

  // ---- OverlayPlatform 接口实现 ----

  /// 移动端的“穿透”映射到悬浮窗是否可触摸。
  /// 这里采用“卡片包围盒窗口”，浏览模式保持穿透；具体触摸标志由
  /// [setAdjustMode] 控制。为避免误改，这里只做状态同步的兜底 no-op。
  @override
  Future<void> setClickThrough(bool clickThrough) async {
    if (!_isAndroid || !await isActive()) return;
    try {
      await FlutterOverlayWindow.updateFlag(
        clickThrough ? OverlayFlag.clickThrough : OverlayFlag.defaultFlag,
      );
    } catch (_) {
      // 忽略。
    }
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
