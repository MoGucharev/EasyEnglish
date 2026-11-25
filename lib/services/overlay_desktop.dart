// ignore_for_file: deprecated_member_use

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/legacy.dart';

import 'overlay_platform.dart';

/// 桌面端（Windows / macOS / Linux）的 [OverlayPlatform] 实现。
///
/// 这里的逻辑与原 `OverlayService` 完全一致，只是被「搬进」了实现类，
/// 方法签名与行为均保持不变，以保证桌面端零回归。
///
/// 关于“铺满屏幕”：
///   窗口的「无边框 + 置顶 + 铺满整个显示器」由 Windows 原生层
///   （见 windows/runner/win32_window.cpp 的 `MakeOverlayFullscreen`）在
///   应用启动时就完成，最可靠。Dart 侧不再用 `setBounds` 去算坐标 / 缩放，
///   因为 `window_manager` 的 bounds 与显示器物理像素 / DPI 之间的换算在
///   不同环境下并不一致，反而会把已经铺满的窗口“改小 / 挪偏”。
///   这里只负责穿透、透明、以及再次确认置顶。
class DesktopOverlayPlatform implements OverlayPlatform {
  WindowManager get _wm => WindowManager.instance;

  static const MethodChannel _cursorChannel =
      MethodChannel('vocab_overlay/cursor');

  @override
  Future<void> initWindowForOverlay() async {
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
  @override
  Future<void> ensureCoverScreen() async {
    await _wm.setAsFrameless();
    await _wm.setAlwaysOnTop(true);
  }

  @override
  Future<void> setClickThrough(bool clickThrough) async {
    await _wm.setIgnoreMouseEvents(clickThrough, forward: true);
  }

  @override
  Future<void> setInteractive(bool interactive) =>
      setClickThrough(!interactive);

  @override
  Future<void> setAlwaysOnTop(bool value) async {
    await _wm.setAlwaysOnTop(value);
  }

  /// 关闭应用（桌面端用 WindowManager，保证资源释放）。
  ///
  /// 其他平台回退为退出进程。
  @override
  Future<void> closeApp() async {
    try {
      await _wm.destroy();
      return;
    } catch (_) {
      // 某些环境 destroy 可能失败，回退到进程退出。
    }
    exit(0);
  }

  @override
  Future<Offset?> getGlobalCursorPos() async {
    if (!Platform.isWindows) return null;
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

/// 是否为桌面平台。
bool isDesktopPlatform() =>
    !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);
