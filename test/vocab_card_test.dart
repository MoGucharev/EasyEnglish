import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_overlay/models/vocab_card.dart';

void main() {
  group('VocabCard 序列化', () {
    test('toJson / fromJson 往返一致', () {
      const card = VocabCard(
        english: 'apple',
        chinese: '苹果',
        x: 12.5,
        y: 30.0,
        width: 210,
        height: 90,
      );

      final json = card.toJson();
      final restored = VocabCard.fromJson(json);

      expect(restored.english, card.english);
      expect(restored.chinese, card.chinese);
      expect(restored.x, card.x);
      expect(restored.y, card.y);
      expect(restored.width, card.width);
      expect(restored.height, card.height);
    });

    test('fromJson 对缺失字段有默认值', () {
      final restored = VocabCard.fromJson({});
      expect(restored.english, '');
      expect(restored.chinese, '');
      expect(restored.x, 0);
      expect(restored.y, 0);
      expect(restored.width, greaterThan(0));
      expect(restored.height, greaterThan(0));
    });
  });

  group('VocabCard 变换', () {
    test('movedTo 更新坐标且保留内容', () {
      const card = VocabCard(english: 'dog', chinese: '狗', x: 0, y: 0);
      final moved = card.movedTo(const Offset(100, 200));
      expect(moved.x, 100);
      expect(moved.y, 200);
      expect(moved.english, 'dog');
      expect(moved.chinese, '狗');
    });

    test('copyWith 只修改指定字段', () {
      const card = VocabCard(english: 'cat', chinese: '猫', x: 5, y: 6);
      final updated = card.copyWith(chinese: '猫咪');
      expect(updated.chinese, '猫咪');
      expect(updated.english, 'cat');
      expect(updated.x, 5);
      expect(updated.y, 6);
    });
  });
}
