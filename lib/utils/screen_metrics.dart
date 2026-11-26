import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

/// 词汇卡坐标系 / 屏幕尺寸的唯一来源。
///
/// ## 为什么需要它（横屏适配）
///
/// 卡片坐标统一使用「逻辑像素，屏幕坐标，原点在屏幕左上角」。此前的实现里，
/// 同一套坐标被三处不同的「屏幕尺寸」夹取，它们在横屏时彼此不一致：
///
///  * 主应用 `MainScreen`：用 `MediaQuery.size`（= 横屏时的宽 × 高）；
///  * 系统悬浮窗引擎 `_OverlayApp`：优先用 `getScreenSize()` 返回的尺寸；
///  * 拖动时的夹取：同样是悬浮窗引擎里用的那个尺寸。
///
/// `flutter_overlay_window 1.0.2` 的 `OverlayService.getScreenSize()` 在
/// **横屏**下返回的是 `宽 × 高`，但它的 `density` 取自
/// `getApplicationContext().getResources().getDisplayMetrics().density` ——
/// 这个 density 不一定跟随「当前横竖屏」。一旦两者不匹配，悬浮窗侧的可用区域
/// 就会比主界面小（典型表现：竖屏时摆好的卡片，切到横屏应用后「下半部分被吞掉」）。
///
/// 因此这里统一规则：
///  * **凡是渲染卡片的地方，都用 Flutter 视图自己的 `MediaQuery.size`**
///    （它就是卡片真正被绘制 / 夹取的空间）；
///  * 向原生查询的屏幕尺寸只在「可信」时作为兜底 —— 即两个方向都与视图尺寸
///    相差不超过 [sizeTolerance]，否则视为换算错误并丢弃。
///
/// ## 再记一笔：只有「视图尺寸」还不够（横屏布局的第二层问题）
///
/// 悬浮窗里的视图宽高**已经是横屏的宽 × 高**，但它不会「重新布局」——
/// 竖屏下摆好的卡片坐标会原样留在竖屏位置，下面那张在横屏里越界后被夹到
/// 屏幕底部，看起来就是「被覆盖 / 被吞掉」。所以布局模式必须再多一步
/// [ScreenMetrics.mapPosition]：把竖屏参考尺寸映射到当前视图尺寸，
/// 让整份布局跟着方向旋转 90°。
class ScreenMetrics {
  ScreenMetrics._();

  /// 允许的相对误差：原生查询结果与视图尺寸超出该比例即判定为不可信。
  static const double sizeTolerance = 0.2;

  /// 当前视图的逻辑屏幕尺寸（卡片坐标系）。
  ///
  /// 用 `MediaQuery.sizeOf` 而不是 `MediaQuery.of(context).size`：
  /// 后者会在**任何** MediaQuery 字段变化时触发重建，前者只在尺寸变化时重建。
  static Size of(BuildContext context) => MediaQuery.sizeOf(context);

  /// 安全区（逻辑像素）。仅用于把长期保存的越界坐标拉回可视区。
  static EdgeInsets safePaddingOf(BuildContext context) =>
      MediaQuery.paddingOf(context);

  /// 判断从原生查到的屏幕尺寸是否可信。
  ///
  /// [native] 为 null / 非正数 → 不可信；与 [view] 两个方向的相对误差都
  /// 不超过 [sizeTolerance] 才可信。
  static bool isPlausible(Size? native, Size view) {
    if (native == null) return false;
    if (native.width <= 0 || native.height <= 0) return false;
    if (view.width <= 0 || view.height <= 0) return false;
    final dw = (native.width - view.width).abs() / view.width;
    final dh = (native.height - view.height).abs() / view.height;
    return dw <= sizeTolerance && dh <= sizeTolerance;
  }

  /// 把卡片左上角限制在屏幕内（允许贴边，但不允许拖出屏幕）。
  ///
  /// [screen] 为卡片坐标系下的屏幕尺寸，[cardWidth] / [cardHeight] 为卡片尺寸。
  /// 屏幕尺寸缺失 / 非法时原样返回，避免把卡片夹到一个错误的坐标系里。
  static Offset clampPosition({
    required Offset pos,
    required Size screen,
    required double cardWidth,
    required double cardHeight,
  }) {
    if (screen.width <= 0 || screen.height <= 0) return pos;
    final maxX = math.max(0, screen.width - cardWidth).toDouble();
    final maxY = math.max(0, screen.height - cardHeight).toDouble();
    return Offset(
      pos.dx.clamp(0.0, maxX).toDouble(),
      pos.dy.clamp(0.0, maxY).toDouble(),
    );
  }

  /// 布局模式下的**卡片坐标**映射。
  ///
  /// ## 为什么不能直接按视图的绝对尺寸渲染
  ///
  /// 系统悬浮窗（`TYPE_APPLICATION_OVERLAY`）里的那个 Flutter 视图**不跟随**
  /// Activity 的 `screenOrientation` 重新布局：它自己的宽高本来就是「横屏的
  /// 宽 × 高」（`matchParent` 时就是整块屏幕）。于是竖屏下摆好的两张卡片如果
  /// 按原样搬过去，就仍然停在竖屏的老位置上，下面那张的 y 在横屏里越界、
  /// 被夹到屏幕底部 —— 这正是「上面那张位置变了，下面那张被覆盖」的来源。
  ///
  /// 需求要的是**布局跟着方向一起转**：卡片之间的相对排布（上/下、左/右）
  /// 保持不变，坐标系与可视区一起旋转 90°。因此把「竖屏参考尺寸」
  /// （[source]，即卡片坐标当前所属的方向）直接映射到当前视图尺寸
  /// （[screen]）：
  ///
  ///  * 方向相同：等价于直接用视图尺寸，去掉方向前缀即可；
  ///  * 方向不同：再叠加一次 90° 顺时针旋转，`(x, y)` → `(W - y - w, x)`。
  ///
  /// 映射是**幂等**的：对已经映射过的坐标再调用一次，结果不变。所以在
  /// 「旋转后重新下发坐标」「拖动」「保存」等任意路径上重复应用都安全。
  static Offset mapPosition({
    required Offset pos,
    required Size source,
    required Size screen,
    required double cardWidth,
    required double cardHeight,
  }) {
    if (source.width <= 0 ||
        source.height <= 0 ||
        screen.width <= 0 ||
        screen.height <= 0) {
      return pos;
    }
    final sameOrientation =
        (source.width > source.height) == (screen.width > screen.height);
    final moved = sameOrientation
        ? pos
        : Offset(screen.width - pos.dy - cardWidth, pos.dx);
    return clampPosition(
      pos: moved,
      screen: screen,
      cardWidth: cardWidth,
      cardHeight: cardHeight,
    );
  }

  /// 屏幕尺寸的稳定标识（用于日志 / 判断尺寸是否真的变了）。
  static String describe(Size size) =>
      '${size.width.toStringAsFixed(1)}x${size.height.toStringAsFixed(1)}';
}
