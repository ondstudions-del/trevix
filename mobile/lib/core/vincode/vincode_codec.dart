/// Codec VINCODE: anillo de bits estable (cian=1 / violeta=0) + CRC8.
library;

const vincodeAlphabet = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';
const _sync = [1, 0, 1, 0, 1, 0, 1, 0];
const vincodeDataBits = 48;
const vincodeModules = 56; // sync + data

String normalizeVincode(String raw) {
  var s = raw.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
  s = s.replaceAll('O', '0').replaceAll(RegExp(r'[IL]'), '1').replaceAll('U', 'V');
  return s;
}

int seedForVincode(String code) {
  var h = 0;
  final c = normalizeVincode(code);
  for (final cu in c.codeUnits) {
    h = ((h << 5) - h + cu) & 0xFFFFFFFF;
  }
  return h;
}

String payloadForVincode(String code) => 'trevix://vincode/${normalizeVincode(code)}';

String? parseVincodePayload(String text) {
  final m = RegExp(r'trevix://vincode/([A-Z0-9]{6,12})', caseSensitive: false).firstMatch(text)
      ?? RegExp(r'\b([0-9A-Z]{8})\b', caseSensitive: false).firstMatch(text);
  return m == null ? null : normalizeVincode(m.group(1)!);
}

int _crc8(List<int> bytes) {
  var crc = 0;
  for (final b in bytes) {
    crc ^= b;
    for (var i = 0; i < 8; i++) {
      crc = (crc & 0x80) != 0 ? ((crc << 1) ^ 0x07) & 0xff : (crc << 1) & 0xff;
    }
  }
  return crc;
}

/// Devuelve 56 bits (0/1) o null si el código no es válido.
List<int>? codeToBits(String code) {
  final c = normalizeVincode(code);
  if (c.length != 8) return null;
  final vals = <int>[];
  for (var i = 0; i < 8; i++) {
    final idx = vincodeAlphabet.indexOf(c[i]);
    if (idx < 0) return null;
    vals.add(idx);
  }
  final bits = <int>[..._sync];
  for (final v in vals) {
    for (var b = 4; b >= 0; b--) {
      bits.add((v >> b) & 1);
    }
  }
  final crc = _crc8(vals);
  for (var b = 7; b >= 0; b--) {
    bits.add((crc >> b) & 1);
  }
  return bits;
}

String? bitsToCode(List<int> bits) {
  if (bits.length < vincodeModules) return null;
  for (var rot = 0; rot < vincodeModules; rot++) {
    final rotated = [...bits.sublist(rot), ...bits.sublist(0, rot)];
    var syncOk = true;
    for (var i = 0; i < _sync.length; i++) {
      if (rotated[i] != _sync[i]) {
        syncOk = false;
        break;
      }
    }
    if (!syncOk) continue;
    final data = rotated.sublist(_sync.length, _sync.length + vincodeDataBits);
    final vals = <int>[];
    for (var i = 0; i < 8; i++) {
      var v = 0;
      for (var b = 0; b < 5; b++) {
        v = (v << 1) | data[i * 5 + b];
      }
      if (v >= vincodeAlphabet.length) {
        vals.clear();
        break;
      }
      vals.add(v);
    }
    if (vals.length != 8) continue;
    var crc = 0;
    for (var b = 0; b < 8; b++) {
      crc = (crc << 1) | data[40 + b];
    }
    if (crc != _crc8(vals)) continue;
    return vals.map((v) => vincodeAlphabet[v]).join();
  }
  return null;
}
