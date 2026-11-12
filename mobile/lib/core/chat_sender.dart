import 'dart:convert';
import 'dart:io';

import 'package:flutter/painting.dart';

import '../models/models.dart';
import 'api.dart';
import 'chat_media.dart';
import 'e2ee.dart';
import 'video_tools.dart';

/// Lo que se va a enviar en un mensaje.
class Outgoing {
  Outgoing({
    this.text = '',
    this.imagePath,
    this.videoPath,
    this.videoSeconds = 0,
    this.videoWidth = 0,
    this.videoHeight = 0,
    this.posterPath,
    this.voicePath,
    this.voiceSeconds = 0,
    this.gif,
    this.location,
    this.viewSeconds,
    this.voiceOnce = false,
    this.replyTo,
    this.forwarded = false,
  });

  final String text;
  final String? imagePath;
  final String? videoPath;
  final int videoSeconds;
  final int videoWidth;
  final int videoHeight;

  /// Miniatura del video (JPEG); no se envía en los de visualización única.
  final String? posterPath;
  final String? voicePath;
  final int voiceSeconds;
  final Gif? gif;

  /// {lat, lng, name?}
  final Map<String, dynamic>? location;

  /// Foto o video de visualización única: null = normal, 0 = una vez (hasta cerrarlo), 3/5/10 = segundos.
  final int? viewSeconds;

  /// Nota de voz que se puede escuchar una sola vez.
  final bool voiceOnce;
  final int? replyTo;
  final bool forwarded;

  bool get viewOnce => (viewSeconds != null && (imagePath != null || videoPath != null)) || (voiceOnce && voicePath != null);

  /// Mensaje de solo texto: se muestra al instante y se confirma después.
  bool get textOnly => imagePath == null && videoPath == null && voicePath == null && gif == null && location == null && text.trim().isNotEmpty;
}

class Sent {
  Sent(this.conversationId, this.message);

  final int conversationId;
  final Message? message;
}

/// Envía mensajes: cifrados de extremo a extremo cuando el chat lo permite (o ya lo está) y sin cifrar si no
/// (por ejemplo, si la otra persona solo usa la web).
class ChatSender {
  ChatSender._();

  /// [conversationId] del chat o, para un chat nuevo con una persona, [to] (su usuario).
  static Future<Sent> send({int? conversationId, String? to, bool chatEncrypted = false, required int myId, required Outgoing out}) async {
    var id = conversationId;
    var encrypted = chatEncrypted;
    if (id == null && to != null && e2ee.ready) {
      final c = Conversation.fromJson((await api.post('conversations', {'to': to})).map);
      id = c.id;
      encrypted = c.e2ee;
    }
    if (id != null && await e2ee.shouldEncrypt(id, chatEncrypted: encrypted)) {
      return _encrypted(id, myId, out);
    }
    return _plain(id, to, out);
  }

  static Future<Sent> _plain(int? id, String? to, Outgoing out) async {
    final fields = <String, dynamic>{
      'body': out.voicePath != null ? '' : out.text,
      if (out.gif != null) 'gif_id': out.gif!.id,
      if (out.gif != null) 'gif_kind': out.gif!.kind,
      if (out.location != null) 'location': out.location,
      if (out.replyTo != null) 'reply_to': '${out.replyTo}',
      if (out.viewOnce) 'view_once': '1',
      if (out.viewOnce && out.viewSeconds != null) 'view_seconds': '${out.viewSeconds}',
      if (id == null) 'to': to,
    };
    final path = id == null ? 'messages' : 'conversations/$id/messages';
    final uploads = <Upload>[
      if (out.voicePath != null)
        Upload('voice', out.voicePath!, filename: 'nota.m4a')
      else if (out.videoPath != null) ...[
        Upload('video', out.videoPath!, filename: 'video.${ChatMedia.extFor(ChatMedia.mimeFor(out.videoPath!))}'),
        if (out.posterPath != null && !out.viewOnce) Upload('poster', out.posterPath!, filename: 'poster.jpg'),
      ] else if (out.imagePath != null)
        Upload('image', out.imagePath!, filename: 'foto.${ChatMedia.extFor(ChatMedia.mimeFor(out.imagePath!))}'),
    ];
    final ApiResponse res = uploads.isNotEmpty
        ? await api.upload(path, fields: fields.map((k, v) => MapEntry(k, '$v')), files: uploads)
        : await api.post(path, fields);
    final data = res.map;
    return Sent(asInt(data['conversation_id'], id ?? 0), data['message'] is Map ? Message.fromJson(asMap(data['message'])) : null);
  }

  static Future<Sent> _encrypted(int id, int myId, Outgoing out) async {
    SealedFile? sealed;
    final source = out.imagePath ?? out.videoPath ?? out.voicePath;
    final payload = <String, dynamic>{'t': 'text', 'b': out.text};
    try {
      if (source != null) {
        final mime = ChatMedia.mimeFor(source);
        var w = 0, h = 0;
        String? thumb;
        if (out.imagePath != null) {
          try {
            final image = await decodeImageFromList(await File(source).readAsBytes());
            w = image.width;
            h = image.height;
            image.dispose();
          } catch (_) {}
        } else if (out.videoPath != null) {
          w = out.videoWidth;
          h = out.videoHeight;
          if (!out.viewOnce) thumb = await _thumb(source, out.videoSeconds);
        }
        sealed = await e2ee.sealFile(source);
        payload['t'] = out.imagePath != null ? 'image' : (out.videoPath != null ? 'video' : 'voice');
        if (out.voicePath != null) payload['b'] = '';
        payload['f'] = {
          'k': sealed.key,
          'm': mime,
          's': sealed.size,
          if (w > 0) 'w': w,
          if (h > 0) 'h': h,
          if (out.voicePath != null) 'd': out.voiceSeconds,
          if (out.videoPath != null && out.videoSeconds > 0) 'd': out.videoSeconds,
          if (thumb != null) 'th': thumb,
        };
      } else if (out.gif != null) {
        final g = out.gif!;
        payload['t'] = 'gif';
        payload['g'] = {'id': g.id, 'kind': g.kind, 'url': g.url, 'w': g.width, 'h': g.height, 'title': g.title};
      } else if (out.location != null) {
        payload['t'] = 'location';
        payload['l'] = out.location;
      }
      for (var attempt = 0;; attempt++) {
        final (epoch, key) = await e2ee.sendingKey(id);
        final fields = <String, String>{
          'e2ee_epoch': '$epoch',
          'ciphertext': await e2ee.seal(id, epoch, key, myId, payload),
          if (out.replyTo != null) 'reply_to': '${out.replyTo}',
          if (out.forwarded) 'forwarded': '1',
          if (out.viewOnce) 'view_once': '1',
          if (out.viewOnce) 'view_seconds': '${out.viewSeconds ?? 0}',
        };
        try {
          final res = sealed != null
              ? await api.upload('conversations/$id/messages', fields: fields, files: [Upload('file', sealed.path, filename: 'cifrado.bin')])
              : await api.post('conversations/$id/messages', fields);
          final data = res.map;
          final message = data['message'] is Map ? Message.fromJson(asMap(data['message'])) : null;
          if (message != null) {
            message.payload = E2eePayload({'v': 1, ...payload});
            if (source != null && !out.viewOnce) await ChatMedia.keep(id, message.id, source, ChatMedia.mimeFor(source));
          }
          return Sent(id, message);
        } on ApiException catch (e) {
          if (e.status == 409 && e.field('e2ee_epoch') != null && attempt < 2) {
            e2ee.invalidate(id);
            continue;
          }
          rethrow;
        }
      }
    } finally {
      final path = sealed?.path;
      if (path != null) {
        try {
          await File(path).delete();
        } catch (_) {}
      }
    }
  }

  /// Miniatura muy pequeña del video (va dentro del mensaje cifrado, que tiene un tamaño máximo).
  static Future<String?> _thumb(String videoPath, int seconds) async {
    final path = await VideoTools.poster(videoPath, seconds > 0 ? seconds.toDouble() : null, side: 160, quality: 55);
    if (path == null) return null;
    try {
      final bytes = await File(path).readAsBytes();
      return bytes.length <= 12000 ? base64Encode(bytes) : null;
    } catch (_) {
      return null;
    } finally {
      try {
        await File(path).delete();
      } catch (_) {}
    }
  }
}
