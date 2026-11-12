import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/audio.dart';
import '../../core/events.dart';
import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/nav.dart';
import '../../core/routes.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';
import '../../widgets/gif_picker.dart';
import '../../widgets/note_bubble.dart';
import '../../widgets/song_chip.dart';
import '../music/music_picker.dart';
import 'close_friends_screen.dart';

/// Público de una nota: clave del servidor, nombre, icono y descripción.
const noteAudiences = <(String, String, IconData, String)>[
  ('followers', 'Seguidores', CupertinoIcons.person_2_fill, 'Las personas que te siguen.'),
  ('friends', 'Amigos', CupertinoIcons.person_3_fill, 'Las personas que sigues y que te siguen.'),
  ('close_friends', 'Mejores amigos', CupertinoIcons.star_fill, 'Solo las personas de tu lista de mejores amigos.'),
];

const _closeFriendsColor = Color(0xFF22C55E);

/// Tiempo que le queda a una nota («Quedan 5 h», «Quedan 20 min»).
String noteRemaining(Note note) {
  final left = note.expiresAt?.difference(DateTime.now());
  if (left == null) return '';
  if (left.inMinutes < 1) return tr('Está por desaparecer');
  if (left.inHours < 1) return tr('Quedan {minutes} min', {'minutes': left.inMinutes});
  return tr('Quedan {hours} h', {'hours': left.inHours});
}

/// Abre la nota: la propia (para cambiarla o eliminarla) o la de otra persona (para responderle).
Future<void> openNote(BuildContext context, Note note) async {
  final action = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _NoteSheet(note: note),
  );
  if (action == 'change' && context.mounted) await composeNote(context, current: note);
}

/// Crear (o reemplazar) la nota propia. Devuelve la nota publicada, o null si se cancela.
/// [song]: nota nueva con esa canción o sonido ya elegido (desde la ficha del sonido).
Future<Note?> composeNote(BuildContext context, {Note? current, Song? song}) {
  return showModalBottomSheet<Note>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _ComposerSheet(current: current, song: song),
  );
}

/// Elimina la nota propia tras confirmarlo. Devuelve true si se eliminó.
Future<bool> deleteNote(BuildContext context) async {
  final ok = await confirm(context, tr('Eliminar nota'), tr('Tu nota dejará de verse en tu perfil y en tus historias.'), action: tr('Eliminar'), destructive: true);
  if (!ok || !context.mounted) return false;
  try {
    final res = await api.delete('notes');
    notesChanged.value++;
    if (context.mounted) toast(context, '${res.map['message'] ?? tr('Eliminaste tu nota.')}');
    return true;
  } catch (e) {
    if (context.mounted) toastError(context, e);
    return false;
  }
}

class _ComposerSheet extends StatefulWidget {
  const _ComposerSheet({this.current, this.song});

  final Note? current;
  final Song? song;

  @override
  State<_ComposerSheet> createState() => _ComposerSheetState();
}

class _ComposerSheetState extends State<_ComposerSheet> {
  late final _text = TextEditingController(text: widget.current?.body ?? '');
  late String _audience = widget.current?.audience ?? 'followers';
  late Gif? _sticker = widget.current?.sticker;
  late PickedSong? _song = _currentSong();
  int? _closeFriends;
  bool _saving = false;

  PickedSong? _currentSong() {
    final s = widget.song ?? widget.current?.song;
    return s != null && s.available ? PickedSong(s, s.clipStart ?? 0) : null;
  }

  bool get _ready => _text.text.trim().isNotEmpty || _sticker != null || _song != null;

  Future<void> _pickSticker() async {
    final gif = await pickGif(context, kind: 'sticker');
    if (gif != null && mounted) setState(() => _sticker = gif);
  }

  Future<void> _pickSong() async {
    final picked = await pickSong(context, current: _song);
    if (picked != null && mounted) setState(() => _song = picked);
  }

  @override
  void initState() {
    super.initState();
    _loadCount();
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _loadCount() async {
    try {
      final res = await api.get('me/close-friends');
      if (mounted) setState(() => _closeFriends = asInt(res.meta['count']));
    } catch (_) {}
  }

  Future<void> _editList() async {
    await push(context, const CloseFriendsScreen());
    _loadCount();
  }

  Future<void> _share() async {
    final body = _text.text.trim();
    if (!_ready || _saving) return;
    if (_audience == 'close_friends' && _closeFriends == 0) {
      toast(context, tr('Agrega al menos una persona a tu lista de mejores amigos.'), error: true);
      return;
    }
    setState(() => _saving = true);
    try {
      final res = await api.post('notes', {
        'body': body,
        'audience': _audience,
        if (_sticker != null) 'sticker_id': _sticker!.id,
        if (_song != null) 'song_id': _song!.song.id,
        if (_song != null) 'song_start': _song!.start,
      });
      notesChanged.value++;
      if (!mounted) return;
      toast(context, '${res.map['message'] ?? tr('Publicaste tu nota.')}');
      Navigator.pop(context, Note.maybe(res.map['note']));
    } catch (e) {
      if (mounted) {
        toastError(context, e);
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = context.watch<AppState>().me!.user;
    final text = _text.text.trim();
    final song = _song?.song;
    final preview = text.isNotEmpty ? text : (song != null ? '♪ ${song.title}' : '');
    final selected = noteAudiences.firstWhere((a) => a.$1 == _audience, orElse: () => noteAudiences.first);
    return SheetFrame(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(child: Text(widget.current == null ? tr('Nueva nota') : tr('Cambiar tu nota'), style: Tx.display(18))),
            Icon(CupertinoIcons.clock, size: 15, color: Tx.subtle),
            const SizedBox(width: 4),
            Text(tr('6 horas'), style: Tx.body(13, color: Tx.subtle)),
          ]),
          const SizedBox(height: 18),
          Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              NoteCloud(
                text: preview.isEmpty && _sticker == null ? tr('¿Qué estás pensando?') : preview,
                placeholder: !_ready,
                sticker: _sticker,
                maxWidth: 240,
                fontSize: 15,
                maxLines: 3,
              ),
              const SizedBox(height: 2),
              Avatar(user: me, size: 76),
            ]),
          ),
          const SizedBox(height: 18),
          TextField(
            controller: _text,
            autofocus: widget.current == null,
            maxLength: 60,
            minLines: 1,
            maxLines: 2,
            textCapitalization: TextCapitalization.sentences,
            onChanged: (_) => setState(() {}),
            style: Tx.body(16),
            decoration: fieldDecoration(tr('Comparte un pensamiento…')),
          ),
          Row(children: [
            if (context.read<AppState>().feature('gifs') || _sticker != null) ...[
              Expanded(
                child: _Extra(
                  icon: CupertinoIcons.smiley,
                  label: _sticker == null ? tr('Sticker') : tr('Cambiar sticker'),
                  active: _sticker != null,
                  onTap: _pickSticker,
                  onClear: _sticker == null ? null : () => setState(() => _sticker = null),
                ),
              ),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: _Extra(
                icon: CupertinoIcons.music_note_2,
                label: song == null ? tr('Música') : song.title,
                active: song != null,
                onTap: _pickSong,
                onClear: song == null ? null : () => setState(() => _song = null),
              ),
            ),
          ]),
          if (song != null) ...[
            const SizedBox(height: 6),
            Text(tr('{artist} · desde {start} (30 s)', {'artist': song.artistLine, 'start': clock(_song!.start)}),
                maxLines: 1, overflow: TextOverflow.ellipsis, style: Tx.body(12.5, color: Tx.subtle)),
          ],
          const SizedBox(height: 14),
          Text(tr('Quién puede verla'), style: Tx.body(13, weight: FontWeight.w600, color: Tx.muted)),
          const SizedBox(height: 8),
          Row(children: [
            for (final a in noteAudiences) ...[
              Expanded(child: _AudienceChip(audience: a, selected: a.$1 == _audience, onTap: () => setState(() => _audience = a.$1))),
              if (a != noteAudiences.last) const SizedBox(width: 8),
            ],
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: Text(
                selected.$1 == 'close_friends' && _closeFriends != null
                    ? '${tr(selected.$4)} (${plural(_closeFriends!, 'persona', 'personas')})'
                    : tr(selected.$4),
                style: Tx.body(13, color: Tx.subtle, height: 1.35),
              ),
            ),
            if (selected.$1 == 'close_friends')
              TextButton(onPressed: _editList, child: Text(tr('Editar lista'), style: Tx.body(13.5, weight: FontWeight.w600, color: Tx.accent))),
          ]),
          const SizedBox(height: 6),
          Text(tr('Se verá durante 6 horas como una nube sobre tu foto, en tu perfil y en tus historias.'),
              style: Tx.body(12.5, color: Tx.subtle, height: 1.35)),
          const SizedBox(height: 14),
          SizedBox(
            height: 50,
            child: FilledButton(
              onPressed: !_ready || _saving ? null : _share,
              style: FilledButton.styleFrom(backgroundColor: Tx.purple, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
              child: _saving
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Text(tr('Compartir'), style: Tx.body(16, weight: FontWeight.w600, color: Colors.white)),
            ),
          ),
        ]),
      ),
    );
  }
}

/// Botón para agregar (o quitar) un sticker o una canción a la nota.
class _Extra extends StatelessWidget {
  const _Extra({required this.icon, required this.label, required this.active, required this.onTap, this.onClear});

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 42,
        padding: const EdgeInsets.only(left: 12, right: 4),
        decoration: BoxDecoration(
          color: active ? Tx.alpha(Tx.accent, .14) : Tx.surface3,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: active ? Tx.accent : Tx.border),
        ),
        child: Row(children: [
          Icon(icon, size: 17, color: active ? Tx.accent : Tx.muted),
          const SizedBox(width: 8),
          Expanded(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: Tx.body(13.5, weight: FontWeight.w600))),
          if (onClear != null)
            IconButton(
              onPressed: onClear,
              visualDensity: VisualDensity.compact,
              tooltip: tr('Quitar'),
              icon: Icon(CupertinoIcons.xmark_circle_fill, size: 18, color: Tx.subtle),
            )
          else
            const SizedBox(width: 8),
        ]),
      ),
    );
  }
}

class _AudienceChip extends StatelessWidget {
  const _AudienceChip({required this.audience, required this.selected, required this.onTap});

  final (String, String, IconData, String) audience;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = audience.$1 == 'close_friends' ? _closeFriendsColor : Tx.accent;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
        decoration: BoxDecoration(
          color: selected ? Tx.alpha(color, .16) : Tx.surface3,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: selected ? color : Tx.border, width: selected ? 1.4 : 1),
        ),
        child: Column(children: [
          Icon(audience.$3, size: 18, color: selected ? color : Tx.muted),
          const SizedBox(height: 4),
          Text(tr(audience.$2),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Tx.body(12.5, weight: FontWeight.w600, color: selected ? Tx.text : Tx.muted)),
        ]),
      ),
    );
  }
}

class _NoteSheet extends StatefulWidget {
  const _NoteSheet({required this.note});

  final Note note;

  @override
  State<_NoteSheet> createState() => _NoteSheetState();
}

class _NoteSheetState extends State<_NoteSheet> {
  final _reply = TextEditingController();
  bool _sending = false;
  bool _liking = false;
  late int? _likes = n.likes;

  /// Actividad de la nota propia: quién la vio y a quién le gustó.
  List<(User, bool liked, bool friend)>? _viewers;
  int _views = 0;
  int _friendViews = 0;

  Note get n => widget.note;
  String get _songKey => 'note:${n.id}';

  @override
  void initState() {
    super.initState();
    _views = n.views ?? 0;
    _friendViews = n.friendViews ?? 0;
    if (n.own) {
      _loadActivity();
    } else {
      api.post('notes/${n.id}/view').then<void>((_) {}, onError: (_) {});
    }
    final song = n.song;
    if (song != null && song.available) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !songPlayer.isPlaying(_songKey)) songPlayer.toggle(_songKey, song, clip: song.hasClip);
      });
    }
  }

  @override
  void dispose() {
    _reply.dispose();
    if (songPlayer.isPlaying(_songKey) || songPlayer.isLoading(_songKey)) songPlayer.stop();
    super.dispose();
  }

  Future<void> _loadActivity() async {
    try {
      final res = await api.get('notes/${n.id}/activity');
      if (!mounted) return;
      setState(() {
        _viewers = [for (final j in res.list) (User.fromJson(j), asBool(j['liked']), asBool(j['friend']))];
        _views = asInt(res.meta['views']);
        _friendViews = asInt(res.meta['friend_views']);
        _likes = asInt(res.meta['likes']);
      });
    } catch (_) {
      if (mounted) setState(() => _viewers = const []);
    }
  }

  Future<void> _like() async {
    if (_liking) return;
    final want = !n.liked;
    setState(() {
      _liking = true;
      n.liked = want;
    });
    try {
      if (want) {
        await api.post('notes/${n.id}/like');
      } else {
        await api.delete('notes/${n.id}/like');
      }
    } catch (e) {
      if (mounted) {
        toastError(context, e);
        setState(() => n.liked = !want);
      }
    }
    if (mounted) setState(() => _liking = false);
  }

  Future<void> _send() async {
    final body = _reply.text.trim();
    if (body.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      final res = await api.post('notes/${n.id}/reply', {'body': body});
      if (!mounted) return;
      toast(context, '${res.map['message'] ?? tr('Respuesta enviada.')}');
      Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        toastError(context, e);
        setState(() => _sending = false);
      }
    }
  }

  Future<void> _delete() async {
    if (await deleteNote(context) && mounted) Navigator.pop(context);
  }

  Widget _ownStats() {
    final viewers = _viewers;
    Widget stat(IconData icon, Color color, int value, String label) => Expanded(
          child: Column(children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(height: 4),
            Text('$value', style: Tx.display(17)),
            Text(label, textAlign: TextAlign.center, style: Tx.body(12, color: Tx.muted)),
          ]),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(color: Tx.surface3, borderRadius: BorderRadius.circular(14)),
        child: Row(children: [
          stat(CupertinoIcons.eye_fill, Tx.accent, _views, _views == 1 ? tr('persona la vio') : tr('personas la vieron')),
          stat(CupertinoIcons.person_2_fill, Tx.success, _friendViews, _friendViews == 1 ? tr('amistad') : tr('amistades')),
          stat(CupertinoIcons.heart_fill, Tx.danger, _likes ?? 0, tr('me gusta')),
        ]),
      ),
      if (viewers == null)
        const Padding(padding: EdgeInsets.all(14), child: Center(child: CupertinoActivityIndicator()))
      else if (viewers.isNotEmpty) ...[
        const SizedBox(height: 12),
        Text(tr('Quién la vio'), style: Tx.body(13, weight: FontWeight.w600, color: Tx.muted)),
        const SizedBox(height: 4),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 260),
          child: ListView(shrinkWrap: true, padding: EdgeInsets.zero, children: [
            for (final (user, liked, friend) in viewers)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(children: [
                  Avatar(user: user, size: 38, onTap: () => openProfile(context, user.username)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(user.displayName, maxLines: 1, overflow: TextOverflow.ellipsis, style: Tx.body(14.5, weight: FontWeight.w600)),
                      Text(friend ? tr('Amistad · @{username}', {'username': user.username}) : '@${user.username}',
                          maxLines: 1, overflow: TextOverflow.ellipsis, style: Tx.body(12.5, color: Tx.subtle)),
                    ]),
                  ),
                  if (liked) const Icon(CupertinoIcons.heart_fill, size: 18, color: Tx.danger),
                ]),
              ),
          ]),
        ),
      ],
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final u = n.user;
    return SheetFrame(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const SizedBox(height: 4),
          Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              NoteCloud(text: n.body, sticker: n.sticker, maxWidth: 280, fontSize: 17, maxLines: 4),
              const SizedBox(height: 2),
              Avatar(user: u, size: 84, onTap: n.own ? null : () => openProfile(context, u.username)),
              const SizedBox(height: 10),
              Row(mainAxisSize: MainAxisSize.min, children: [
                Flexible(child: Text(n.own ? tr('Tu nota') : u.displayName, maxLines: 1, overflow: TextOverflow.ellipsis, style: Tx.display(17))),
                if (u.isVerified && !n.own) ...[const SizedBox(width: 5), const VerifiedBadge(size: 16)],
              ]),
              const SizedBox(height: 3),
              Text([timeAgo(n.createdAt), noteRemaining(n)].where((s) => s.isNotEmpty).join(' · '), style: Tx.body(13, color: Tx.subtle)),
            ]),
          ),
          if (n.song != null) ...[
            const SizedBox(height: 14),
            SongChip(song: n.song!, playKey: _songKey, clip: n.song!.hasClip, compact: true),
          ],
          const SizedBox(height: 18),
          if (n.own) ...[
            _ownStats(),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(color: Tx.surface3, borderRadius: BorderRadius.circular(14)),
              child: Row(children: [
                Icon(n.audience == 'close_friends' ? CupertinoIcons.star_fill : CupertinoIcons.eye,
                    size: 17, color: n.audience == 'close_friends' ? _closeFriendsColor : Tx.muted),
                const SizedBox(width: 10),
                Expanded(child: Text(tr('Visible para: {audience}', {'audience': n.audienceLabel ?? tr('Seguidores')}), style: Tx.body(14, weight: FontWeight.w500))),
              ]),
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: SizedBox(
                  height: 48,
                  child: OutlinedButton.icon(
                    onPressed: _delete,
                    icon: const Icon(CupertinoIcons.trash, size: 17, color: Tx.danger),
                    label: Text(tr('Eliminar'), style: Tx.body(15, weight: FontWeight.w600, color: Tx.danger)),
                    style: OutlinedButton.styleFrom(side: BorderSide(color: Tx.border), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: SizedBox(
                  height: 48,
                  child: FilledButton.icon(
                    onPressed: () => Navigator.pop(context, 'change'),
                    icon: const Icon(CupertinoIcons.pencil, size: 17, color: Colors.white),
                    label: Text(tr('Nueva nota'), style: Tx.body(15, weight: FontWeight.w600, color: Colors.white)),
                    style: FilledButton.styleFrom(backgroundColor: Tx.purple, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                  ),
                ),
              ),
            ]),
          ] else
            Row(children: [
              IconButton(
                onPressed: _like,
                tooltip: n.liked ? tr('Quitar me gusta') : tr('Me gusta'),
                icon: Icon(n.liked ? CupertinoIcons.heart_fill : CupertinoIcons.heart, size: 28, color: n.liked ? Tx.danger : Tx.text),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: TextField(
                  controller: _reply,
                  maxLength: 2000,
                  textInputAction: TextInputAction.send,
                  textCapitalization: TextCapitalization.sentences,
                  onSubmitted: (_) => _send(),
                  onChanged: (_) => setState(() {}),
                  style: Tx.body(15.5),
                  decoration: fieldDecoration(tr('Responder a {name}…', {'name': u.displayName.split(' ').first})).copyWith(counterText: ''),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: _reply.text.trim().isEmpty ? null : _send,
                child: Opacity(
                  opacity: _reply.text.trim().isEmpty ? .5 : 1,
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: const BoxDecoration(gradient: Tx.brand, shape: BoxShape.circle),
                    child: _sending
                        ? const Padding(padding: EdgeInsets.all(14), child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(CupertinoIcons.paperplane_fill, color: Colors.white, size: 20),
                  ),
                ),
              ),
            ]),
          if (!n.own) ...[
            const SizedBox(height: 6),
            Text(tr('Tu respuesta le llegará por mensaje privado.'), textAlign: TextAlign.center, style: Tx.body(12.5, color: Tx.subtle)),
          ],
        ]),
      ),
    );
  }
}
