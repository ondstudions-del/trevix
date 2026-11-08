import 'dart:ui';

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
import '../settings/permissions_screen.dart';
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
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (await shouldShowPermissionsIntro() && mounted) {
        push(context, const PermissionsScreen(onboarding: true), fullscreen: true);
      }
    });
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
                glyph: TxGlyph.compose,
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
                glyph: TxGlyph.quote,
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
                glyph: TxGlyph.camera,
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
                glyph: TxGlyph.music,
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

  static const _height = 66.0;

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom;

    Widget indicator(bool selected) => AnimatedContainer(
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
          width: selected ? 18 : 0,
          height: 3,
          margin: const EdgeInsets.only(top: 6),
          decoration: BoxDecoration(
            gradient: Tx.brand,
            borderRadius: BorderRadius.circular(2),
            boxShadow: selected ? [BoxShadow(color: Tx.alpha(Tx.purple500, .8), blurRadius: 8)] : null,
          ),
        );

    Widget slot(int i, Widget child) => Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => onTap(i),
            child: SizedBox(height: _height, child: child),
          ),
        );

    Widget item(int i, TxGlyph glyph, {int badge = 0}) {
      final selected = i == index;
      return slot(
        i,
        Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const SizedBox(height: 9),
          Stack(clipBehavior: Clip.none, children: [
            AnimatedScale(
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOutBack,
              scale: selected ? 1.1 : 1,
              child: selected
                  ? TxIcon(glyph, size: 25, filled: true, gradient: Tx.brandText, stroke: 2)
                  : TxIcon(glyph, size: 25, color: Tx.muted, stroke: 1.9),
            ),
            if (badge > 0) Positioned(right: -11, top: -7, child: CountBadge(badge)),
          ]),
          indicator(selected),
        ]),
      );
    }

    return Padding(
      padding: EdgeInsets.fromLTRB(14, 0, 14, bottom > 0 ? bottom - 10 : 12),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(color: Colors.black.withAlpha(140), blurRadius: 30, offset: const Offset(0, 12)),
            BoxShadow(color: Tx.alpha(Tx.purple, .16), blurRadius: 40, spreadRadius: -6),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 26, sigmaY: 26),
            child: Container(
              height: _height,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(28),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Tx.alpha(Tx.surface3, .82), Tx.alpha(Tx.surface1, .9)],
                ),
                border: Border.all(color: Tx.alpha(Colors.white, .09)),
              ),
              child: Row(children: [
                item(0, TxGlyph.home),
                item(1, TxGlyph.explore),
                slot(
                  2,
                  Center(
                    child: Container(
                      width: 52,
                      height: 44,
                      decoration: BoxDecoration(
                        gradient: Tx.brand,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Tx.alpha(Colors.white, .18)),
                        boxShadow: [BoxShadow(color: Tx.alpha(Tx.purple, .55), blurRadius: 18, offset: const Offset(0, 6))],
                      ),
                      alignment: Alignment.center,
                      child: const TxIcon(TxGlyph.plus, size: 24, color: Colors.white, stroke: 2.6),
                    ),
                  ),
                ),
                item(3, TxGlyph.bell, badge: activity),
                slot(
                  4,
                  Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    const SizedBox(height: 9),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: index == 4 ? Tx.brand : null,
                        color: index == 4 ? null : Tx.alpha(Colors.white, .12),
                      ),
                      child: avatar,
                    ),
                    indicator(index == 4),
                  ]),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class _CreateTile extends StatelessWidget {
  const _CreateTile({required this.glyph, required this.label, required this.colors, required this.onTap});

  final TxGlyph glyph;
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
              alignment: Alignment.center,
              child: TxIcon(glyph, color: Colors.white, size: 22, stroke: 2.1),
            ),
            Text(label, style: Tx.body(15, weight: FontWeight.w600)),
          ]),
        ),
      ),
    );
  }
}
