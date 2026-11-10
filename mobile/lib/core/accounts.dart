import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/models.dart';

/// Cuenta con sesión abierta en este teléfono (para cambiar entre cuentas sin volver a escribir la contraseña).
class SavedAccount {
  SavedAccount({required this.id, required this.username, required this.displayName, this.avatarUrl, this.verified = false, required this.token});

  factory SavedAccount.fromJson(Json j) => SavedAccount(
        id: asInt(j['id']),
        username: asStr(j['username']),
        displayName: asStr(j['display_name']),
        avatarUrl: asStrOrNull(j['avatar_url']),
        verified: asBool(j['is_verified']),
        token: asStr(j['token']),
      );

  factory SavedAccount.of(User u, String token) =>
      SavedAccount(id: u.id, username: u.username, displayName: u.displayName, avatarUrl: u.avatarUrl, verified: u.isVerified, token: token);

  final int id;
  final String username;
  final String displayName;
  final String? avatarUrl;
  final bool verified;
  final String token;

  /// Para pintar el avatar con los widgets de siempre.
  User get user => User.fromJson({'id': id, 'username': username, 'display_name': displayName, 'avatar_url': avatarUrl, 'is_verified': verified});

  Json toJson() => {'id': id, 'username': username, 'display_name': displayName, 'avatar_url': avatarUrl, 'is_verified': verified, 'token': token};
}

/// Lista de cuentas guardadas, en el llavero / almacenamiento cifrado (como el token de la sesión activa).
class AccountStore {
  AccountStore(this._storage);

  static const _key = 'trevix_accounts';
  static const max = 5;

  final FlutterSecureStorage _storage;

  Future<List<SavedAccount>> read() async {
    try {
      final raw = await _storage.read(key: _key);
      if (raw == null || raw.isEmpty) return [];
      final list = jsonDecode(raw);
      if (list is! List) return [];
      return [
        for (final e in list)
          if (e is Map) SavedAccount.fromJson(asMap(e)),
      ].where((a) => a.id > 0 && a.token.isNotEmpty).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> write(List<SavedAccount> accounts) async {
    if (accounts.isEmpty) {
      await _storage.delete(key: _key);
    } else {
      await _storage.write(key: _key, value: jsonEncode([for (final a in accounts) a.toJson()]));
    }
  }
}
