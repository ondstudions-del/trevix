import 'dart:io';
import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';

import 'api.dart';
import 'i18n.dart';

/// Galería sin recomprimir calidad (mantiene GIF); cámara con JPEG optimizado.
Future<XFile?> pickProfileImage(
  ImageSource source, {
  required double maxWidthCamera,
}) {
  final picker = ImagePicker();
  if (source == ImageSource.gallery) {
    // imageQuality convierte HEIC (iOS) a JPEG; en Android suele respetar PNG/GIF.
    return picker.pickImage(
      source: ImageSource.gallery,
      requestFullMetadata: true,
      maxWidth: maxWidthCamera,
      imageQuality: 88,
    );
  }
  return picker.pickImage(
    source: source,
    imageQuality: 92,
    maxWidth: maxWidthCamera,
  );
}

String _profileImageFilename(XFile file) {
  if (file.name.isNotEmpty) return file.name;
  final mime = (file.mimeType ?? '').toLowerCase();
  final path = file.path.toLowerCase();
  if (mime.contains('gif') || path.endsWith('.gif')) return 'photo.gif';
  if (mime.contains('png') || path.endsWith('.png')) return 'photo.png';
  if (mime.contains('webp') || path.endsWith('.webp')) return 'photo.webp';
  return 'photo.jpg';
}

String _mimeFrom(XFile file) {
  final mime = file.mimeType;
  if (mime != null && mime.isNotEmpty) return mime.toLowerCase();
  final p = file.path.toLowerCase();
  if (p.endsWith('.gif')) return 'image/gif';
  if (p.endsWith('.png')) return 'image/png';
  if (p.endsWith('.webp')) return 'image/webp';
  if (p.endsWith('.heic')) return 'image/heic';
  return 'image/jpeg';
}

/// Lee la imagen y construye el multipart (iOS a veces devuelve rutas vacías o efímeras).
Future<Upload> profileImageUpload(String field, XFile file) async {
  Uint8List bytes;
  try {
    final path = file.path;
    if (path.isNotEmpty && await File(path).exists()) {
      bytes = await File(path).readAsBytes();
    } else {
      bytes = await file.readAsBytes();
    }
  } catch (_) {
    bytes = await file.readAsBytes();
  }
  if (bytes.isEmpty) {
    throw ApiException(0, 'empty_file', tr('No se pudo leer la imagen. Prueba otra foto.'));
  }
  final filename = _profileImageFilename(file);
  final mime = _mimeFrom(file);
  return Upload(field, file.path, filename: filename, bytes: bytes);
}

/// Sufijo al reutilizar una URL de foto de perfil (portada desde avatar, etc.).
String profileImageFileSuffix({required String url, String? contentType}) {
  final ct = (contentType ?? '').toLowerCase();
  if (ct.contains('gif')) return '.gif';
  if (ct.contains('webp')) return '.webp';
  if (ct.contains('png')) return '.png';
  if (ct.contains('jpeg') || ct.contains('jpg')) return '.jpg';
  final path = Uri.tryParse(url)?.path.toLowerCase() ?? '';
  if (path.endsWith('.gif')) return '.gif';
  if (path.endsWith('.webp')) return '.webp';
  if (path.endsWith('.png')) return '.png';
  return '.jpg';
}