import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vocab_overlay/models/card_style.dart';
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

  group('VocabCard 字体样式', () {
    test('默认字体颜色为白色、字号为默认值', () {
      const card = VocabCard(english: 'a', chinese: '啊', x: 0, y: 0);
      expect(card.fontColor, Colors.white);
      expect(card.fontSize, VocabCard.defaultFontSize);
    });

    test('中文字号为英文字号的 0.8 倍', () {
      const card = VocabCard(
        english: 'a',
        chinese: '啊',
        x: 0,
        y: 0,
        fontSize: 30,
      );
      expect(card.chineseFontSize, 24);
    });

    test('字体颜色（含透明度）与字号可序列化往返', () {
      const color = Color(0x80FF8800);
      final card = VocabCard(
        english: 'orange',
        chinese: '橙色',
        x: 1,
        y: 2,
        fontColor: color,
        fontSize: 28,
      );
      final restored = VocabCard.fromJson(card.toJson());
      expect(restored.fontColor, color);
      expect(restored.fontSize, 28);
    });

    test('fromJson 对缺失的字体字段使用默认值', () {
      final restored = VocabCard.fromJson({'english': 'x'});
      expect(restored.fontColor, Colors.white);
      expect(restored.fontSize, VocabCard.defaultFontSize);
    });

    test('fromJson 把越界字号夹回允许范围', () {
      final tooBig = VocabCard.fromJson({'fontSize': 9999});
      expect(tooBig.fontSize, VocabCard.maxFontSize);
      final tooSmall = VocabCard.fromJson({'fontSize': 1});
      expect(tooSmall.fontSize, VocabCard.minFontSize);
    });
  });

  group('CardStyle 样式', () {
    test('fromId 识别已知样式', () {
      expect(CardStyle.fromId('borderless'), CardStyle.borderless);
      expect(CardStyle.fromId('bordered'), CardStyle.bordered);
    });

    test('fromId 对未知 / 缺失值回退到有边框', () {
      expect(CardStyle.fromId(null), CardStyle.bordered);
      expect(CardStyle.fromId('unknown'), CardStyle.bordered);
    });

    test('id 可往返还原', () {
      expect(CardStyle.fromId(CardStyle.borderless.id), CardStyle.borderless);
      expect(CardStyle.fromId(CardStyle.bordered.id), CardStyle.bordered);
    });
  });
}
