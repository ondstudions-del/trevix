import 'dart:io';
import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/audio.dart';
import '../../core/background.dart';
import '../../core/push.dart';
import '../../core/deeplinks.dart';
import '../../core/e2ee.dart';
import '../../core/events.dart';
import '../../core/i18n.dart';
import '../../core/nav.dart';
import '../../core/routes.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../widgets/account_switcher.dart';
import '../../widgets/common.dart';
import '../explore/explore_screen.dart';
import '../feed/feed_screen.dart';
import '../music/artist_screen.dart';
import '../notifications/notifications_screen.dart';
import '../playlists/playlist_screens.dart';
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
    homeTabRequest.addListener(_onTabRequest);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final uid = context.read<AppState>().me?.id;
      if (await shouldShowPermissionsIntro() && mounted) {
        push(context, const PermissionsScreen(onboarding: true), fullscreen: true);
      }
      if (mounted) DeepLinks.instance.attach();
      await BackgroundNotices.start();
      // Con la clave del cifrado cargada, las notificaciones muestran el mensaje y se puede responder desde ellas.
      if (BackgroundNotices.instant && AndroidPush.supported && uid != null) {
        try {
          await e2ee.load(uid);
        } catch (_) {}
      }
    });
  }

  @override
  void dispose() {
    DeepLinks.instance.detach();
    homeTabRequest.removeListener(_onTabRequest);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _onTabRequest() {
    final tab = homeTabRequest.value;
    if (tab < 0 || !mounted) return;
    homeTabRequest.value = -1;
    setState(() {
      _tab = tab;
      _visited.add(tab);
    });
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
            child: Text(tr('Crear'), style: Tx.display(22)),
          ),
          Row(children: [
            Expanded(
              child: _CreateTile(
                glyph: TxGlyph.compose,
                label: tr('Publicación'),
                colors: const [Tx.purple500, Tx.blue],
                onTap: () {
                  Navigator.pop(ctx);
                  openComposer(context);
                },
              ),
            ),
            const SizedBox(width: 10),
            // Las cuentas de creador de contenido no publican hilos: en su lugar, sus listas de reproducción.
            if (me != null && me.user.isCreator)
              Expanded(
                child: _CreateTile(
                  glyph: TxGlyph.reels,
                  label: tr('Lista de reproducción'),
                  colors: const [Color(0xFFA855F7), Color(0xFFEC4899)],
                  onTap: () async {
                    Navigator.pop(ctx);
                    final created = await editPlaylist(context);
                    if (created != null && mounted) push(context, PlaylistScreen(playlist: created));
                  },
                ),
              )
            else
              Expanded(
                child: _CreateTile(
                  glyph: TxGlyph.quote,
                  label: tr('Hilo'),
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
                label: tr('Historia'),
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
                glyph: TxGlyph.reels,
                label: 'Reel',
                colors: const [Color(0xFFF43F5E), Color(0xFF8B5CF6)],
                onTap: () {
                  Navigator.pop(ctx);
                  openReelCamera(context);
                },
              ),
            ),
          ]),
          // Solo quien ya es artista ve «Subir canción»; el resto llega al Panel de artista desde Música o Ajustes.
          if (me != null && me.user.isMusicArtist) ...[
            const SizedBox(height: 10),
            _CreateTile(
              glyph: TxGlyph.music,
              label: tr('Subir canción'),
              colors: const [Tx.blue, Tx.cyan],
              compact: true,
              onTap: () {
                Navigator.pop(ctx);
                push(context, const ArtistScreen());
              },
            ),
          ],
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
    // Botón o gesto «atrás» de Android: desde otra pestaña vuelve al inicio antes de salir de la app.
    return PopScope(
      canPop: _tab == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _tab != 0) _select(0);
      },
      child: Scaffold(
        extendBody: true,
        body: IndexedStack(index: _tab, children: pages),
        bottomNavigationBar: _GlassNav(
          index: _tab,
          onTap: _select,
          activity: state.counts.activity,
          avatar: Avatar(user: me.user, size: 28),
          onProfileLongPress: () => showAccountSwitcher(context),
        ),
      ),
    );
  }
}

class _GlassNav extends StatelessWidget {
  const _GlassNav({required this.index, required this.onTap, required this.activity, required this.avatar, this.onProfileLongPress});

  final int index;
  final ValueChanged<int> onTap;

  /// Mantener pulsada la pestaña del perfil abre el cambio de cuenta.
  final VoidCallback? onProfileLongPress;
  final int activity;
  final Widget avatar;

  static const _height = 66.0;
  static const _labels = ['Inicio', 'Explorar', 'Crear', 'Notificaciones', 'Perfil'];

  /// Android con los tres botones (atrás, inicio, recientes): la barra del sistema es alta y no tiene gestos laterales.
  /// Con navegación por gestos Android reserva las zonas de «atrás» a los lados.
  static bool _buttonNavigation(MediaQueryData media) =>
      Platform.isAndroid && media.viewPadding.bottom >= 32 && media.systemGestureInsets.left == 0 && media.systemGestureInsets.right == 0;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final bottom = media.padding.bottom;
    final docked = _buttonNavigation(media);

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
          child: Semantics(
            button: true,
            selected: i == index,
            label: i == 3 && activity > 0 ? tr('{label}, {count} sin ver', {'label': tr(_labels[i]), 'count': activity}) : tr(_labels[i]),
            hint: i == 4 && onProfileLongPress != null ? tr('Mantén pulsado para cambiar de cuenta') : null,
            excludeSemantics: true,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => onTap(i),
              onLongPress: i == 4 && onProfileLongPress != null
                  ? () {
                      HapticFeedback.mediumImpact();
                      onProfileLongPress!();
                    }
                  : null,
              child: SizedBox(height: _height, child: child),
            ),
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

    final tabs = Row(children: [
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
              color: index == 4 ? null : Tx.alpha(Tx.text, .12),
            ),
            child: avatar,
          ),
          indicator(index == 4),
        ]),
      ),
    ]);
    final glass = ImageFilter.blur(sigmaX: 26, sigmaY: 26);

    // Botones de Android: barra pegada al borde que también queda detrás de los botones del sistema, para que no
    // floten sobre el contenido.
    if (docked) {
      const radius = BorderRadius.vertical(top: Radius.circular(24));
      return DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: radius,
          boxShadow: [BoxShadow(color: Colors.black.withAlpha(Tx.isDark ? 120 : 26), blurRadius: 24, offset: const Offset(0, -4))],
        ),
        child: ClipRRect(
          borderRadius: radius,
          child: BackdropFilter(
            filter: glass,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Tx.alpha(Tx.surface3, .9), Tx.alpha(Tx.surface1, .97)],
                ),
              ),
              child: Stack(children: [
                Padding(padding: EdgeInsets.only(bottom: bottom), child: SizedBox(height: _height, child: tabs)),
                // Solo el filo superior: los lados y la base del borde quedan fuera del recorte.
                Positioned(
                  left: -1,
                  right: -1,
                  top: 0,
                  bottom: -1,
                  child: IgnorePointer(
                    child: DecoratedBox(decoration: BoxDecoration(borderRadius: radius, border: Border.all(color: Tx.border))),
                  ),
                ),
              ]),
            ),
          ),
        ),
      );
    }

    // Gestos de Android: la pastilla queda justo encima de la zona del gesto de inicio, sin tapar la barrita.
    final gap = bottom <= 0 ? 12.0 : (Platform.isAndroid ? bottom + 2 : bottom - 10);
    return Padding(
      padding: EdgeInsets.fromLTRB(14, 0, 14, gap),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(color: Colors.black.withAlpha(Tx.isDark ? 140 : 34), blurRadius: 30, offset: const Offset(0, 12)),
            BoxShadow(color: Tx.alpha(Tx.purple, .16), blurRadius: 40, spreadRadius: -6),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: BackdropFilter(
            filter: glass,
            child: Container(
              height: _height,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(28),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Tx.alpha(Tx.surface3, .82), Tx.alpha(Tx.surface1, .9)],
                ),
                border: Border.all(color: Tx.border),
              ),
              child: tabs,
            ),
          ),
        ),
      ),
    );
  }
}

class _CreateTile extends StatelessWidget {
  const _CreateTile({required this.glyph, required this.label, required this.colors, required this.onTap, this.compact = false});

  final TxGlyph glyph;
  final String label;
  final List<Color> colors;
  final VoidCallback onTap;
  /// Fila de ancho completo (icono y texto en línea) en vez de tarjeta.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final icon = Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: colors),
        borderRadius: BorderRadius.circular(13),
        boxShadow: [BoxShadow(color: colors.first.withAlpha(90), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      alignment: Alignment.center,
      child: TxIcon(glyph, color: Colors.white, size: 22, stroke: 2.1),
    );
    final text = Text(label, style: Tx.body(15, weight: FontWeight.w600));
    return Material(
      color: Tx.surface3,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          height: compact ? 70 : 104,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(20), border: Border.all(color: Tx.border)),
          child: compact
              ? Row(children: [icon, const SizedBox(width: 12), Expanded(child: text), Icon(CupertinoIcons.chevron_right, size: 15, color: Tx.subtle)])
              : Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [icon, text]),
        ),
      ),
    );
  }
}
