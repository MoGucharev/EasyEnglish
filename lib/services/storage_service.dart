import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/card_style.dart';
import '../models/vocab_card.dart';

/// 应用设置（目前只有词汇卡的整体样式）。
class AppSettings {
  /// 词汇卡整体外观样式。
  final CardStyle cardStyle;

  const AppSettings({this.cardStyle = CardStyle.bordered});

  AppSettings copyWith({CardStyle? cardStyle}) =>
      AppSettings(cardStyle: cardStyle ?? this.cardStyle);

  Map<String, dynamic> toJson() => {'cardStyle': cardStyle.id};

  factory AppSettings.fromJson(Map<String, dynamic> json) =>
      AppSettings(cardStyle: CardStyle.fromId(json['cardStyle']));
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
