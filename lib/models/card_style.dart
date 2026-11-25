/// 词汇卡的整体外观样式。
enum CardStyle {
  /// 只有字体、无边框（透明背景，仅显示文字）。
  borderless,

  /// 有边框（透明背景 + 圆角描边）。
  bordered;

  /// 用于 JSON 序列化的稳定字符串。
  String get id => name;

  /// 从持久化字符串还原样式；未知 / 缺失时回退到 [CardStyle.bordered]
  /// （旧版本保存的数据没有样式字段，按原来的有边框样式显示）。
  static CardStyle fromId(Object? id) {
    for (final value in CardStyle.values) {
      if (value.name == id) return value;
    }
    return CardStyle.bordered;
  }

  /// 界面上展示的名称。
  String get label {
    switch (this) {
      case CardStyle.borderless:
        return '无边框（仅字体）';
      case CardStyle.bordered:
        return '有边框';
    }
  }
}
