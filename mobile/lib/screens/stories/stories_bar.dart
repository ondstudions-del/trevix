import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/events.dart';
import '../../core/i18n.dart';
import '../../core/livekit_api.dart';
import '../../core/livekit_nav.dart';
import '../../core/nav.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';
import '../../widgets/note_bubble.dart';
import '../notes/note_sheets.dart';
import 'story_create_screen.dart';
import 'story_viewer.dart';
import '../ads/ads_screen.dart';
import '../../widgets/ond_ad_meta.dart';

class StoriesController extends ChangeNotifier {
  List<StoryGroup> groups = [];

  /// Notas visibles (la propia primero), de las cuentas con y sin historias.
  List<Note> notes = [];

  /// Lives activos indexados por host user id.
  Map<int, LiveKitSession> livesByHost = {};
  bool loaded = false;
  bool _loading = false;
  Json? storyAd;
  int storyAdPosition = 3;

  Future<void> load() async {
    if (_loading) return;
    _loading = true;
    final results = await Future.wait([
      api.get('stories').then<List<StoryGroup>?>((res) {
            storyAd = OndAdBinding.slotFromMeta(res.meta)?.ad;
            storyAdPosition = OndAdBinding.slotFromMeta(res.meta)?.position ?? 3;
            return res.list.map(StoryGroup.fromJson).where((g) => g.items.isNotEmpty).toList();
          }, onError: (_) => null),
      api.get('notes').then<List<Note>?>((res) => res.list.map(Note.fromJson).toList(), onError: (_) => null),
      liveKitListLives().then<List<LiveKitSession>?>((list) => list, onError: (_) => null),
    ]);
    groups = (results[0] as List<StoryGroup>?) ?? groups;
    notes = (results[1] as List<Note>?) ?? notes;
    final lives = (results[2] as List<LiveKitSession>?) ?? const <LiveKitSession>[];
    livesByHost = {
      for (final s in lives)
        if (s.hostId != null) s.hostId!: s,
    };
    _loading = false;
    loaded = true;
    notifyListeners();
  }

  void changed() => notifyListeners();
}

/// Barra de historias del inicio: la propia primero; si alguien está en live, anillo rojo + VIVO.
class StoriesBar extends StatelessWidget {
  const StoriesBar({super.key, required this.controller});

  final StoriesController controller;

  Future<void> _open(BuildContext context, List<StoryGroup> ordered, StoryGroup group) async {
    await pushFade(context, StoryViewer(groups: ordered, initialGroup: ordered.indexOf(group).clamp(0, ordered.length - 1)));
    controller.changed();
  }

  Future<void> _openLive(BuildContext context, LiveKitSession session) async {
    try {
      await openLiveSession(context, session.id, title: session.title, video: session.liveMode != 'voice_chat');
      await controller.load();
    } catch (e) {
      if (context.mounted) toastError(context, e);
    }
  }

  Widget _liveBadge() {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(color: const Color(0xFFE11D48), borderRadius: BorderRadius.circular(6)),
          child: Text(tr('VIVO'), style: Tx.body(9, weight: FontWeight.w800, color: Colors.white)),
        ),
      ),
    );
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
          ..sort((a, b) {
            final aLive = controller.livesByHost.containsKey(a.user.id) ? 1 : 0;
            final bLive = controller.livesByHost.containsKey(b.user.id) ? 1 : 0;
            if (aLive != bLive) return bLive - aLive;
            return (b.hasUnseen ? 1 : 0) - (a.hasUnseen ? 1 : 0);
          });
        final ordered = [...own, ...others];
        for (final g in ordered) {
          g.note = notes[g.user.id];
        }
        final withStories = ordered.map((g) => g.user.id).toSet();
        final noteOnly = controller.notes.where((n) => !n.own && !n.expired && !withStories.contains(n.user.id)).toList();
        final liveOnly = controller.livesByHost.entries
            .where((e) => e.key != me.user.id && !withStories.contains(e.key))
            .map((e) => e.value)
            .toList();
        final ownLive = controller.livesByHost[me.user.id];

        return SizedBox(
          height: 152,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
            children: [
              _Bubble(
                label: ownLive != null ? tr('Tu live') : tr('Tu historia'),
                note: NoteCloud(
                  text: ownNote?.label ?? tr('Publicar una nota'),
                  sticker: ownNote?.sticker,
                  placeholder: ownNote == null,
                  maxWidth: 80,
                  fontSize: 11,
                  onTap: () => ownNote != null ? openNote(context, ownNote) : composeNote(context),
                ),
                avatar: Stack(clipBehavior: Clip.none, children: [
                  ValueListenableBuilder<double?>(
                    valueListenable: storyUploadProgress,
                    builder: (context, progress, _) => progress == null
                        ? Avatar(
                            user: me.user,
                            size: 64,
                            liveRing: ownLive != null,
                            ring: ownLive == null && own.isNotEmpty,
                            ringSeen: ownLive == null && own.isNotEmpty && !own.first.hasUnseen,
                          )
                        : Semantics(
                            label: tr('Subiendo tu historia… {percent} %', {'percent': '${(progress * 100).round()}'}),
                            child: Stack(alignment: Alignment.center, children: [
                              Opacity(opacity: .6, child: Avatar(user: me.user, size: 64)),
                              SizedBox(
                                width: 70,
                                height: 70,
                                child: CircularProgressIndicator(value: progress < .02 ? null : progress, strokeWidth: 3, color: Tx.purple500, backgroundColor: Tx.surface4),
                              ),
                              Text(
                                '${(progress.clamp(0, 1) * 100).round()}%',
                                style: Tx.body(11, weight: FontWeight.w800, color: Colors.white),
                              ),
                            ]),
                          ),
                  ),
                  if (ownLive != null) _liveBadge(),
                  if (ownLive == null)
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
                  if (ownLive != null) {
                    _openLive(context, ownLive);
                  } else if (own.isNotEmpty) {
                    _open(context, ordered, own.first);
                  } else {
                    push(context, const StoryCreateScreen(), fullscreen: true);
                  }
                },
              ),
              for (var si = 0; si < others.length; si++) ...[
                if (controller.storyAd != null && si + 1 == controller.storyAdPosition.clamp(1, others.length + 1))
                  SponsoredStoryBubble(ad: controller.storyAd!),
                Builder(builder: (context) {
                  final g = others[si];
                  final live = controller.livesByHost[g.user.id];
                  return _Bubble(
                    label: g.user.displayName.split(' ').first,
                    dim: live == null && !g.hasUnseen,
                    note: g.note == null ? null : NoteCloud(text: g.note!.label, sticker: g.note!.sticker, maxWidth: 80, fontSize: 11, onTap: () => openNote(context, g.note!)),
                    avatar: Stack(clipBehavior: Clip.none, children: [
                      Avatar(
                        user: g.user,
                        size: 64,
                        liveRing: live != null,
                        ring: live == null,
                        ringSeen: live == null && !g.hasUnseen,
                      ),
                      if (live != null) _liveBadge(),
                    ]),
                    onTap: () => live != null ? _openLive(context, live) : _open(context, ordered, g),
                  );
                }),
              ],
              if (controller.storyAd != null && controller.storyAdPosition > others.length)
                SponsoredStoryBubble(ad: controller.storyAd!),
              for (final s in liveOnly)
                if (s.hostUser != null)
                  _Bubble(
                    label: (s.hostName ?? s.hostUsername ?? '').split(' ').first,
                    avatar: Stack(clipBehavior: Clip.none, children: [
                      Avatar(user: s.hostUser!, size: 64, liveRing: true),
                      _liveBadge(),
                    ]),
                    onTap: () => _openLive(context, s),
                  ),
              for (final n in noteOnly)
                if (!controller.livesByHost.containsKey(n.user.id))
                  _Bubble(
                    label: n.user.displayName.split(' ').first,
                    note: NoteCloud(text: n.label, sticker: n.sticker, maxWidth: 80, fontSize: 11, onTap: () => openNote(context, n)),
                    avatar: Avatar(user: n.user, size: 64),
                    onTap: () => openNote(context, n),
                  ),
              if (controller.loaded && others.isEmpty && noteOnly.isEmpty && liveOnly.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(left: 8, top: 52),
                  child: SizedBox(
                    width: 210,
                    child: Text(tr('Las historias y notas de quienes sigues aparecerán aquí.'),
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
