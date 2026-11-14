import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';

import '../../core/i18n.dart';
import '../../core/nav.dart';
import '../../core/session.dart';
import '../../core/share_in.dart';
import '../../core/video_tools.dart';
import '../../models/models.dart';
import '../../widgets/media.dart' show clockText;
import '../post/composer_screen.dart';
import '../reels/reel_draft.dart';
import '../reels/reel_editor_screen.dart';
import '../reels/reel_photos_screen.dart';
import '../stories/story_create_screen.dart';

/// «Publicar en TREVIX» con lo que otra app compartió: un video como reel o historia; fotos como publicación,
/// historia o reel de fotos animadas; un texto o enlace, como publicación.
Future<void> openSharedContent(BuildContext context, SharedContent content) async {
  final text = content.text?.trim();
  final videos = content.files.where((f) => f.isVideo).toList();
  final photos = content.files.where((f) => !f.isVideo).map((f) => f.path).toList();

  if (content.files.isEmpty) {
    if (text != null && text.isNotEmpty) await push<Post>(context, ComposerScreen(sharedText: text), fullscreen: true);
    return;
  }

  if (videos.isNotEmpty) {
    final video = videos.first.path;
    if (content.files.length > 1) toast(context, tr('Se usará solo el primer video.'));
    await actionSheet(context, [
      SheetAction(tr('Reel'), CupertinoIcons.film, () => _reel(context, video)),
      SheetAction(tr('Historia'), CupertinoIcons.circle_grid_hex, () => push(context, StoryCreateScreen(media: video, mediaIsVideo: true), fullscreen: true)),
    ], title: tr('Publicar en TREVIX'));
    return;
  }

  await actionSheet(context, [
    SheetAction(
      photos.length == 1 ? tr('Publicación') : tr('Publicación con {n} fotos', {'n': photos.length}),
      CupertinoIcons.square_grid_2x2,
      () => push<Post>(context, ComposerScreen(sharedImages: photos, sharedText: text), fullscreen: true),
    ),
    SheetAction(tr('Historia'), CupertinoIcons.circle_grid_hex, () {
      if (photos.length > 1) toast(context, tr('La historia usará la primera foto.'));
      push(context, StoryCreateScreen(media: photos.first), fullscreen: true);
    }),
    SheetAction(tr('Reel con fotos animadas'), CupertinoIcons.sparkles, () => _photosReel(context, photos)),
  ], title: tr('Publicar en TREVIX'));
}

Future<void> _reel(BuildContext context, String path) async {
  final app = context.read<AppState>();
  final maxSeconds = app.limit('video_max_seconds', 300);
  final maxBytes = app.limit('video_max_bytes', 300 * 1024 * 1024);
  final size = await File(path).length();
  if (!context.mounted) return;
  if (size > maxBytes) {
    toast(context, tr('El video pesa {size} MB y el máximo es {max} MB. Recórtalo o grábalo en menor calidad.', {'size': (size / 1048576).round(), 'max': (maxBytes / 1048576).round()}),
        error: true);
    return;
  }
  final info = await VideoTools.info(path);
  if (!context.mounted) return;
  final seconds = info.seconds;
  if (seconds != null && seconds > maxSeconds + 0.5) {
    toast(context, tr('El video dura {length}. Los videos pueden durar como máximo {max} minutos.', {'length': clockText(seconds.round()), 'max': clockText(maxSeconds)}),
        error: true);
    return;
  }
  await push<Post>(context, ReelEditorScreen(draft: ReelDraft(path: path, seconds: seconds)));
}

Future<void> _photosReel(BuildContext context, List<String> photos) async {
  if (photos.length > reelMaxPhotos) toast(context, tr('Se usarán las primeras {max} fotos.', {'max': reelMaxPhotos}));
  final draft = await push<ReelDraft>(context, ReelPhotosScreen(photos: photos.take(reelMaxPhotos).toList()));
  if (draft == null || !context.mounted) return;
  await push<Post>(context, ReelEditorScreen(draft: draft));
}
