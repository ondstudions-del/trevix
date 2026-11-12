import '../music/music_picker.dart';

/// Reel listo para el compositor: el video grabado con la cámara de reels (o elegido de la galería), su miniatura,
/// el filtro y la canción. Con [songSync] el video no tiene sonido propio y la canción suena a su compás desde
/// [song].start; el compositor no deja cambiar esa canción.
class ReelDraft {
  ReelDraft({required this.path, this.seconds, this.poster, this.filter, this.song, this.songSync = false});

  final String path;
  final double? seconds;
  String? poster;
  String? filter;
  final PickedSong? song;
  final bool songSync;
}
