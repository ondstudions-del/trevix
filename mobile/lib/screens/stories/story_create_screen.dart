import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

import '../../app.dart' show navigatorKey;
import '../../core/api.dart';
import '../../core/audio.dart';
import '../../core/catalog.dart';
import '../../core/device.dart';
import '../../core/drafts.dart';
import '../../core/events.dart';
import '../../core/i18n.dart';
import '../../core/nav.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';
import '../../widgets/gif_picker.dart';
import '../../widgets/media.dart';
import '../../widgets/media_gallery.dart';
import '../../widgets/song_chip.dart';
import '../../widgets/story_layers.dart';
import '../music/music_picker.dart';
import 'story_collage.dart';
import 'story_editor_tools.dart';

/// Nueva historia: se abre con la galería del teléfono dentro de la app (fotos, videos y fotos en movimiento) o
/// de texto sobre un fondo de la marca. La foto o video lleva canción, filtro y capas (textos, stickers, ubicación,
/// encuesta, menciones y enlace). Cada elemento se mueve con un dedo y se agranda, achica y gira pellizcando con
/// dos dedos (en cualquier parte), con el control de su esquina o con el control de tamaño de la izquierda.
/// Las fotos en movimiento (Live Photos) se publican como su video corto en bucle si «LIVE» está activado.
class StoryCreateScreen extends StatefulWidget {
  const StoryCreateScreen({super.key, this.song, this.draft});

  /// Canción o sonido ya elegido («Usar este sonido» en su ficha).
  final Song? song;

  /// Borrador guardado en el teléfono que se retoma (se borra al publicarlo).
  final Draft? draft;

  @override
  State<StoryCreateScreen> createState() => _StoryCreateScreenState();
}

class _StoryCreateScreenState extends State<StoryCreateScreen> {
  static const _limits = {'text': 5, 'sticker': 5, 'location': 1, 'poll': 1, 'mention': 5, 'link': 1};
  static const _maxLayers = 12;

  static const _maxVideoSeconds = 30;

  bool _textMode = false;
  String _background = 'violet';
  final _text = TextEditingController();
  final _caption = TextEditingController();
  XFile? _file;
  bool _isVideo = false;
  VideoPlayerController? _video;

  /// Video corto de la foto en movimiento elegida (si tiene) y si se publica en movimiento.
  String? _livePath;
  bool _live = false;
  PickedSong? _song;
  bool _busy = false;

  final List<StoryLayer> _layers = [];
  String? _filter;
  bool _showFilters = false;
  bool _locating = false;
  /// Elemento elegido: muestra su marco, el control de tamaño de la izquierda y la barra de acciones.
  StoryLayer? _selected;

  /// Elemento que se está tocando (mover, pellizcar o el control de la esquina).
  StoryLayer? _target;
  bool _resizing = false;

  /// Elemento que se arrastra con un dedo (muestra la papelera).
  StoryLayer? _dragging;
  bool _overTrash = false;
  double _startScale = 1;
  double _startRotation = 0;
  Offset _resizeCenter = Offset.zero;
  Offset _resizeStart = Offset.zero;
  final Map<StoryLayer, GlobalKey> _layerKeys = {};
  final _handleKey = GlobalKey();

  /// Solo yo: nadie más la ve y queda en Guardado › Solo yo (no se borra a las 24 horas).
  bool _private = false;
  late String? _draftId = widget.draft?.id;

  @override
  void initState() {
    super.initState();
    final song = widget.song;
    if (song != null && song.available) _song = PickedSong(song, song.clipStart ?? 0);
    final draft = widget.draft;
    if (draft != null) _restore(draft);
  }

  Future<void> _restore(Draft d) async {
    final data = d.data;
    _textMode = asStr(data['type']) == 'text';
    _background = asStr(data['background'], 'violet');
    _text.text = asStr(data['text']);
    _caption.text = asStr(data['caption']);
    _filter = asStrOrNull(data['filter']);
    _private = asBool(data['private']);
    _layers.addAll(asList(data['overlays'], StoryLayer.fromJson));
    final media = d.files['media'];
    if (!_textMode && media != null) {
      await _useMedia(media, video: asStr(data['type']) == 'video', livePath: d.files['live']);
      if (mounted && d.files['live'] != null) setState(() => _live = asBool(data['live']));
    }
    final picked = await draftSong(data);
    if (!mounted) return;
    if (picked != null) {
      setState(() => _song = PickedSong(picked.$1, picked.$2));
      _video?.setVolume(0);
    } else if (asInt(data['song_id']) > 0) {
      toast(context, tr('La canción del borrador ya no está disponible.'), error: true);
    }
  }

  bool get _hasContent => _textMode ? _text.text.trim().isNotEmpty : _file != null;

  /// Datos y archivos del borrador con lo que hay en pantalla.
  (Json, Map<String, String>) _draftSnapshot() {
    final song = _song;
    return (
      {
        'type': _textMode ? 'text' : (_isVideo ? 'video' : 'image'),
        'text': _text.text,
        'background': _background,
        'caption': _caption.text,
        if (_filter != null) 'filter': _filter,
        'overlays': _layers.map((l) => l.toDraftJson()).toList(),
        'live': _live,
        'private': _private,
        if (song != null) ...{'song_id': song.song.id, 'song_start': song.start},
      },
      {
        if (!_textMode && _file != null) 'media': _file!.path,
        if (!_textMode && _livePath != null) 'live': _livePath!,
      },
    );
  }

  Future<bool> _saveDraft() async {
    final me = context.read<AppState>().me;
    if (me == null) return false;
    final (data, files) = _draftSnapshot();
    try {
      _draftId = await drafts.save(id: _draftId, kind: 'story', userId: me.user.id, data: data, files: files);
      if (mounted) toast(context, tr('Guardado en Borradores (en tu perfil).'));
      return true;
    } catch (_) {
      if (mounted) toast(context, tr('No se pudo guardar el borrador. Revisa el espacio libre del teléfono.'), error: true);
      return false;
    }
  }

  Future<void> _close() async {
    if (!_hasContent || _busy) {
      Navigator.pop(context);
      return;
    }
    final choice = await showCupertinoModalPopup<String>(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        title: Text(tr('¿Guardar como borrador?')),
        message: Text(tr('Los borradores se guardan solo en este teléfono, en tu perfil › Borradores.')),
        actions: [
          CupertinoActionSheetAction(onPressed: () => Navigator.pop(ctx, 'save'), child: Text(tr('Guardar borrador'))),
          CupertinoActionSheetAction(isDestructiveAction: true, onPressed: () => Navigator.pop(ctx, 'discard'), child: Text(_draftId != null ? tr('Salir sin guardar los cambios') : tr('Descartar'))),
        ],
        cancelButton: CupertinoActionSheetAction(onPressed: () => Navigator.pop(ctx), child: Text(tr('Seguir editando'))),
      ),
    );
    if (!mounted || choice == null) return;
    if (choice == 'save' && !await _saveDraft()) return;
    if (mounted) Navigator.pop(context);
  }

  @override
  void dispose() {
    _text.dispose();
    _caption.dispose();
    _video?.dispose();
    songPlayer.stop();
    super.dispose();
  }

  /// Reproductor en bucle de [path] (el video elegido o el de la foto en movimiento).
  Future<VideoPlayerController?> _player(String path, {required bool muted}) async {
    final c = VideoPlayerController.file(File(path));
    try {
      await c.initialize();
      await c.setLooping(true);
      await c.setVolume(muted ? 0 : 1);
      c.play();
      return c;
    } catch (_) {
      c.dispose();
      return null;
    }
  }

  void _dropVideo() {
    releaseVideo(_video);
    _video = null;
  }

  Future<void> _useMedia(String path, {required bool video, String? livePath}) async {
    _dropVideo();
    VideoPlayerController? controller;
    if (video) {
      controller = await _player(path, muted: _song != null);
      if (controller == null) {
        if (mounted) toast(context, tr('No se pudo abrir el archivo. Revisa los permisos de Fotos y Cámara.'), error: true);
        return;
      }
      if (controller.value.duration > const Duration(seconds: _maxVideoSeconds + 1)) {
        controller.dispose();
        if (mounted) toast(context, tr('El video puede durar como mucho 30 segundos.'), error: true);
        return;
      }
    } else if (livePath != null) {
      controller = await _player(livePath, muted: true);
    }
    if (!mounted) {
      controller?.dispose();
      return;
    }
    setState(() {
      _file = XFile(path);
      _isVideo = video;
      _livePath = controller != null && !video ? livePath : null;
      _live = _livePath != null;
      _video = controller;
      _textMode = false;
    });
  }

  /// Foto en movimiento: alterna entre publicar el video corto en bucle o la foto fija.
  void _toggleLive() {
    final v = _video;
    setState(() => _live = !_live);
    if (v == null) return;
    _live ? v.play() : v.pause();
  }

  Future<void> _pick(ImageSource source, bool video) async {
    final picker = ImagePicker();
    try {
      final file = video
          ? await picker.pickVideo(source: source, maxDuration: const Duration(seconds: _maxVideoSeconds))
          : await picker.pickImage(source: source, maxWidth: 2160, imageQuality: 90);
      if (file == null) return;
      await _useMedia(file.path, video: video);
    } catch (e) {
      if (mounted) toast(context, tr('No se pudo abrir el archivo. Revisa los permisos de Fotos y Cámara.'), error: true);
    }
  }

  void _openCamera() {
    actionSheet(context, [
      SheetAction(tr('Tomar foto'), CupertinoIcons.camera, () => _pick(ImageSource.camera, false)),
      SheetAction(tr('Grabar video'), CupertinoIcons.videocam, () => _pick(ImageSource.camera, true)),
    ]);
  }

  /// Collage de 2 a 6 fotos: vuelve como una sola foto que se edita igual que las demás.
  Future<void> _openCollage() async {
    final path = await Navigator.push<String>(context, MaterialPageRoute(builder: (_) => const StoryCollageScreen()));
    if (path != null && mounted) await _useMedia(path, video: false);
  }

  /// Vuelve a la galería para elegir otra foto o video (las capas se conservan).
  void _chooseMedia() {
    _dropVideo();
    setState(() {
      _file = null;
      _isVideo = false;
      _livePath = null;
      _live = false;
      _textMode = false;
      _showFilters = false;
    });
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
    if (_isVideo) _video?.setVolume(1);
    setState(() => _song = null);
  }

  // ---- Capas ----

  bool _canAdd(String type) {
    final count = _layers.where((l) => l.type == type).length;
    final limit = _limits[type] ?? 1;
    if (_layers.length >= _maxLayers) {
      toast(context, tr('Puedes añadir como mucho {max} elementos a una historia.', {'max': _maxLayers}), error: true);
      return false;
    }
    if (count >= limit) {
      toast(context, limit == 1 ? tr('Solo puedes añadir uno de este tipo.') : tr('Puedes añadir como mucho {max} de este tipo.', {'max': limit}), error: true);
      return false;
    }
    return true;
  }

  void _add(StoryLayer layer) {
    final offset = (_layers.length % 4) * .04;
    layer
      ..x = .5
      ..y = (layer.type == 'poll' ? .5 : .4) + offset;
    setState(() {
      _layers.add(layer);
      _selected = layer;
    });
  }

  void _remove(StoryLayer layer) {
    setState(() {
      _layers.remove(layer);
      _layerKeys.remove(layer);
      if (_selected == layer) _selected = null;
    });
  }

  Future<void> _addText() async {
    if (!_canAdd('text')) return;
    final r = await editStoryText(context);
    if (r == null || r.text.isEmpty || !mounted) return;
    _add(StoryLayer(type: 'text', text: r.text, color: r.color, style: r.style, font: r.font));
  }

  Future<void> _openStickers() async {
    final picked = await pickStorySticker(context, header: (sheet) {
      Widget chip(IconData icon, String label, String key) => Expanded(
            child: GestureDetector(
              onTap: () => Navigator.pop(sheet, key),
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 4),
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(color: TxDark.surface3, borderRadius: BorderRadius.circular(16), border: Border.all(color: TxDark.border)),
                child: Column(children: [
                  Icon(icon, color: Tx.purple300, size: 22),
                  const SizedBox(height: 6),
                  Text(label, style: TxDark.body(12.5, weight: FontWeight.w600)),
                ]),
              ),
            ),
          );
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: Row(children: [
          chip(CupertinoIcons.location_solid, tr('Ubicación'), 'location'),
          chip(CupertinoIcons.chart_bar_alt_fill, tr('Encuesta'), 'poll'),
          chip(CupertinoIcons.at, tr('Mención'), 'mention'),
          chip(CupertinoIcons.link, tr('Enlace'), 'link'),
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
      SheetAction(tr('Usar mi ubicación actual'), CupertinoIcons.location_fill, () async {
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
      SheetAction(tr('Escribir un lugar'), CupertinoIcons.pencil, () async {
        final name = await prompt(context, tr('¿Dónde estás?'), hint: tr('Ej.: Parque Simón Bolívar, Bogotá'), action: tr('Añadir'), maxLength: 80);
        final clean = name?.trim() ?? '';
        if (clean.length >= 2 && mounted && _canAdd('location')) _add(StoryLayer(type: 'location', name: clean));
      }),
    ], title: tr('Ubicación'));
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
      toast(context, tr('Ya mencionaste a @{username}.', {'username': username}), error: true);
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
        final r = await editStoryText(context, text: layer.text, color: layer.color, style: layer.style, font: layer.font);
        if (r == null || !mounted) return;
        if (r.text.isEmpty) {
          _remove(layer);
          return;
        }
        setState(() {
          layer
            ..text = r.text
            ..color = r.color
            ..style = r.style
            ..font = r.font;
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
        setState(() {
          _layers[index] = updated;
          _layerKeys.remove(layer);
          if (_selected == layer) _selected = updated;
        });
      default:
        _layerMenu(layer);
    }
  }

  bool _editable(StoryLayer layer) => const {'text', 'poll', 'link'}.contains(layer.type);

  void _layerMenu(StoryLayer layer) {
    actionSheet(context, [
      if (_editable(layer)) SheetAction(tr('Editar'), CupertinoIcons.pencil, () => _editLayer(layer)),
      SheetAction(tr('Tamaño y giro originales'), CupertinoIcons.arrow_counterclockwise, () {
        setState(() {
          layer
            ..scale = 1
            ..rotation = 0;
        });
      }),
      SheetAction(tr('Quitar de la historia'), CupertinoIcons.trash, () => _remove(layer), destructive: true),
    ]);
  }

  // ---- Gestos del lienzo ----
  //
  // Un solo detector para todo el lienzo: un dedo sobre un elemento lo mueve (y a la papelera lo quita); dos
  // dedos en cualquier parte lo agrandan, achican y giran (el que tocaste o el elegido); el control de la
  // esquina del elegido hace lo mismo con un dedo. Tocar elige un elemento; tocarlo otra vez lo edita.

  GlobalKey _keyFor(StoryLayer layer) => _layerKeys.putIfAbsent(layer, GlobalKey.new);

  RenderBox? _boxOf(GlobalKey key) {
    final box = key.currentContext?.findRenderObject();
    return box is RenderBox && box.hasSize && box.attached ? box : null;
  }

  /// El elemento de más arriba bajo el dedo (con un margen para los pequeños).
  StoryLayer? _hitLayer(Offset global) {
    for (final layer in _layers.reversed) {
      final box = _boxOf(_keyFor(layer));
      if (box == null) continue;
      final local = box.globalToLocal(global);
      if ((Offset.zero & box.size).inflate(14 / layer.scale).contains(local)) return layer;
    }
    return null;
  }

  bool _hitHandle(Offset global) {
    final box = _boxOf(_handleKey);
    if (box == null || _selected == null) return false;
    return (box.globalToLocal(global) - box.size.center(Offset.zero)).distance <= 26;
  }

  Offset _centerOf(StoryLayer layer) {
    final box = _boxOf(_keyFor(layer));
    return box == null ? Offset.zero : box.localToGlobal(box.size.center(Offset.zero));
  }

  /// Giro en (-π, π], con un imán a 0° para dejarlo derecho.
  static double _snapRotation(double r) {
    final n = math.atan2(math.sin(r), math.cos(r));
    return n.abs() < .06 ? 0 : n;
  }

  void _onCanvasTap(Offset global) {
    if (_hitHandle(global)) return;
    final hit = _hitLayer(global);
    if (hit == null) {
      if (_selected != null) setState(() => _selected = null);
    } else if (hit == _selected) {
      _editable(hit) ? _editLayer(hit) : _layerMenu(hit);
    } else {
      setState(() => _selected = hit);
    }
  }

  void _onScaleStart(ScaleStartDetails d) {
    final current = _target;
    if (current != null && _layers.contains(current)) {
      // Se sumó o se levantó un dedo: el mismo gesto sigue desde el estado actual.
      _resizing = false;
      _startScale = current.scale;
      _startRotation = current.rotation;
      return;
    }
    if (d.pointerCount == 1 && _selected != null && _hitHandle(d.focalPoint)) {
      final layer = _selected!;
      _resizeCenter = _centerOf(layer);
      _resizeStart = d.focalPoint - _resizeCenter;
      _startScale = layer.scale;
      _startRotation = layer.rotation;
      setState(() {
        _target = layer;
        _resizing = true;
      });
      return;
    }
    final layer = _hitLayer(d.focalPoint) ?? (d.pointerCount >= 2 ? _selected : null);
    if (layer == null) return;
    _startScale = layer.scale;
    _startRotation = layer.rotation;
    setState(() {
      _target = layer;
      _selected = layer;
      _resizing = false;
      _layers
        ..remove(layer)
        ..add(layer);
    });
  }

  void _onScaleUpdate(ScaleUpdateDetails d, Size size) {
    final layer = _target;
    if (layer == null) return;
    setState(() {
      if (_resizing) {
        final v = d.focalPoint - _resizeCenter;
        if (_resizeStart.distance > 4) {
          layer
            ..scale = (_startScale * v.distance / _resizeStart.distance).clamp(StoryLayer.minScale, StoryLayer.maxScale)
            ..rotation = _snapRotation(_startRotation + v.direction - _resizeStart.direction);
        }
        return;
      }
      layer
        ..x = (layer.x + d.focalPointDelta.dx / size.width).clamp(0.0, 1.0)
        ..y = (layer.y + d.focalPointDelta.dy / size.height).clamp(0.0, 1.0);
      if (d.pointerCount >= 2) {
        layer
          ..scale = (_startScale * d.scale).clamp(StoryLayer.minScale, StoryLayer.maxScale)
          ..rotation = _snapRotation(_startRotation + d.rotation);
      }
      final moved = d.focalPointDelta.distance > 0;
      if (d.pointerCount == 1 && moved) _dragging = layer;
      _overTrash = _dragging == layer && d.pointerCount == 1 && (d.focalPoint - _trashCenter(MediaQuery.of(context).size)).distance < 56;
    });
  }

  void _onScaleEnd(ScaleEndDetails d) {
    if (d.pointerCount > 0) return;
    final layer = _target;
    final trash = _overTrash;
    setState(() {
      _target = null;
      _dragging = null;
      _resizing = false;
      _overTrash = false;
    });
    if (layer != null && trash) _remove(layer);
  }

  Offset _trashCenter(Size screen) => Offset(screen.width / 2, screen.height - MediaQuery.of(context).padding.bottom - 70);

  // ---- Publicar ----

  Future<void> _publish() async {
    FocusScope.of(context).unfocus();
    if (_textMode && _text.text.trim().isEmpty) {
      toast(context, tr('Escribe el texto de tu historia.'), error: true);
      return;
    }
    if (!_textMode && _file == null) {
      toast(context, tr('Elige una foto o un video.'), error: true);
      return;
    }
    final song = _song;
    if (!_textMode) {
      if (storyUploadProgress.value != null) {
        toast(context, tr('Espera a que termine de subirse tu otra historia.'), error: true);
        return;
      }
      _uploadInBackground();
      return;
    }
    setState(() => _busy = true);
    try {
      final res = await api.post('stories', {
        'type': 'text',
        'text': _text.text.trim(),
        'background': _background,
        if (song != null) 'song_id': song.song.id,
        if (song != null) 'song_start': song.start,
        if (_private) 'private': '1',
      });
      final draftId = _draftId;
      if (draftId != null) unawaited(drafts.delete(draftId));
      storiesChanged.value++;
      if (!mounted) return;
      toast(context, '${res.map['message'] ?? tr('Tu historia se publicó.')}');
      Navigator.pop(context);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        toast(context, e.fields.values.isNotEmpty ? e.fields.values.first : e.message, error: true);
      }
    }
  }

  /// Foto o video: la pantalla se cierra al instante y la subida sigue con su avance en «Tu historia». Si falla,
  /// la historia queda en Borradores para reintentarla sin rehacerla.
  void _uploadInBackground() {
    final song = _song;
    final live = _live && _livePath != null;
    final path = live ? _livePath! : _file!.path;
    final fields = {
      'type': 'media',
      'caption': _caption.text.trim(),
      if (song != null) 'song_id': '${song.song.id}',
      if (song != null) 'song_start': '${song.start}',
      if (_layers.isNotEmpty) 'overlays': jsonEncode(_layers.map((l) => l.toJson()).toList()),
      if (_filter != null) 'filter': _filter!,
      if (live) 'live': '1',
      if (_private) 'private': '1',
    };
    final (draftData, draftFiles) = _draftSnapshot();
    final draftId = _draftId;
    final userId = context.read<AppState>().me?.user.id;
    storyUploadProgress.value = 0;
    toast(context, tr('Subiendo tu historia…'));
    Navigator.pop(context);
    () async {
      String message;
      var error = false;
      try {
        final res = await api.upload('stories', fields: fields, files: [
          Upload('media', path, filename: path.split(RegExp(r'[\\/]')).last),
        ], onProgress: (p) => storyUploadProgress.value = p);
        if (draftId != null) unawaited(drafts.delete(draftId));
        storiesChanged.value++;
        message = '${res.map['message'] ?? tr('Tu historia se publicó.')}';
      } on ApiException catch (e) {
        error = true;
        message = e.fields.values.isNotEmpty ? e.fields.values.first : e.message;
        if (userId != null) {
          try {
            await drafts.save(id: draftId, kind: 'story', userId: userId, data: draftData, files: draftFiles);
            message = '$message ${tr('La guardamos en Borradores (en tu perfil) para que la vuelvas a intentar.')}';
          } catch (_) {}
        }
      } finally {
        storyUploadProgress.value = null;
      }
      final overlay = navigatorKey.currentState?.overlay?.context;
      if (overlay != null && overlay.mounted) toast(overlay, message, error: error);
    }();
  }

  @override
  Widget build(BuildContext context) {
    if (!_textMode && _file == null) return _gallery();
    final maxText = context.read<AppState>().limit('story_text', 300);
    final maxCaption = context.read<AppState>().limit('story_caption', 200);
    final editing = !_textMode && _file != null;
    final dragging = _dragging != null;
    final gesturing = _target != null;
    final selected = editing && _selected != null && _layers.contains(_selected) ? _selected : null;
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
                    style: TxDark.display(30, color: Colors.white, height: 1.25),
                    cursorColor: Colors.white,
                    decoration: InputDecoration(
                      border: InputBorder.none,
                      hintText: tr('Escribe algo…'),
                      hintStyle: TxDark.display(30, color: Colors.white.withAlpha(140)),
                      counterStyle: TxDark.body(12, color: Colors.white.withAlpha(170)),
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
          ignoring: gesturing,
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 150),
            opacity: gesturing ? 0 : 1,
            child: SafeArea(
              child: Column(children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(6, 4, 10, 0),
                  child: Row(children: [
                    IconButton(
                      onPressed: _close,
                      icon: const Icon(CupertinoIcons.xmark, color: Colors.white, size: 24),
                    ),
                    const Spacer(),
                    if (selected != null)
                      _SelectionBar(
                        onEdit: _editable(selected) ? () => _editLayer(selected) : null,
                        onReset: () => setState(() {
                          selected
                            ..scale = 1
                            ..rotation = 0;
                        }),
                        onDelete: () => _remove(selected),
                        onDone: () => setState(() => _selected = null),
                      )
                    else
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
                    if (editing && _livePath != null && selected == null)
                      Semantics(
                        button: true,
                        toggled: _live,
                        label: tr('Foto en movimiento'),
                        child: GestureDetector(onTap: _toggleLive, child: LiveBadge(active: _live)),
                      )
                    else
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
                      style: TxDark.body(15, color: Colors.white),
                      decoration: InputDecoration(
                        counterText: '',
                        hintText: tr('Añade un texto (opcional)'),
                        hintStyle: TxDark.body(15, color: Colors.white.withAlpha(170)),
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
                    if (!editing) _RoundTool(icon: CupertinoIcons.music_note_2, label: _song == null ? tr('Música') : tr('Cambiar'), onTap: _chooseSong),
                    if (editing) _RoundTool(icon: CupertinoIcons.photo_on_rectangle, label: tr('Cambiar'), onTap: _chooseMedia),
                    const SizedBox(width: 10),
                    Semantics(
                      toggled: _private,
                      child: _RoundTool(
                        icon: _private ? CupertinoIcons.lock_fill : CupertinoIcons.lock_open,
                        label: tr('Solo yo'),
                        active: _private,
                        onTap: () {
                          setState(() => _private = !_private);
                          toast(context, _private
                              ? tr('Solo tú la verás. Quedará en Guardado › Solo yo y no se borrará a las 24 horas.')
                              : tr('La verán quienes pueden ver tus historias.'));
                        },
                      ),
                    ),
                    const Spacer(),
                    SizedBox(
                      width: 150,
                      child: GradientButton(label: tr('Compartir'), icon: CupertinoIcons.paperplane_fill, loading: _busy, onPressed: _publish, height: 48),
                    ),
                  ]),
                ),
              ]),
            ),
          ),
        ),
        if (selected != null && !gesturing)
          Positioned(
            left: 6,
            top: screen.height * .22,
            height: (screen.height * .34).clamp(160.0, 300.0),
            child: _SizeSlider(
              value: selected.scale,
              onChanged: (s) => setState(() => selected.scale = s),
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
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: (d) => _onCanvasTap(d.globalPosition),
        onLongPressStart: (d) {
          final layer = _hitLayer(d.globalPosition);
          if (layer != null) _layerMenu(layer);
        },
        onScaleStart: _onScaleStart,
        onScaleUpdate: (d) => _onScaleUpdate(d, size),
        onScaleEnd: _onScaleEnd,
        child: Stack(clipBehavior: Clip.hardEdge, children: [
          const Positioned.fill(child: SizedBox.shrink()),
          for (final layer in _layers)
            PlacedLayer(
              key: ObjectKey(layer),
              layer: layer,
              size: size,
              child: IgnorePointer(child: KeyedSubtree(key: _keyFor(layer), child: _layerView(layer, size))),
            ),
        ]),
      );
    });
  }

  /// Contenido de un elemento; el elegido lleva un marco y el control de la esquina (agrandar y girar) con un
  /// tamaño en pantalla fijo, aunque el elemento esté escalado.
  Widget _layerView(StoryLayer layer, Size size) {
    final content = Opacity(
      opacity: _dragging == layer && _overTrash ? .5 : 1,
      child: LayerContent(layer: layer, w: size.width),
    );
    if (layer != _selected || _dragging == layer) return content;
    final inv = 1 / layer.scale;
    return Stack(clipBehavior: Clip.none, children: [
      Container(
        padding: EdgeInsets.all(10 * inv),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12 * inv),
          border: Border.all(color: Colors.white.withAlpha(230), width: 1.5 * inv),
        ),
        child: content,
      ),
      Positioned(
        right: -14,
        bottom: -14,
        child: Transform.scale(
          scale: inv,
          child: KeyedSubtree(
            key: _handleKey,
            child: Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: Colors.black.withAlpha(90), blurRadius: 6)],
              ),
              child: const Icon(CupertinoIcons.arrow_up_left_arrow_down_right, size: 14, color: Colors.black),
            ),
          ),
        ),
      ),
    ]);
  }

  Widget _sideTools() {
    return Padding(
      padding: const EdgeInsets.only(top: 8, right: 10),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        _SideTool(icon: CupertinoIcons.textformat, label: tr('Texto'), onTap: _addText),
        _SideTool(icon: CupertinoIcons.smiley, label: tr('Stickers'), onTap: _openStickers),
        _SideTool(icon: CupertinoIcons.music_note_2, label: _song == null ? tr('Música') : tr('Cambiar'), onTap: _chooseSong),
        _SideTool(
          icon: CupertinoIcons.wand_stars,
          label: tr('Filtros'),
          active: _showFilters || _filter != null,
          onTap: () => setState(() => _showFilters = !_showFilters),
        ),
        _SideTool(icon: CupertinoIcons.at, label: tr('Mencionar'), onTap: _addMention),
        _SideTool(icon: CupertinoIcons.link, label: tr('Enlace'), onTap: _addLink),
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
            Text(label, style: TxDark.body(11.5, weight: selected ? FontWeight.w700 : FontWeight.w500, color: Colors.white)),
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
          thumb(null, tr('Original')),
          for (final e in storyFilterNames.entries) thumb(e.key, tr(e.value)),
        ],
      ),
    );
  }

  Widget _mediaPreview() {
    final file = _file;
    if (file == null) {
      return Container(
        decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [TxDark.surface3, Colors.black])),
        child: Center(
          child: GestureDetector(
            onTap: _chooseMedia,
            child: EmptyState(icon: CupertinoIcons.photo_on_rectangle, title: tr('Elige una foto o un video'), message: tr('Videos de hasta 30 segundos.')),
          ),
        ),
      );
    }
    if (_isVideo || _live) {
      final v = _video;
      if (v == null || !v.value.isInitialized) return const Center(child: CupertinoActivityIndicator(color: Colors.white));
      return Center(child: AspectRatio(aspectRatio: v.value.aspectRatio, child: filtered(_filter, VideoPlayer(v))));
    }
    return filtered(_filter, Image.file(File(file.path), fit: BoxFit.contain));
  }

  /// Primera pantalla: la galería del teléfono, con la cámara como primera casilla.
  Widget _gallery() {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        bottom: false,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 4, 10, 6),
            child: Row(children: [
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(CupertinoIcons.xmark, color: Colors.white, size: 24),
              ),
              const Spacer(),
              _ModeSwitch(
                textMode: false,
                onChanged: (text) {
                  if (text) setState(() => _textMode = true);
                },
              ),
              const Spacer(),
              const SizedBox(width: 48),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(tr('Añadir a tu historia'), style: TxDark.display(22)),
            ),
          ),
          Expanded(
            child: PhoneGallery(
              maxVideoSeconds: _maxVideoSeconds,
              onPick: (p) => _useMedia(p.path, video: p.isVideo, livePath: p.livePath),
              leading: [
                GestureDetector(
                  onTap: _openCamera,
                  child: Container(
                    decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF7C3AED), Color(0xFFEC4899)])),
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      const Icon(CupertinoIcons.camera_fill, color: Colors.white, size: 30),
                      const SizedBox(height: 8),
                      Text(tr('Cámara'), style: TxDark.body(13.5, weight: FontWeight.w700)),
                    ]),
                  ),
                ),
                GestureDetector(
                  onTap: _openCollage,
                  child: Container(
                    decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF0EA5E9), Color(0xFF7C3AED)])),
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      const Icon(CupertinoIcons.square_grid_2x2_fill, color: Colors.white, size: 30),
                      const SizedBox(height: 8),
                      Text(tr('Collage'), style: TxDark.body(13.5, weight: FontWeight.w700)),
                    ]),
                  ),
                ),
              ],
            ),
          ),
        ]),
      ),
    );
  }
}

/// Acciones del elemento elegido (en lugar del selector Texto / Foto o video).
class _SelectionBar extends StatelessWidget {
  const _SelectionBar({required this.onEdit, required this.onReset, required this.onDelete, required this.onDone});

  final VoidCallback? onEdit;
  final VoidCallback onReset;
  final VoidCallback onDelete;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    Widget icon(IconData icon, String label, VoidCallback onTap, {Color color = Colors.white}) => Semantics(
          button: true,
          label: label,
          child: GestureDetector(
            onTap: onTap,
            child: Padding(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7), child: Icon(icon, color: color, size: 20)),
          ),
        );
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: Colors.black.withAlpha(110), borderRadius: BorderRadius.circular(21)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (onEdit != null) icon(CupertinoIcons.pencil, tr('Editar'), onEdit!),
        icon(CupertinoIcons.arrow_counterclockwise, tr('Tamaño y giro originales'), onReset),
        icon(CupertinoIcons.trash, tr('Quitar'), onDelete, color: const Color(0xFFFF8A9B)),
        GestureDetector(
          onTap: onDone,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
            child: Text(tr('Listo'), style: TxDark.body(14, weight: FontWeight.w700, color: Colors.black)),
          ),
        ),
      ]),
    );
  }
}

/// Control vertical de tamaño del elemento elegido (arriba más grande), en escala logarítmica entre los límites
/// que acepta el servidor.
class _SizeSlider extends StatelessWidget {
  const _SizeSlider({required this.value, required this.onChanged});

  final double value;
  final ValueChanged<double> onChanged;

  static double _toT(double scale) =>
      (math.log(scale / StoryLayer.minScale) / math.log(StoryLayer.maxScale / StoryLayer.minScale)).clamp(0.0, 1.0);

  static double _fromT(double t) => StoryLayer.minScale * math.pow(StoryLayer.maxScale / StoryLayer.minScale, t);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final h = box.maxHeight;
      const thumb = 26.0;
      final t = _toT(value);
      void set(double dy) => onChanged(_fromT((1 - (dy - thumb / 2) / (h - thumb)).clamp(0.0, 1.0)));
      return Semantics(
        slider: true,
        label: tr('Tamaño'),
        value: '${(value * 100).round()} %',
        increasedValue: '${(_fromT((t + .1).clamp(0.0, 1.0)) * 100).round()} %',
        decreasedValue: '${(_fromT((t - .1).clamp(0.0, 1.0)) * 100).round()} %',
        onIncrease: () => onChanged(_fromT((t + .1).clamp(0.0, 1.0))),
        onDecrease: () => onChanged(_fromT((t - .1).clamp(0.0, 1.0))),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) => set(d.localPosition.dy),
          onVerticalDragStart: (d) => set(d.localPosition.dy),
          onVerticalDragUpdate: (d) => set(d.localPosition.dy),
          child: SizedBox(
            width: 44,
            child: Stack(alignment: Alignment.topCenter, children: [
              const Positioned.fill(
                top: thumb / 2,
                bottom: thumb / 2,
                child: CustomPaint(painter: _WedgePainter()),
              ),
              Positioned(
                top: (1 - t) * (h - thumb),
                child: Container(
                  width: thumb,
                  height: thumb,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [BoxShadow(color: Colors.black.withAlpha(110), blurRadius: 6)],
                  ),
                ),
              ),
            ]),
          ),
        ),
      );
    });
  }
}

/// Guía del control de tamaño: una cuña ancha arriba y fina abajo.
class _WedgePainter extends CustomPainter {
  const _WedgePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.width / 2;
    final path = Path()
      ..moveTo(c - 7, 0)
      ..lineTo(c + 7, 0)
      ..lineTo(c + 1.5, size.height)
      ..lineTo(c - 1.5, size.height)
      ..close();
    canvas.drawPath(path, Paint()..color = Colors.white.withAlpha(110));
    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.black.withAlpha(60)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(covariant _WedgePainter oldDelegate) => false;
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
            child: Text(label, style: TxDark.body(14, weight: FontWeight.w600, color: selected ? Colors.black : Colors.white)),
          ),
        );
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: Colors.black.withAlpha(90), borderRadius: BorderRadius.circular(21)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        seg(tr('Texto'), textMode, true),
        seg(tr('Foto o video'), !textMode, false),
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
            Text(label, style: TxDark.body(13, weight: FontWeight.w600, color: Colors.white).copyWith(shadows: const [Shadow(color: Color(0x99000000), blurRadius: 6)])),
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
  const _RoundTool({required this.icon, required this.label, required this.onTap, this.active = false});

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final fg = active ? Colors.black : Colors.white;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: active ? Colors.white : Colors.black.withAlpha(110),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: Colors.white.withAlpha(50)),
        ),
        child: Row(children: [
          Icon(icon, color: fg, size: 18),
          const SizedBox(width: 6),
          Text(label, style: TxDark.body(13.5, weight: FontWeight.w600, color: fg)),
        ]),
      ),
    );
  }
}
