import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vocab_overlay/utils/screen_metrics.dart';

/// 横竖屏「布局旋转」的回归测试。
///
/// 覆盖的故障现象：竖屏摆好两张词汇卡（一张靠上、一张靠下），切到横屏 /
/// 别的应用后，**下方那张卡被覆盖 / 被吞掉**。
///
/// 根因：悬浮窗里的 Flutter 视图切到横屏后，视图本身已经是「横屏的宽 × 高」，
/// 但它**不会重新布局** —— 竖屏下摆好的卡片坐标原样留在竖屏位置，下面那张的
/// y 在横屏里越界，被 clamp 到屏幕底部。
///
/// 正确行为：整份布局跟着方向一起旋转 90°（相对排布不变、且一定在屏幕内）。
void main() {
  const portrait = Size(400, 800);
  const landscape = Size(800, 400);
  const cardW = 200.0;
  const cardH = 84.0;

  Offset map(Offset pos, Size source, Size screen) => ScreenMetrics.mapPosition(
    pos: pos,
    source: source,
    screen: screen,
    cardWidth: cardW,
    cardHeight: cardH,
  );

  /// 断言卡片完整落在屏幕内。
  void expectInside(Offset pos, Size screen, {String? reason}) {
    expect(pos.dx, greaterThanOrEqualTo(0), reason: reason);
    expect(pos.dy, greaterThanOrEqualTo(0), reason: reason);
    expect(
      pos.dx + cardW <= screen.width + 0.5,
      isTrue,
      reason: '$reason 超出宽度: $pos / ${ScreenMetrics.describe(screen)}',
    );
    expect(
      pos.dy + cardH <= screen.height + 0.5,
      isTrue,
      reason: '$reason 超出高度: $pos / ${ScreenMetrics.describe(screen)}',
    );
  }

  test('方向不变：位置原样保留', () {
    expect(map(const Offset(40, 300), portrait, portrait), const Offset(40, 300));
    expect(
      map(const Offset(600, 100), landscape, landscape),
      const Offset(600, 100),
    );
  });

  test('竖屏 → 横屏：两张卡的相对排布保持（下方那张不再被夹到底部）', () {
    // 原始：upper 在上（y 小），lower 在下（y 大，横屏下 600 已越界）。
    const upper = Offset(100, 100);
    const lower = Offset(100, 600);

    final upperL = map(upper, portrait, landscape);
    final lowerL = map(lower, portrait, landscape);

    expectInside(upperL, landscape, reason: 'upper');
    expectInside(lowerL, landscape, reason: 'lower');

    // 顺时针旋转 90°：原来在上方的卡转到右侧，在下方的卡转到左侧。
    expect(upperL.dx, greaterThan(lowerL.dx));
    // 两张卡不能重合（旧实现里 lower 被夹到屏幕底部，与 upper 叠在一起）。
    expect(upperL, isNot(lowerL));
  });

  test('旋转后的坐标一定在屏幕内（永不越界）', () {
    for (final pos in const [
      Offset(0, 0),
      Offset(390, 790),
      Offset(200, 400),
      Offset(10, 700),
    ]) {
      expectInside(map(pos, portrait, landscape), landscape, reason: '$pos');
    }
  });

  test('映射幂等：同一方向重复应用不会漂移', () {
    const pos = Offset(120, 520);
    final once = map(pos, portrait, landscape);
    final twice = map(once, landscape, landscape);
    expect(twice, once);
    expect(map(twice, landscape, landscape), once);
  });

  test('转过去再转回来：落在屏幕内的坐标往返稳定', () {
    // 竖屏里离下边缘 84+ 的位置（横屏下 600 会越界，旋转时必然被夹一次，
    // 那是「宁可少动一点也不画出屏幕」的有意取舍，见下一条测试）。
    const pos = Offset(100, 300);
    final rotated = map(pos, portrait, landscape);
    expectInside(rotated, landscape);
    expect(map(rotated, landscape, portrait), pos);
  });

  test('越界坐标被夹取是幂等的：不会来回漂移', () {
    // 600 在竖屏里离下边缘只剩 116，转成横屏后必须夹到 screen.height - cardH。
    const pos = Offset(100, 600);
    final once = map(pos, portrait, landscape);
    expectInside(once, landscape);
    // 以横屏为参考再映射一次，结果不变（不会继续往左上漂）。
    final twice = map(once, landscape, landscape);
    expect(twice, once);
  });

  test('非法尺寸：原样返回，不做任何映射', () {
    const pos = Offset(30, 40);
    expect(map(pos, Size.zero, landscape), pos);
    expect(map(pos, portrait, Size.zero), pos);
  });
}
