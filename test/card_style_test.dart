import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vocab_overlay/models/card_style.dart';
import 'package:vocab_overlay/models/vocab_card.dart';
import 'package:vocab_overlay/widgets/color_wheel_picker.dart';
import 'package:vocab_overlay/widgets/vocab_card_view.dart';

void main() {
  group('VocabCardView 样式', () {
    testWidgets('有边框样式渲染边框容器', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Center(
            child: VocabCardView(
              card: VocabCard(english: 'apple', chinese: '苹果', x: 0, y: 0),
              style: CardStyle.bordered,
            ),
          ),
        ),
      );
      expect(find.text('apple'), findsOneWidget);
      expect(find.text('苹果'), findsOneWidget);

      final container = tester.widget<Container>(find.byType(Container).first);
      expect(container.decoration, isA<BoxDecoration>());
      final deco = container.decoration as BoxDecoration;
      expect(deco.border, isNotNull);
    });

    testWidgets('无边框样式不渲染边框 / 背景', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Center(
            child: VocabCardView(
              card: VocabCard(english: 'dog', chinese: '狗', x: 0, y: 0),
              style: CardStyle.borderless,
            ),
          ),
        ),
      );
      final container = tester.widget<Container>(find.byType(Container).first);
      final deco = container.decoration as BoxDecoration?;
      expect(deco?.border, isNull);
    });

    testWidgets('使用卡片自身的字体颜色与字号', (tester) async {
      const color = Color(0xFF00FF00);
      await tester.pumpWidget(
        const MaterialApp(
          home: Center(
            child: VocabCardView(
              card: VocabCard(
                english: 'go',
                chinese: '走',
                x: 0,
                y: 0,
                fontColor: color,
                fontSize: 30,
              ),
            ),
          ),
        ),
      );
      final enText = tester.widget<Text>(find.text('go'));
      expect(enText.style?.color, color);
      expect(enText.style?.fontSize, 30);

      final zhText = tester.widget<Text>(find.text('走'));
      expect(zhText.style?.color, color);
      expect(zhText.style?.fontSize, 24); // 0.8 倍
    });
  });

  group('ColorWheelPicker', () {
    testWidgets('渲染并能通过回调改变颜色', (tester) async {
      Color? changed;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: ColorWheelPicker(
                initialColor: Colors.white,
                size: 200,
                onChanged: (c) => changed = c,
              ),
            ),
          ),
        ),
      );
      // 组件正常渲染。
      expect(find.byType(ColorWheelPicker), findsOneWidget);
      expect(find.text('透明度'), findsOneWidget);
      expect(find.text('预览'), findsOneWidget);

      // 拖动透明度滑条应触发颜色回调（透明度变化）。
      final alphaText = find.text('透明度');
      final alphaCenter = tester.getCenter(alphaText);
      // 透明度滑条在“透明度”标签右侧。
      final sliderPoint = alphaCenter + const Offset(120, 0);
      await tester.tapAt(sliderPoint);
      await tester.pump();

      expect(changed, isNotNull);
      expect(tester.takeException(), isNull);
    });
  });
}
