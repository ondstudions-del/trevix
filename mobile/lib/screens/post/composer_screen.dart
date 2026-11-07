import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/audio.dart';
import '../../core/catalog.dart';
import '../../core/events.dart';
import '../../core/nav.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';
import '../../widgets/song_chip.dart';
import '../music/music_picker.dart';

/// Crear (publicación o hilo), editar o compartir. Devuelve la publicación resultante al cerrar.
class ComposerScreen extends StatefulWidget {
  const ComposerScreen({super.key, this.edit, this.share, this.community, this.format = 'post', this.song});

  final Post? edit;
  final Post? share;
  final Community? community;
  final String format;
  final Song? song;

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
  PickedSong? _song;
  bool _songRemoved = false;
  bool _busy = false;
  String? _error;

  bool get _editing => widget.edit != null;
  bool get _sharing => widget.share != null;
  int get _maxFiles => context.read<AppState>().limit('max_files_per_post', 10);

  @override
  void initState() {
    super.initState();
    final song = widget.edit?.song ?? widget.song;
    if (song != null && song.available) _song = PickedSong(song, song.clipStart ?? 0);
  }

  @override
  void dispose() {
    _body.dispose();
    songPlayer.stop('composer');
    super.dispose();
  }

  Future<void> _addImages() async {
    final remaining = _maxFiles - _images.length;
    if (_video != null || remaining <= 0) {
      toast(context, _video != null ? 'Una publicación con video no admite más archivos.' : 'Puedes adjuntar hasta $_maxFiles archivos.', error: true);
      return;
    }
    try {
      final files = await ImagePicker().pickMultiImage(imageQuality: 90, maxWidth: 2560);
      if (files.isEmpty) return;
      setState(() => _images.addAll(files.take(remaining)));
      if (files.length > remaining && mounted) toast(context, 'Solo se añadieron $remaining (máximo $_maxFiles).', error: true);
    } catch (_) {
      if (mounted) toast(context, 'No se pudo abrir la galería. Revisa el permiso de Fotos.', error: true);
    }
  }

  Future<void> _addCamera() async {
    if (_video != null || _images.length >= _maxFiles) return;
    try {
      final file = await ImagePicker().pickImage(source: ImageSource.camera, imageQuality: 90, maxWidth: 2560);
      if (file != null) setState(() => _images.add(file));
    } catch (_) {
      if (mounted) toast(context, 'No se pudo abrir la cámara. Revisa el permiso.', error: true);
    }
  }

  Future<void> _addVideo() async {
    if (_images.isNotEmpty) {
      toast(context, 'Un video va solo: quita las imágenes para añadirlo.', error: true);
      return;
    }
    try {
      final file = await ImagePicker().pickVideo(source: ImageSource.gallery);
      if (file == null) return;
      final size = await File(file.path).length();
      if (size > 60 * 1024 * 1024) {
        if (mounted) toast(context, 'El video supera los 60 MB.', error: true);
        return;
      }
      setState(() => _video = file);
    } catch (_) {
      if (mounted) toast(context, 'No se pudo abrir la galería. Revisa el permiso de Fotos.', error: true);
    }
  }

  Future<void> _chooseSong() async {
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
    if (!_sharing && body.isEmpty && _images.isEmpty && _video == null && song == null) {
      setState(() => _error = 'Escribe algo, añade una foto o video, o elige una canción.');
      return;
    }
    if (_format == 'thread' && body.isEmpty) {
      setState(() => _error = 'Los hilos necesitan texto.');
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
        };
        final files = <Upload>[
          for (var i = 0; i < _images.length; i++) Upload('media[$i]', _images[i].path, filename: _images[i].name),
          if (_video != null) Upload('media[0]', _video!.path, filename: _video!.name),
        ];
        res = files.isEmpty ? await api.post('posts', fields) : await api.upload('posts', fields: fields, files: files);
      }
      final post = Post.fromJson(res.map);
      if (!_editing) postCreated.value = post;
      if (!mounted) return;
      toast(context, _editing ? 'Cambios guardados.' : (_sharing ? 'Compartiste la publicación.' : '¡Publicado!'));
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
        ? 'Editar'
        : _sharing
            ? 'Compartir'
            : (_format == 'thread' ? 'Nuevo hilo' : 'Nueva publicación');
    final canMedia = !_editing && !_sharing;
    final canSong = !_sharing;

    return Scaffold(
      appBar: GlassBar(
        title: title,
        leading: CupertinoButton(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          onPressed: () => Navigator.pop(context),
          child: Text('Cancelar', style: Tx.body(15.5, color: Tx.muted)),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: GradientButton(
              label: _editing ? 'Guardar' : 'Publicar',
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
                  PillChip(label: 'Publicación', icon: CupertinoIcons.square_pencil, selected: _format == 'post', onTap: () => setState(() => _format = 'post')),
                  const SizedBox(width: 8),
                  PillChip(label: 'Hilo', icon: CupertinoIcons.text_quote, selected: _format == 'thread', onTap: () => setState(() => _format = 'thread')),
                ]),
              ),
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
                        icon: _visibility == 'public'
                            ? CupertinoIcons.globe
                            : _visibility == 'followers'
                                ? CupertinoIcons.person_2_fill
                                : CupertinoIcons.lock_fill,
                        label: visibilities[_visibility]!,
                        onTap: () => actionSheet(context, [
                          for (final e in visibilities.entries)
                            SheetAction(
                              e.value,
                              e.key == 'public'
                                  ? CupertinoIcons.globe
                                  : e.key == 'followers'
                                      ? CupertinoIcons.person_2_fill
                                      : CupertinoIcons.lock_fill,
                              () => setState(() => _visibility = e.key),
                            ),
                        ], title: '¿Quién puede verla?'),
                      ),
                    if (!_editing && widget.community == null)
                      _MiniSelect(
                        icon: CupertinoIcons.person_3_fill,
                        label: _community?.name ?? 'Mi perfil',
                        onTap: _chooseCommunity,
                      ),
                    if (widget.community != null) _MiniSelect(icon: CupertinoIcons.person_3_fill, label: widget.community!.name),
                  ]),
                ]),
              ),
            ]),
            const SizedBox(height: 12),
            TextField(
              controller: _body,
              autofocus: !_editing,
              maxLength: maxBody,
              minLines: _format == 'thread' ? 8 : 5,
              maxLines: null,
              textCapitalization: TextCapitalization.sentences,
              style: _format == 'thread' ? Tx.body(18, height: 1.5) : Tx.body(17, height: 1.45),
              decoration: InputDecoration(
                border: InputBorder.none,
                hintText: _sharing
                    ? 'Añade un comentario (opcional)'
                    : _format == 'thread'
                        ? 'Desarrolla tu idea… usa #hashtags y @menciones'
                        : '¿Qué está pasando?',
                hintStyle: Tx.body(17, color: Tx.subtle),
                counterStyle: Tx.body(11.5, color: Tx.subtle),
              ),
            ),
            if (_error != null)
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Tx.alpha(Tx.danger, .1), borderRadius: BorderRadius.circular(14), border: Border.all(color: Tx.alpha(Tx.danger, .35))),
                child: Text(_error!, style: Tx.body(13.5, color: Tx.text)),
              ),
            if (_images.isNotEmpty || _video != null) _attachments(),
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
                    }),
                    icon: const Icon(CupertinoIcons.xmark_circle_fill, color: Tx.muted),
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
                child: Text('Las fotos y videos no se pueden cambiar al editar.', style: Tx.body(12.5, color: Tx.subtle)),
              ),
          ]),
        ),
        if (canMedia || canSong)
          Container(
            decoration: const BoxDecoration(color: Tx.surface1, border: Border(top: BorderSide(color: Tx.border))),
            padding: EdgeInsets.fromLTRB(10, 8, 10, 8 + MediaQuery.of(context).padding.bottom * (MediaQuery.of(context).viewInsets.bottom > 0 ? 0 : 1)),
            child: Row(children: [
              if (canMedia) ...[
                _Tool(icon: CupertinoIcons.photo_on_rectangle, onTap: _addImages),
                _Tool(icon: CupertinoIcons.camera, onTap: _addCamera),
                _Tool(icon: CupertinoIcons.film, onTap: _addVideo),
              ],
              if (canSong) _Tool(icon: CupertinoIcons.music_note_2, onTap: _chooseSong, active: _song != null),
              const Spacer(),
              if (canMedia && (_images.isNotEmpty || _video != null))
                Text('${_video != null ? 1 : _images.length}/$_maxFiles', style: Tx.body(13, color: Tx.subtle)),
              const SizedBox(width: 8),
            ]),
          ),
      ]),
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
          child: Container(
            color: Tx.surface3,
            child: const Center(child: Icon(CupertinoIcons.play_circle_fill, color: Colors.white, size: 40)),
          ),
          onRemove: () => setState(() => _video = null),
        ),
    ];
    return SizedBox(
      height: 150,
      child: ReorderableListView(
        scrollDirection: Axis.horizontal,
        buildDefaultDragHandles: true,
        onReorder: (from, to) {
          if (_video != null) return;
          setState(() {
            if (to > from) to--;
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
  const _Tool({required this.icon, required this.onTap, this.active = false});

  final IconData icon;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onTap,
      icon: active
          ? ShaderMask(
              blendMode: BlendMode.srcIn,
              shaderCallback: (b) => Tx.brandText.createShader(Offset.zero & b.size),
              child: Icon(icon, size: 24),
            )
          : Icon(icon, size: 24, color: Tx.purple300),
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
          Icon(icon, size: 13, color: Tx.purple300),
          const SizedBox(width: 5),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 150),
            child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: Tx.body(12.5, weight: FontWeight.w600, color: Tx.purple300)),
          ),
          if (onTap != null) ...[const SizedBox(width: 3), const Icon(CupertinoIcons.chevron_down, size: 11, color: Tx.purple300)],
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
              Text(post.body, maxLines: 4, overflow: TextOverflow.ellipsis, style: Tx.body(14, color: Tx.muted)),
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
          Padding(padding: const EdgeInsets.fromLTRB(20, 0, 20, 10), child: Text('¿Dónde publicar?', style: Tx.display(19))),
          ListTile(
            leading: const Icon(CupertinoIcons.person_crop_circle, color: Tx.purple300),
            title: Text('Mi perfil', style: Tx.body(15.5, weight: FontWeight.w600)),
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
              child: Text('Aún no perteneces a ninguna comunidad.', style: Tx.body(14, color: Tx.muted)),
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
                    subtitle: Text(c.category, style: Tx.body(12.5, color: Tx.muted)),
                    onTap: () => Navigator.pop(context, c),
                  ),
              ]),
            ),
        ]),
      ),
    );
  }
}
