import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';

/// Bandeja de chats para modo offline (lista de conversaciones ya cargada).
class InboxCache {
  InboxCache._();

  static const _key = 'trevix_inbox_v1';

  static Future<void> save(List<Map<String, dynamic>> raw) async {
    if (raw.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, jsonEncode(raw));
    } catch (_) {}
  }

  static Future<List<Conversation>?> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final s = prefs.getString(_key);
      if (s == null || s.isEmpty) return null;
      final json = jsonDecode(s);
      if (json is! List) return null;
      final out = <Conversation>[];
      for (final e in json) {
        if (e is Map) out.add(Conversation.fromJson(Map<String, dynamic>.from(e)));
      }
      return out.isEmpty ? null : out;
    } catch (_) {
      return null;
    }
  }
}