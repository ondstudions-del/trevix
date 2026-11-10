import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/nav.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';
import '../../widgets/note_bubble.dart';
import '../notes/note_sheets.dart';
import 'story_create_screen.dart';
import 'story_viewer.dart';

class StoriesController extends ChangeNotifier {
  List<StoryGroup> groups = [];

  /// Notas visibles (la propia primero), de las cuentas con y sin historias.
  List<Note> notes = [];
  bool loaded = false;
  bool _loading = false;

  Future<void> load() async {
    if (_loading) return;
    _loading = true;
    final results = await Future.wait([
      api.get('stories').then<List<StoryGroup>?>((res) => res.list.map(StoryGroup.fromJson).where((g) => g.items.isNotEmpty).toList(),
          onError: (_) => null),
      api.get('notes').then<List<Note>?>((res) => res.list.map(Note.fromJson).toList(), onError: (_) => null),
    ]);
    groups = (results[0] as List<StoryGroup>?) ?? groups;
    notes = (results[1] as List<Note>?) ?? notes;
    _loading = false;
    loaded = true;
    notifyListeners();
  }

  void changed() => notifyListeners();
}

/// Barra de historias del inicio: la propia primero, con el anillo de la marca en las no vistas. Sobre cada avatar
/// aparece su nota de 6 horas como una nube; en la propia, «Publicar una nota» si no hay ninguna. Las cuentas con
/// nota pero sin historias van al final.
class StoriesBar extends StatelessWidget {
  const StoriesBar({super.key, required this.controller});

  final StoriesController controller;

  Future<void> _open(BuildContext context, List<StoryGroup> ordered, StoryGroup group) async {
    await pushFade(context, StoryViewer(groups: ordered, initialGroup: ordered.indexOf(group).clamp(0, ordered.length - 1)));
    controller.changed();
  }

  @override
  Widget build(BuildContext context) {
    final me = context.watch<AppState>().me!;
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final notes = {for (final n in controller.notes.where((n) => !n.expired)) n.user.id: n};
        final ownNote = notes[me.user.id];
        final own = controller.groups.where((g) => g.own).toList();
        final others = controller.groups.where((g) => !g.own).toList()
          ..sort((a, b) => (b.hasUnseen ? 1 : 0) - (a.hasUnseen ? 1 : 0));
        final ordered = [...own, ...others];
        for (final g in ordered) {
          g.note = notes[g.user.id];
        }
        final withStories = ordered.map((g) => g.user.id).toSet();
        final noteOnly = controller.notes.where((n) => !n.own && !n.expired && !withStories.contains(n.user.id)).toList();
        return SizedBox(
          height: 152,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
            children: [
              _Bubble(
                label: 'Tu historia',
                note: NoteCloud(
                  text: ownNote?.body ?? 'Publicar una nota',
                  placeholder: ownNote == null,
                  maxWidth: 80,
                  fontSize: 11,
                  onTap: () => ownNote != null ? openNote(context, ownNote) : composeNote(context),
                ),
                avatar: Stack(clipBehavior: Clip.none, children: [
                  Avatar(user: me.user, size: 64, ring: own.isNotEmpty, ringSeen: own.isNotEmpty && !own.first.hasUnseen),
                  Positioned(
                    right: -2,
                    bottom: -2,
                    child: GestureDetector(
                      onTap: () => push(context, const StoryCreateScreen(), fullscreen: true),
                      child: Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(gradient: Tx.brand, shape: BoxShape.circle, border: Border.all(color: Tx.bg, width: 2.5)),
                        child: const Icon(CupertinoIcons.add, size: 14, color: Colors.white),
                      ),
                    ),
                  ),
                ]),
                onTap: () {
                  if (own.isNotEmpty) {
                    _open(context, ordered, own.first);
                  } else {
                    push(context, const StoryCreateScreen(), fullscreen: true);
                  }
                },
              ),
              for (final g in others)
                _Bubble(
                  label: g.user.displayName.split(' ').first,
                  dim: !g.hasUnseen,
                  note: g.note == null ? null : NoteCloud(text: g.note!.body, maxWidth: 80, fontSize: 11, onTap: () => openNote(context, g.note!)),
                  avatar: Avatar(user: g.user, size: 64, ring: true, ringSeen: !g.hasUnseen),
                  onTap: () => _open(context, ordered, g),
                ),
              for (final n in noteOnly)
                _Bubble(
                  label: n.user.displayName.split(' ').first,
                  note: NoteCloud(text: n.body, maxWidth: 80, fontSize: 11, onTap: () => openNote(context, n)),
                  avatar: Avatar(user: n.user, size: 64),
                  onTap: () => openNote(context, n),
                ),
              if (controller.loaded && others.isEmpty && noteOnly.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(left: 8, top: 52),
                  child: SizedBox(
                    width: 210,
                    child: Text('Las historias y notas de quienes sigues aparecerán aquí.',
                        style: Tx.body(12.5, color: Tx.subtle, height: 1.4)),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.label, required this.avatar, required this.onTap, this.note, this.dim = false});

  final String label;
  final Widget avatar;
  final Widget? note;
  final VoidCallback onTap;
  final bool dim;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 86,
        child: Column(children: [
          SizedBox(
            height: 118,
            child: Stack(alignment: Alignment.topCenter, children: [
              Positioned(top: 38, left: 0, right: 0, child: SizedBox(height: 78, child: Center(child: avatar))),
              if (note != null) Positioned(top: 0, child: note!),
            ]),
          ),
          const SizedBox(height: 2),
          Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Tx.body(12, weight: FontWeight.w500, color: dim ? Tx.subtle : Tx.text)),
        ]),
      ),
    );
  }
}
