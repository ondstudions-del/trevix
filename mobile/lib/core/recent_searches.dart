import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';

/// Cuentas abiertas desde la búsqueda, guardadas solo en este dispositivo (máximo 12, la más reciente primero).
class RecentSearches extends ValueNotifier<List<User>> {
  RecentSearches() : super(const []);

  static const _key = 'trevix_recent_people';
  static const _max = 12;
  bool _loaded = false;

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null) return;
      final list = jsonDecode(raw);
      if (list is List) value = list.whereType<Map>().map((m) => User.fromJson(asMap(m))).where((u) => u.id > 0).toList();
    } catch (_) {
      value = const [];
    }
  }

  Future<void> add(User user) async {
    value = [user, ...value.where((u) => u.id != user.id)].take(_max).toList();
    await _save();
  }

  Future<void> remove(int id) async {
    value = value.where((u) => u.id != id).toList();
    await _save();
  }

  Future<void> clear() async {
    value = const [];
    await _save();
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode([
        for (final u in value)
          {'id': u.id, 'username': u.username, 'display_name': u.displayName, 'avatar_url': u.avatarUrl, 'is_verified': u.isVerified},
      ]),
    );
  }
}

final recentSearches = RecentSearches();
