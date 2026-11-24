// ignore_for_file: deprecated_member_use

import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/legacy.dart';

/// 负责主界面“穿透 / 置顶 / 透明 / 铺满屏幕”这些与平台窗口相关的设置。
///
/// 关于“铺满屏幕”：
///   窗口的「无边框 + 置顶 + 铺满整个显示器」由 Windows 原生层
///   （见 windows/runner/win32_window.cpp 的 `MakeOverlayFullscreen`）在
///   应用启动时就完成，最可靠。Dart 侧不再用 `setBounds` 去算坐标 / 缩放，
///   因为 `window_manager` 的 bounds 与显示器物理像素 / DPI 之间的换算在
///   不同环境下并不一致，反而会把已经铺满的窗口“改小 / 挪偏”。
///   这里只负责穿透、透明、以及再次确认置顶。
class OverlayService {
  OverlayService._();

  static final OverlayService instance = OverlayService._();

  WindowManager get _wm => WindowManager.instance;

  static bool get _isDesktop =>
      !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

  /// 应用启动时的窗口初始化（仅桌面端有效）。
  Future<void> initWindowForOverlay() async {
    if (!_isDesktop) return;
    // 原生层已经把窗口设为无边框 / 置顶 / 铺满屏幕；这里只处理 Flutter 侧
    // 需要的透明背景与穿透，并对无边框 / 置顶再做一次“兜底确认”。
    await _wm.setAsFrameless();
    await _wm.setAlwaysOnTop(true);
    await _wm.setBackgroundColor(const Color(0x00000000));
    await _wm.setHasShadow(false);
    // 默认让整个窗口穿透。
    await setClickThrough(true);
  }

  /// 再次确认窗口“无边框 + 置顶”。
  ///
  /// 注意：不做任何 `setBounds` / 缩放换算——铺满屏幕完全交给原生层，
  /// 避免与原生窗口尺寸互相拉扯。保留此方法是为了兼容既有调用点。
  Future<void> ensureCoverScreen() async {
    if (!_isDesktop) return;
    await _wm.setAsFrameless();
    await _wm.setAlwaysOnTop(true);
  }

  /// 让整个窗口是否“穿透”鼠标事件。
  ///
  /// [clickThrough] 为 true 时，鼠标/触摸事件会传递给下面的其他应用。
  Future<void> setClickThrough(bool clickThrough) async {
    if (!_isDesktop) return;
    await _wm.setIgnoreMouseEvents(clickThrough, forward: true);
  }

  /// 兼容命名：设置窗口是否拦截交互（与 [setClickThrough] 相反）。
  Future<void> setInteractive(bool interactive) =>
      setClickThrough(!interactive);

  /// 切换主界面 / 设置界面的置顶状态。
  Future<void> setAlwaysOnTop(bool value) async {
    if (!_isDesktop) return;
    await _wm.setAlwaysOnTop(value);
  }

  /// 关闭应用（桌面端用 WindowManager，保证资源释放）。
  Future<void> closeApp() async {
    if (_isDesktop) {
      await _wm.destroy();
    }
  }

  /// 查询全局鼠标光标位置（物理像素，屏幕坐标）。
  ///
  /// 仅 Windows 端实现（见 windows/runner/flutter_window.cpp）；其他平台返回 null。
  /// 用途：窗口整体穿透时，仍能感知光标是否进入“设置”按钮热区，从而临时
  /// 关闭穿透，让按钮可以点击。
  static const MethodChannel _cursorChannel =
      MethodChannel('vocab_overlay/cursor');

  Future<Offset?> getGlobalCursorPos() async {
    if (!(!kIsWeb && Platform.isWindows)) return null;
    try {
      final result =
          await _cursorChannel.invokeMapMethod<String, dynamic>('getCursorPos');
      if (result == null) return null;
      final x = (result['x'] as num?)?.toDouble();
      final y = (result['y'] as num?)?.toDouble();
      if (x == null || y == null) return null;
      return Offset(x, y);
    } catch (_) {
      return null;
    }
  }
}

