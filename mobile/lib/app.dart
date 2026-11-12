import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'core/appearance.dart';
import 'core/i18n.dart';
import 'core/session.dart';
import 'core/theme.dart';
import 'screens/auth/login_screen.dart';
import 'screens/home/home_shell.dart';
import 'screens/intro/intro_screen.dart';
import 'widgets/common.dart';
import 'widgets/logo.dart';

final navigatorKey = GlobalKey<NavigatorState>();

/// Si algo cierra también la pantalla de inicio (dos «atrás» seguidos al terminar una descarga, un diálogo que se
/// cierra dos veces…), el Navigator quedaría vacío: la app se vería en blanco y Android la mandaría al fondo así.
/// Esto vuelve a poner el inicio.
class _RootGuard extends NavigatorObserver {
  int _routes = 0;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) => _routes++;

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) => _check(-1);

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) => _check(-1);

  void _check(int delta) {
    _routes = (_routes + delta).clamp(0, 1 << 20);
    if (_routes > 0) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_routes > 0) return;
      navigator?.push(MaterialPageRoute<void>(settings: const RouteSettings(name: Navigator.defaultRouteName), builder: (_) => const _Gate()));
    });
  }
}

final _rootGuard = _RootGuard();

class TrevixApp extends StatefulWidget {
  const TrevixApp({super.key});

  @override
  State<TrevixApp> createState() => _TrevixAppState();
}

class _TrevixAppState extends State<TrevixApp> with WidgetsBindingObserver {
  final _appearance = Appearance.instance;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _appearance.addListener(_restyle);
    Lang.instance.addListener(_restyle);
  }

  @override
  void dispose() {
    _appearance.removeListener(_restyle);
    Lang.instance.removeListener(_restyle);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangePlatformBrightness() =>
      _appearance.platformChanged(WidgetsBinding.instance.platformDispatcher.platformBrightness);

  @override
  void didChangeLocales(List<Locale>? locales) => Lang.instance.systemChanged();

  /// Los colores de [Tx] y los textos de [tr] no dependen del contexto: al cambiar la paleta o el idioma se
  /// reconstruye todo lo que está montado, sin perder el estado de las pantallas abiertas.
  void _restyle() {
    setState(() {});
    void mark(Element e) {
      e.markNeedsBuild();
      e.visitChildren(mark);
    }

    (context as Element).visitChildren(mark);
    SystemChrome.setSystemUIOverlayStyle(Tx.overlay);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Tx.theme(reduceMotion: _appearance.reduceMotion);
    return MaterialApp(
      navigatorKey: navigatorKey,
      navigatorObservers: [_rootGuard],
      title: 'TREVIX',
      debugShowCheckedModeBanner: false,
      theme: theme,
      darkTheme: theme,
      themeMode: Tx.isDark ? ThemeMode.dark : ThemeMode.light,
      locale: Lang.instance.locale,
      supportedLocales: const [Locale('es'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      builder: (context, child) => MediaQuery(
        data: _appearance.apply(MediaQuery.of(context)),
        child: AnnotatedRegion<SystemUiOverlayStyle>(value: Tx.overlay, child: child ?? const SizedBox.shrink()),
      ),
      home: const _Gate(),
      // Un enlace que abre la app llega como ruta inicial («/post.php?id=5»): lo atiende DeepLinks, no el Navigator.
      onGenerateInitialRoutes: (_) => [
        MaterialPageRoute<void>(settings: const RouteSettings(name: Navigator.defaultRouteName), builder: (_) => const _Gate()),
      ],
    );
  }
}

/// Arranque → intro (solo la primera vez) → inicio de sesión o la app.
class _Gate extends StatefulWidget {
  const _Gate();

  @override
  State<_Gate> createState() => _GateState();
}

class _GateState extends State<_Gate> {
  Key? _current;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final Widget child;
    if (state.boot == BootState.loading) {
      child = const _Splash(key: ValueKey('splash'));
    } else if (state.boot == BootState.failed) {
      child = _BootError(key: const ValueKey('error'), message: state.bootError ?? '', onRetry: state.start);
    } else if (!state.introSeen) {
      child = const IntroScreen(key: ValueKey('intro'));
    } else if (!state.signedIn || state.addingAccount) {
      child = const LoginScreen(key: ValueKey('login'));
    } else {
      child = HomeShell(key: ValueKey('home-${state.me!.id}'));
    }
    if (_current != null && _current != child.key) {
      // Al entrar o salir de la cuenta se cierran las pantallas abiertas encima (registro, ajustes…).
      WidgetsBinding.instance.addPostFrameCallback((_) => navigatorKey.currentState?.popUntil((r) => r.isFirst));
    }
    _current = child.key;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 500),
      switchInCurve: Curves.easeOutCubic,
      transitionBuilder: (c, anim) => FadeTransition(
        opacity: anim,
        child: ScaleTransition(scale: Tween(begin: .98, end: 1.0).animate(anim), child: c),
      ),
      child: child,
    );
  }
}

class _Splash extends StatelessWidget {
  const _Splash({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: RadialGradient(center: Alignment(0, -.2), radius: .9, colors: [Color(0x407C3AED), Tx.bg]),
        ),
        child: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TrevixLogo(size: 92, glow: true),
            SizedBox(height: 34),
            CupertinoActivityIndicator(radius: 11, color: Tx.accent),
          ]),
        ),
      ),
    );
  }
}

class _BootError extends StatelessWidget {
  const _BootError({super.key, required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: EmptyState(
            icon: CupertinoIcons.wifi_slash,
            title: tr('No pudimos conectar'),
            message: message,
            action: SizedBox(width: 220, child: GradientButton(label: tr('Reintentar'), icon: CupertinoIcons.refresh, onPressed: onRetry)),
          ),
        ),
      ),
    );
  }
}
