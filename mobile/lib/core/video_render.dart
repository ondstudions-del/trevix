import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gal/gal.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:trevix_video/trevix_video.dart';

import '../models/models.dart';
import '../widgets/story_layers.dart' show storyFilterMatrix;
import 'config.dart';
import 'device.dart';
import 'i18n.dart';
import 'nav.dart';
import 'theme.dart';
import 'video_tools.dart';

/// Web de la plataforma que aparece en el cierre de los videos descargados.
String get _siteLabel => Uri.parse(AppConfig.site).host;

/// Carpeta temporal propia de un trabajo (se borra entera al terminar).
Future<Directory> renderDir(String prefix) async {
  final base = await getTemporaryDirectory();
  return Directory('${base.path}/${prefix}_${DateTime.now().microsecondsSinceEpoch}').create(recursive: true);
}

Future<ui.Image> _logo(int size) async {
  final data = await rootBundle.load('assets/icon/icon.png');
  final codec = await ui.instantiateImageCodec(data.buffer.asUint8List(), targetWidth: size, targetHeight: size);
  return (await codec.getNextFrame()).image;
}

Future<String> _png(String path, Size size, void Function(Canvas c) paint) async {
  final recorder = ui.PictureRecorder();
  paint(Canvas(recorder));
  final image = await recorder.endRecording().toImage(size.width.round(), size.height.round());
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  await File(path).writeAsBytes(data!.buffer.asUint8List());
  return path;
}

void _text(Canvas c, String text, TextStyle style, Offset at, {double? maxWidth, bool center = false}) {
  final tp = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: TextDirection.ltr,
    maxLines: 1,
    ellipsis: '…',
  )..layout(maxWidth: maxWidth ?? double.infinity);
  tp.paint(c, center ? at - Offset(tp.width / 2, 0) : at);
}

void _logoAt(Canvas c, ui.Image logo, Rect rect) {
  c.save();
  c.clipRRect(RRect.fromRectAndRadius(rect, Radius.circular(rect.width * .24)));
  c.drawImageRect(logo, Rect.fromLTWH(0, 0, logo.width.toDouble(), logo.height.toDouble()), rect, Paint()..filterQuality = FilterQuality.high);
  c.restore();
}

const _shadow = [Shadow(color: Color(0x99000000), blurRadius: 10, offset: Offset(0, 2))];

/// Marca de agua (logo, «TREVIX» y @usuario) con fondo transparente. Devuelve la ruta y la proporción alto/ancho.
Future<(String, double)> watermarkPng(String dir, String username) async {
  const size = Size(640, 200);
  final logo = await _logo(256);
  final path = await _png('$dir/watermark.png', size, (c) {
    final shadow = Paint()
      ..color = const Color(0x66000000)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
    c.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(14, 30, 140, 140), const Radius.circular(34)), shadow);
    _logoAt(c, logo, const Rect.fromLTWH(10, 26, 140, 140));
    _text(c, 'TREVIX', const TextStyle(color: Colors.white, fontSize: 74, fontWeight: FontWeight.w900, letterSpacing: 2, shadows: _shadow),
        const Offset(172, 18));
    _text(c, '@$username', const TextStyle(color: Colors.white, fontSize: 42, fontWeight: FontWeight.w700, shadows: _shadow), const Offset(176, 110),
        maxWidth: 450);
  });
  logo.dispose();
  return (path, size.height / size.width);
}

/// Cierre del video descargado: logo, @usuario del autor y la web de la plataforma.
Future<String> outroPng(String dir, String username, double aspect) async {
  const w = 1080.0;
  final h = (w / aspect).roundToDouble();
  final unit = min(w, h);
  final logo = await _logo(512);
  final path = await _png('$dir/outro.png', Size(w, h), (c) {
    final full = Rect.fromLTWH(0, 0, w, h);
    c.drawRect(full, Paint()..color = const Color(0xFF07060D));
    c.drawRect(
      full,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(0, -.15),
          radius: .9,
          colors: [Color(0xAA7C3AED), Color(0x332563EB), Color(0x0007060D)],
        ).createShader(full),
    );
    final side = unit * .3;
    final logoRect = Rect.fromCenter(center: Offset(w / 2, h * .42), width: side, height: side);
    _logoAt(c, logo, logoRect);
    _text(c, 'TREVIX', TextStyle(color: Colors.white, fontSize: unit * .1, fontWeight: FontWeight.w900, letterSpacing: unit * .01),
        Offset(w / 2, logoRect.bottom + unit * .05), center: true);
    _text(c, '@$username', TextStyle(color: Colors.white, fontSize: unit * .058, fontWeight: FontWeight.w700),
        Offset(w / 2, logoRect.bottom + unit * .2), center: true, maxWidth: w * .9);
    _text(c, _siteLabel, TextStyle(color: const Color(0xCCFFFFFF), fontSize: unit * .045, fontWeight: FontWeight.w600),
        Offset(w / 2, h - unit * .16), center: true);
  });
  logo.dispose();
  return path;
}

/// Ejecuta un trabajo de edición informando el avance (0–1) cada 300 ms.
Future<String> renderWithProgress(VideoRenderJob job, void Function(double) onProgress) async {
  final timer = Timer.periodic(const Duration(milliseconds: 300), (_) async {
    try {
      final p = await TrevixVideo.progress();
      if (p != null) onProgress(p);
    } catch (_) {}
  });
  try {
    return await TrevixVideo.render(job);
  } finally {
    timer.cancel();
  }
}

Future<void> _download(http.Client client, String url, String path, void Function(double?) onProgress) async {
  final res = await client.send(http.Request('GET', Uri.parse(url))).timeout(const Duration(seconds: 60));
  if (res.statusCode != 200) throw DeviceException(tr('No se pudo descargar el video.'));
  final total = res.contentLength ?? 0;
  var got = 0;
  final sink = File(path).openWrite();
  try {
    await for (final chunk in res.stream) {
      sink.add(chunk);
      got += chunk.length;
      onProgress(total > 0 ? got / total : null);
    }
  } finally {
    await sink.close();
  }
  if (await File(path).length() == 0) throw DeviceException(tr('No se pudo descargar el video.'));
}

String _ext(String url, String fallback) {
  final path = Uri.parse(url).path;
  final dot = path.lastIndexOf('.');
  final ext = dot < 0 ? '' : path.substring(dot + 1).toLowerCase();
  return RegExp(r'^[a-z0-9]{2,4}$').hasMatch(ext) ? ext : fallback;
}

/// Descarga un reel a la galería como en TikTok: con su filtro, la marca de agua de TREVIX y el @usuario que cambia
/// de esquina a la mitad, la canción si se grabó a su compás y, al final, 3 s de cierre con el autor y la web.
Future<void> downloadReel(BuildContext context, Post post) async {
  final media = post.media.where((m) => m.isVideo).firstOrNull;
  if (media == null) return;
  if (!await DeviceAccess.request(Access.photos)) {
    if (context.mounted) toast(context, tr('TREVIX no tiene permiso para guardar en Fotos. Puedes activarlo en Ajustes.'), error: true);
    return;
  }
  if (!context.mounted) return;
  final status = ValueNotifier<(String, double?)>((tr('Descargando el video…'), null));
  final client = http.Client();
  var cancelled = false;
  final close = showRenderProgress(context, status, () {
    cancelled = true;
    client.close();
    TrevixVideo.cancel().ignore();
  });

  Directory? dir;
  try {
    dir = await renderDir('reel_download');
    final input = '${dir.path}/video.${_ext(media.url, 'mp4')}';
    await _download(client, media.url, input, (p) => status.value = (tr('Descargando el video…'), p));
    final song = post.song;
    final synced = media.songSync && song != null && song.available && song.audioUrl.isNotEmpty;
    String? audio;
    if (synced && !cancelled) {
      audio = '${dir.path}/song.${_ext(song.audioUrl, 'mp3')}';
      await _download(client, song.audioUrl, audio, (p) => status.value = (tr('Descargando la canción…'), p));
    }
    if (cancelled) throw const _Cancelled();
    status.value = (tr('Preparando el video…'), null);

    final info = await VideoTools.info(input);
    var aspect = 9 / 16;
    if ((media.width ?? 0) > 0 && (media.height ?? 0) > 0) {
      aspect = media.width! / media.height!;
    } else if (info.width > 0 && info.height > 0) {
      aspect = info.width / info.height;
    }
    final durationMs = ((info.seconds ?? media.duration?.toDouble() ?? 15) * 1000).round();
    final username = post.user.username;
    final (mark, markAspect) = await watermarkPng(dir.path, username);
    const markWidth = .34;
    final markHeight = markWidth * aspect * markAspect;
    final a = (x: .04 + markWidth / 2, y: .06 + markHeight / 2);
    final b = (x: 1 - .04 - markWidth / 2, y: 1 - .12 - markHeight / 2);
    final half = max(1, durationMs ~/ 2);
    final keys = [
      OverlayKey(0, x: a.x, y: a.y, width: markWidth, alpha: .92),
      OverlayKey(half - 1, x: a.x, y: a.y, width: markWidth, alpha: .92),
      OverlayKey(half, x: b.x, y: b.y, width: markWidth, alpha: .92),
      OverlayKey(durationMs, x: b.x, y: b.y, width: markWidth, alpha: .92),
    ];
    final outro = await outroPng(dir.path, username, aspect);
    if (cancelled) throw const _Cancelled();

    final output = '${dir.path}/trevix_${post.id}.mp4';
    status.value = (tr('Añadiendo la marca de agua…'), 0);
    await renderWithProgress(
      VideoRenderJob(
        input: input,
        output: output,
        colorMatrix: storyFilterMatrix(media.filter),
        overlays: [VideoOverlay(mark, keys)],
        outroImage: outro,
        outroMs: 3000,
        audio: audio,
        audioStartMs: (song?.clipStart ?? 0) * 1000,
      ),
      (p) => status.value = (tr('Añadiendo la marca de agua…'), p),
    );
    if (cancelled) throw const _Cancelled();
    status.value = (tr('Guardando en tu galería…'), null);
    await Gal.putVideo(output);
    close();
    if (context.mounted) toast(context, tr('Video guardado en tu galería.'));
  } catch (e) {
    close();
    if (cancelled || e is _Cancelled || !context.mounted) return;
    if (e is GalException) {
      toast(context, e.type == GalExceptionType.accessDenied ? tr('TREVIX no tiene permiso para guardar en Fotos.') : tr('No se pudo guardar el video.'),
          error: true);
    } else if (e is DeviceException) {
      toast(context, e.message, error: true);
    } else {
      toast(context, tr('No se pudo preparar el video. Inténtalo de nuevo.'), error: true);
    }
  } finally {
    client.close();
    if (dir != null) dir.delete(recursive: true).ignore();
  }
}

class _Cancelled implements Exception {
  const _Cancelled();
}

/// Guarda en la galería la historia completa, como se publicó:
/// - Video: con su filtro, textos, stickers y pie de foto encima, y la canción con la que se publicó (o su propio
///   sonido si no lleva canción), en el marco de la historia ([aspect], con franjas negras donde no llega el video).
/// - Foto o texto con canción: un video de lo que dura la historia con la imagen tal como se ve y la canción.
/// - Foto o texto sin canción: la imagen tal como se ve.
/// - Foto en movimiento: su video corto con el filtro, lo de encima y la canción (sin su sonido propio).
/// Los textos con fuentes y efectos, los collages y los stickers salen igual porque se capturan de la pantalla.
/// [capture] devuelve la historia entera como PNG; [captureLayers], solo lo que va encima del video (fondo
/// transparente) o null si no hay nada encima.
Future<void> downloadStory(
  BuildContext context,
  StoryItem item, {
  required double aspect,
  required Future<Uint8List?> Function() capture,
  required Future<Uint8List?> Function() captureLayers,
}) async {
  if (!await DeviceAccess.request(Access.photos)) {
    if (context.mounted) toast(context, tr('TREVIX no tiene permiso para guardar en Fotos. Puedes activarlo en Ajustes.'), error: true);
    return;
  }
  if (!context.mounted) return;
  final song = item.song != null && item.song!.available && item.song!.audioUrl.isNotEmpty ? item.song : null;
  final video = item.isVideo && item.mediaUrl != null;

  if (!video && song == null) {
    final bytes = await capture();
    if (bytes == null) throw DeviceException(tr('No se pudo guardar la imagen.'));
    await DeviceAccess.saveImageBytes(bytes);
    if (context.mounted) toast(context, tr('Imagen guardada en tu galería.'));
    return;
  }
  // Las fotos en movimiento se guardan como su video corto con todo lo de encima; sin su sonido propio, que en la
  // historia no se oye.
  final live = video && item.live;

  // Lo que se captura de la pantalla se toma antes de abrir el diálogo, que lo taparía.
  final still = video ? null : await capture();
  if (!video && still == null) throw DeviceException(tr('No se pudo guardar la imagen.'));
  final layers = video ? await captureLayers() : null;
  if (!context.mounted) return;

  final status = ValueNotifier<(String, double?)>((tr('Preparando la historia…'), null));
  final client = http.Client();
  var cancelled = false;
  final close = showRenderProgress(context, status, () {
    cancelled = true;
    client.close();
    TrevixVideo.cancel().ignore();
  });
  Directory? dir;
  try {
    dir = await renderDir('story_download');
    String input;
    if (video) {
      input = '${dir.path}/video.${_ext(item.mediaUrl!, 'mp4')}';
      await _download(client, item.mediaUrl!, input, (p) => status.value = (tr('Descargando el video…'), p));
    } else {
      input = '${dir.path}/story.png';
      await File(input).writeAsBytes(still!);
    }
    String? audio;
    if (song != null && !cancelled) {
      audio = '${dir.path}/song.${_ext(song.audioUrl, 'mp3')}';
      await _download(client, song.audioUrl, audio, (p) => status.value = (tr('Descargando la canción…'), p));
    }
    if (cancelled) throw const _Cancelled();

    final overlays = <VideoOverlay>[];
    if (layers != null) {
      final path = '${dir.path}/layers.png';
      await File(path).writeAsBytes(layers);
      overlays.add(VideoOverlay(path, const [OverlayKey(0, x: .5, y: .5, width: 1)]));
    }
    final matrix = video ? storyFilterMatrix(item.filter) : null;
    String output = input;
    if (!video || live || audio != null || overlays.isNotEmpty || matrix != null) {
      output = '${dir.path}/trevix_story_${item.id}.mp4';
      status.value = (tr('Preparando la historia…'), 0);
      await renderWithProgress(
        VideoRenderJob(
          input: input,
          output: output,
          imageMs: video ? 0 : (item.seconds > 0 ? item.seconds : 15) * 1000,
          aspect: aspect,
          contain: video,
          colorMatrix: matrix,
          overlays: overlays,
          audio: audio,
          audioStartMs: (song?.clipStart ?? 0) * 1000,
          keepAudio: !live,
        ),
        (p) => status.value = (tr('Preparando la historia…'), p),
      );
    }
    if (cancelled) throw const _Cancelled();
    status.value = (tr('Guardando en tu galería…'), null);
    await Gal.putVideo(output);
    close();
    if (context.mounted) toast(context, tr('Video guardado en tu galería.'));
  } catch (e) {
    close();
    if (cancelled || e is _Cancelled || !context.mounted) return;
    if (e is GalException) {
      toast(context, e.type == GalExceptionType.accessDenied ? tr('TREVIX no tiene permiso para guardar en Fotos.') : tr('No se pudo guardar el video.'),
          error: true);
    } else if (e is DeviceException) {
      toast(context, e.message, error: true);
    } else {
      toast(context, tr('No se pudo preparar la historia. Inténtalo de nuevo.'), error: true);
    }
  } finally {
    client.close();
    if (dir != null) dir.delete(recursive: true).ignore();
  }
}

/// Abre [RenderProgressDialog] y devuelve la función que lo cierra. Se cierra esa ruta concreta y una sola vez: nunca
/// la pantalla de debajo, aunque coincidan «Cancelar» y el final del trabajo.
VoidCallback showRenderProgress(BuildContext context, ValueListenable<(String, double?)> status, VoidCallback onCancel) {
  final navigator = Navigator.of(context, rootNavigator: true);
  late final DialogRoute<void> route;
  void close() {
    if (route.isActive) navigator.removeRoute(route);
  }

  route = DialogRoute<void>(
    context: context,
    barrierDismissible: false,
    themes: InheritedTheme.capture(from: context, to: navigator.context),
    builder: (_) => RenderProgressDialog(
      status: status,
      onCancel: () {
        onCancel();
        close();
      },
    ),
  );
  unawaited(navigator.push(route));
  return close;
}

/// Diálogo con el paso actual, la barra de avance y «Cancelar».
class RenderProgressDialog extends StatelessWidget {
  const RenderProgressDialog({super.key, required this.status, required this.onCancel});

  final ValueListenable<(String, double?)> status;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Dialog(
        backgroundColor: TxDark.surface2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 22, 22, 10),
          child: ValueListenableBuilder<(String, double?)>(
            valueListenable: status,
            builder: (context, s, _) {
              final (label, progress) = s;
              return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text(label, style: TxDark.body(15, weight: FontWeight.w700, color: Colors.white)),
                const SizedBox(height: 16),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 6,
                    backgroundColor: Colors.white12,
                    valueColor: AlwaysStoppedAnimation(Tx.purple300),
                  ),
                ),
                const SizedBox(height: 8),
                Text(progress == null ? ' ' : '${(progress * 100).round()} %', textAlign: TextAlign.right, style: TxDark.body(12.5, color: Colors.white70)),
                Align(
                  alignment: Alignment.centerRight,
                  child: CupertinoButton(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    onPressed: onCancel,
                    child: Text(tr('Cancelar'), style: TxDark.body(15, weight: FontWeight.w600, color: Tx.purple300)),
                  ),
                ),
              ]);
            },
          ),
        ),
      ),
    );
  }
}
