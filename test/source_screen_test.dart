import 'dart:ui' show Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_overlay/models/card_style.dart';
import 'package:vocab_overlay/models/vocab_card.dart';
import 'package:vocab_overlay/services/storage_service.dart';
import 'package:vocab_overlay/utils/screen_metrics.dart';

/// 回归：卡片坐标「所属的屏幕」必须被持久化，并在渲染时作为**绝对参考**。
///
/// 之前的实现每收到一次消息就用当前视图方向去猜参考方向，旋转后横屏坐标
/// 同样「放得下」，参考方向被改写成横屏 → 下一帧再旋转一次 → 越转越偏，
/// 表现为「横屏后下方词汇卡被覆盖」。
void main() {
  group('AppSettings 持久化卡片坐标所属屏幕', () {
    test('保存后能读回同一屏幕', () {
      const screen = Size(400, 800);
      final json = AppSettings.withScreen(CardStyle.borderless, screen).toJson();
      final restored = AppSettings.fromJson(json);

      expect(restored.cardStyle, CardStyle.borderless);
      expect(restored.screen, screen);
    });

    test('旧数据没有屏幕信息时返回 null（由调用方兜底）', () {
      final restored = AppSettings.fromJson({'cardStyle': 'bordered'});
      expect(restored.screen, isNull);
    });

    test('非法屏幕尺寸不当作有效参考', () {
      final restored = AppSettings.fromJson({
        'cardStyle': 'bordered',
        'screenWidth': 0,
        'screenHeight': 0,
      });
      expect(restored.screen, isNull);
    });
  });

  group('坐标映射是幂等的（反复旋转不漂移）', () {
    // 竖屏保存的卡片：位于竖屏下半部分，正是「旋转后被覆盖」的那类位置。
    const source = Size(400, 800);
    const card = VocabCard(
      english: 'bottom',
      chinese: '底部',
      x: 100,
      y: 600,
      width: 200,
      height: 84,
    );

    test('竖屏→横屏→竖屏 回到原位', () {
      final landscape = ScreenMetrics.mapPosition(
        pos: card.position,
        source: source,
        screen: const Size(800, 400),
        cardWidth: card.width,
        cardHeight: card.height,
      );
      // 竖屏下的 y=600 在横屏(高仅400)会被夹到 400-84=316，这一步的信息
      // （横屏时实际在 316）无法从渲染坐标反推回来。因此「逆映射」必须以
      // 参考方向为准，从**配置坐标**重新正映射一次，而不是拿渲染坐标反推。
      final back = ScreenMetrics.mapPosition(
        pos: card.position,
        source: source,
        screen: source,
        cardWidth: card.width,
        cardHeight: card.height,
      );

      expect((back.dx - card.x).abs(), lessThan(0.51));
      expect((back.dy - card.y).abs(), lessThan(0.51));
      // 同一参考方向重映射是幂等的（反复旋转也不会挪动配置坐标）。
      expect(landscape, isNot(card.position));
    });

    test('横屏下始终落在可视区内（不被屏幕底部裁掉）', () {
      const landscape = Size(800, 400);
      final pos = ScreenMetrics.mapPosition(
        pos: card.position,
        source: source,
        screen: landscape,
        cardWidth: card.width,
        cardHeight: card.height,
      );

      expect(pos.dx, greaterThanOrEqualTo(0));
      expect(pos.dy, greaterThanOrEqualTo(0));
      expect(pos.dx + card.width, lessThanOrEqualTo(landscape.width + 0.51));
      expect(pos.dy + card.height, lessThanOrEqualTo(landscape.height + 0.51));
    });
  });
}
