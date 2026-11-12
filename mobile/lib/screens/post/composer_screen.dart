import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:fc_native_video_thumbnail/fc_native_video_thumbnail.dart';
import 'package:fc_native_video_thumbnail/fc_native_video_thumbnail_platform_interface.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

import '../../core/api.dart';
import '../../core/audio.dart';
import '../../core/catalog.dart';
import '../../core/device.dart';
import '../../core/drafts.dart';
import '../../core/events.dart';
import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/nav.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';
import '../../widgets/event_card.dart';
import '../../widgets/format_bar.dart';
import '../../widgets/gif_picker.dart';
import '../../widgets/media.dart';
import '../../widgets/mention_field.dart';
import '../../widgets/rich_body.dart';
import '../../widgets/song_chip.dart';
import '../../widgets/story_layers.dart' show filtered;
import '../music/music_picker.dart';
import '../reels/reel_draft.dart';
import 'event_form_screen.dart';

const _lifeEventsFallback = {
  'job': 'Nuevo trabajo',
  'graduation': 'Graduación',
  'move': 'Mudanza a una nueva ciudad',
  'relationship': 'Nueva relación',
  'family': 'Nuevo miembro en la familia',
  'travel': 'Viaje',
  'achievement': 'Logro personal',
  'project': 'Nuevo proyecto',
  'birthday': 'Cumpleaños',
  'other': 'Acontecimiento importante',
};

/// Crear (publicación o hilo), editar o compartir. Devuelve la publicación resultante al cerrar.
class ComposerScreen extends StatefulWidget {
  const ComposerScreen({
    super.key,
    this.edit,
    this.share,
    this.community,
    this.format = 'post',
    this.song,
    this.startWithEvent = false,
    this.startWithVideo = false,
    this.reel,
    this.draft,
  });

  final Post? edit;
  final Post? share;
  final Community? community;
  final String format;
  final Song? song;

  /// Abre directamente el formulario del evento (botón «Crear evento» de la sección Eventos).
  final bool startWithEvent;
  /// Abre directamente la elección del video (botón «Reel» del menú Crear y Reels).
  final bool startWithVideo;
  /// Reel que viene de la cámara de reels (video, miniatura, filtro y canción sincronizada).
  final ReelDraft? reel;

  /// Borrador guardado en el teléfono que se retoma (se borra al publicarlo).
  final Draft? draft;

  @override
  State<ComposerScreen> createState() => _ComposerScreenState();
}

class _ComposerScreenState extends State<ComposerScreen> {
  late final TextEditingController _body = TextEditingController(text: widget.edit?.body ?? '');
  late String _format = widget.edit?.format ?? widget.format;
  late String _visibility = widget.edit?.visibility ?? 'public';
  late Community? _community = widget.community;
  final List<XFile> _images = [];
  XFile? _video;
  /// Miniatura del video (primer segundo), generada en el teléfono y subida junto al video.
  String? _poster;
  int? _videoSeconds;
  bool _preparingVideo = false;
  PickedSong? _song;
  bool _songRemoved = false;
  /// Filtro del reel y si el video va sin sonido propio, con la canción a su compás.
  String? _reelFilter;
  bool _songSync = false;
  bool _busy = false;
  String? _error;
  final FocusNode _focus = FocusNode();
  String? _background;
  String? _lifeEvent;
  PostPlace? _place;
  Gif? _gif;
  EventDraft? _event;
  bool _locating = false;

  bool get _editing => widget.edit != null;
  bool get _sharing => widget.share != null;
  int get _maxFiles => context.read<AppState>().limit('max_files_per_post', 10);
  bool get _hasFiles => _images.isNotEmpty || _video != null;

  /// Motivo por el que no se pueden adjuntar fotos o videos ahora mismo (o null si se puede).
  String? get _filesBlocked {
    if (_gif != null) return tr('Un GIF se publica sin fotos ni videos. Quita el GIF primero.');
    if (_event != null) return tr('Un evento solo lleva su portada. Quita el evento primero.');
    if (_background != null) return tr('Un hilo con fondo de color no lleva fotos ni videos.');
    return null;
  }

  Map<String, String> get _lifeEvents {
    final fromServer = asMap(context.read<AppState>().config['life_events']);
    return fromServer.isEmpty ? _lifeEventsFallback : {for (final e in fromServer.entries) e.key: asStr(e.value)};
  }

  /// Para que el botón «Atrás» del sistema pregunte si guardar el borrador en cuanto hay texto.
  bool _bodyEmpty = true;

  @override
  void initState() {
    super.initState();
    final song = widget.edit?.song ?? widget.song;
    if (song != null && song.available) _song = PickedSong(song, song.clipStart ?? 0);
    final reel = widget.reel;
    final draft = widget.draft;
    if (draft != null && !_editing && !_sharing) {
      _restore(draft);
    } else if (reel != null && !_editing && !_sharing) {
      _format = 'post';
      _video = XFile(reel.path);
      _poster = reel.poster;
      _videoSeconds = reel.seconds?.round();
      _reelFilter = reel.filter;
      if (reel.song != null) _song = reel.song;
      _songSync = reel.songSync && reel.song != null;
    } else if (widget.startWithEvent && !_editing && !_sharing) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _editEvent();
      });
    } else if (widget.startWithVideo && !_editing && !_sharing) {
      _format = 'post';
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _addVideo();
      });
    }
    _bodyEmpty = _body.text.trim().isEmpty;
    _body.addListener(() {
      final empty = _body.text.trim().isEmpty;
      if (empty != _bodyEmpty && mounted) setState(() => _bodyEmpty = empty);
    });
  }

  bool get _isThread => _format == 'thread';

  late String? _draftId = widget.draft?.id;

  void _restore(Draft d) {
    final data = d.data;
    _format = asStr(data['format'], 'post');
    _body.text = asStr(data['body']);
    _visibility = asStr(data['visibility'], 'public');
    _background = asStrOrNull(data['background']);
    _lifeEvent = asStrOrNull(data['life_event']);
    _place = PostPlace.maybe(data['place']);
    _reelFilter = asStrOrNull(data['filter']);
    _videoSeconds = asIntOrNull(data['seconds']);
    for (var i = 0; d.files.containsKey('image$i'); i++) {
      _images.add(XFile(d.files['image$i']!));
    }
    final video = d.files['video'];
    if (video != null) _video = XFile(video);
    _poster = d.files['poster'];
    draftSong(data).then((picked) {
      if (!mounted) return;
      if (picked == null) {
        if (asInt(data['song_id']) > 0) toast(context, tr('La canción del borrador ya no está disponible.'), error: true);
        return;
      }
      setState(() {
        _song = PickedSong(picked.$1, picked.$2);
        _songSync = asBool(data['song_sync']) && _video != null;
      });
    });
  }

  bool get _hasContent =>
      !_bodyEmpty || _hasFiles || _song != null || _place != null || _lifeEvent != null || _gif != null || _event != null;

  /// Guarda lo escrito y los archivos en el teléfono (Perfil › Borradores). El GIF, el evento y la comunidad no se guardan.
  Future<bool> _saveDraft() async {
    final me = context.read<AppState>().me;
    if (me == null) return false;
    final song = _song;
    try {
      _draftId = await drafts.save(
        id: _draftId,
        kind: _video != null ? 'reel' : 'post',
        userId: me.user.id,
        data: {
          'format': _format,
          'body': _body.text,
          'visibility': _visibility,
          if (_background != null) 'background': _background,
          if (_lifeEvent != null) 'life_event': _lifeEvent,
          if (_place != null) 'place': {'name': _place!.name, 'lat': _place!.lat, 'lng': _place!.lng},
          if (_reelFilter != null) 'filter': _reelFilter,
          if (_videoSeconds != null) 'seconds': _videoSeconds,
          if (song != null) ...{'song_id': song.song.id, 'song_start': song.start, 'song_sync': _songSync},
        },
        files: {
          for (var i = 0; i < _images.length; i++) 'image$i': _images[i].path,
          if (_video != null) 'video': _video!.path,
          if (_poster != null) 'poster': _poster!,
        },
      );
      if (mounted) toast(context, tr('Guardado en Borradores (en tu perfil).'));
      return true;
    } catch (_) {
      if (mounted) toast(context, tr('No se pudo guardar el borrador. Revisa el espacio libre del teléfono.'), error: true);
      return false;
    }
  }

  Future<void> _cancel() async {
    if (_editing || _sharing || !_hasContent || _busy) {
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

  /// Los hilos solo llevan texto e imágenes: al elegir «Hilo» se quita lo que no admite.
  void _setFormat(String format) {
    if (format == _format) return;
    if (format == 'thread') {
      final dropped = _video != null || _gif != null || (_song != null && !_songRemoved) || _place != null || _lifeEvent != null || _event != null;
      if (dropped) songPlayer.stop('composer');
      setState(() {
        _format = 'thread';
        _video = null;
        _poster = null;
        _videoSeconds = null;
        _reelFilter = null;
        _songSync = false;
        _gif = null;
        _song = null;
        _place = null;
        _lifeEvent = null;
        _event = null;
      });
      if (dropped) toast(context, tr('Los hilos solo llevan texto e imágenes: quitamos lo demás.'));
    } else {
      setState(() {
        _format = 'post';
        _background = null;
      });
    }
  }

  @override
  void dispose() {
    _body.dispose();
    _focus.dispose();
    songPlayer.stop('composer');
    super.dispose();
  }

  bool _blockFiles() {
    final reason = _filesBlocked;
    if (reason != null) toast(context, reason, error: true);
    return reason != null;
  }

  Future<void> _chooseGif() async {
    if (_hasFiles) {
      toast(context, tr('Un GIF se publica sin fotos ni videos. Quítalos primero.'), error: true);
      return;
    }
    final gif = await pickGif(context, kind: 'gif');
    if (gif != null && mounted) {
      setState(() {
        _gif = gif;
        _event = null;
        _background = null;
      });
    }
  }

  Future<void> _chooseLocation() async {
    actionSheet(context, [
      SheetAction(tr('Usar mi ubicación actual'), CupertinoIcons.location_fill, _useCurrentPlace),
      SheetAction(tr('Escribir un lugar'), CupertinoIcons.pencil, () async {
        final name = await prompt(context, tr('¿Dónde estás?'), hint: tr('Ej.: Parque Simón Bolívar, Bogotá'), action: tr('Añadir'), maxLength: 120);
        final clean = name?.trim() ?? '';
        if (clean.isNotEmpty && mounted) setState(() => _place = PostPlace(name: clean));
      }),
      if (_place != null) SheetAction(tr('Quitar ubicación'), CupertinoIcons.trash, () => setState(() => _place = null), destructive: true),
    ], title: tr('Ubicación'));
  }

  Future<void> _useCurrentPlace() async {
    setState(() => _locating = true);
    try {
      final place = await DeviceAccess.currentPlace();
      if (mounted) setState(() => _place = PostPlace(name: place.name, lat: place.lat, lng: place.lng));
    } catch (e) {
      if (mounted) toastError(context, e);
    }
    if (mounted) setState(() => _locating = false);
  }

  void _chooseLifeEvent() {
    actionSheet(context, [
      for (final e in _lifeEvents.entries) SheetAction(tr(e.value), lifeEventIcon(e.key), () => setState(() => _lifeEvent = e.key)),
      if (_lifeEvent != null) SheetAction(tr('Quitar acontecimiento'), CupertinoIcons.trash, () => setState(() => _lifeEvent = null), destructive: true),
    ], title: tr('Acontecimiento importante'));
  }

  Future<void> _editEvent() async {
    if (_hasFiles || _gif != null) {
      toast(context, tr('Un evento solo lleva su portada: quita las fotos, el video o el GIF.'), error: true);
      return;
    }
    final draft = await Navigator.of(context).push<EventDraft>(
      CupertinoPageRoute(fullscreenDialog: true, builder: (_) => EventFormScreen(initial: _event)),
    );
    if (draft != null && mounted) {
      setState(() {
        _event = draft;
        _format = 'post';
        _background = null;
      });
    }
  }

  void _insertMention() {
    final v = _body.value;
    final start = v.selection.isValid ? v.selection.start : v.text.length;
    final end = v.selection.isValid ? v.selection.end : v.text.length;
    final insert = start > 0 && v.text[start - 1].trim().isNotEmpty ? ' @' : '@';
    _body.value = TextEditingValue(
      text: v.text.replaceRange(start, end, insert),
      selection: TextSelection.collapsed(offset: start + insert.length),
    );
    _focus.requestFocus();
  }

  Future<void> _addImages() async {
    if (_blockFiles()) return;
    final remaining = _maxFiles - _images.length;
    if (_video != null || remaining <= 0) {
      toast(context, _video != null ? tr('Una publicación con video no admite más archivos.') : tr('Puedes adjuntar hasta {max} archivos.', {'max': _maxFiles}), error: true);
      return;
    }
    try {
      final files = await ImagePicker().pickMultiImage(imageQuality: 90, maxWidth: 2560);
      if (files.isEmpty) return;
      setState(() => _images.addAll(files.take(remaining)));
      if (files.length > remaining && mounted) toast(context, tr('Solo se añadieron {added} (máximo {max}).', {'added': remaining, 'max': _maxFiles}), error: true);
    } catch (_) {
      if (mounted) toast(context, tr('No se pudo abrir la galería. Revisa el permiso de Fotos.'), error: true);
    }
  }

  Future<void> _addCamera() async {
    if (_blockFiles() || _video != null || _images.length >= _maxFiles) return;
    try {
      final file = await ImagePicker().pickImage(source: ImageSource.camera, imageQuality: 90, maxWidth: 2560);
      if (file != null) setState(() => _images.add(file));
    } catch (_) {
      if (mounted) toast(context, tr('No se pudo abrir la cámara. Revisa el permiso.'), error: true);
    }
  }

  void _addVideo() {
    if (_isThread) {
      toast(context, tr('Los hilos solo llevan texto e imágenes. Elige «Publicación» para subir un video.'), error: true);
      return;
    }
    if (_blockFiles()) return;
    if (_images.isNotEmpty) {
      toast(context, tr('Un video va solo: quita las imágenes para añadirlo.'), error: true);
      return;
    }
    actionSheet(context, [
      SheetAction(tr('Elegir de la galería'), CupertinoIcons.photo_on_rectangle, () => _pickVideo(ImageSource.gallery)),
      SheetAction(tr('Grabar un video'), CupertinoIcons.videocam, () => _pickVideo(ImageSource.camera)),
    ], title: tr('Video (se verá también en Reels)'));
  }

  Future<void> _pickVideo(ImageSource source) async {
    final app = context.read<AppState>();
    final maxBytes = app.limit('video_max_bytes', 300 * 1024 * 1024);
    final maxSeconds = app.limit('video_max_seconds', 300);
    XFile? file;
    try {
      file = await ImagePicker().pickVideo(
        source: source,
        maxDuration: source == ImageSource.camera ? Duration(seconds: maxSeconds) : null,
      );
    } catch (_) {
      if (mounted) {
        toast(
          context,
          source == ImageSource.camera ? tr('No se pudo abrir la cámara. Revisa el permiso.') : tr('No se pudo abrir la galería. Revisa el permiso de Fotos.'),
          error: true,
        );
      }
      return;
    }
    if (file == null || !mounted) return;
    setState(() => _preparingVideo = true);
    try {
      final size = await File(file.path).length();
      if (size > maxBytes) {
        if (mounted) {
          toast(context, tr('El video pesa {size} MB y el máximo es {max} MB. Recórtalo o grábalo en menor calidad.', {'size': (size / 1048576).round(), 'max': (maxBytes / 1048576).round()}), error: true);
        }
        return;
      }
      final seconds = await _videoLength(file.path);
      if (seconds != null && seconds > maxSeconds + 0.5) {
        if (mounted) toast(context, tr('El video dura {length}. Los videos pueden durar como máximo {max} minutos.', {'length': clockText(seconds.round()), 'max': clockText(maxSeconds)}), error: true);
        return;
      }
      final poster = await _makePoster(file.path, seconds);
      if (!mounted) return;
      setState(() {
        _video = file;
        _poster = poster;
        _videoSeconds = seconds?.round();
      });
    } finally {
      if (mounted) setState(() => _preparingVideo = false);
    }
  }

  /// Duración del video en segundos (null si el teléfono no puede leerla; el servidor la vuelve a comprobar).
  Future<double?> _videoLength(String path) async {
    final c = VideoPlayerController.file(File(path));
    try {
      await c.initialize();
      final ms = c.value.duration.inMilliseconds;
      return ms > 0 ? ms / 1000 : null;
    } catch (_) {
      return null;
    } finally {
      await c.dispose();
    }
  }

  /// Fotograma del primer segundo (o antes si el video es muy corto) como miniatura del reel.
  Future<String?> _makePoster(String path, double? seconds) async {
    try {
      final dir = await getTemporaryDirectory();
      final dest = '${dir.path}/poster_${DateTime.now().microsecondsSinceEpoch}.jpg';
      final atMs = seconds == null ? 0 : min(1000, (seconds * 1000 / 3).round());
      final ok = await FcNativeVideoThumbnail().saveThumbnailToFile(
        srcFile: path,
        destFile: dest,
        width: 1080,
        height: 1080,
        quality: 82,
        at: FcVideoThumbnailTime(atMs, FcVideoThumbnailTimeUnit.milliseconds),
      );
      return ok && await File(dest).exists() ? dest : null;
    } catch (_) {
      return null;
    }
  }

  Map<String, String> _visibilities(Me me) =>
      visibilitiesFor(collaborator: me.collaboratorActive && !_sharing, current: widget.edit?.visibility);

  static IconData _visibilityIcon(String key) => switch (key) {
        'public' => CupertinoIcons.globe,
        'followers' => CupertinoIcons.person_2_fill,
        'subscribers' => CupertinoIcons.star_circle_fill,
        _ => CupertinoIcons.lock_fill,
      };

  Future<void> _chooseSong() async {
    if (_songSync) {
      toast(context, tr('El reel se grabó al ritmo de esta canción. Quítala si quieres publicarlo con su propio sonido.'));
      return;
    }
    final picked = await pickSong(context, clipSeconds: context.read<AppState>().limit('song_clip_seconds', 30), current: _song);
    if (picked != null && mounted) {
      setState(() {
        _song = picked;
        _songRemoved = false;
      });
    }
  }

  Future<void> _chooseCommunity() async {
    final picked = await showModalBottomSheet<Community?>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _CommunityPicker(),
    );
    if (picked != null && mounted) setState(() => _community = picked.id == 0 ? null : picked);
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    final body = _body.text.trim();
    final song = _song;
    if (!_sharing && body.isEmpty && !_hasFiles && song == null && _gif == null && _event == null && _lifeEvent == null) {
      setState(() => _error = tr('Escribe algo, añade una foto, un video, un GIF o elige una canción.'));
      return;
    }
    if (_format == 'thread' && body.isEmpty) {
      setState(() => _error = tr('Los hilos necesitan texto.'));
      return;
    }
    if (_preparingVideo) {
      setState(() => _error = tr('Espera un momento: estamos preparando el video.'));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final ApiResponse res;
      if (_editing) {
        final original = widget.edit!.song;
        res = await api.patch('posts/${widget.edit!.id}', {
          'body': body,
          if (widget.edit!.community == null) 'visibility': _visibility,
          if (_songRemoved) 'song_id': 0,
          if (song != null && song.song.id != original?.id) 'song_id': song.song.id,
          if (song != null) 'song_start': song.start,
        });
      } else {
        final fields = <String, String>{
          'body': body,
          'format': _sharing ? 'post' : _format,
          'visibility': _community != null ? 'public' : _visibility,
          if (_community != null) 'community_id': '${_community!.id}',
          if (_sharing) 'shared_post_id': '${widget.share!.id}',
          if (song != null && !_sharing) 'song_id': '${song.song.id}',
          if (song != null && !_sharing) 'song_start': '${song.start}',
          if (!_sharing) ...{
            if (_format == 'thread' && _background != null) 'background': _background!,
            if (_lifeEvent != null) 'life_event': _lifeEvent!,
            if (_place != null) 'location_name': _place!.name,
            if (_place?.lat != null && _place?.lng != null) ...{'location_lat': '${_place!.lat}', 'location_lng': '${_place!.lng}'},
            if (_gif != null) ...{'gif_id': _gif!.id, 'gif_kind': _gif!.kind},
            if (_video != null && _reelFilter != null) 'filter': _reelFilter!,
            if (_video != null && _songSync && song != null) 'song_sync': '1',
          },
        };
        final event = _sharing ? null : _event;
        final cover = event?.cover;
        final files = <Upload>[
          for (var i = 0; i < _images.length; i++) Upload('media[$i]', _images[i].path, filename: _images[i].name),
          if (_video != null) Upload('media[0]', _video!.path, filename: _video!.name),
          if (_video != null && _poster != null) Upload('poster', _poster!, filename: 'poster.jpg'),
          if (cover != null) Upload('event_cover', cover.path, filename: cover.name),
        ];
        if (files.isEmpty) {
          res = await api.post('posts', {...fields, if (event != null) 'event': event.fields()});
        } else {
          res = await api.upload('posts', fields: {
            ...fields,
            if (event != null)
              for (final e in event.fields().entries) 'event[${e.key}]': e.value,
          }, files: files);
        }
      }
      final post = Post.fromJson(res.map);
      if (!_editing) postCreated.value = post;
      final draftId = _draftId;
      if (draftId != null) unawaited(drafts.delete(draftId));
      if (!mounted) return;
      toast(context, _editing ? tr('Cambios guardados.') : (_sharing ? tr('Compartiste la publicación.') : tr('¡Publicado!')));
      Navigator.pop(context, post);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.fields.isNotEmpty ? e.fields.values.join('\n') : e.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = context.watch<AppState>().me!;
    final maxBody = context.read<AppState>().limit('post_body', 2000);
    final title = _editing
        ? tr('Editar')
        : _sharing
            ? tr('Compartir')
            : (_format == 'thread' ? tr('Nuevo hilo') : tr('Nueva publicación'));
    final canMedia = !_editing && !_sharing;
    final canSong = !_sharing;

    return PopScope(
      canPop: _editing || _sharing || _busy || !_hasContent,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _cancel();
      },
      child: Scaffold(
      appBar: GlassBar(
        title: title,
        leading: CupertinoButton(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          onPressed: _cancel,
          child: Text(tr('Cancelar'), style: Tx.body(15.5, color: Tx.muted)),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: GradientButton(
              label: _editing ? tr('Guardar') : tr('Publicar'),
              expand: false,
              height: 38,
              loading: _busy,
              onPressed: _submit,
            ),
          ),
        ],
      ),
      body: Column(children: [
        Expanded(
          child: ListView(padding: const EdgeInsets.fromLTRB(16, 14, 16, 30), children: [
            if (!_editing && !_sharing)
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Row(children: [
                  PillChip(
                    label: tr('Publicación'),
                    icon: CupertinoIcons.square_pencil,
                    selected: _format == 'post',
                    onTap: () => _setFormat('post'),
                  ),
                  const SizedBox(width: 8),
                  PillChip(label: tr('Hilo'), icon: CupertinoIcons.text_quote, selected: _format == 'thread', onTap: () => _setFormat('thread')),
                ]),
              ),
            if (!_editing && !_sharing && _isThread)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(tr('Los hilos llevan texto y, si quieres, imágenes.'), style: Tx.body(12.5, color: Tx.subtle)),
              ),
            if (!_editing && !_sharing && _format == 'thread') _backgroundPicker(),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Avatar(user: me.user, size: 44),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  NameLine(user: me.user),
                  const SizedBox(height: 6),
                  Wrap(spacing: 6, runSpacing: 6, children: [
                    if (_community == null && widget.edit?.community == null)
                      _MiniSelect(
                        icon: _visibilityIcon(_visibility),
                        label: _visibilities(me)[_visibility] ?? _visibility,
                        onTap: () => actionSheet(context, [
                          for (final e in _visibilities(me).entries)
                            SheetAction(e.value, _visibilityIcon(e.key), () => setState(() => _visibility = e.key)),
                        ], title: tr('¿Quién puede verla?')),
                      ),
                    if (!_editing && widget.community == null)
                      _MiniSelect(
                        icon: CupertinoIcons.person_3_fill,
                        label: _community?.name ?? tr('Mi perfil'),
                        onTap: _chooseCommunity,
                      ),
                    if (widget.community != null) _MiniSelect(icon: CupertinoIcons.person_3_fill, label: widget.community!.name),
                  ]),
                ]),
              ),
            ]),
            const SizedBox(height: 12),
            if (_lifeEvent != null) _lifeEventPreview(),
            _bodyField(maxBody),
            MentionSuggestions(controller: _body),
            Padding(padding: const EdgeInsets.only(bottom: 8), child: FormatBar(controller: _body)),
            if (_error != null)
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Tx.alpha(Tx.danger, .1), borderRadius: BorderRadius.circular(14), border: Border.all(color: Tx.alpha(Tx.danger, .35))),
                child: Text(_error!, style: Tx.body(13.5, color: Tx.text)),
              ),
            if (_place != null || _locating) _placePreview(),
            if (_preparingVideo)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(children: [
                  const CupertinoActivityIndicator(radius: 9),
                  const SizedBox(width: 10),
                  Text(tr('Preparando el video…'), style: Tx.body(13.5, color: Tx.muted)),
                ]),
              ),
            if (_hasFiles) _attachments(),
            if (_gif != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Stack(clipBehavior: Clip.none, children: [
                  GifView(gif: _gif!, maxWidth: 260, maxHeight: 260),
                  Positioned(top: 6, right: 6, child: _RemoveButton(onTap: () => setState(() => _gif = null))),
                ]),
              ),
            if (_event != null) _eventPreview(),
            if (_song != null && !_songRemoved)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Row(children: [
                  Expanded(child: SongChip(song: _song!.song.withClip(_song!.start), playKey: 'composer', clip: true)),
                  IconButton(
                    onPressed: () => setState(() {
                      songPlayer.stop('composer');
                      if (_editing && widget.edit!.song != null) _songRemoved = true;
                      _song = null;
                      _songSync = false;
                    }),
                    icon: Icon(CupertinoIcons.xmark_circle_fill, color: Tx.muted),
                  ),
                ]),
              ),
            if (_sharing) ...[
              const SizedBox(height: 12),
              _SharePreview(post: widget.share!),
            ],
            if (_editing && widget.edit!.media.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(tr('Las fotos y videos no se pueden cambiar al editar.'), style: Tx.body(12.5, color: Tx.subtle)),
              ),
          ]),
        ),
        if (canMedia || canSong)
          Container(
            decoration: BoxDecoration(color: Tx.surface1, border: Border(top: BorderSide(color: Tx.border))),
            padding: EdgeInsets.fromLTRB(10, 8, 10, 8 + MediaQuery.of(context).padding.bottom * (MediaQuery.of(context).viewInsets.bottom > 0 ? 0 : 1)),
            child: Row(children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(children: [
                    if (canMedia) ...[
                      _Tool(icon: CupertinoIcons.photo_on_rectangle, onTap: _addImages, tooltip: tr('Fotos')),
                      _Tool(icon: CupertinoIcons.camera, onTap: _addCamera, tooltip: tr('Cámara')),
                    ],
                    if (canMedia && !_isThread) ...[
                      _Tool(icon: CupertinoIcons.film, onTap: _addVideo, active: _video != null, tooltip: tr('Video')),
                      if (context.read<AppState>().feature('gifs')) _Tool(label: 'GIF', onTap: _chooseGif, active: _gif != null, tooltip: 'GIF'),
                    ],
                    if (canSong && !_isThread) _Tool(icon: CupertinoIcons.music_note_2, onTap: _chooseSong, active: _song != null, tooltip: tr('Música')),
                    if (!_isThread) _Tool(icon: CupertinoIcons.at, onTap: _insertMention, tooltip: tr('Mencionar')),
                    if (canMedia && !_isThread) ...[
                      _Tool(icon: CupertinoIcons.location_solid, onTap: _chooseLocation, active: _place != null, tooltip: tr('Ubicación')),
                      _Tool(icon: CupertinoIcons.star_circle, onTap: _chooseLifeEvent, active: _lifeEvent != null, tooltip: tr('Acontecimiento')),
                      _Tool(icon: CupertinoIcons.calendar_badge_plus, onTap: _editEvent, active: _event != null, tooltip: tr('Evento')),
                    ],
                  ]),
                ),
              ),
              if (canMedia && _hasFiles)
                Padding(
                  padding: const EdgeInsets.only(left: 6, right: 8),
                  child: Text('${_video != null ? 1 : _images.length}/$_maxFiles', style: Tx.body(13, color: Tx.subtle)),
                ),
            ]),
          ),
      ]),
    ),
    );
  }

  Widget _bodyField(int maxBody) {
    final bg = _format == 'thread' ? _background : null;
    final field = TextField(
      controller: _body,
      focusNode: _focus,
      autofocus: !_editing,
      maxLength: maxBody,
      minLines: bg != null ? 4 : (_format == 'thread' ? 8 : 5),
      maxLines: null,
      textCapitalization: TextCapitalization.sentences,
      textAlign: bg != null ? TextAlign.center : TextAlign.start,
      style: bg != null
          ? Tx.display(22, color: Colors.white)
          : (_format == 'thread' ? Tx.body(18, height: 1.5) : Tx.body(17, height: 1.45)),
      decoration: InputDecoration(
        border: InputBorder.none,
        hintText: _sharing
            ? tr('Añade un comentario (opcional)')
            : _format == 'thread'
                ? tr('Desarrolla tu idea… usa #hashtags y @menciones')
                : tr('¿Qué está pasando?'),
        hintStyle: bg != null ? Tx.display(20, color: Colors.white70) : Tx.body(17, color: Tx.subtle),
        counterStyle: Tx.body(11.5, color: bg != null ? Colors.white70 : Tx.subtle),
      ),
    );
    if (bg == null) return field;
    return Container(
      constraints: const BoxConstraints(minHeight: 220),
      alignment: Alignment.center,
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
      decoration: BoxDecoration(gradient: Tx.storyBackground(bg), borderRadius: BorderRadius.circular(22)),
      child: field,
    );
  }

  Widget _backgroundPicker() {
    final backgrounds = asMap(context.read<AppState>().config['story_backgrounds']);
    final keys = backgrounds.isEmpty ? const ['violet', 'blue', 'midnight', 'sunset', 'ocean', 'graphite'] : backgrounds.keys.toList();
    Widget swatch({String? key, required String label}) {
      final selected = _background == key;
      return Tooltip(
        message: label,
        child: GestureDetector(
          onTap: () {
            if (key != null && (_hasFiles || _gif != null || _event != null)) {
              toast(context, tr('Un hilo con fondo de color va solo con texto: quita las fotos, el GIF o el evento.'), error: true);
              return;
            }
            setState(() => _background = key);
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            width: 36,
            height: 36,
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
              gradient: key == null ? null : Tx.storyBackground(key),
              color: key == null ? Tx.surface3 : null,
              shape: BoxShape.circle,
              border: Border.all(color: selected ? Colors.white : Tx.borderStrong, width: selected ? 2.5 : 1),
            ),
            child: key == null ? Icon(CupertinoIcons.nosign, size: 16, color: Tx.muted) : null,
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(children: [
        Text(tr('Fondo'), style: Tx.body(13, weight: FontWeight.w600, color: Tx.muted)),
        const SizedBox(width: 10),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              swatch(label: tr('Sin fondo')),
              for (final k in keys) swatch(key: k, label: asStr(backgrounds[k]).isEmpty ? k : asStr(backgrounds[k])),
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _lifeEventPreview() {
    final key = _lifeEvent!;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
      decoration: BoxDecoration(
        color: Tx.alpha(Tx.purple, .12),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Tx.alpha(Tx.purple500, .4)),
      ),
      child: Row(children: [
        Container(
          width: 40,
          height: 40,
          decoration: const BoxDecoration(gradient: Tx.brand, shape: BoxShape.circle),
          child: Icon(lifeEventIcon(key), color: Colors.white, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: GestureDetector(
            onTap: _chooseLifeEvent,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tr('Acontecimiento importante'), style: Tx.body(12, color: Tx.muted)),
              Text(tr(_lifeEvents[key] ?? key), style: Tx.body(15.5, weight: FontWeight.w700)),
            ]),
          ),
        ),
        IconButton(onPressed: () => setState(() => _lifeEvent = null), icon: Icon(CupertinoIcons.xmark_circle_fill, color: Tx.muted)),
      ]),
    );
  }

  Widget _placePreview() {
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 4),
      child: Row(children: [
        Icon(CupertinoIcons.location_solid, size: 16, color: Tx.accent),
        const SizedBox(width: 6),
        Expanded(
          child: _locating
              ? Row(children: [
                  const CupertinoActivityIndicator(radius: 8),
                  const SizedBox(width: 8),
                  Text(tr('Buscando tu ubicación…'), style: Tx.body(13.5, color: Tx.muted)),
                ])
              : GestureDetector(
                  onTap: _chooseLocation,
                  child: Text(_place!.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: Tx.body(14, weight: FontWeight.w600, color: Tx.accent)),
                ),
        ),
        if (!_locating && _place != null)
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: () => setState(() => _place = null),
            icon: Icon(CupertinoIcons.xmark_circle_fill, size: 20, color: Tx.muted),
          ),
      ]),
    );
  }

  Widget _eventPreview() {
    final e = _event!;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: GestureDetector(
        onTap: _editEvent,
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(color: Tx.surface2, borderRadius: BorderRadius.circular(20), border: Border.all(color: Tx.borderStrong)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Stack(children: [
              SizedBox(
                height: 120,
                width: double.infinity,
                child: e.cover != null
                    ? Image.file(File(e.cover!.path), fit: BoxFit.cover)
                    : Container(decoration: const BoxDecoration(gradient: LinearGradient(colors: [Tx.purple700, Tx.blue]))),
              ),
              Positioned(top: 8, right: 8, child: _RemoveButton(onTap: () => setState(() => _event = null))),
            ]),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(eventWhen(e.startsAt, e.endsAt).toUpperCase(), style: Tx.body(12, weight: FontWeight.w700, color: Tx.accent)),
                const SizedBox(height: 4),
                Text(e.title, style: Tx.display(17)),
                const SizedBox(height: 4),
                Row(children: [
                  Icon(CupertinoIcons.location_solid, size: 14, color: Tx.muted),
                  const SizedBox(width: 4),
                  Expanded(child: Text(e.place, maxLines: 1, overflow: TextOverflow.ellipsis, style: Tx.body(13.5, color: Tx.muted))),
                ]),
                const SizedBox(height: 6),
                Text(tr('Toca para editar'), style: Tx.body(12, color: Tx.subtle)),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _attachments() {
    final items = <Widget>[
      for (var i = 0; i < _images.length; i++)
        _Thumb(
          child: Image.file(File(_images[i].path), fit: BoxFit.cover),
          onRemove: () => setState(() => _images.removeAt(i)),
        ),
      if (_video != null)
        _Thumb(
          child: Stack(fit: StackFit.expand, children: [
            ColoredBox(color: Tx.surface3),
            if (_poster != null) filtered(_reelFilter, Image.file(File(_poster!), fit: BoxFit.cover)),
            const Center(child: Icon(CupertinoIcons.play_circle_fill, color: Colors.white, size: 40)),
            Positioned(
              left: 8,
              bottom: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(color: Colors.black.withAlpha(150), borderRadius: BorderRadius.circular(8)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const TxIcon(TxGlyph.reels, size: 12, color: Colors.white, stroke: 2.2),
                  const SizedBox(width: 4),
                  Text(_videoSeconds != null ? clockText(_videoSeconds!) : 'Reel', style: TxDark.body(11.5, weight: FontWeight.w700, color: Colors.white)),
                ]),
              ),
            ),
          ]),
          onRemove: () => setState(() {
            _video = null;
            _poster = null;
            _videoSeconds = null;
            _reelFilter = null;
            _songSync = false;
          }),
        ),
    ];
    return SizedBox(
      height: 150,
      child: ReorderableListView(
        scrollDirection: Axis.horizontal,
        buildDefaultDragHandles: true,
        onReorderItem: (from, to) {
          if (_video != null) return;
          setState(() {
            final item = _images.removeAt(from);
            _images.insert(to, item);
          });
        },
        children: [
          for (var i = 0; i < items.length; i++) KeyedSubtree(key: ValueKey('att-$i-${_images.length}'), child: items[i]),
        ],
      ),
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({required this.child, required this.onRemove});

  final Widget child;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: Stack(children: [
        ClipRRect(borderRadius: BorderRadius.circular(16), child: SizedBox(width: 120, height: 150, child: child)),
        Positioned(
          top: 6,
          right: 6,
          child: GestureDetector(
            onTap: onRemove,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(color: Colors.black.withAlpha(160), shape: BoxShape.circle),
              child: const Icon(CupertinoIcons.xmark, color: Colors.white, size: 14),
            ),
          ),
        ),
      ]),
    );
  }
}

class _Tool extends StatelessWidget {
  const _Tool({this.icon, this.label, required this.onTap, this.active = false, this.tooltip});

  final IconData? icon;
  final String? label;
  final VoidCallback onTap;
  final bool active;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    Widget glyph(Color? color) => label != null
        ? Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(6), border: Border.all(color: color ?? Colors.white, width: 1.6)),
            child: Text(label!, style: Tx.body(11.5, weight: FontWeight.w800, color: color ?? Colors.white)),
          )
        : Icon(icon, size: 24, color: color);
    return IconButton(
      onPressed: onTap,
      tooltip: tooltip,
      icon: active
          ? ShaderMask(
              blendMode: BlendMode.srcIn,
              shaderCallback: (b) => Tx.brandText.createShader(Offset.zero & b.size),
              child: glyph(null),
            )
          : glyph(Tx.accent),
    );
  }
}

class _RemoveButton extends StatelessWidget {
  const _RemoveButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(5),
        decoration: BoxDecoration(color: Colors.black.withAlpha(160), shape: BoxShape.circle),
        child: const Icon(CupertinoIcons.xmark, color: Colors.white, size: 14),
      ),
    );
  }
}

class _MiniSelect extends StatelessWidget {
  const _MiniSelect({required this.icon, required this.label, this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Tx.alpha(Tx.purple500, .45)),
          color: Tx.alpha(Tx.purple, .1),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 13, color: Tx.accent),
          const SizedBox(width: 5),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 150),
            child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: Tx.body(12.5, weight: FontWeight.w600, color: Tx.accent)),
          ),
          if (onTap != null) ...[const SizedBox(width: 3), Icon(CupertinoIcons.chevron_down, size: 11, color: Tx.accent)],
        ]),
      ),
    );
  }
}

class _SharePreview extends StatelessWidget {
  const _SharePreview({required this.post});

  final Post post;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Tx.surface2, borderRadius: BorderRadius.circular(18), border: Border.all(color: Tx.borderStrong)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Avatar(user: post.user, size: 32),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            NameLine(user: post.user, size: 14),
            if (post.body.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(plainText(post.body), maxLines: 4, overflow: TextOverflow.ellipsis, style: Tx.body(14, color: Tx.muted)),
            ],
          ]),
        ),
        if (post.media.isNotEmpty && !post.media.first.isVideo) ...[
          const SizedBox(width: 10),
          NetImage(post.media.first.url, width: 56, height: 56, radius: 10),
        ],
      ]),
    );
  }
}

/// Elegir dónde publicar: el perfil o una comunidad de la que se es miembro.
class _CommunityPicker extends StatefulWidget {
  const _CommunityPicker();

  @override
  State<_CommunityPicker> createState() => _CommunityPickerState();
}

class _CommunityPickerState extends State<_CommunityPicker> {
  List<Community>? _items;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await api.get('communities', {'tab': 'mine'});
      setState(() => _items = res.list.map(Community.fromJson).where((c) => c.isMember).toList());
    } catch (e) {
      setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    return SheetFrame(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * .6),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(padding: const EdgeInsets.fromLTRB(20, 0, 20, 10), child: Text(tr('¿Dónde publicar?'), style: Tx.display(19))),
          ListTile(
            leading: Icon(CupertinoIcons.person_crop_circle, color: Tx.accent),
            title: Text(tr('Mi perfil'), style: Tx.body(15.5, weight: FontWeight.w600)),
            onTap: () => Navigator.pop(context, Community(id: 0, slug: '', name: '')),
          ),
          if (_error != null)
            ErrorState(error: _error!, onRetry: () {
              setState(() => _error = null);
              _load();
            })
          else if (items == null)
            const Loading()
          else if (items.isEmpty)
            Padding(
              padding: const EdgeInsets.all(20),
              child: Text(tr('Aún no perteneces a ninguna comunidad.'), style: Tx.body(14, color: Tx.muted)),
            )
          else
            Flexible(
              child: ListView(shrinkWrap: true, children: [
                for (final c in items)
                  ListTile(
                    leading: c.avatarUrl != null
                        ? NetImage(c.avatarUrl, width: 40, height: 40, radius: 12)
                        : Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(gradient: Tx.brand, borderRadius: BorderRadius.circular(12)),
                            child: const Icon(CupertinoIcons.person_3_fill, color: Colors.white, size: 20),
                          ),
                    title: Text(c.name, style: Tx.body(15, weight: FontWeight.w600)),
                    subtitle: Text(tr(c.category), style: Tx.body(12.5, color: Tx.muted)),
                    onTap: () => Navigator.pop(context, c),
                  ),
              ]),
            ),
        ]),
      ),
    );
  }
}
