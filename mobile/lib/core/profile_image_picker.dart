import 'package:image_picker/image_picker.dart';

/// Galería: conserva GIF y otros formatos sin recomprimir. Cámara: JPEG optimizado.
Future<XFile?> pickProfileImage(
  ImageSource source, {
  required int maxWidthCamera,
}) {
  final picker = ImagePicker();
  if (source == ImageSource.gallery) {
    return picker.pickMedia(requestFullMetadata: true).then((file) {
      if (file == null) return null;
      final mime = file.mimeType ?? '';
      if (mime.startsWith('video/')) return null;
      return file;
    });
  }
  return picker.pickImage(
    source: source,
    imageQuality: 92,
    maxWidth: maxWidthCamera,
  );
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