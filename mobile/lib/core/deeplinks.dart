import 'package:flutter/widgets.dart';

import '../app.dart';
import '../screens/explore/post_list_screens.dart';
import '../screens/notifications/follow_requests_screen.dart';
import '../screens/wallet/collaborator_screen.dart';
import '../screens/wallet/wallet_screen.dart';
import 'events.dart';
import 'nav.dart';
import 'routes.dart';

/// Enlaces que abren la app: trevix://open/post.php?id=5 y, con el dominio asociado, https://trevix.ond-s.com/post.php?id=5.
/// Los avisos de Android abren también messages.php?c=ID (un chat) y notifications.php (la pestaña de notificaciones).
/// iOS los entrega como ruta (FlutterDeepLinkingEnabled); si la sesión aún no está lista quedan pendientes hasta el inicio.
class DeepLinks with WidgetsBindingObserver {
  DeepLinks._();

  static final DeepLinks instance = DeepLinks._();

  Uri? _pending;
  bool _ready = false;

  /// Se registra antes que la app para recibir el enlace primero (el Navigator no conoce estas rutas).
  void install() {
    WidgetsBinding.instance.addObserver(this);
    final initial = WidgetsBinding.instance.platformDispatcher.defaultRouteName;
    if (initial != '/' && initial.isNotEmpty) _pending = Uri.tryParse(initial);
  }

  @override
  Future<bool> didPushRouteInformation(RouteInformation routeInformation) async {
    _pending = routeInformation.uri;
    _flush();
    return true;
  }

  /// El inicio (con sesión) avisa que ya puede abrir pantallas.
  void attach() {
    _ready = true;
    WidgetsBinding.instance.addPostFrameCallback((_) => _flush());
  }

  void detach() => _ready = false;

  void _flush() {
    final uri = _pending;
    final context = navigatorKey.currentState?.overlay?.context;
    if (uri == null || !_ready || context == null) return;
    _pending = null;
    open(context, uri);
  }

  /// Ruta de TREVIX que representa el enlace: «post.php», «profile.php»…
  static String page(Uri uri) {
    final segments = [
      if (uri.scheme == 'trevix' && uri.host.isNotEmpty && uri.host != 'open') uri.host,
      ...uri.pathSegments.where((s) => s.isNotEmpty),
    ];
    return segments.isEmpty ? '' : segments.last.toLowerCase();
  }

  /// Abre la pantalla que corresponde. Devuelve false si el enlace no lleva a ninguna (entonces solo se abre la app).
  static bool open(BuildContext context, Uri uri) {
    final q = uri.queryParameters;
    final id = int.tryParse(q['id'] ?? '') ?? 0;
    switch (page(uri)) {
      case 'post.php' when id > 0:
        openPost(context, id);
      case 'profile.php' || 'artist.php' when (q['u'] ?? '').isNotEmpty:
        openProfile(context, q['u']!);
      case 'community.php' when (q['c'] ?? '').isNotEmpty:
        openCommunity(context, q['c']!);
      case 'music.php' when id > 0:
        openSong(context, id);
      case 'explore.php' when (q['tag'] ?? '').isNotEmpty:
        openHashtag(context, q['tag']!);
      case 'explore.php' when q['type'] == 'featured':
        push(context, const FeaturedScreen());
      case 'event.php' when id > 0:
        openEvent(context, id);
      case 'events.php':
        push(context, const EventsScreen());
      case 'messages.php' when (int.tryParse(q['c'] ?? '') ?? 0) > 0:
        openChat(context, int.parse(q['c']!));
      case 'g.php' when (q['c'] ?? '').isNotEmpty:
        openGroupInvite(context, q['c']!);
      case 'wallet.php' when walletAvailable:
        push(context, switch (q['tab']) {
          'collaborator' => const CollaboratorScreen(),
          'subscriptions' => const SubscriptionsScreen(),
          _ => const WalletScreen(),
        });
      case 'notifications.php':
        Navigator.of(context).popUntil((r) => r.isFirst);
        homeTabRequest.value = 3;
        if (q['tab'] == 'requests') push(context, const FollowRequestsScreen());
      default:
        return false;
    }
    return true;
  }
}
