import 'dart:io';
import 'dart:math';

import 'package:fc_native_video_thumbnail/fc_native_video_thumbnail.dart';
import 'package:fc_native_video_thumbnail/fc_native_video_thumbnail_platform_interface.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';

/// Datos de un video del teléfono que hacen falta para enviarlo.
class VideoInfo {
  VideoInfo({this.seconds, this.width = 0, this.height = 0});

  /// null si el teléfono no puede leer la duración (el servidor la vuelve a comprobar).
  final double? seconds;
  final int width;
  final int height;
}

class VideoTools {
  VideoTools._();

  static Future<VideoInfo> info(String path) async {
    final c = VideoPlayerController.file(File(path));
    try {
      await c.initialize();
      final ms = c.value.duration.inMilliseconds;
      final size = c.value.size;
      return VideoInfo(seconds: ms > 0 ? ms / 1000 : null, width: size.width.round(), height: size.height.round());
    } catch (_) {
      return VideoInfo();
    } finally {
      await c.dispose();
    }
  }

  /// Fotograma del primer segundo (o antes si el video es muy corto) como JPEG de lado mayor [side].
  static Future<String?> poster(String path, double? seconds, {int side = 1080, int quality = 82}) async {
    try {
      final dir = await getTemporaryDirectory();
      final dest = '${dir.path}/poster_${DateTime.now().microsecondsSinceEpoch}.jpg';
      final atMs = seconds == null ? 0 : min(1000, (seconds * 1000 / 3).round());
      final ok = await FcNativeVideoThumbnail().saveThumbnailToFile(
        srcFile: path,
        destFile: dest,
        width: side,
        height: side,
        quality: quality,
        at: FcVideoThumbnailTime(atMs, FcVideoThumbnailTimeUnit.milliseconds),
      );
      return ok && await File(dest).exists() ? dest : null;
    } catch (_) {
      return null;
    }
  }
}
