import 'dart:ui' show Offset;

/// 平台相关的窗口 / 穿透能力抽象。
///
/// 之所以抽成接口，是为了把「桌面端（window_manager + Windows 原生通道）」
/// 与「移动端（原生悬浮窗）」解耦：
///  * 桌面端：整窗穿透、置顶、透明、全局光标轮询；
///  * 移动端：暂无系统级穿透，这里提供空实现（no-op），业务代码无需感知。
///
/// 调用方统一通过 [OverlayService.instance] 使用，不直接依赖具体平台实现。
abstract class OverlayPlatform {
  /// 应用启动时的窗口初始化（透明 / 穿透 / 置顶 / 无边框）。
  Future<void> initWindowForOverlay();

  /// 再次确认窗口「无边框 + 置顶 / 铺满屏幕」。
  Future<void> ensureCoverScreen();

  /// 设置整窗是否「穿透」鼠标 / 触摸事件。
  Future<void> setClickThrough(bool clickThrough);

  /// 设置窗口是否拦截交互（与 [setClickThrough] 相反）。
  Future<void> setInteractive(bool interactive);

  /// 设置窗口置顶。
  Future<void> setAlwaysOnTop(bool value);

  /// 关闭应用。
  Future<void> closeApp();

  /// 查询全局光标位置（物理像素，屏幕坐标）。不支持的平台返回 null。
  Future<Offset?> getGlobalCursorPos();
}
