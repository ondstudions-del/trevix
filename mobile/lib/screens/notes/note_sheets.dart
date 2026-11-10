import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/events.dart';
import '../../core/format.dart';
import '../../core/nav.dart';
import '../../core/routes.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';
import '../../widgets/note_bubble.dart';
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
  if (left.inMinutes < 1) return 'Está por desaparecer';
  if (left.inHours < 1) return 'Quedan ${left.inMinutes} min';
  return 'Quedan ${left.inHours} h';
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
Future<Note?> composeNote(BuildContext context, {Note? current}) {
  return showModalBottomSheet<Note>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _ComposerSheet(current: current),
  );
}

/// Elimina la nota propia tras confirmarlo. Devuelve true si se eliminó.
Future<bool> deleteNote(BuildContext context) async {
  final ok = await confirm(context, 'Eliminar nota', 'Tu nota dejará de verse en tu perfil y en tus historias.', action: 'Eliminar', destructive: true);
  if (!ok || !context.mounted) return false;
  try {
    final res = await api.delete('notes');
    notesChanged.value++;
    if (context.mounted) toast(context, '${res.map['message'] ?? 'Eliminaste tu nota.'}');
    return true;
  } catch (e) {
    if (context.mounted) toastError(context, e);
    return false;
  }
}

class _ComposerSheet extends StatefulWidget {
  const _ComposerSheet({this.current});

  final Note? current;

  @override
  State<_ComposerSheet> createState() => _ComposerSheetState();
}

class _ComposerSheetState extends State<_ComposerSheet> {
  late final _text = TextEditingController(text: widget.current?.body ?? '');
  late String _audience = widget.current?.audience ?? 'followers';
  int? _closeFriends;
  bool _saving = false;

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
    if (body.isEmpty || _saving) return;
    if (_audience == 'close_friends' && _closeFriends == 0) {
      toast(context, 'Agrega al menos una persona a tu lista de mejores amigos.', error: true);
      return;
    }
    setState(() => _saving = true);
    try {
      final res = await api.post('notes', {'body': body, 'audience': _audience});
      notesChanged.value++;
      if (!mounted) return;
      toast(context, '${res.map['message'] ?? 'Publicaste tu nota.'}');
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
    final selected = noteAudiences.firstWhere((a) => a.$1 == _audience, orElse: () => noteAudiences.first);
    return SheetFrame(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(child: Text(widget.current == null ? 'Nueva nota' : 'Cambiar tu nota', style: Tx.display(18))),
            Icon(CupertinoIcons.clock, size: 15, color: Tx.subtle),
            const SizedBox(width: 4),
            Text('6 horas', style: Tx.body(13, color: Tx.subtle)),
          ]),
          const SizedBox(height: 18),
          Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              NoteCloud(
                text: text.isEmpty ? '¿Qué estás pensando?' : text,
                placeholder: text.isEmpty,
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
            decoration: fieldDecoration('Comparte un pensamiento…'),
          ),
          const SizedBox(height: 6),
          Text('Quién puede verla', style: Tx.body(13, weight: FontWeight.w600, color: Tx.muted)),
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
                    ? '${selected.$4} (${plural(_closeFriends!, 'persona', 'personas')})'
                    : selected.$4,
                style: Tx.body(13, color: Tx.subtle, height: 1.35),
              ),
            ),
            if (selected.$1 == 'close_friends')
              TextButton(onPressed: _editList, child: Text('Editar lista', style: Tx.body(13.5, weight: FontWeight.w600, color: Tx.accent))),
          ]),
          const SizedBox(height: 6),
          Text('Se verá durante 6 horas como una nube sobre tu foto, en tu perfil y en tus historias.',
              style: Tx.body(12.5, color: Tx.subtle, height: 1.35)),
          const SizedBox(height: 14),
          SizedBox(
            height: 50,
            child: FilledButton(
              onPressed: text.isEmpty || _saving ? null : _share,
              style: FilledButton.styleFrom(backgroundColor: Tx.purple, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
              child: _saving
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Text('Compartir', style: Tx.body(16, weight: FontWeight.w600, color: Colors.white)),
            ),
          ),
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
          Text(audience.$2,
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

  Note get n => widget.note;

  @override
  void dispose() {
    _reply.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final body = _reply.text.trim();
    if (body.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      final res = await api.post('notes/${n.id}/reply', {'body': body});
      if (!mounted) return;
      toast(context, '${res.map['message'] ?? 'Respuesta enviada.'}');
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
              NoteCloud(text: n.body, maxWidth: 280, fontSize: 17, maxLines: 4),
              const SizedBox(height: 2),
              Avatar(user: u, size: 84, onTap: n.own ? null : () => openProfile(context, u.username)),
              const SizedBox(height: 10),
              Row(mainAxisSize: MainAxisSize.min, children: [
                Flexible(child: Text(n.own ? 'Tu nota' : u.displayName, maxLines: 1, overflow: TextOverflow.ellipsis, style: Tx.display(17))),
                if (u.isVerified && !n.own) ...[const SizedBox(width: 5), const VerifiedBadge(size: 16)],
              ]),
              const SizedBox(height: 3),
              Text([timeAgo(n.createdAt), noteRemaining(n)].where((s) => s.isNotEmpty).join(' · '), style: Tx.body(13, color: Tx.subtle)),
            ]),
          ),
          const SizedBox(height: 18),
          if (n.own) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(color: Tx.surface3, borderRadius: BorderRadius.circular(14)),
              child: Row(children: [
                Icon(n.audience == 'close_friends' ? CupertinoIcons.star_fill : CupertinoIcons.eye,
                    size: 17, color: n.audience == 'close_friends' ? _closeFriendsColor : Tx.muted),
                const SizedBox(width: 10),
                Expanded(child: Text('Visible para: ${n.audienceLabel ?? 'Seguidores'}', style: Tx.body(14, weight: FontWeight.w500))),
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
                    label: Text('Eliminar', style: Tx.body(15, weight: FontWeight.w600, color: Tx.danger)),
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
                    label: Text('Nueva nota', style: Tx.body(15, weight: FontWeight.w600, color: Colors.white)),
                    style: FilledButton.styleFrom(backgroundColor: Tx.purple, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                  ),
                ),
              ),
            ]),
          ] else
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _reply,
                  maxLength: 2000,
                  textInputAction: TextInputAction.send,
                  textCapitalization: TextCapitalization.sentences,
                  onSubmitted: (_) => _send(),
                  onChanged: (_) => setState(() {}),
                  style: Tx.body(15.5),
                  decoration: fieldDecoration('Responder a ${u.displayName.split(' ').first}…').copyWith(counterText: ''),
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
            Text('Tu respuesta le llegará por mensaje privado.', textAlign: TextAlign.center, style: Tx.body(12.5, color: Tx.subtle)),
          ],
        ]),
      ),
    );
  }
}
