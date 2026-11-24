import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/vocab_card.dart';

/// 负责词汇卡的持久化存储。
///
/// 将词汇卡列表（数量隐含在列表长度中、位置、英文、中文）序列化为 JSON
/// 写入本地存储，应用启动时读取还原。
class StorageService {
  static const String _key = 'vocab_cards_v1';

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
}
