import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/audio.dart';
import '../../core/nav.dart';
import '../../core/routes.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';
import '../explore/explore_screen.dart';
import '../feed/feed_screen.dart';
import '../music/artist_screen.dart';
import '../notifications/notifications_screen.dart';
import '../profile/profile_screen.dart';
import '../stories/story_create_screen.dart';

/// Señal para que una pestaña vuelva arriba al tocarla estando activa.
final tabReselect = ValueNotifier<int>(-1);

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  int _tab = 0;
  final _visited = <int>{0};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final app = context.read<AppState>();
    if (state == AppLifecycleState.resumed) {
      app.resumePolling();
    } else if (state == AppLifecycleState.paused) {
      app.pausePolling();
      songPlayer.pause();
    }
  }

  void _select(int i) {
    HapticFeedback.selectionClick();
    if (i == 2) {
      _create();
      return;
    }
    if (i == _tab) {
      tabReselect.value = -1;
      tabReselect.value = i;
      return;
    }
    setState(() {
      _tab = i;
      _visited.add(i);
    });
  }

  void _create() {
    final me = context.read<AppState>().me;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => SheetFrame(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 14),
            child: Text('Crear', style: Tx.display(22)),
          ),
          Row(children: [
            Expanded(
              child: _CreateTile(
                icon: CupertinoIcons.square_pencil,
                label: 'Publicación',
                colors: const [Tx.purple500, Tx.blue],
                onTap: () {
                  Navigator.pop(ctx);
                  openComposer(context);
                },
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _CreateTile(
                icon: CupertinoIcons.text_quote,
                label: 'Hilo',
                colors: const [Color(0xFFA855F7), Color(0xFFEC4899)],
                onTap: () {
                  Navigator.pop(ctx);
                  openComposer(context, format: 'thread');
                },
              ),
            ),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: _CreateTile(
                icon: CupertinoIcons.camera_circle,
                label: 'Historia',
                colors: const [Color(0xFFDB2777), Color(0xFFF59E0B)],
                onTap: () {
                  Navigator.pop(ctx);
                  push(context, const StoryCreateScreen(), fullscreen: true);
                },
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _CreateTile(
                icon: CupertinoIcons.music_note_2,
                label: me != null && me.user.isMusicArtist ? 'Subir canción' : 'Panel de artista',
                colors: const [Tx.blue, Tx.cyan],
                onTap: () {
                  Navigator.pop(ctx);
                  push(context, const ArtistScreen());
                },
              ),
            ),
          ]),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final me = state.me!;
    final pages = <Widget>[
      const FeedScreen(),
      _visited.contains(1) ? const ExploreScreen() : const SizedBox.shrink(),
      const SizedBox.shrink(),
      _visited.contains(3) ? const NotificationsScreen() : const SizedBox.shrink(),
      _visited.contains(4) ? ProfileScreen(username: me.username, asTab: true) : const SizedBox.shrink(),
    ];
    return Scaffold(
      extendBody: true,
      body: IndexedStack(index: _tab, children: pages),
      bottomNavigationBar: _GlassNav(
        index: _tab,
        onTap: _select,
        activity: state.counts.activity,
        avatar: Avatar(user: me.user, size: 28),
      ),
    );
  }
}

class _GlassNav extends StatelessWidget {
  const _GlassNav({required this.index, required this.onTap, required this.activity, required this.avatar});

  final int index;
  final ValueChanged<int> onTap;
  final int activity;
  final Widget avatar;

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom;
    Widget item(int i, IconData icon, IconData active, {int badge = 0}) {
      final selected = i == index;
      return Expanded(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => onTap(i),
          child: SizedBox(
            height: 56,
            child: Center(
              child: Stack(clipBehavior: Clip.none, children: [
                AnimatedScale(
                  duration: const Duration(milliseconds: 220),
                  scale: selected ? 1.08 : 1,
                  child: selected
                      ? ShaderMask(
                          blendMode: BlendMode.srcIn,
                          shaderCallback: (b) => Tx.brandText.createShader(Offset.zero & b.size),
                          child: Icon(active, size: 27),
                        )
                      : Icon(icon, size: 26, color: Tx.muted),
                ),
                if (badge > 0) Positioned(right: -10, top: -6, child: CountBadge(badge)),
              ]),
            ),
          ),
        ),
      );
    }

    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
          padding: EdgeInsets.only(bottom: bottom > 0 ? bottom - 8 : 6, top: 2),
          decoration: BoxDecoration(
            color: Tx.alpha(Tx.bg, .78),
            border: const Border(top: BorderSide(color: Tx.border)),
          ),
          child: Row(children: [
            item(0, CupertinoIcons.house, CupertinoIcons.house_fill),
            item(1, CupertinoIcons.compass, CupertinoIcons.compass_fill),
            Expanded(
              child: GestureDetector(
                onTap: () => onTap(2),
                child: Center(
                  child: Container(
                    width: 50,
                    height: 40,
                    decoration: BoxDecoration(
                      gradient: Tx.brand,
                      borderRadius: BorderRadius.circular(15),
                      boxShadow: [BoxShadow(color: Tx.alpha(Tx.purple, .5), blurRadius: 16, offset: const Offset(0, 4))],
                    ),
                    child: const Icon(CupertinoIcons.add, color: Colors.white, size: 26),
                  ),
                ),
              ),
            ),
            item(3, CupertinoIcons.bell, CupertinoIcons.bell_fill, badge: activity),
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onTap(4),
                child: SizedBox(
                  height: 56,
                  child: Center(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: index == 4 ? Tx.brand : null,
                        color: index == 4 ? null : Colors.transparent,
                      ),
                      child: avatar,
                    ),
                  ),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

class _CreateTile extends StatelessWidget {
  const _CreateTile({required this.icon, required this.label, required this.colors, required this.onTap});

  final IconData icon;
  final String label;
  final List<Color> colors;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Tx.surface3,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          height: 104,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(20), border: Border.all(color: Tx.border)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: colors),
                borderRadius: BorderRadius.circular(13),
                boxShadow: [BoxShadow(color: colors.first.withAlpha(90), blurRadius: 12, offset: const Offset(0, 4))],
              ),
              child: Icon(icon, color: Colors.white, size: 22),
            ),
            Text(label, style: Tx.body(15, weight: FontWeight.w600)),
          ]),
        ),
      ),
    );
  }
}
