import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

import '../../core/api.dart';
import '../../core/audio.dart';
import '../../core/catalog.dart';
import '../../core/events.dart';
import '../../core/nav.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';
import '../../widgets/song_chip.dart';
import '../music/music_picker.dart';

/// Nueva historia: de texto sobre un fondo de la marca, o una foto o video corto, con canción opcional.
class StoryCreateScreen extends StatefulWidget {
  const StoryCreateScreen({super.key});

  @override
  State<StoryCreateScreen> createState() => _StoryCreateScreenState();
}

class _StoryCreateScreenState extends State<StoryCreateScreen> {
  bool _textMode = true;
  String _background = 'violet';
  final _text = TextEditingController();
  final _caption = TextEditingController();
  XFile? _file;
  bool _isVideo = false;
  VideoPlayerController? _video;
  PickedSong? _song;
  bool _busy = false;

  @override
  void dispose() {
    _text.dispose();
    _caption.dispose();
    _video?.dispose();
    songPlayer.stop();
    super.dispose();
  }

  Future<void> _pick(ImageSource source, bool video) async {
    final picker = ImagePicker();
    try {
      final file = video
          ? await picker.pickVideo(source: source, maxDuration: const Duration(seconds: 30))
          : await picker.pickImage(source: source, maxWidth: 2160, imageQuality: 90);
      if (file == null) return;
      _video?.dispose();
      _video = null;
      if (video) {
        final c = VideoPlayerController.file(File(file.path));
        await c.initialize();
        if (c.value.duration > const Duration(seconds: 31)) {
          c.dispose();
          if (mounted) toast(context, 'El video puede durar como mucho 30 segundos.', error: true);
          return;
        }
        await c.setLooping(true);
        await c.setVolume(_song == null ? 1 : 0);
        c.play();
        _video = c;
      }
      setState(() {
        _file = file;
        _isVideo = video;
        _textMode = false;
      });
    } catch (e) {
      if (mounted) toast(context, 'No se pudo abrir el archivo. Revisa los permisos de Fotos y Cámara.', error: true);
    }
  }

  void _chooseMedia() {
    actionSheet(context, [
      SheetAction('Foto de la galería', CupertinoIcons.photo, () => _pick(ImageSource.gallery, false)),
      SheetAction('Video de la galería', CupertinoIcons.film, () => _pick(ImageSource.gallery, true)),
      SheetAction('Tomar foto', CupertinoIcons.camera, () => _pick(ImageSource.camera, false)),
      SheetAction('Grabar video', CupertinoIcons.videocam, () => _pick(ImageSource.camera, true)),
    ]);
  }

  Future<void> _chooseSong() async {
    final seconds = context.read<AppState>().limit('song_clip_seconds', 30);
    final picked = await pickSong(context, clipSeconds: seconds, current: _song);
    if (picked == null || !mounted) return;
    setState(() => _song = picked);
    _video?.setVolume(0);
    songPlayer.play('story-new', picked.song.withClip(picked.start, seconds), clip: true, loop: true);
  }

  void _removeSong() {
    songPlayer.stop();
    _video?.setVolume(1);
    setState(() => _song = null);
  }

  Future<void> _publish() async {
    FocusScope.of(context).unfocus();
    if (_textMode && _text.text.trim().isEmpty) {
      toast(context, 'Escribe el texto de tu historia.', error: true);
      return;
    }
    if (!_textMode && _file == null) {
      toast(context, 'Elige una foto o un video.', error: true);
      return;
    }
    setState(() => _busy = true);
    final song = _song;
    try {
      final ApiResponse res;
      if (_textMode) {
        res = await api.post('stories', {
          'type': 'text',
          'text': _text.text.trim(),
          'background': _background,
          if (song != null) 'song_id': song.song.id,
          if (song != null) 'song_start': song.start,
        });
      } else {
        res = await api.upload('stories', fields: {
          'type': 'media',
          'caption': _caption.text.trim(),
          if (song != null) 'song_id': '${song.song.id}',
          if (song != null) 'song_start': '${song.start}',
        }, files: [
          Upload('media', _file!.path, filename: _file!.name),
        ]);
      }
      storiesChanged.value++;
      if (!mounted) return;
      toast(context, '${res.map['message'] ?? 'Tu historia se publicó.'}');
      Navigator.pop(context);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        toast(context, e.fields.values.isNotEmpty ? e.fields.values.first : e.message, error: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final maxText = context.read<AppState>().limit('story_text', 300);
    final maxCaption = context.read<AppState>().limit('story_caption', 200);
    return Scaffold(
      backgroundColor: Colors.black,
      resizeToAvoidBottomInset: true,
      body: Stack(fit: StackFit.expand, children: [
        if (_textMode)
          AnimatedContainer(
            duration: const Duration(milliseconds: 400),
            decoration: BoxDecoration(gradient: Tx.storyBackground(_background)),
            child: SafeArea(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 90),
                  child: TextField(
                    controller: _text,
                    autofocus: true,
                    maxLength: maxText,
                    maxLines: null,
                    textAlign: TextAlign.center,
                    textCapitalization: TextCapitalization.sentences,
                    style: Tx.display(30, color: Colors.white, height: 1.25),
                    cursorColor: Colors.white,
                    decoration: InputDecoration(
                      border: InputBorder.none,
                      hintText: 'Escribe algo…',
                      hintStyle: Tx.display(30, color: Colors.white.withAlpha(140)),
                      counterStyle: Tx.body(12, color: Colors.white.withAlpha(170)),
                    ),
                  ),
                ),
              ),
            ),
          )
        else
          _mediaPreview(),
        SafeArea(
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 4, 10, 0),
              child: Row(children: [
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(CupertinoIcons.xmark, color: Colors.white, size: 24),
                ),
                const Spacer(),
                _ModeSwitch(
                  textMode: _textMode,
                  onChanged: (text) {
                    if (text) {
                      setState(() => _textMode = true);
                    } else if (_file == null) {
                      _chooseMedia();
                    } else {
                      setState(() => _textMode = false);
                    }
                  },
                ),
                const Spacer(),
                const SizedBox(width: 48),
              ]),
            ),
            const Spacer(),
            if (!_textMode && _file != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                child: TextField(
                  controller: _caption,
                  maxLength: maxCaption,
                  style: Tx.body(15, color: Colors.white),
                  decoration: InputDecoration(
                    counterText: '',
                    hintText: 'Añade un texto (opcional)',
                    hintStyle: Tx.body(15, color: Colors.white.withAlpha(170)),
                    filled: true,
                    fillColor: Colors.black.withAlpha(110),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: BorderSide.none),
                  ),
                ),
              ),
            if (_song != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                child: Row(children: [
                  Expanded(child: SongChip(song: _song!.song.withClip(_song!.start), playKey: 'story-new', clip: true, compact: true)),
                  IconButton(onPressed: _removeSong, icon: const Icon(CupertinoIcons.xmark_circle_fill, color: Colors.white)),
                ]),
              ),
            if (_textMode)
              SizedBox(
                height: 50,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  children: [
                    for (final key in storyBackgrounds.keys)
                      GestureDetector(
                        onTap: () => setState(() => _background = key),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          width: 40,
                          height: 40,
                          margin: const EdgeInsets.symmetric(horizontal: 5),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: Tx.storyBackground(key),
                            border: Border.all(color: Colors.white, width: _background == key ? 3 : 1),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Row(children: [
                _RoundTool(icon: CupertinoIcons.music_note_2, label: _song == null ? 'Música' : 'Cambiar', onTap: _chooseSong),
                const SizedBox(width: 10),
                if (!_textMode) _RoundTool(icon: CupertinoIcons.photo_on_rectangle, label: 'Cambiar', onTap: _chooseMedia),
                const Spacer(),
                SizedBox(
                  width: 150,
                  child: GradientButton(label: 'Compartir', icon: CupertinoIcons.paperplane_fill, loading: _busy, onPressed: _publish, height: 48),
                ),
              ]),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _mediaPreview() {
    final file = _file;
    if (file == null) {
      return Container(
        decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Tx.surface3, Colors.black])),
        child: Center(
          child: GestureDetector(
            onTap: _chooseMedia,
            child: const EmptyState(icon: CupertinoIcons.photo_on_rectangle, title: 'Elige una foto o un video', message: 'Videos de hasta 30 segundos.'),
          ),
        ),
      );
    }
    if (_isVideo) {
      final v = _video;
      if (v == null || !v.value.isInitialized) return const Center(child: CupertinoActivityIndicator(color: Colors.white));
      return Center(child: AspectRatio(aspectRatio: v.value.aspectRatio, child: VideoPlayer(v)));
    }
    return Image.file(File(file.path), fit: BoxFit.contain);
  }
}

class _ModeSwitch extends StatelessWidget {
  const _ModeSwitch({required this.textMode, required this.onChanged});

  final bool textMode;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget seg(String label, bool selected, bool value) => GestureDetector(
          onTap: () => onChanged(value),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(color: selected ? Colors.white : Colors.transparent, borderRadius: BorderRadius.circular(18)),
            child: Text(label, style: Tx.body(14, weight: FontWeight.w600, color: selected ? Colors.black : Colors.white)),
          ),
        );
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: Colors.black.withAlpha(90), borderRadius: BorderRadius.circular(21)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        seg('Texto', textMode, true),
        seg('Foto o video', !textMode, false),
      ]),
    );
  }
}

class _RoundTool extends StatelessWidget {
  const _RoundTool({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(color: Colors.black.withAlpha(110), borderRadius: BorderRadius.circular(22), border: Border.all(color: Colors.white.withAlpha(50))),
        child: Row(children: [
          Icon(icon, color: Colors.white, size: 18),
          const SizedBox(width: 6),
          Text(label, style: Tx.body(13.5, weight: FontWeight.w600, color: Colors.white)),
        ]),
      ),
    );
  }
}
