import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';

import 'api.dart';

/// Contenido descifrado de un mensaje cifrado de extremo a extremo.
///
/// JSON dentro del texto cifrado: {"v":1, "t":"text|image|voice|gif|location", "b":"texto",
/// "f":{"k":clave, "m":mime, "s":bytes, "w":ancho, "h":alto, "d":segundos}, "g":{gif}, "l":{"lat","lng","name"}}.
class E2eePayload {
  E2eePayload(this.raw);

  final Map<String, dynamic> raw;

  String get type => '${raw['t'] ?? 'text'}';
  String get body => '${raw['b'] ?? ''}';
  Map<String, dynamic>? get file => raw['f'] is Map ? Map<String, dynamic>.from(raw['f'] as Map) : null;
  Map<String, dynamic>? get gif => raw['g'] is Map ? Map<String, dynamic>.from(raw['g'] as Map) : null;
  Map<String, dynamic>? get location => raw['l'] is Map ? Map<String, dynamic>.from(raw['l'] as Map) : null;
  String? get fileKey => file?['k'] is String ? file!['k'] as String : null;
  String get mime => '${file?['m'] ?? ''}';
  int get duration => (file?['d'] as num?)?.toInt() ?? 0;
  double? get aspect {
    final w = (file?['w'] as num?)?.toDouble() ?? 0;
    final h = (file?['h'] as num?)?.toDouble() ?? 0;
    return w > 0 && h > 0 ? w / h : null;
  }

  /// Resumen en una línea (respuestas, vistas previas).
  String get summary => switch (type) {
        'image' => body.isNotEmpty ? '📷 $body' : '📷 Foto',
        'voice' => '🎤 Nota de voz',
        'gif' => gif?['kind'] == 'sticker' ? 'Sticker' : 'GIF',
        'location' => '📍 Ubicación',
        _ => body,
      };
}

/// Estado del cifrado de la cuenta en el servidor.
class E2eeStatus {
  E2eeStatus(Map<String, dynamic> j)
      : configured = j['configured'] == true,
        keyId = (j['key_id'] as num?)?.toInt(),
        publicKey = j['public_key'] as String?,
        hasBackup = j['has_backup'] == true,
        salt = j['salt'] as String?;

  final bool configured;
  final int? keyId;
  final String? publicKey;
  final bool hasBackup;
  final String? salt;
}

class ChatMember {
  ChatMember(this.userId, this.keyId, this.publicKey);

  final int userId;
  final int? keyId;
  final String? publicKey;
}

/// Claves de un chat tal como las devuelve el servidor.
class ChatKeys {
  ChatKeys(Map<String, dynamic> j)
      : e2ee = j['e2ee'] == true,
        epoch = (j['epoch'] as num?)?.toInt() ?? 0,
        stale = j['stale'] == true,
        members = [
          for (final m in (j['members'] as List? ?? const []).whereType<Map>())
            ChatMember((m['user_id'] as num).toInt(), (m['key_id'] as num?)?.toInt(), m['public_key'] as String?),
        ],
        wraps = [for (final w in (j['wraps'] as List? ?? const []).whereType<Map>()) Map<String, dynamic>.from(w)];

  final bool e2ee;
  final int epoch;
  final bool stale;
  final List<ChatMember> members;
  final List<Map<String, dynamic>> wraps;

  bool get everyoneHasKey => members.isNotEmpty && members.every((m) => m.publicKey != null);
  List<String> get publicKeys => [for (final m in members) if (m.publicKey != null) m.publicKey!];
}

/// Archivo cifrado listo para subir (se borra después del envío).
class SealedFile {
  SealedFile(this.path, this.key, this.size);

  final String path;
  final String key;
  final int size;
}

/// La cuenta aún no tiene la clave en este teléfono (hay que crear o recuperar el PIN).
class E2eeLocked implements Exception {
  const E2eeLocked();

  @override
  String toString() => 'Configura el cifrado con tu PIN para usar este chat.';
}

/// Cifrado de extremo a extremo de los chats.
///
/// - Cada cuenta tiene un par X25519; la privada vive en el llavero del teléfono y se respalda en el servidor cifrada
///   con una clave derivada del PIN de 6 dígitos (PBKDF2-SHA256 + HKDF). Del PIN sale también la prueba «auth».
/// - Cada chat tiene una clave AES-256 por época que quien escribe cifra para cada participante: HKDF de
///   ECDH(efímera, destinatario) ‖ ECDH(estática de quien cifra, destinatario).
/// - Los mensajes son AES-GCM con la clave de su época; los archivos, AES-GCM con una clave propia que viaja dentro
///   del mensaje.
class E2ee {
  E2ee._();

  static final E2ee instance = E2ee._();

  static const _pinIterations = 100000;
  static const _storage = FlutterSecureStorage(iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock));

  final _x25519 = X25519();
  final _aes = AesGcm.with256bits();
  final _random = Random.secure();

  int? _uid;
  SimpleKeyPair? _identity;
  String? _publicKey;
  int? _keyId;
  E2eeStatus? status;

  final Map<int, Map<int, SecretKey>> _epochKeys = {};
  final Map<int, ChatKeys> _chatKeys = {};
  final Map<int, E2eePayload?> _plain = {};

  bool get ready => _identity != null;
  String? get publicKey => _publicKey;

  /// Descarta lo que hay en memoria (al cerrar sesión). La clave queda en el llavero para la próxima vez.
  void forget() {
    _uid = null;
    _identity = null;
    _publicKey = null;
    _keyId = null;
    status = null;
    _epochKeys.clear();
    _chatKeys.clear();
    _plain.clear();
  }

  String _privKey(int uid) => 'trevix_e2ee_priv_$uid';
  String _idKey(int uid) => 'trevix_e2ee_kid_$uid';

  Uint8List _bytes(int n) => Uint8List.fromList(List<int>.generate(n, (_) => _random.nextInt(256)));

  /// Carga la clave de este teléfono y comprueba con el servidor que sigue siendo la de la cuenta.
  Future<E2eeStatus> load(int uid) async {
    if (_uid != uid) {
      forget();
      _uid = uid;
    }
    final s = E2eeStatus((await api.get('me/keys')).map);
    status = s;
    if (_identity == null) {
      String? seed;
      try {
        seed = await _storage.read(key: _privKey(uid));
      } catch (_) {
        seed = null;
      }
      if (seed != null) {
        final pair = await _x25519.newKeyPairFromSeed(base64Decode(seed));
        final pub = base64Encode((await pair.extractPublicKey()).bytes);
        if (s.configured && s.publicKey == pub) {
          _identity = pair;
          _publicKey = pub;
          _keyId = s.keyId;
        }
      }
    } else if (!s.configured || s.publicKey != _publicKey) {
      _identity = null;
      _publicKey = null;
      _epochKeys.clear();
      _chatKeys.clear();
    } else {
      _keyId = s.keyId;
    }
    return s;
  }

  Future<void> _keep(SimpleKeyPair pair, int? keyId) async {
    final uid = _uid!;
    final seed = await pair.extractPrivateKeyBytes();
    await _storage.write(key: _privKey(uid), value: base64Encode(seed));
    if (keyId != null) await _storage.write(key: _idKey(uid), value: '$keyId');
    _identity = pair;
    _publicKey = base64Encode((await pair.extractPublicKey()).bytes);
    _keyId = keyId;
    _epochKeys.clear();
    _chatKeys.clear();
    _plain.clear();
  }

  // ---- PIN ----

  /// [auth, enc] derivados del PIN (PBKDF2 en otro hilo para no congelar la pantalla).
  static Future<List<Uint8List>> _pinKeys(String pin, Uint8List salt) => Isolate.run(() async {
        final master = await Pbkdf2(macAlgorithm: Hmac.sha256(), iterations: _pinIterations, bits: 256)
            .deriveKeyFromPassword(password: pin, nonce: salt);
        final hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
        final zero = List<int>.filled(32, 0);
        final auth = await hkdf.deriveKey(secretKey: master, nonce: zero, info: utf8.encode('trevix-pin-auth'));
        final enc = await hkdf.deriveKey(secretKey: master, nonce: zero, info: utf8.encode('trevix-pin-enc'));
        return [Uint8List.fromList(await auth.extractBytes()), Uint8List.fromList(await enc.extractBytes())];
      });

  Future<Map<String, String>> _backup(SimpleKeyPair pair, String pin) async {
    final salt = _bytes(16);
    final keys = await _pinKeys(pin, salt);
    final box = await _aes.encrypt(await pair.extractPrivateKeyBytes(),
        secretKey: SecretKey(keys[1]), nonce: _bytes(12), aad: utf8.encode('trevix-key-backup'));
    return {
      'blob': base64Encode(box.concatenation()),
      'salt': base64Encode(salt),
      'auth': base64Encode(keys[0]),
    };
  }

  /// Primera vez (o clave nueva tras olvidar el PIN): par nuevo, copia con el PIN y clave pública al servidor.
  /// Con una clave nueva, los mensajes cifrados anteriores ya no se pueden leer en este teléfono.
  Future<void> create(String pin) async {
    final pair = await _x25519.newKeyPair();
    final pub = base64Encode((await pair.extractPublicKey()).bytes);
    final res = await api.put('me/keys', {'public_key': pub, 'backup': await _backup(pair, pin)});
    final s = E2eeStatus(res.map);
    status = s;
    await _keep(pair, s.keyId);
  }

  /// Recupera la clave de la cuenta en este teléfono con el PIN (403 en «pin» si no es correcto).
  Future<void> recover(String pin) async {
    final salt = status?.salt ?? E2eeStatus((await api.get('me/keys')).map).salt;
    if (salt == null) throw ApiException(404, 'no_backup', 'Esta cuenta no tiene una copia de la clave con PIN.');
    final keys = await _pinKeys(pin, base64Decode(salt));
    final res = (await api.post('me/keys/recover', {'auth': base64Encode(keys[0])})).map;
    final blob = base64Decode('${res['blob']}');
    final box = SecretBox.fromConcatenation(blob, nonceLength: 12, macLength: 16);
    final List<int> seed;
    try {
      seed = await _aes.decrypt(box, secretKey: SecretKey(keys[1]), aad: utf8.encode('trevix-key-backup'));
    } on SecretBoxAuthenticationError {
      throw ApiException(403, 'bad_pin', 'El PIN no es correcto.', {'pin': 'El PIN no es correcto.'});
    }
    final pair = await _x25519.newKeyPairFromSeed(seed);
    final pub = base64Encode((await pair.extractPublicKey()).bytes);
    if (pub != res['public_key']) {
      throw ApiException(409, 'key_mismatch', 'La copia de la clave no coincide con tu cuenta. Crea una clave nueva.');
    }
    status = E2eeStatus((await api.get('me/keys')).map);
    await _keep(pair, (res['key_id'] as num?)?.toInt());
  }

  /// Cambia el PIN (misma clave, copia nueva).
  Future<void> changePin(String pin) async {
    final pair = _identity;
    if (pair == null) throw const E2eeLocked();
    status = E2eeStatus((await api.put('me/keys/backup', await _backup(pair, pin))).map);
  }

  // ---- Código de seguridad ----

  /// 60 cifras en 12 grupos de 5, iguales en los teléfonos de todo el chat mientras nadie cambie de clave.
  Future<String> securityCode(List<String> publicKeys) async {
    final sorted = [...publicKeys]..sort();
    final hash = await Sha256().hash(utf8.encode('trevix-safety:${sorted.join(',')}'));
    final more = await Sha256().hash([...hash.bytes, ...utf8.encode('2')]);
    final bytes = [...hash.bytes, ...more.bytes];
    final groups = <String>[];
    for (var i = 0; i < 12; i++) {
      final n = (bytes[i * 3] << 16) | (bytes[i * 3 + 1] << 8) | bytes[i * 3 + 2];
      groups.add((n % 100000).toString().padLeft(5, '0'));
    }
    return groups.join(' ');
  }

  // ---- Claves del chat ----

  Future<ChatKeys> chatKeys(int conversationId, {bool refresh = false}) async {
    final cached = _chatKeys[conversationId];
    if (cached != null && !refresh) return cached;
    final keys = ChatKeys((await api.get('conversations/$conversationId/keys')).map);
    _chatKeys[conversationId] = keys;
    final mine = _identity;
    if (mine != null) {
      final epochs = _epochKeys.putIfAbsent(conversationId, () => {});
      for (final w in keys.wraps) {
        final epoch = (w['epoch'] as num).toInt();
        if (epochs.containsKey(epoch) || (w['key_id'] as num?)?.toInt() != _keyId) continue;
        final key = await _unwrap(conversationId, epoch, '${w['wrapped']}', '${w['wrapper_public']}', mine);
        if (key != null) epochs[epoch] = key;
      }
    }
    return keys;
  }

  /// Si los mensajes nuevos de este chat se deben cifrar: siempre si el chat ya está cifrado; si no, cuando todos
  /// los participantes (y este teléfono) tienen clave. Lanza [E2eeLocked] si el chat está cifrado y falta el PIN.
  Future<bool> shouldEncrypt(int conversationId, {required bool chatEncrypted}) async {
    if (!ready) {
      if (chatEncrypted) throw const E2eeLocked();
      return false;
    }
    if (chatEncrypted) return true;
    try {
      return (await chatKeys(conversationId, refresh: true)).everyoneHasKey;
    } on ApiException {
      return false;
    }
  }

  List<int> _info(int conversationId, int epoch, int recipientId) =>
      utf8.encode('trevix-wrap:$conversationId:$epoch:$recipientId');

  Future<SecretKey> _wrapKey(List<int> s1, List<int> s2, List<int> info) =>
      Hkdf(hmac: Hmac.sha256(), outputLength: 32)
          .deriveKey(secretKey: SecretKey([...s1, ...s2]), nonce: List<int>.filled(32, 0), info: info);

  Future<List<int>> _ecdh(SimpleKeyPair pair, List<int> remote) async =>
      (await _x25519.sharedSecretKey(keyPair: pair, remotePublicKey: SimplePublicKey(remote, type: KeyPairType.x25519)))
          .extractBytes();

  Future<String> _wrap(int conversationId, int epoch, int recipientId, String recipientPublic, SecretKey chatKey) async {
    final remote = base64Decode(recipientPublic);
    final eph = await _x25519.newKeyPair();
    final ephPub = (await eph.extractPublicKey()).bytes;
    final info = _info(conversationId, epoch, recipientId);
    final k = await _wrapKey(await _ecdh(eph, remote), await _ecdh(_identity!, remote), info);
    final box = await _aes.encrypt(await chatKey.extractBytes(), secretKey: k, nonce: _bytes(12), aad: info);
    return base64Encode([...ephPub, ...box.concatenation()]);
  }

  Future<SecretKey?> _unwrap(int conversationId, int epoch, String wrapped, String wrapperPublic, SimpleKeyPair mine) async {
    try {
      final raw = base64Decode(wrapped);
      if (raw.length < 32 + 12 + 16) return null;
      final info = _info(conversationId, epoch, _uid!);
      final k = await _wrapKey(await _ecdh(mine, raw.sublist(0, 32)), await _ecdh(mine, base64Decode(wrapperPublic)), info);
      final box = SecretBox.fromConcatenation(raw.sublist(32), nonceLength: 12, macLength: 16);
      return SecretKey(await _aes.decrypt(box, secretKey: k, aad: info));
    } catch (_) {
      return null;
    }
  }

  /// Época vigente y su clave para escribir. Si no hay o ya no cubre a los participantes, crea una nueva y la
  /// reparte (reintenta si otra persona se adelantó).
  Future<(int, SecretKey)> sendingKey(int conversationId) async {
    if (!ready) throw const E2eeLocked();
    for (var attempt = 0; attempt < 3; attempt++) {
      final keys = await chatKeys(conversationId, refresh: true);
      final current = _epochKeys[conversationId]?[keys.epoch];
      if (keys.epoch > 0 && !keys.stale && current != null) return (keys.epoch, current);
      final epoch = keys.epoch + 1;
      final chatKey = SecretKey(_bytes(32));
      final wraps = <Map<String, dynamic>>[];
      for (final m in keys.members) {
        if (m.publicKey == null || m.keyId == null) continue;
        wraps.add({'user_id': m.userId, 'key_id': m.keyId, 'wrapped': await _wrap(conversationId, epoch, m.userId, m.publicKey!, chatKey)});
      }
      try {
        await api.post('conversations/$conversationId/keys', {'epoch': epoch, 'keys': wraps});
        _epochKeys.putIfAbsent(conversationId, () => {})[epoch] = chatKey;
        _chatKeys.remove(conversationId);
        return (epoch, chatKey);
      } on ApiException catch (e) {
        if (e.status != 409 || attempt == 2) rethrow;
      }
    }
    throw ApiException(409, 'epoch', 'Las claves del chat cambiaron. Vuelve a intentarlo.');
  }

  /// Llamar cuando el servidor responde 409 en «e2ee_epoch»: la próxima vez se vuelven a pedir las claves.
  void invalidate(int conversationId) => _chatKeys.remove(conversationId);

  // ---- Mensajes ----

  List<int> _aad(int conversationId, int epoch, int senderId) => utf8.encode('msg:$conversationId:$epoch:$senderId');

  Future<String> seal(int conversationId, int epoch, SecretKey key, int senderId, Map<String, dynamic> payload) async {
    final box = await _aes.encrypt(utf8.encode(jsonEncode({'v': 1, ...payload})),
        secretKey: key, nonce: _bytes(12), aad: _aad(conversationId, epoch, senderId));
    return base64Encode(box.concatenation());
  }

  /// Ya descifrado (sin esperar). null si no está en memoria o no se pudo descifrar.
  E2eePayload? cached(int messageId) => _plain[messageId];
  bool isKnown(int messageId) => _plain.containsKey(messageId);

  /// Descifra un mensaje; null si falta la clave de su época (otra clave de la cuenta o no estaba en el chat).
  Future<E2eePayload?> open(int conversationId, int messageId, int epoch, int senderId, String ciphertext) async {
    if (_plain.containsKey(messageId) && _plain[messageId] != null) return _plain[messageId];
    final payload = await openText(conversationId, epoch, senderId, ciphertext);
    if (messageId > 0) _plain[messageId] = payload;
    return payload;
  }

  Future<E2eePayload?> openText(int conversationId, int epoch, int senderId, String ciphertext) async {
    if (!ready) return null;
    var key = _epochKeys[conversationId]?[epoch];
    if (key == null) {
      try {
        await chatKeys(conversationId, refresh: true);
      } catch (_) {
        return null;
      }
      key = _epochKeys[conversationId]?[epoch];
      if (key == null) return null;
    }
    try {
      final box = SecretBox.fromConcatenation(base64Decode(ciphertext), nonceLength: 12, macLength: 16);
      final clear = await _aes.decrypt(box, secretKey: key, aad: _aad(conversationId, epoch, senderId));
      final json = jsonDecode(utf8.decode(clear));
      return json is Map ? E2eePayload(Map<String, dynamic>.from(json)) : null;
    } catch (_) {
      return null;
    }
  }

  // ---- Archivos ----

  /// Cifra un archivo con una clave propia (nonce ‖ cifrado ‖ etiqueta) en un temporal.
  Future<SealedFile> sealFile(String path) async {
    final clear = await File(path).readAsBytes();
    final key = _bytes(32);
    final box = await _aes.encrypt(clear, secretKey: SecretKey(key), nonce: _bytes(12));
    final dir = await getTemporaryDirectory();
    final out = File('${dir.path}/e2ee_${DateTime.now().microsecondsSinceEpoch}.bin');
    await out.writeAsBytes(box.concatenation(), flush: true);
    return SealedFile(out.path, base64Encode(key), clear.length);
  }

  Future<Uint8List> openFile(Uint8List data, String key) async {
    final box = SecretBox.fromConcatenation(data, nonceLength: 12, macLength: 16);
    return Uint8List.fromList(await _aes.decrypt(box, secretKey: SecretKey(base64Decode(key))));
  }
}

final e2ee = E2ee.instance;
