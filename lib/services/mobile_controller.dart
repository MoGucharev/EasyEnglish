import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:material_ui/material_ui.dart' show Size;

import '../models/card_style.dart';
import '../models/vocab_card.dart';
import '../utils/screen_metrics.dart';
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

  /// 卡片坐标所属的屏幕（逻辑像素）。
  ///
  /// 用于把悬浮窗回传的坐标换算回主界面当前的坐标系；也用于判断要不要换算。
  Size? _sourceScreen;

  /// 解析消息里的 `sourceScreen: {"w":.., "h":..}`；缺失 / 非法返回 null。
  static Size? _parseSourceScreen(Object? raw) {
    if (raw is! Map) return null;
    final w = (raw['w'] as num?)?.toDouble();
    final h = (raw['h'] as num?)?.toDouble();
    if (w == null || h == null || w <= 0 || h <= 0) return null;
    return Size(w, h);
  }

  /// 监听悬浮窗引擎回传的数据。
  void startListening() {
    if (_listening) return;
    _listening = true;
    FlutterOverlayWindow.overlayListener.listen((message) async {
      if (message is! String) return;
      try {
        final decoded = jsonDecode(message);
        if (decoded is! Map) return;
        final map = Map<String, dynamic>.from(decoded);

        // 握手：悬浮窗引擎启动后主动上报 ready。
        //
        // 引擎可能被重建多次（插件在 onStartCommand 里会先 cleanup 再
        // addView），每次重建后原生窗口的触摸标志与卡片内容都会丢，所以这里
        // 每次握手都先由平台层**无条件**补齐“期望状态”，再通知上层回推卡片。
        if (map['ready'] == true) {
          debugPrint('[main] overlay ready → re-push cards');
          await _platform.onEngineReady();
          onOverlayReady?.call();
          return;
        }

        final rawCards = map['cards'];
        if (rawCards is! List) return;
        // ★ 只有「悬浮窗引擎主动回传」才当作拖动结果保存 ★
        //
        // 这条 channel 是双向的：主应用 push 出去的卡片也会回到这里。
        // 若不区分，就会把「我刚发出去的卡片」当成「用户拖动后的结果」
        // 再 `setState` + 写一次存储，形成自激回路（日志里那条消息反复出现、
        // 每次都触发一次 `_saveCards`）。
        //
        // 悬浮窗引擎侧发送时带 `requestSave: true`（见 overlay_main._sendCards）。
        if (map['requestSave'] != true) return;
        var cards = <VocabCard>[];
        for (final e in rawCards) {
          if (e is Map) {
            cards.add(VocabCard.fromJson(Map<String, dynamic>.from(e)));
          }
        }
        // 回传的坐标属于 sourceScreen 方向（悬浮窗引擎已经逆映射过）。
        // 方向不同则先映射回主界面当前的坐标系，避免把横屏坐标直接当竖屏用。
        final announced = _parseSourceScreen(map['sourceScreen']);
        final current = _sourceScreen;
        if (announced != null &&
            current != null &&
            announced != current &&
            current.width > 0 &&
            current.height > 0) {
          cards = cards
              .map(
                (c) => c.movedTo(
                  ScreenMetrics.mapPosition(
                    pos: c.position,
                    source: announced,
                    screen: current,
                    cardWidth: c.width,
                    cardHeight: c.height,
                  ),
                ),
              )
              .toList();
        }
        debugPrint('[main] overlay returned cards=${cards.length} '
            'source=${announced == null ? '?' : ScreenMetrics.describe(announced)}');
        onCardsUpdated?.call(cards);
      } catch (e) {
        // 不静默吞异常：非法消息 / 解析失败都要在日志里可见，
        // 否则「卡片位置回传有没有成功」无从判断。
        debugPrint('[main] overlay message handling failed: $e');
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

  /// 横竖屏切换后：把原生悬浮窗重新贴回整块屏幕。
  Future<void> refreshWindowForOrientation() =>
      _platform.refreshWindowForOrientation();

  /// 显示 / 隐藏悬浮窗窗口本身（不销毁服务与引擎）。
  ///
  /// 设置界面打开期间用它把原生窗口缩成 0×0，避免可触摸的全屏悬浮窗
  /// 在横屏下遮挡主应用自己的控件。
  Future<void> setWindowVisible(bool visible) =>
      NativeOverlay.setWindowVisible(visible);

  /// 只切换悬浮窗内容的可见性（不重建 / 不移动卡片）。
  Future<void> setCardsVisible(bool visible) =>
      _platform.setCardsVisible(visible);

  /// 主应用界面（设置 / 调整）是否正在显示。
  ///
  /// 平台层据此决定悬浮窗内容是否隐藏；并且会记住这个意图，等悬浮窗引擎就绪
  /// 时补发，避免“界面已切走、悬浮窗却仍然隐藏”的时序问题。
  void setPageVisible(bool visible) {
    _platform.setPageVisible(visible);
    onPageStateChanged?.call(visible);
  }

  /// 告知平台层：卡片坐标属于哪块屏幕（宽 / 高，逻辑像素）。
  ///
  /// 必须与卡片数据一起下发，否则悬浮窗引擎无法判断该不该把坐标旋转 90°，
  /// 旋转后卡片就会错位 / 被裁剪。
  void setSourceScreen(Size size) {
    _sourceScreen = size;
    _platform.setSourceScreen(size);
  }

  /// 主应用移到后台（让悬浮窗显示在其他应用之上）。
  Future<void> moveToBackground() => _platform.moveToBackground();
}
