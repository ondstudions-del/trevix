import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../models/models.dart';
import 'api.dart';

/// Borrador guardado en el teléfono: una publicación, un reel o una historia sin publicar. No se sube a TREVIX
/// hasta publicarlo; sus fotos y videos se copian a la carpeta del borrador para que no dependan de la galería.
class Draft {
  Draft({required this.id, required this.kind, required this.userId, required this.savedAt, required this.data, this.files = const {}});

  factory Draft.fromJson(Json j, String dir) => Draft(
        id: asStr(j['id']),
        kind: asStr(j['kind'], 'post'),
        userId: asInt(j['user_id']),
        savedAt: DateTime.tryParse(asStr(j['saved_at'])) ?? DateTime.now(),
        data: asMap(j['data']),
        files: {for (final e in asMap(j['files']).entries) e.key: '$dir/${e.value}'},
      );

  final String id;

  /// post | reel | story
  final String kind;
  final int userId;
  final DateTime savedAt;

  /// Estado de la pantalla que lo creó (texto, visibilidad, filtro, capas, canción…).
  final Json data;

  /// Nombre → ruta del archivo dentro de la carpeta del borrador ('video', 'poster', 'image0'…).
  final Map<String, String> files;

  /// Miniatura para la lista: la portada del video o la primera foto.
  String? get thumb => files['poster'] ?? files['image0'] ?? (asStr(data['type']) == 'image' ? files['media'] : null);

  bool get isVideo => files.containsKey('video') || (files.containsKey('media') && asStr(data['type']) == 'video');

  String get text => asStr(data['body'], asStr(data['text'], asStr(data['caption'])));
}

/// Borradores de la cuenta en este teléfono (cada cuenta ve solo los suyos).
class DraftStore extends ChangeNotifier {
  DraftStore._();

  static final DraftStore instance = DraftStore._();

  Future<Directory> _root() async {
    final dir = Directory('${(await getApplicationDocumentsDirectory()).path}/drafts');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<List<Draft>> list(int userId) async {
    final root = await _root();
    final out = <Draft>[];
    await for (final entry in root.list()) {
      if (entry is! Directory) continue;
      final meta = File('${entry.path}/draft.json');
      if (!await meta.exists()) continue;
      try {
        final draft = Draft.fromJson(asMap(jsonDecode(await meta.readAsString())), entry.path);
        if (draft.userId == userId) out.add(draft);
      } catch (_) {}
    }
    out.sort((a, b) => b.savedAt.compareTo(a.savedAt));
    return out;
  }

  /// Guarda (o reemplaza, con [id]) un borrador. [files]: nombre → ruta actual del archivo; los que aún no están en
  /// la carpeta del borrador se copian. Devuelve el id.
  Future<String> save({String? id, required String kind, required int userId, required Json data, Map<String, String> files = const {}}) async {
    final root = await _root();
    final draftId = id ?? '${DateTime.now().millisecondsSinceEpoch}${(DateTime.now().microsecond % 1000).toString().padLeft(3, '0')}';
    final dir = Directory('${root.path}/$draftId');
    if (!await dir.exists()) await dir.create(recursive: true);
    final stored = <String, String>{};
    for (final e in files.entries) {
      final src = File(e.value);
      if (!await src.exists()) continue;
      final ext = e.value.contains('.') ? e.value.substring(e.value.lastIndexOf('.')).toLowerCase() : '';
      final name = '${e.key}${ext.length <= 6 ? ext : ''}';
      final target = '${dir.path}/$name';
      if (File(target).absolute.path != src.absolute.path) await src.copy(target);
      stored[e.key] = name;
    }
    await for (final entry in dir.list()) {
      final name = entry.uri.pathSegments.isEmpty ? '' : entry.uri.pathSegments.last;
      if (entry is File && name != 'draft.json' && !stored.containsValue(name)) await entry.delete();
    }
    await File('${dir.path}/draft.json').writeAsString(jsonEncode({
      'id': draftId,
      'kind': kind,
      'user_id': userId,
      'saved_at': DateTime.now().toIso8601String(),
      'data': data,
      'files': stored,
    }));
    notifyListeners();
    return draftId;
  }

  Future<void> delete(String id) async {
    final dir = Directory('${(await _root()).path}/$id');
    if (await dir.exists()) await dir.delete(recursive: true);
    notifyListeners();
  }
}

final drafts = DraftStore.instance;

/// Canción guardada en un borrador (id e inicio): se vuelve a pedir por si ya no está disponible.
Future<(Song, int)?> draftSong(Json data) async {
  final id = asInt(data['song_id']);
  if (id <= 0) return null;
  try {
    final song = Song.fromJson((await api.get('music/$id')).map);
    return song.available ? (song, asInt(data['song_start'])) : null;
  } catch (_) {
    return null;
  }
}
