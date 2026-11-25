import 'dart:ui' show Offset;

import 'overlay_desktop.dart';
import 'overlay_mobile.dart';
import 'overlay_platform.dart';

/// 负责主界面“穿透 / 置顶 / 透明 / 铺满屏幕 / 全局光标”等与平台窗口相关的
/// 能力的**统一入口**。
///
/// 实现上按平台委派给 [OverlayPlatform]：
///  * 桌面端 → [DesktopOverlayPlatform]（window_manager + Windows 原生通道）；
///  * 移动端 → [MobileOverlayPlatform]（当前为 no-op 占位）。
///
/// 说明：此类的公开 API（[instance] 及所有方法）与重构前保持一致，
/// 既有调用点（main / 各界面）无需任何改动，桌面端行为零回归。
class OverlayService {
  OverlayService._(this._platform);

  /// 用指定的平台实现构造（便于测试注入）。
  factory OverlayService.withPlatform(OverlayPlatform platform) =>
      OverlayService._(platform);

  /// 全局单例：按运行平台自动选择实现。
  static final OverlayService instance = OverlayService._(defaultPlatform());

  final OverlayPlatform _platform;

  /// 根据运行平台选择默认实现。
  static OverlayPlatform defaultPlatform() {
    if (isDesktopPlatform()) {
      return DesktopOverlayPlatform();
    }
    return MobileOverlayPlatform();
  }

  /// 当前使用的平台实现（便于测试注入 / 排查）。
  OverlayPlatform get platform => _platform;

  /// 应用启动时的窗口初始化（仅桌面端有效）。
  Future<void> initWindowForOverlay() => _platform.initWindowForOverlay();

  /// 再次确认窗口“无边框 + 置顶”（桌面端；铺满屏幕交给原生层）。
  Future<void> ensureCoverScreen() => _platform.ensureCoverScreen();

  /// 让整个窗口是否“穿透”鼠标事件。
  ///
  /// [clickThrough] 为 true 时，鼠标/触摸事件会传递给下面的其他应用。
  Future<void> setClickThrough(bool clickThrough) =>
      _platform.setClickThrough(clickThrough);

  /// 兼容命名：设置窗口是否拦截交互（与 [setClickThrough] 相反）。
  Future<void> setInteractive(bool interactive) =>
      _platform.setInteractive(interactive);

  /// 切换主界面 / 设置界面的置顶状态。
  Future<void> setAlwaysOnTop(bool value) => _platform.setAlwaysOnTop(value);

  /// 关闭应用。
  Future<void> closeApp() => _platform.closeApp();

  /// 查询全局鼠标光标位置（物理像素，屏幕坐标）。不支持的平台返回 null。
  ///
  /// 用途：窗口整体穿透时，仍能感知光标是否进入“设置”按钮热区，从而临时
  /// 关闭穿透，让按钮可以点击。
  Future<Offset?> getGlobalCursorPos() => _platform.getGlobalCursorPos();
}
