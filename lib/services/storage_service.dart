import 'dart:convert';
import 'dart:ui' show Size;

import 'package:shared_preferences/shared_preferences.dart';

import '../models/card_style.dart';
import '../models/vocab_card.dart';

/// 应用设置（词汇卡整体样式 + 卡片坐标所属的屏幕）。
class AppSettings {
  /// 词汇卡整体外观样式。
  final CardStyle cardStyle;

  /// 保存的卡片坐标属于哪个方向的屏幕（宽 / 高，逻辑像素）。
  ///
  /// 卡片坐标是「相对屏幕的绝对值」，只有配上它当时的屏幕尺寸才能被正确
  /// 映射到另一个方向。缺少它就只能靠猜（例如把横屏保存的坐标当成竖屏坐标
  /// 旋转），旋转会越转越偏 —— 这是「旋转后卡片位置错乱」的根因之一。
  final double? screenWidth;
  final double? screenHeight;

  const AppSettings({
    this.cardStyle = CardStyle.bordered,
    this.screenWidth,
    this.screenHeight,
  });

  /// 以「坐标所属屏幕」构造（width / height 同时给出或都不给）。
  factory AppSettings.withScreen(CardStyle style, Size? screen) => AppSettings(
    cardStyle: style,
    screenWidth: screen?.width,
    screenHeight: screen?.height,
  );

  /// 卡片坐标所属屏幕（两个分量都有效时才有值）。
  Size? get screen {
    final w = screenWidth;
    final h = screenHeight;
    if (w == null || h == null || w <= 0 || h <= 0) return null;
    return Size(w, h);
  }

  AppSettings copyWith({CardStyle? cardStyle, Size? screen}) => AppSettings(
    cardStyle: cardStyle ?? this.cardStyle,
    screenWidth: screen?.width ?? screenWidth,
    screenHeight: screen?.height ?? screenHeight,
  );

  Map<String, dynamic> toJson() => {
    'cardStyle': cardStyle.id,
    if (screenWidth != null) 'screenWidth': screenWidth,
    if (screenHeight != null) 'screenHeight': screenHeight,
  };

  factory AppSettings.fromJson(Map<String, dynamic> json) => AppSettings(
    cardStyle: CardStyle.fromId(json['cardStyle']),
    screenWidth: (json['screenWidth'] as num?)?.toDouble(),
    screenHeight: (json['screenHeight'] as num?)?.toDouble(),
  );
}

/// 负责词汇卡与应用设置的持久化存储。
///
/// 将词汇卡列表（数量隐含在列表长度中、位置、英文、中文、字体颜色、字号）
/// 序列化为 JSON 写入本地存储，应用启动时读取还原。
class StorageService {
  static const String _key = 'vocab_cards_v1';
  static const String _settingsKey = 'vocab_settings_v1';

  Future<List<VocabCard>> loadCards() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return <VocabCard>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return <VocabCard>[];
      return decoded
          .whereType<Map>()
          .map((e) => VocabCard.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } catch (_) {
      return <VocabCard>[];
    }
  }

  Future<void> saveCards(List<VocabCard> cards) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = jsonEncode(cards.map((c) => c.toJson()).toList());
    await prefs.setString(_key, raw);
  }

  /// 读取应用设置；从未保存过时返回默认设置。
  Future<AppSettings> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_settingsKey);
    if (raw == null || raw.isEmpty) return const AppSettings();
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const AppSettings();
      return AppSettings.fromJson(Map<String, dynamic>.from(decoded));
    } catch (_) {
      return const AppSettings();
    }
  }

  Future<void> saveSettings(AppSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_settingsKey, jsonEncode(settings.toJson()));
  }
}

