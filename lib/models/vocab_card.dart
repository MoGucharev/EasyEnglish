import 'package:material_ui/material_ui.dart';

/// 一张词汇卡的数据模型。
///
/// 存储内容：
///  * [english] / [chinese]：卡片上显示的英文和中文；
///  * [x] / [y]：卡片左上角在主界面（屏幕）中的像素坐标；
///  * [width] / [height]：卡片尺寸。
class VocabCard {
  final String english;
  final String chinese;
  final double x;
  final double y;
  final double width;
  final double height;

  const VocabCard({
    required this.english,
    required this.chinese,
    required this.x,
    required this.y,
    this.width = 200,
    this.height = 84,
  });

  Offset get position => Offset(x, y);

  Size get size => Size(width, height);

  Rect get rect => Rect.fromLTWH(x, y, width, height);

  VocabCard copyWith({
    String? english,
    String? chinese,
    double? x,
    double? y,
    double? width,
    double? height,
  }) {
    return VocabCard(
      english: english ?? this.english,
      chinese: chinese ?? this.chinese,
      x: x ?? this.x,
      y: y ?? this.y,
      width: width ?? this.width,
      height: height ?? this.height,
    );
  }

  VocabCard movedTo(Offset offset) => copyWith(x: offset.dx, y: offset.dy);

  Map<String, dynamic> toJson() => {
        'english': english,
        'chinese': chinese,
        'x': x,
        'y': y,
        'width': width,
        'height': height,
      };

  factory VocabCard.fromJson(Map<String, dynamic> json) {
    return VocabCard(
      english: (json['english'] ?? '') as String,
      chinese: (json['chinese'] ?? '') as String,
      x: (json['x'] as num?)?.toDouble() ?? 0,
      y: (json['y'] as num?)?.toDouble() ?? 0,
      width: (json['width'] as num?)?.toDouble() ?? 200,
      height: (json['height'] as num?)?.toDouble() ?? 84,
    );
  }
}
