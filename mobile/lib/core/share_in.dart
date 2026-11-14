import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'deeplinks.dart';

/// Archivo compartido desde otra app (ya copiado dentro de la app).
class SharedFile {
  const SharedFile(this.path, {required this.isVideo});

  final String path;
  final bool isVideo;
}

/// Lo que otra app compartió con TREVIX: fotos o videos y, a veces, un texto o enlace.
class SharedContent {
  const SharedContent({this.files = const [], this.text});

  final List<SharedFile> files;
  final String? text;

  bool get isEmpty => files.isEmpty && (text == null || text!.trim().isEmpty);
}

const _videoExtensions = {'mp4', 'mov', 'm4v', '3gp', 'webm', 'mkv'};

bool _looksLikeVideo(String path) => _videoExtensions.contains(path.split('.').last.toLowerCase());

/// Recibe lo compartido: en Android por el canal «trevix/share» (MainActivity + ShareIn.kt); en iOS TREVIX aparece
/// como «Abrir en TREVIX» para fotos y videos y el archivo llega como enlace file:// ([fromFileUri]). Todo pasa por
/// [DeepLinks], que lo abre cuando la sesión ya está lista.
class ShareIn {
  ShareIn._();

  static const _channel = MethodChannel('trevix/share');

  static void install() {
    if (kIsWeb || !Platform.isAndroid) return;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'shared') await _take();
    });
    _take();
  }

  static Future<void> _take() async {
    try {
      final m = await _channel.invokeMapMethod<String, Object?>('take');
      if (m == null) return;
      final files = <SharedFile>[
        for (final f in (m['files'] as List?) ?? const [])
          if (f is Map && f['path'] is String) SharedFile(f['path'] as String, isVideo: '${f['mime']}'.startsWith('video/')),
      ];
      final content = SharedContent(files: files, text: m['text'] as String?);
      if (!content.isEmpty) DeepLinks.instance.share(content);
    } on PlatformException {
      // Sin nada pendiente o canal no disponible: no hay nada que abrir.
    } on MissingPluginException {
      // Idem.
    }
  }

  /// iOS: el sistema copia el archivo a Documents/Inbox; se mueve a la carpeta temporal para no acumularlos.
  static Future<SharedContent?> fromFileUri(Uri uri) async {
    try {
      final source = File(uri.toFilePath());
      if (!await source.exists()) return null;
      final name = source.path.split('/').last;
      final dir = await Directory('${(await getTemporaryDirectory()).path}/shared').create(recursive: true);
      final dest = '${dir.path}/${DateTime.now().microsecondsSinceEpoch}_$name';
      await source.copy(dest);
      if (source.path.contains('/Inbox/')) source.delete().ignore();
      return SharedContent(files: [SharedFile(dest, isVideo: _looksLikeVideo(dest))]);
    } catch (_) {
      return null;
    }
  }
}
