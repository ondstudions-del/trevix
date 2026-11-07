import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/nav.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';
import 'story_create_screen.dart';
import 'story_viewer.dart';

class StoriesController extends ChangeNotifier {
  List<StoryGroup> groups = [];
  bool loaded = false;
  bool _loading = false;

  Future<void> load() async {
    if (_loading) return;
    _loading = true;
    try {
      final res = await api.get('stories');
      groups = res.list.map(StoryGroup.fromJson).where((g) => g.items.isNotEmpty).toList();
    } catch (_) {}
    _loading = false;
    loaded = true;
    notifyListeners();
  }

  void changed() => notifyListeners();
}

/// Barra de historias del inicio: la propia primero, con el anillo de la marca en las no vistas.
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
        final own = controller.groups.where((g) => g.own).toList();
        final others = controller.groups.where((g) => !g.own).toList()
          ..sort((a, b) => (b.hasUnseen ? 1 : 0) - (a.hasUnseen ? 1 : 0));
        final ordered = [...own, ...others];
        return SizedBox(
          height: 118,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(10, 12, 10, 4),
            children: [
              _Bubble(
                label: 'Tu historia',
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
                  avatar: Avatar(user: g.user, size: 64, ring: true, ringSeen: !g.hasUnseen),
                  onTap: () => _open(context, ordered, g),
                ),
              if (controller.loaded && others.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(left: 8, top: 22),
                  child: SizedBox(
                    width: 200,
                    child: Text('Las historias de quienes sigues aparecerán aquí durante 24 horas.',
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
  const _Bubble({required this.label, required this.avatar, required this.onTap, this.dim = false});

  final String label;
  final Widget avatar;
  final VoidCallback onTap;
  final bool dim;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 82,
        child: Column(children: [
          SizedBox(height: 76, child: Center(child: avatar)),
          const SizedBox(height: 6),
          Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Tx.body(12, weight: FontWeight.w500, color: dim ? Tx.subtle : Tx.text)),
        ]),
      ),
    );
  }
}
