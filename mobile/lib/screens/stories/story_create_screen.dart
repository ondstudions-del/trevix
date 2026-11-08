import 'dart:convert';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

import '../../core/api.dart';
import '../../core/audio.dart';
import '../../core/catalog.dart';
import '../../core/device.dart';
import '../../core/events.dart';
import '../../core/nav.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';
import '../../widgets/gif_picker.dart';
import '../../widgets/song_chip.dart';
import '../../widgets/story_layers.dart';
import '../music/music_picker.dart';
import 'story_editor_tools.dart';

/// Nueva historia: de texto sobre un fondo de la marca, o una foto o video corto con canción, filtro y capas
/// (textos, stickers, ubicación, encuesta, menciones y enlace) que se mueven, giran y escalan con los dedos.
class StoryCreateScreen extends StatefulWidget {
  const StoryCreateScreen({super.key});

  @override
  State<StoryCreateScreen> createState() => _StoryCreateScreenState();
}

class _StoryCreateScreenState extends State<StoryCreateScreen> {
  static const _limits = {'text': 5, 'sticker': 5, 'location': 1, 'poll': 1, 'mention': 5, 'link': 1};
  static const _maxLayers = 12;

  bool _textMode = true;
  String _background = 'violet';
  final _text = TextEditingController();
  final _caption = TextEditingController();
  XFile? _file;
  bool _isVideo = false;
  VideoPlayerController? _video;
  PickedSong? _song;
  bool _busy = false;

  final List<StoryLayer> _layers = [];
  String? _filter;
  bool _showFilters = false;
  bool _locating = false;
  StoryLayer? _dragging;
  bool _overTrash = false;
  double _startScale = 1;
  double _startRotation = 0;

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

  // ---- Capas ----

  bool _canAdd(String type) {
    final count = _layers.where((l) => l.type == type).length;
    final limit = _limits[type] ?? 1;
    if (_layers.length >= _maxLayers) {
      toast(context, 'Puedes añadir como mucho $_maxLayers elementos a una historia.', error: true);
      return false;
    }
    if (count >= limit) {
      toast(context, limit == 1 ? 'Solo puedes añadir uno de este tipo.' : 'Puedes añadir como mucho $limit de este tipo.', error: true);
      return false;
    }
    return true;
  }

  void _add(StoryLayer layer) {
    final offset = (_layers.length % 4) * .04;
    layer
      ..x = .5
      ..y = (layer.type == 'poll' ? .5 : .4) + offset;
    setState(() => _layers.add(layer));
  }

  Future<void> _addText() async {
    if (!_canAdd('text')) return;
    final r = await editStoryText(context);
    if (r == null || r.text.isEmpty || !mounted) return;
    _add(StoryLayer(type: 'text', text: r.text, color: r.color, style: r.style));
  }

  Future<void> _openStickers() async {
    final picked = await pickStorySticker(context, header: (sheet) {
      Widget chip(IconData icon, String label, String key) => Expanded(
            child: GestureDetector(
              onTap: () => Navigator.pop(sheet, key),
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 4),
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(color: Tx.surface3, borderRadius: BorderRadius.circular(16), border: Border.all(color: Tx.border)),
                child: Column(children: [
                  Icon(icon, color: Tx.purple300, size: 22),
                  const SizedBox(height: 6),
                  Text(label, style: Tx.body(12.5, weight: FontWeight.w600)),
                ]),
              ),
            ),
          );
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: Row(children: [
          chip(CupertinoIcons.location_solid, 'Ubicación', 'location'),
          chip(CupertinoIcons.chart_bar_alt_fill, 'Encuesta', 'poll'),
          chip(CupertinoIcons.at, 'Mención', 'mention'),
          chip(CupertinoIcons.link, 'Enlace', 'link'),
        ]),
      );
    });
    if (!mounted || picked == null) return;
    if (picked is Gif) {
      if (!_canAdd('sticker')) return;
      _add(StoryLayer(type: 'sticker', gifId: picked.id, url: picked.url, width: picked.width, height: picked.height));
      return;
    }
    switch (picked) {
      case 'location':
        _addLocation();
      case 'poll':
        _addPoll();
      case 'mention':
        _addMention();
      case 'link':
        _addLink();
    }
  }

  void _addLocation() {
    if (!_canAdd('location')) return;
    actionSheet(context, [
      SheetAction('Usar mi ubicación actual', CupertinoIcons.location_fill, () async {
        setState(() => _locating = true);
        try {
          final place = await DeviceAccess.currentPlace();
          final name = place.name.length > 80 ? place.name.substring(0, 80) : place.name;
          if (mounted && _canAdd('location')) _add(StoryLayer(type: 'location', name: name));
        } catch (e) {
          if (mounted) toastError(context, e);
        }
        if (mounted) setState(() => _locating = false);
      }),
      SheetAction('Escribir un lugar', CupertinoIcons.pencil, () async {
        final name = await prompt(context, '¿Dónde estás?', hint: 'Ej.: Parque Simón Bolívar, Bogotá', action: 'Añadir', maxLength: 80);
        final clean = name?.trim() ?? '';
        if (clean.length >= 2 && mounted && _canAdd('location')) _add(StoryLayer(type: 'location', name: clean));
      }),
    ], title: 'Ubicación');
  }

  Future<void> _addPoll() async {
    if (!_canAdd('poll')) return;
    final r = await editStoryPoll(context);
    if (r == null || !mounted) return;
    _add(StoryLayer(type: 'poll', question: r.question, options: r.options));
  }

  Future<void> _addMention() async {
    if (!_canAdd('mention')) return;
    final username = await pickMention(context);
    if (username == null || !mounted) return;
    if (_layers.any((l) => l.type == 'mention' && l.username.toLowerCase() == username.toLowerCase())) {
      toast(context, 'Ya mencionaste a @$username.', error: true);
      return;
    }
    _add(StoryLayer(type: 'mention', username: username));
  }

  Future<void> _addLink() async {
    if (!_canAdd('link')) return;
    final r = await editStoryLink(context);
    if (r == null || !mounted) return;
    _add(StoryLayer(type: 'link', url: r.url, label: r.label));
  }

  Future<void> _editLayer(StoryLayer layer) async {
    switch (layer.type) {
      case 'text':
        final r = await editStoryText(context, text: layer.text, color: layer.color, style: layer.style);
        if (r == null || !mounted) return;
        setState(() {
          if (r.text.isEmpty) {
            _layers.remove(layer);
          } else {
            layer
              ..text = r.text
              ..color = r.color
              ..style = r.style;
          }
        });
      case 'poll':
        final r = await editStoryPoll(context, question: layer.question, options: layer.options);
        if (r == null || !mounted) return;
        setState(() {
          layer
            ..question = r.question
            ..options = r.options;
        });
      case 'link':
        final r = await editStoryLink(context, url: layer.url ?? '', label: layer.label);
        if (r == null || !mounted) return;
        final index = _layers.indexOf(layer);
        if (index < 0) return;
        final updated = StoryLayer(type: 'link', url: r.url, label: r.label, x: layer.x, y: layer.y, scale: layer.scale, rotation: layer.rotation);
        setState(() => _layers[index] = updated);
      default:
        _layerMenu(layer);
    }
  }

  void _layerMenu(StoryLayer layer) {
    actionSheet(context, [
      SheetAction('Quitar de la historia', CupertinoIcons.trash, () => setState(() => _layers.remove(layer)), destructive: true),
    ]);
  }

  Offset _trashCenter(Size screen) => Offset(screen.width / 2, screen.height - MediaQuery.of(context).padding.bottom - 70);

  // ---- Publicar ----

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
          if (_layers.isNotEmpty) 'overlays': jsonEncode(_layers.map((l) => l.toJson()).toList()),
          if (_filter != null) 'filter': _filter!,
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
    final editing = !_textMode && _file != null;
    final dragging = _dragging != null;
    final screen = MediaQuery.of(context).size;
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
        if (editing) Positioned.fill(child: _layersCanvas()),
        IgnorePointer(
          ignoring: dragging,
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 150),
            opacity: dragging ? 0 : 1,
            child: SafeArea(
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
                Expanded(
                  child: Align(
                    alignment: Alignment.topRight,
                    child: editing ? _sideTools() : const SizedBox.shrink(),
                  ),
                ),
                if (editing && _showFilters) _filterStrip(),
                if (editing)
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
                    if (!editing) _RoundTool(icon: CupertinoIcons.music_note_2, label: _song == null ? 'Música' : 'Cambiar', onTap: _chooseSong),
                    if (editing) _RoundTool(icon: CupertinoIcons.photo_on_rectangle, label: 'Cambiar', onTap: _chooseMedia),
                    const Spacer(),
                    SizedBox(
                      width: 150,
                      child: GradientButton(label: 'Compartir', icon: CupertinoIcons.paperplane_fill, loading: _busy, onPressed: _publish, height: 48),
                    ),
                  ]),
                ),
              ]),
            ),
          ),
        ),
        if (dragging)
          Positioned(
            left: _trashCenter(screen).dx - 28,
            top: _trashCenter(screen).dy - 28,
            child: IgnorePointer(
              child: AnimatedScale(
                duration: const Duration(milliseconds: 120),
                scale: _overTrash ? 1.25 : 1,
                child: Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _overTrash ? Tx.danger : Colors.black.withAlpha(140),
                    border: Border.all(color: Colors.white, width: 1.5),
                  ),
                  child: const Icon(CupertinoIcons.trash, color: Colors.white, size: 24),
                ),
              ),
            ),
          ),
        if (_locating)
          const Positioned.fill(
            child: ColoredBox(color: Color(0x66000000), child: Center(child: CupertinoActivityIndicator(color: Colors.white, radius: 14))),
          ),
      ]),
    );
  }

  Widget _layersCanvas() {
    return LayoutBuilder(builder: (context, box) {
      final size = Size(box.maxWidth, box.maxHeight);
      return Stack(clipBehavior: Clip.hardEdge, children: [
        for (final layer in _layers)
          PlacedLayer(
            key: ObjectKey(layer),
            layer: layer,
            size: size,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _editLayer(layer),
              onLongPress: () => _layerMenu(layer),
              onScaleStart: (_) {
                _startScale = layer.scale;
                _startRotation = layer.rotation;
                setState(() {
                  _dragging = layer;
                  _layers
                    ..remove(layer)
                    ..add(layer);
                });
              },
              onScaleUpdate: (d) {
                setState(() {
                  layer
                    ..x = (layer.x + d.focalPointDelta.dx / size.width).clamp(0.0, 1.0)
                    ..y = (layer.y + d.focalPointDelta.dy / size.height).clamp(0.0, 1.0)
                    ..scale = (_startScale * d.scale).clamp(.3, 4.0)
                    ..rotation = _startRotation + d.rotation;
                  _overTrash = (d.focalPoint - _trashCenter(MediaQuery.of(context).size)).distance < 56;
                });
              },
              onScaleEnd: (_) {
                setState(() {
                  if (_overTrash) _layers.remove(layer);
                  _dragging = null;
                  _overTrash = false;
                });
              },
              child: IgnorePointer(
                child: Opacity(
                  opacity: _dragging == layer && _overTrash ? .5 : 1,
                  child: LayerContent(layer: layer, w: size.width),
                ),
              ),
            ),
          ),
      ]);
    });
  }

  Widget _sideTools() {
    return Padding(
      padding: const EdgeInsets.only(top: 8, right: 10),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        _SideTool(icon: CupertinoIcons.textformat, label: 'Texto', onTap: _addText),
        _SideTool(icon: CupertinoIcons.smiley, label: 'Stickers', onTap: _openStickers),
        _SideTool(icon: CupertinoIcons.music_note_2, label: _song == null ? 'Música' : 'Cambiar', onTap: _chooseSong),
        _SideTool(
          icon: CupertinoIcons.wand_stars,
          label: 'Filtros',
          active: _showFilters || _filter != null,
          onTap: () => setState(() => _showFilters = !_showFilters),
        ),
        _SideTool(icon: CupertinoIcons.at, label: 'Mencionar', onTap: _addMention),
        _SideTool(icon: CupertinoIcons.link, label: 'Enlace', onTap: _addLink),
      ]),
    );
  }

  Widget _filterStrip() {
    final file = _file!;
    Widget thumb(String? key, String label) {
      final selected = _filter == key;
      return GestureDetector(
        onTap: () => setState(() => _filter = key),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 5),
          child: Column(children: [
            Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white, width: selected ? 3 : 1),
              ),
              clipBehavior: Clip.antiAlias,
              child: filtered(
                key,
                _isVideo
                    ? Container(decoration: const BoxDecoration(gradient: LinearGradient(colors: [Color(0xFFF59E0B), Color(0xFFEC4899), Color(0xFF3B82F6)])))
                    : Image.file(File(file.path), fit: BoxFit.cover, cacheWidth: 160),
              ),
            ),
            const SizedBox(height: 4),
            Text(label, style: Tx.body(11.5, weight: selected ? FontWeight.w700 : FontWeight.w500, color: Colors.white)),
          ]),
        ),
      );
    }

    return SizedBox(
      height: 92,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 11),
        children: [
          thumb(null, 'Original'),
          for (final e in storyFilterNames.entries) thumb(e.key, e.value),
        ],
      ),
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
      return Center(child: AspectRatio(aspectRatio: v.value.aspectRatio, child: filtered(_filter, VideoPlayer(v))));
    }
    return filtered(_filter, Image.file(File(file.path), fit: BoxFit.contain));
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

class _SideTool extends StatelessWidget {
  const _SideTool({required this.icon, required this.label, required this.onTap, this.active = false});

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(label, style: Tx.body(13, weight: FontWeight.w600, color: Colors.white).copyWith(shadows: const [Shadow(color: Color(0x99000000), blurRadius: 6)])),
            const SizedBox(width: 8),
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: active ? Colors.white : Colors.black.withAlpha(110),
                border: Border.all(color: Colors.white.withAlpha(70)),
              ),
              child: Icon(icon, color: active ? Colors.black : Colors.white, size: 21),
            ),
          ]),
        ),
      ),
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
