import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import '../models/models.dart';
import 'api.dart';
import 'e2ee.dart';
import 'i18n.dart';

/// Archivos de los chats guardados en el teléfono (los cifrados ya descifrados), en chat_cache/{conversación}/.
/// «Almacenamiento del chat» los cuenta y los borra; si se borran, se vuelven a descargar al abrirlos.
class ChatMedia {
  ChatMedia._();

  static final Map<int, Future<File>> _pending = {};

  static Future<Directory> dir([int? conversationId]) async {
    final base = await getApplicationSupportDirectory();
    final d = Directory(conversationId == null ? '${base.path}/chat_cache' : '${base.path}/chat_cache/$conversationId');
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  static String extFor(String? mime) => switch (mime ?? '') {
        'image/png' => 'png',
        'image/gif' => 'gif',
        'image/webp' => 'webp',
        'image/heic' => 'heic',
        final m when m.startsWith('image/') => 'jpg',
        'video/quicktime' => 'mov',
        'video/webm' => 'webm',
        final m when m.startsWith('video/') => 'mp4',
        final m when m.startsWith('audio/') => 'm4a',
        _ => 'bin',
      };

  /// Las notas de voz se graban en .m4a; .mp4 y .mov son videos.
  static String mimeFor(String path) {
    final p = path.toLowerCase();
    if (p.endsWith('.png')) return 'image/png';
    if (p.endsWith('.gif')) return 'image/gif';
    if (p.endsWith('.webp')) return 'image/webp';
    if (p.endsWith('.heic')) return 'image/heic';
    if (p.endsWith('.mov')) return 'video/quicktime';
    if (p.endsWith('.webm')) return 'video/webm';
    if (p.endsWith('.mp4') || p.endsWith('.m4v') || p.endsWith('.3gp')) return 'video/mp4';
    if (p.endsWith('.m4a') || p.endsWith('.aac')) return 'audio/mp4';
    return 'image/jpeg';
  }

  /// MIME del archivo protegido del mensaje (el real en los cifrados).
  static String? mimeOf(Message m) => m.file?.encrypted == true ? m.payload?.mime : m.file?.mime;

  static Future<File?> cached(int conversationId, int messageId) async {
    final d = await dir(conversationId);
    await for (final f in d.list()) {
      if (f is File && f.uri.pathSegments.last.startsWith('$messageId.')) return f;
    }
    return null;
  }

  /// Guarda en la caché el archivo que acabas de enviar (así no hay que descargarlo de nuevo).
  static Future<void> keep(int conversationId, int messageId, String sourcePath, String mime) async {
    try {
      final d = await dir(conversationId);
      await File(sourcePath).copy('${d.path}/$messageId.${extFor(mime)}');
    } catch (_) {}
  }

  /// Archivo del mensaje en el teléfono: de la caché o descargado (y descifrado si está cifrado).
  static Future<File> load(Message m) {
    return _pending.putIfAbsent(m.id, () async {
      try {
        final hit = await cached(m.conversationId, m.id);
        if (hit != null) return hit;
        final file = m.file;
        if (file == null) throw ApiException(404, 'gone', tr('Este archivo ya no está disponible.'));
        var bytes = await api.bytes(file.url);
        var mime = file.mime;
        if (file.encrypted) {
          final key = m.payload?.fileKey;
          if (key == null) throw ApiException(403, 'locked', tr('No se pudo descifrar este archivo.'));
          bytes = await e2ee.openFile(bytes, key);
          mime = m.payload?.mime;
        }
        final d = await dir(m.conversationId);
        final out = File('${d.path}/${m.id}.${extFor(mime)}');
        await out.writeAsBytes(bytes, flush: true);
        return out;
      } finally {
        _pending.remove(m.id);
      }
    });
  }

  /// Foto o video de visualización única: en memoria (el servidor lo entrega una vez). Los videos se reproducen desde
  /// un archivo temporal que el visor borra al cerrarse.
  static Future<Uint8List> once(Message m) async {
    final file = m.file;
    if (file == null) throw ApiException(410, 'gone', tr('Esto ya no está disponible.'));
    final bytes = await api.bytes(file.url);
    if (!file.encrypted) return bytes;
    final key = m.payload?.fileKey;
    if (key == null) throw ApiException(403, 'locked', tr('No se pudo descifrar.'));
    return e2ee.openFile(bytes, key);
  }

  /// Bytes por conversación guardados en el teléfono.
  static Future<Map<int, int>> sizes() async {
    final out = <int, int>{};
    final root = await dir();
    await for (final d in root.list()) {
      if (d is! Directory) continue;
      final id = int.tryParse(d.uri.pathSegments.where((s) => s.isNotEmpty).last);
      if (id == null) continue;
      var total = 0;
      await for (final f in d.list(recursive: true)) {
        if (f is File) total += await f.length();
      }
      if (total > 0) out[id] = total;
    }
    return out;
  }

  static Future<int> size(int conversationId) async => (await sizes())[conversationId] ?? 0;

  /// Borra la caché de una conversación (o de todas).
  static Future<void> clear([int? conversationId]) async {
    final d = await dir(conversationId);
    if (await d.exists()) await d.delete(recursive: true);
  }
}
