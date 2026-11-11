import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import '../../core/audio.dart';
import '../../core/chat_media.dart';
import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/nav.dart';
import '../../core/theme.dart';
import '../../core/video_tools.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';
import '../../widgets/media.dart' show FittedVideo, KeyboardLift, StableSafeArea, clockText;
import 'photo_editor.dart' show ViewChip;

/// Peso y duración máximos de un video del chat (el servidor los vuelve a comprobar).
const chatVideoMaxBytes = 64 * 1024 * 1024;
const chatVideoMaxSeconds = 180;

/// Video listo para enviar: [viewSeconds] null = normal, 0 = una vez, 3/5/10 = segundos.
class PreparedVideo {
  PreparedVideo({required this.path, this.viewSeconds, this.caption = '', this.seconds = 0, this.width = 0, this.height = 0, this.poster});

  final String path;
  final int? viewSeconds;
  final String caption;
  final int seconds;
  final int width;
  final int height;
  final String? poster;
}

/// Revisa el video elegido (peso y duración) y abre la pantalla para enviarlo. null si se canceló o no es válido.
Future<PreparedVideo?> prepareVideo(BuildContext context, String path, {List<int> viewSeconds = const [0, 3, 5, 10]}) async {
  final size = await File(path).length();
  if (!context.mounted) return null;
  if (size > chatVideoMaxBytes) {
    toast(context, tr('El video pesa {size} MB y el máximo es {max} MB.', {'size': (size / 1048576).round(), 'max': chatVideoMaxBytes ~/ 1048576}), error: true);
    return null;
  }
  final info = await VideoTools.info(path);
  if (!context.mounted) return null;
  final seconds = info.seconds;
  if (seconds != null && seconds > chatVideoMaxSeconds + 0.5) {
    toast(context, tr('El video dura {length}. En los chats pueden durar hasta {max} minutos.', {'length': clockText(seconds.round()), 'max': clockText(chatVideoMaxSeconds)}), error: true);
    return null;
  }
  return push<PreparedVideo>(context, SendVideoScreen(path: path, info: info, viewSeconds: viewSeconds), fullscreen: true);
}

class SendVideoScreen extends StatefulWidget {
  const SendVideoScreen({super.key, required this.path, required this.info, this.viewSeconds = const [0, 3, 5, 10]});

  final String path;
  final VideoInfo info;
  final List<int> viewSeconds;

  @override
  State<SendVideoScreen> createState() => _SendVideoScreenState();
}

class _SendVideoScreenState extends State<SendVideoScreen> {
  late final VideoPlayerController _c = VideoPlayerController.file(File(widget.path));
  final _caption = TextEditingController();
  int? _view;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    songPlayer.pause();
    _c.initialize().then((_) {
      if (!mounted) return;
      _c.setLooping(true);
      _c.play();
      setState(() {});
    }).catchError((_) {});
  }

  @override
  void dispose() {
    _c.dispose();
    _caption.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_busy) return;
    setState(() => _busy = true);
    await _c.pause();
    final seconds = widget.info.seconds;
    final poster = _view == null ? await VideoTools.poster(widget.path, seconds) : null;
    if (!mounted) return;
    Navigator.of(context).pop(PreparedVideo(
      path: widget.path,
      viewSeconds: _view,
      caption: _view == null ? _caption.text.trim() : '',
      seconds: seconds?.round() ?? 0,
      width: widget.info.width,
      height: widget.info.height,
      poster: poster,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final options = <int?>[null, ...widget.viewSeconds];
    return TxDark.scope(
      context,
      AnnotatedRegion<SystemUiOverlayStyle>(
        value: Tx.immersive,
        child: Scaffold(
          backgroundColor: Colors.black,
          resizeToAvoidBottomInset: false,
          body: StableSafeArea(
            child: Column(children: [
              Row(children: [
                CupertinoButton(
                  padding: const EdgeInsets.all(12),
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Icon(CupertinoIcons.xmark, color: Colors.white, size: 26),
                ),
                const Spacer(),
                if (widget.info.seconds != null)
                  Padding(
                    padding: const EdgeInsets.only(right: 16),
                    child: Text(clock(widget.info.seconds!), style: TxDark.body(14, weight: FontWeight.w600)),
                  ),
              ]),
              Expanded(
                child: GestureDetector(
                  onTap: () => _c.value.isPlaying ? _c.pause() : _c.play(),
                  child: _c.value.isInitialized
                      ? FittedVideo(controller: _c)
                      : const Center(child: CupertinoActivityIndicator(color: Colors.white, radius: 14)),
                ),
              ),
              KeyboardLift(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
              const SizedBox(height: 10),
              SizedBox(
                height: 40,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  children: [
                    for (final o in options)
                      ViewChip(
                        label: o == null ? tr('Normal') : (o == 0 ? tr('1 vez') : '$o s'),
                        icon: o == null ? null : (o == 0 ? CupertinoIcons.eye : CupertinoIcons.timer),
                        selected: _view == o,
                        onTap: () => setState(() => _view = o),
                      ),
                  ],
                ),
              ),
              if (_view != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
                  child: Text(
                    _view == 0 ? tr('Se podrá ver una sola vez.') : tr('Se podrá ver una vez durante {n} segundos.', {'n': _view}),
                    style: TxDark.body(12.5, color: Colors.white70),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                child: Row(children: [
                  Expanded(
                    child: TextField(
                      controller: _caption,
                      enabled: _view == null,
                      maxLength: 500,
                      minLines: 1,
                      maxLines: 3,
                      style: TxDark.body(15),
                      cursorColor: Colors.white,
                      decoration: InputDecoration(
                        counterText: '',
                        hintText: _view == null ? tr('Añade un comentario…') : tr('Sin comentario en videos de una vez'),
                        hintStyle: TxDark.body(15, color: Colors.white54),
                        filled: true,
                        fillColor: Colors.white.withAlpha(30),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  GestureDetector(
                    onTap: _send,
                    child: Container(
                      width: 50,
                      height: 50,
                      decoration: const BoxDecoration(gradient: Tx.brand, shape: BoxShape.circle),
                      child: _busy
                          ? const Center(child: CupertinoActivityIndicator(color: Colors.white))
                          : const Icon(CupertinoIcons.paperplane_fill, color: Colors.white, size: 22),
                    ),
                  ),
                ]),
              ),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Reproductor a pantalla completa de un video del chat (de internet o ya descifrado en el teléfono).
class ChatVideoScreen extends StatefulWidget {
  const ChatVideoScreen({super.key, this.url, this.file});

  final String? url;
  final File? file;

  @override
  State<ChatVideoScreen> createState() => _ChatVideoScreenState();
}

class _ChatVideoScreenState extends State<ChatVideoScreen> {
  late final VideoPlayerController _c =
      widget.file != null ? VideoPlayerController.file(widget.file!) : VideoPlayerController.networkUrl(Uri.parse(widget.url!));
  bool _failed = false;
  final _zoom = TransformationController();
  bool _zoomed = false;

  /// Sin ampliar, el video vuelve exactamente al centro y a su tamaño.
  void _settle() {
    final zoomed = _zoom.value.getMaxScaleOnAxis() > 1.01;
    if (!zoomed) _zoom.value = Matrix4.identity();
    if (zoomed != _zoomed) setState(() => _zoomed = zoomed);
  }

  @override
  void initState() {
    super.initState();
    FocusManager.instance.primaryFocus?.unfocus();
    songPlayer.pause();
    _c.addListener(_tick);
    _c.initialize().then((_) {
      if (mounted) _c.play();
    }).catchError((_) {
      if (mounted) setState(() => _failed = true);
    });
  }

  void _tick() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _c.removeListener(_tick);
    _c.dispose();
    _zoom.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final v = _c.value;
    final total = v.duration.inMilliseconds;
    return TxDark.scope(
      context,
      AnnotatedRegion<SystemUiOverlayStyle>(
        value: Tx.immersive,
        child: MediaQuery.removeViewInsets(
          context: context,
          removeBottom: true,
          child: Scaffold(
          backgroundColor: Colors.black,
          resizeToAvoidBottomInset: false,
          body: SizedBox.expand(child: Stack(children: [
            Positioned.fill(
              child: GestureDetector(
                onTap: () => v.isPlaying ? _c.pause() : _c.play(),
                child: _failed
                    ? Center(child: Text(tr('No se pudo reproducir el video.'), style: TxDark.body(15)))
                    : v.isInitialized
                        ? InteractiveViewer(
                            transformationController: _zoom,
                            minScale: 1,
                            maxScale: 4,
                            panEnabled: _zoomed,
                            onInteractionEnd: (_) => _settle(),
                            child: FittedVideo(controller: _c),
                          )
                        : const Center(child: CupertinoActivityIndicator(color: Colors.white, radius: 14)),
              ),
            ),
            if (v.isInitialized && !v.isPlaying)
              const IgnorePointer(child: Center(child: Icon(CupertinoIcons.play_circle_fill, color: Colors.white70, size: 72))),
            SafeArea(
              child: CupertinoButton(
                padding: const EdgeInsets.all(14),
                onPressed: () => Navigator.of(context).pop(),
                child: const Icon(CupertinoIcons.xmark, color: Colors.white, size: 26),
              ),
            ),
            if (v.isInitialized)
              Positioned(
                left: 16,
                right: 16,
                bottom: 0,
                child: SafeArea(
                  top: false,
                  child: Row(children: [
                    Text(clock(v.position.inMilliseconds / 1000), style: TxDark.body(12.5, weight: FontWeight.w600)),
                    Expanded(
                      child: Slider(
                        value: total > 0 ? (v.position.inMilliseconds / total).clamp(0.0, 1.0).toDouble() : 0,
                        activeColor: Colors.white,
                        inactiveColor: Colors.white24,
                        onChanged: total > 0 ? (x) => _c.seekTo(Duration(milliseconds: (x * total).round())) : null,
                      ),
                    ),
                    Text(clock(total / 1000), style: TxDark.body(12.5, weight: FontWeight.w600)),
                  ]),
                ),
              ),
          ])),
        ),
        ),
      ),
    );
  }
}

/// Video dentro de la burbuja: miniatura con el botón de reproducir y la duración. Los cifrados se descargan y
/// descifran al tocarlos (y quedan en la caché del teléfono).
class ChatVideoTile extends StatefulWidget {
  const ChatVideoTile({super.key, required this.message});

  final Message message;

  @override
  State<ChatVideoTile> createState() => _ChatVideoTileState();
}

class _ChatVideoTileState extends State<ChatVideoTile> {
  bool _loading = false;

  Future<void> _open() async {
    final m = widget.message;
    final video = m.video;
    if (video != null) {
      pushFade(context, ChatVideoScreen(url: video.url));
      return;
    }
    if (_loading) return;
    setState(() => _loading = true);
    try {
      final file = await ChatMedia.load(m);
      if (mounted) pushFade(context, ChatVideoScreen(file: file));
    } catch (_) {
      if (mounted) toast(context, tr('No se pudo abrir el video.'), error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.message;
    final video = m.video;
    final p = m.payload;
    final aspect = (video?.aspect ?? p?.aspect ?? 9 / 16).clamp(.56, 1.8).toDouble();
    const width = 220.0;
    final seconds = video?.duration ?? p?.duration ?? 0;
    final thumb = p?.thumb;
    Widget cover;
    if (video?.posterUrl != null) {
      cover = NetImage(video!.posterUrl, fit: BoxFit.cover, width: width, height: width / aspect);
    } else if (thumb != null) {
      cover = Image.memory(thumb, fit: BoxFit.cover, width: width, height: width / aspect, gaplessPlayback: true);
    } else {
      cover = Container(width: width, height: width / aspect, color: const Color(0xFF1C1C1F));
    }
    return GestureDetector(
      onTap: _open,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: SizedBox(
          width: width,
          height: width / aspect,
          child: Stack(fit: StackFit.expand, children: [
            cover,
            Center(
              child: Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.black.withAlpha(120)),
                child: _loading ? const CupertinoActivityIndicator(color: Colors.white) : const Icon(CupertinoIcons.play_fill, color: Colors.white, size: 24),
              ),
            ),
            if (seconds > 0)
              Positioned(
                right: 8,
                bottom: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(color: Colors.black.withAlpha(140), borderRadius: BorderRadius.circular(10)),
                  child: Text(clock(seconds), style: TxDark.body(11.5, weight: FontWeight.w600)),
                ),
              ),
          ]),
        ),
      ),
    );
  }
}
