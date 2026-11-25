import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vocab_overlay/widgets/color_wheel_picker.dart';

void main() {
  testWidgets('ColorWheelPicker inside AlertDialog lays out without errors', (
    tester,
  ) async {
    Color? lastColor;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              return Center(
                child: ElevatedButton(
                  onPressed: () {
                    showDialog<void>(
                      context: context,
                      builder: (dialogContext) {
                        return AlertDialog(
                          title: const Text('字体颜色'),
                          content: SingleChildScrollView(
                            child: ColorWheelPicker(
                              initialColor: Colors.white,
                              size: 220,
                              onChanged: (c) => lastColor = c,
                            ),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () =>
                                  Navigator.of(dialogContext).pop(),
                              child: const Text('确定'),
                            ),
                          ],
                        );
                      },
                    );
                  },
                  child: const Text('open'),
                ),
              );
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // AlertDialog 会按 IntrinsicWidth 布局 content；修复前 LayoutBuilder 会导致
    // “LayoutBuilder does not support returning intrinsic dimensions.” 异常，
    // 表现为只显示变灰遮罩、圆盘和滑条都不出现。
    expect(tester.takeException(), isNull);

    expect(find.byType(ColorWheelPicker), findsOneWidget);
    expect(find.text('透明度'), findsOneWidget);
    expect(find.text('预览'), findsOneWidget);

    // 圆盘与滑条确实被布局（有非零尺寸）。
    final pickerSize = tester.getSize(find.byType(ColorWheelPicker));
    expect(pickerSize.width, greaterThan(0));
    expect(pickerSize.height, greaterThan(0));

    // 拖动透明度滑条应仍然触发颜色回调（验证改用 Builder 读宽度后功能正常）。
    final alphaCenter = tester.getCenter(find.text('透明度'));
    await tester.tapAt(alphaCenter + const Offset(120, 0));
    await tester.pump();
    expect(lastColor, isNotNull);
    expect(tester.takeException(), isNull);
  });
}

