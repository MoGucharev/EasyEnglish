import 'package:material_ui/material_ui.dart';

/// 一张词汇卡的数据模型。
///
/// 存储内容：
///  * [english] / [chinese]：卡片上显示的英文和中文；
///  * [x] / [y]：卡片左上角在主界面（屏幕）中的像素坐标；
///  * [width] / [height]：卡片尺寸；
///  * [fontColor]：整张卡片的字体颜色（含透明度）；
///  * [fontSize]：英文的基础字号（中文字号按比例略小）。
///
/// 整体外观（是否有边框）不逐卡存储，而是全局的 CardStyle。
class VocabCard {
  final String english;
  final String chinese;
  final double x;
  final double y;
  final double width;
  final double height;

  /// 字体颜色（ARGB，含透明度）。默认白色，透明背景下清晰可读。
  final Color fontColor;

  /// 英文字号（逻辑像素）。中文字号取它的 0.8 倍（见 [chineseFontSize]）。
  final double fontSize;

  /// 默认字号，也是设置界面“字体大小”输入框里的默认值。
  static const double defaultFontSize = 20;

  /// “字体大小”输入框允许的最小 / 最大字号。
  static const double minFontSize = 8;
  static const double maxFontSize = 96;

  const VocabCard({
    required this.english,
    required this.chinese,
    required this.x,
    required this.y,
    this.width = 200,
    this.height = 84,
    this.fontColor = Colors.white,
    this.fontSize = defaultFontSize,
  });

  Offset get position => Offset(x, y);

  Size get size => Size(width, height);

  Rect get rect => Rect.fromLTWH(x, y, width, height);

  /// 中文字号：按英文的 0.8 倍缩放，保持上下两行视觉比例。
  double get chineseFontSize => fontSize * 0.8;

  VocabCard copyWith({
    String? english,
    String? chinese,
    double? x,
    double? y,
    double? width,
    double? height,
    Color? fontColor,
    double? fontSize,
  }) {
    return VocabCard(
      english: english ?? this.english,
      chinese: chinese ?? this.chinese,
      x: x ?? this.x,
      y: y ?? this.y,
      width: width ?? this.width,
      height: height ?? this.height,
      fontColor: fontColor ?? this.fontColor,
      fontSize: fontSize ?? this.fontSize,
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
    'fontColor': fontColor.toARGB32(),
    'fontSize': fontSize,
  };

  factory VocabCard.fromJson(Map<String, dynamic> json) {
    return VocabCard(
      english: (json['english'] ?? '') as String,
      chinese: (json['chinese'] ?? '') as String,
      x: (json['x'] as num?)?.toDouble() ?? 0,
      y: (json['y'] as num?)?.toDouble() ?? 0,
      width: (json['width'] as num?)?.toDouble() ?? 200,
      height: (json['height'] as num?)?.toDouble() ?? 84,
      fontColor: _colorFromJson(json['fontColor']),
      fontSize: _fontSizeFromJson(json['fontSize']),
    );
  }

  /// 还原字体颜色；缺失 / 非法时沿用默认白色。
  static Color _colorFromJson(Object? raw) {
    if (raw is num) return Color(raw.toInt());
    return Colors.white;
  }

  /// 还原字号；缺失 / 非法时使用默认值，并把越界值夹回允许范围。
  static double _fontSizeFromJson(Object? raw) {
    if (raw is num && raw > 0) {
      return raw.toDouble().clamp(minFontSize, maxFontSize).toDouble();
    }
    return defaultFontSize;
  }
}
