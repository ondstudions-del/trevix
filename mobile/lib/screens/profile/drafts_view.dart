import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/drafts.dart';
import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/nav.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';
import '../../widgets/story_layers.dart' show filtered;
import '../post/composer_screen.dart';
import '../stories/story_create_screen.dart';

/// Perfil › Borradores: publicaciones, reels e historias guardados en este teléfono. Al tocar uno se retoma en su
/// pantalla; al publicarlo se borra.
class DraftsSliver extends StatefulWidget {
  const DraftsSliver({super.key});

  @override
  State<DraftsSliver> createState() => _DraftsSliverState();
}

class _DraftsSliverState extends State<DraftsSliver> {
  List<Draft>? _items;

  @override
  void initState() {
    super.initState();
    drafts.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    drafts.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final me = context.read<AppState>().me;
    if (me == null) return;
    final items = await drafts.list(me.user.id);
    if (mounted) setState(() => _items = items);
  }

  Future<void> _open(Draft d) async {
    if (d.kind == 'story') {
      await push(context, StoryCreateScreen(draft: d), fullscreen: true);
    } else {
      await push<Post>(context, ComposerScreen(draft: d), fullscreen: true);
    }
    _load();
  }

  void _menu(Draft d) {
    actionSheet(context, [
      SheetAction(tr('Seguir editando'), CupertinoIcons.pencil, () => _open(d)),
      SheetAction(tr('Eliminar borrador'), CupertinoIcons.trash, () async {
        if (await confirm(context, tr('Eliminar borrador'), tr('Se borrará de este teléfono y no se puede deshacer.'), action: tr('Eliminar'), destructive: true)) {
          await drafts.delete(d.id);
        }
      }, destructive: true),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    if (items == null) return const SliverToBoxAdapter(child: Padding(padding: EdgeInsets.all(40), child: Loading()));
    if (items.isEmpty) {
      return SliverToBoxAdapter(
        child: EmptyState(
          icon: CupertinoIcons.tray,
          title: tr('Sin borradores'),
          message: tr('Al salir de una publicación, un reel o una historia sin publicar, elige «Guardar borrador». Se guardan solo en este teléfono.'),
        ),
      );
    }
    return SliverPadding(
      padding: const EdgeInsets.all(10),
      sliver: SliverGrid(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, mainAxisSpacing: 4, crossAxisSpacing: 4, childAspectRatio: 3 / 4),
        delegate: SliverChildBuilderDelegate(
          (_, i) => _DraftTile(draft: items[i], onTap: () => _open(items[i]), onMenu: () => _menu(items[i])),
          childCount: items.length,
        ),
      ),
    );
  }
}

class _DraftTile extends StatelessWidget {
  const _DraftTile({required this.draft, required this.onTap, required this.onMenu});

  final Draft draft;
  final VoidCallback onTap;
  final VoidCallback onMenu;

  @override
  Widget build(BuildContext context) {
    final thumb = draft.thumb;
    final filter = asStrOrNull(draft.data['filter']);
    final (IconData icon, String label) = switch (draft.kind) {
      'story' => (CupertinoIcons.circle_grid_hex, tr('Historia')),
      'reel' => (CupertinoIcons.play_rectangle, tr('Reel')),
      _ => (CupertinoIcons.square_pencil, tr('Publicación')),
    };
    return Semantics(
      button: true,
      label: '$label · ${tr('Borrador')} · ${timeAgo(draft.savedAt)}',
      child: GestureDetector(
        onTap: onTap,
        onLongPress: onMenu,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Stack(fit: StackFit.expand, children: [
            if (thumb != null && File(thumb).existsSync())
              filtered(filter, Image.file(File(thumb), fit: BoxFit.cover, cacheWidth: 360))
            else
              Container(
                decoration: BoxDecoration(gradient: draft.kind == 'story' ? Tx.storyBackground(asStr(draft.data['background'], 'violet')) : null, color: Tx.surface2),
                padding: const EdgeInsets.all(10),
                alignment: Alignment.center,
                child: Text(
                  draft.text.trim().isEmpty ? label : draft.text.trim(),
                  maxLines: 5,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: Tx.body(12.5, weight: FontWeight.w600, color: draft.kind == 'story' ? Colors.white : Tx.text),
                ),
              ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.fromLTRB(7, 16, 4, 5),
                decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, Color(0xB3000000)])),
                child: Row(children: [
                  Icon(icon, size: 13, color: Colors.white),
                  const SizedBox(width: 4),
                  Expanded(child: Text(timeAgo(draft.savedAt), maxLines: 1, overflow: TextOverflow.ellipsis, style: TxDark.body(11, color: Colors.white))),
                  GestureDetector(
                    onTap: onMenu,
                    child: Semantics(
                      button: true,
                      label: tr('Opciones del borrador'),
                      child: const Padding(padding: EdgeInsets.all(2), child: Icon(CupertinoIcons.ellipsis, size: 15, color: Colors.white)),
                    ),
                  ),
                ]),
              ),
            ),
            if (asBool(draft.data['private']))
              const Positioned(top: 6, right: 6, child: Icon(CupertinoIcons.lock_fill, size: 14, color: Colors.white)),
          ]),
        ),
      ),
    );
  }
}
