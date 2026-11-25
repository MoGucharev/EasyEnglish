import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';

import '../models/card_style.dart';
import '../models/vocab_card.dart';
import 'overlay_mobile.dart';

/// 移动端（Android）协调器：把“主应用（设置 / 控制台）”与“系统悬浮窗
/// （卡片显示在其他应用之上）”连接起来。
///
/// 职责：
///  * 申请悬浮窗权限；
///  * 把卡片数据推送到悬浮窗引擎；
///  * 监听悬浮窗引擎回传的卡片位置（拖动后），回调给上层持久化；
///  * 控制浏览（穿透）/ 调整（可触摸）模式。
class MobileController {
  MobileController._();
  static final MobileController instance = MobileController._();

  final MobileOverlayPlatform _platform = MobileOverlayPlatform();

  MobileOverlayPlatform get platform => _platform;

  /// 悬浮窗引擎回传卡片位置时触发（用于持久化）。
  ValueChanged<List<VocabCard>>? onCardsUpdated;

  /// 悬浮窗引擎就绪（握手）时触发：主应用应回推最新卡片。
  VoidCallback? onOverlayReady;

  /// “设置 / 调整”界面打开或关闭时触发（true = 已打开）。
  ///
  /// 悬浮窗（第二个 Flutter 引擎）会据此把卡片内容隐藏起来，避免与本应用
  /// 设置界面里的预览重复显示；也避免在数据同步的间隙显示得过小 / 错位。
  ValueChanged<bool>? onPageStateChanged;

  bool _listening = false;

  /// 监听悬浮窗引擎回传的数据。
  void startListening() {
    if (_listening) return;
    _listening = true;
    FlutterOverlayWindow.overlayListener.listen((message) {
      if (message is! String) return;
      try {
        final decoded = jsonDecode(message);
        if (decoded is! Map) return;
        final map = Map<String, dynamic>.from(decoded);

        // 握手：悬浮窗引擎启动后主动上报 ready，主应用据此回推卡片，
        // 彻底消除“showOverlay 后立刻推送、数据在引擎就绪前丢失”的时序问题。
        if (map['ready'] == true) {
          debugPrint('[main] overlay ready → re-push cards');
          onOverlayReady?.call();
          return;
        }

        final rawCards = map['cards'];
        if (rawCards is! List) return;
        final cards = <VocabCard>[];
        for (final e in rawCards) {
          if (e is Map) {
            cards.add(VocabCard.fromJson(Map<String, dynamic>.from(e)));
          }
        }
        onCardsUpdated?.call(cards);
      } catch (_) {
        // 忽略非法消息。
      }
    });
  }

  /// 确保已获得悬浮窗权限；未获得时请求。返回是否已授权。
  Future<bool> ensurePermission() => _platform.requestPermission();

  /// 显示悬浮窗并推送卡片（浏览 / 穿透模式）。
  Future<void> showCards(
    List<VocabCard> cards, {
    CardStyle style = CardStyle.bordered,
  }) async {
    await _platform.showOverlay(
      cards: cards,
      adjustMode: false,
      cardStyle: style,
    );
  }

  /// 悬浮窗是否正在显示。
  Future<bool> isShowing() async {
    // 以原生侧的真实状态为准：主界面被销毁重建、或进程被系统回收后，
    // Dart 侧缓存的 _showing 可能与真实状态不一致。
    final active = await _platform.isActive();
    return _platform.showing || active;
  }

  /// 进入调整模式（悬浮窗可触摸拖动）。
  Future<void> enterAdjust(List<VocabCard> cards) async {
    await _platform.setAdjustMode(adjustMode: true, cards: cards);
  }

  /// 退出调整模式（回到穿透）。
  Future<void> exitAdjust(List<VocabCard> cards) async {
    await _platform.setAdjustMode(adjustMode: false, cards: cards);
  }

  /// 仅更新卡片内容。[visible] 非空时同时切换可见性。
  Future<void> updateCards(
    List<VocabCard> cards, {
    bool? visible,
    CardStyle style = CardStyle.bordered,
  }) async {
    await _platform.updateCards(cards, visible: visible, cardStyle: style);
  }

  /// 关闭悬浮窗。
  Future<void> hide() => _platform.hideOverlay();

  /// 只切换悬浮窗内容的可见性（不重建 / 不移动卡片）。
  Future<void> setCardsVisible(bool visible) =>
      _platform.setCardsVisible(visible);

  /// 主应用移到后台（让悬浮窗显示在其他应用之上）。
  Future<void> moveToBackground() => _platform.moveToBackground();
}
