import '../widgets/media_gallery.dart';

/// Foto del reel con su clip de fotografía en movimiento (Live Photo / Motion Photo), igual que en historias.
class ReelPhotoItem {
  const ReelPhotoItem({required this.path, this.livePath});

  final String path;
  final String? livePath;

  bool get hasLive => livePath != null && livePath!.isNotEmpty;

  factory ReelPhotoItem.fromPick(GalleryPick p) => ReelPhotoItem(path: p.path, livePath: p.livePath);
}