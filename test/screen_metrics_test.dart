import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vocab_overlay/utils/screen_metrics.dart';

void main() {
  group('ScreenMetrics.clampPosition', () {
    test('屏幕内位置保持不变', () {
      final pos = ScreenMetrics.clampPosition(
        pos: const Offset(200, 300),
        screen: const Size(400, 800),
        cardWidth: 200,
        cardHeight: 84,
      );
      expect(pos, const Offset(200, 300));
    });

    test('允许贴边：右下角最多到 屏幕 - 卡片尺寸', () {
      final pos = ScreenMetrics.clampPosition(
        pos: const Offset(9999, 9999),
        screen: const Size(400, 800),
        cardWidth: 200,
        cardHeight: 84,
      );
      expect(pos, const Offset(200, 716));
    });

    test('负坐标被拉到左上角', () {
      final pos = ScreenMetrics.clampPosition(
        pos: const Offset(-50, -50),
        screen: const Size(400, 800),
        cardWidth: 200,
        cardHeight: 84,
      );
      expect(pos, Offset.zero);
    });

    test('横屏 → 竖屏：原先合法的 y 被拉回竖屏底部之内', () {
      final card = Size(200, 84);
      // 竖屏 x=10,y=700：在竖屏 (400x800) 下合法（700+84=784 <= 800）。
      expect(700.0 + card.height <= 800, isTrue);

      // 切到横屏 (800x400)：700+84 > 400，必须被夹到 400-84=316。
      final pos = ScreenMetrics.clampPosition(
        pos: const Offset(10, 700),
        screen: const Size(800, 400),
        cardWidth: card.width,
        cardHeight: card.height,
      );
      expect(pos, const Offset(10, 316));

      // 切回竖屏：原坐标重新合法，保持不变。
      final pos2 = ScreenMetrics.clampPosition(
        pos: const Offset(10, 700),
        screen: const Size(400, 800),
        cardWidth: card.width,
        cardHeight: card.height,
      );
      expect(pos2, const Offset(10, 700));
    });

    test('屏幕比卡片还小时不会出现负的上界', () {
      final pos = ScreenMetrics.clampPosition(
        pos: const Offset(100, 100),
        screen: const Size(120, 50),
        cardWidth: 200,
        cardHeight: 84,
      );
      expect(pos, Offset.zero);
    });

    test('非法屏幕尺寸原样返回（不把卡片夹到错误坐标系）', () {
      const original = Offset(123, 456);
      expect(
        ScreenMetrics.clampPosition(
          pos: original,
          screen: Size.zero,
          cardWidth: 200,
          cardHeight: 84,
        ),
        original,
      );
    });
  });

  group('ScreenMetrics.isPlausible', () {
    test('null / 非正数不可信', () {
      expect(ScreenMetrics.isPlausible(null, const Size(400, 800)), isFalse);
      expect(
        ScreenMetrics.isPlausible(Size.zero, const Size(400, 800)),
        isFalse,
      );
    });

    test('与视图尺寸吻合时可信', () {
      expect(
        ScreenMetrics.isPlausible(const Size(800, 400), const Size(800, 400)),
        isTrue,
      );
      // 小幅误差（dp 取整）仍可信。
      expect(
        ScreenMetrics.isPlausible(const Size(792, 398), const Size(800, 400)),
        isTrue,
      );
    });

    test('横屏下原生结果与视图尺寸差异过大时不可信', () {
      // 典型故障：density 没跟随横屏，原生给出的尺寸明显偏小。
      expect(
        ScreenMetrics.isPlausible(const Size(400, 800), const Size(800, 400)),
        isFalse,
      );
    });
  });

  test('describe 输出稳定的尺寸标识', () {
    expect(ScreenMetrics.describe(const Size(802.4, 397.6)), '802.4x397.6');
  });
}
