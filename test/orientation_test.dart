import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vocab_overlay/models/vocab_card.dart';
import 'package:vocab_overlay/screens/main_screen.dart';
import 'package:vocab_overlay/widgets/vocab_card_view.dart';

/// 横竖屏适配回归测试。
///
/// 覆盖的问题：卡片坐标是「逻辑像素 + 屏幕坐标」。如果渲染时用的屏幕尺寸与
/// 当前方向不一致（横屏用竖屏尺寸，或反之），卡片就会被画到可视区之外 /
/// 被夹进一个比屏幕小的区域 —— 也就是「横屏后卡片跑偏 / 被吞掉」。
void main() {
  /// 以指定屏幕尺寸渲染主界面。
  ///
  /// 每个 testWidgets 只能调用一次：测试框架的 devicePixelRatio 覆盖项一旦
  /// 被设置，就不允许在同一测试内再次设置（即使值相同）。同一测试内的旋转
  /// 直接修改 `tester.view.physicalSize` 即可。
  Future<void> pumpMainScreen(
    WidgetTester tester, {
    required Size screen,
    required List<VocabCard> cards,
  }) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = screen;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      // 用 fromView 让 MediaQuery 跟随视图尺寸（与真实 App 的 MaterialApp
      // 行为一致），否则旋转后 MediaQuery.size 仍停留在旧值。
      MediaQuery.fromView(
        view: tester.view,
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: MainScreen(cards: cards, onOpenSettings: () {}),
        ),
      ),
    );
    await tester.pump();
  }

  /// 断言当前渲染出的所有卡片都落在 [screen] 之内。
  void expectAllInside(WidgetTester tester, Size screen) {
    const eps = 0.01;
    final found = find.byType(VocabCardView).evaluate().toList();
    expect(found, isNotEmpty, reason: '应当至少渲染出一张卡片');
    for (final element in found) {
      final rect = tester.getRect(find.byWidget(element.widget));
      expect(rect.top, greaterThanOrEqualTo(-eps));
      expect(rect.left, greaterThanOrEqualTo(-eps));
      expect(rect.bottom, lessThanOrEqualTo(screen.height + eps));
      expect(rect.right, lessThanOrEqualTo(screen.width + eps));
    }
  }

  testWidgets('竖屏：坐标合法的卡片按原坐标渲染', (tester) async {
    await pumpMainScreen(
      tester,
      screen: const Size(400, 800),
      cards: const [VocabCard(english: 'apple', chinese: '苹果', x: 40, y: 300)],
    );

    expect(
      tester.getTopLeft(find.byType(VocabCardView)),
      const Offset(40, 300),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('横屏：坐标合法的卡片按原坐标渲染', (tester) async {
    await pumpMainScreen(
      tester,
      screen: const Size(800, 400),
      cards: const [
        VocabCard(english: 'apple', chinese: '苹果', x: 600, y: 200),
      ],
    );

    expect(
      tester.getTopLeft(find.byType(VocabCardView)),
      const Offset(600, 200),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('横屏：竖屏时合法的 y 被拉回横屏可视区', (tester) async {
    // y = 700：竖屏 (400x800) 合法，横屏 (800x400) 不合法。
    await pumpMainScreen(
      tester,
      screen: const Size(800, 400),
      cards: const [VocabCard(english: 'apple', chinese: '苹果', x: 10, y: 700)],
    );

    expectAllInside(tester, const Size(800, 400));
    expect(tester.takeException(), isNull);
  });

  testWidgets('竖屏：横屏时合法的 x 被拉回竖屏可视区', (tester) async {
    // x = 700：横屏 (800x400) 合法，竖屏 (400x800) 不合法。
    await pumpMainScreen(
      tester,
      screen: const Size(400, 800),
      cards: const [VocabCard(english: 'apple', chinese: '苹果', x: 700, y: 10)],
    );

    expectAllInside(tester, const Size(400, 800));
    expect(tester.takeException(), isNull);
  });

  testWidgets('主界面旋转（didChangeMetrics）后布局跟着方向旋转', (tester) async {
    await pumpMainScreen(
      tester,
      screen: const Size(400, 800),
      cards: const [VocabCard(english: 'apple', chinese: '苹果', x: 10, y: 700)],
    );
    expect(tester.getTopLeft(find.byType(VocabCardView)), const Offset(10, 700));

    // 模拟系统旋转：视图尺寸变化 → Flutter 派发 metrics changed。
    //
    // 期望：布局跟着坐标系旋转 90°（而不是把竖屏坐标原样搬过去后被夹到屏幕
    // 底部 —— 那正是「下方词汇卡被覆盖」的来源）。卡片必须完整落在横屏
    // 可视区内，且位置确实变了。
    tester.view.physicalSize = const Size(800, 400);
    await tester.pumpAndSettle();
    expectAllInside(tester, const Size(800, 400));
    expect(
      tester.getTopLeft(find.byType(VocabCardView)),
      isNot(const Offset(10, 700)),
    );
    expect(tester.takeException(), isNull);

    // 再转回竖屏：往返稳定，卡片回到原坐标（不会被逐步改写 / 漂移）。
    tester.view.physicalSize = const Size(400, 800);
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(find.byType(VocabCardView)),
      const Offset(10, 700),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('多张卡片在两种方向下来回切换都不越界', (tester) async {
    await pumpMainScreen(
      tester,
      screen: const Size(400, 800),
      cards: const [
        VocabCard(english: 'a', chinese: '甲', x: 200, y: 500),
        VocabCard(english: 'b', chinese: '乙', x: 350, y: 20),
      ],
    );
    expectAllInside(tester, const Size(400, 800));

    tester.view.physicalSize = const Size(800, 400);
    await tester.pumpAndSettle();
    expectAllInside(tester, const Size(800, 400));

    tester.view.physicalSize = const Size(400, 800);
    await tester.pumpAndSettle();
    expectAllInside(tester, const Size(400, 800));

    expect(tester.takeException(), isNull);
  });
}
