import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart' show Contact;
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/config.dart';
import '../../core/device.dart';
import '../../core/nav.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';

const _seenKey = 'trevix_permissions_seen';

/// Si aún no se mostró la presentación de permisos en este iPhone.
Future<bool> shouldShowPermissionsIntro() async {
  final prefs = await SharedPreferences.getInstance();
  return !(prefs.getBool(_seenKey) ?? false);
}

class _Item {
  const _Item(this.access, this.icon, this.color, this.title, this.text);

  final Access access;
  final IconData icon;
  final Color color;
  final String title;
  final String text;
}

final _items = [
  _Item(Access.notifications, CupertinoIcons.bell_fill, Tx.like, 'Notificaciones',
      'Te avisamos de mensajes y notificaciones nuevas mientras usas TREVIX.'),
  _Item(Access.microphone, CupertinoIcons.mic_fill, Tx.accentSoft, 'Micrófono', 'Para grabar notas de voz en tus chats.'),
  _Item(Access.photos, CupertinoIcons.photo_fill, Tx.warning, 'Fotos', 'Para guardar en tu galería las imágenes que abras en TREVIX.'),
  _Item(Access.location, CupertinoIcons.location_fill, Tx.success, 'Ubicación',
      'Para completar el país de tu perfil. Solo mientras usas la app; no la compartimos.'),
  _Item(Access.contacts, CupertinoIcons.person_2_fill, Tx.blue400, 'Contactos',
      'Para invitar a tus contactos a TREVIX por SMS. Tus contactos no se suben a nuestros servidores.'),
];

/// Permisos del iPhone: qué usa TREVIX, su estado y botones para concederlos.
/// Con [onboarding], se muestra una vez después de iniciar sesión.
class PermissionsScreen extends StatefulWidget {
  const PermissionsScreen({super.key, this.onboarding = false});

  final bool onboarding;

  @override
  State<PermissionsScreen> createState() => _PermissionsScreenState();
}

class _PermissionsScreenState extends State<PermissionsScreen> with WidgetsBindingObserver {
  final Map<Access, AccessState> _states = {};
  final Set<Access> _busy = {};
  bool _requestingAll = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    for (final item in _items) {
      final s = await DeviceAccess.state(item.access);
      if (!mounted) return;
      setState(() => _states[item.access] = s);
    }
  }

  Future<void> _request(Access a) async {
    if (_states[a] == AccessState.denied) {
      await DeviceAccess.openSettings();
      return;
    }
    setState(() => _busy.add(a));
    bool granted = false;
    try {
      granted = await DeviceAccess.request(a);
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _busy.remove(a);
      _states[a] = granted ? AccessState.granted : AccessState.denied;
    });
  }

  Future<void> _requestAll() async {
    setState(() => _requestingAll = true);
    for (final item in _items) {
      if (_states[item.access] == AccessState.unknown) await _request(item.access);
      if (!mounted) return;
    }
    setState(() => _requestingAll = false);
  }

  Future<void> _finish() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_seenKey, true);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final list = ListView(padding: const EdgeInsets.fromLTRB(16, 14, 16, 30), children: [
      if (widget.onboarding) ...[
        const SizedBox(height: 18),
        Text('Prepara TREVIX', style: Tx.display(28)),
        const SizedBox(height: 8),
        Text('Estos permisos activan funciones de la app. Puedes darlos ahora o más tarde desde Ajustes › Permisos.',
            style: Tx.body(15, color: Tx.muted, height: 1.45)),
        const SizedBox(height: 20),
      ],
      Container(
        decoration: BoxDecoration(color: Tx.surface1, borderRadius: BorderRadius.circular(Tx.radiusLg), border: Border.all(color: Tx.border)),
        clipBehavior: Clip.antiAlias,
        child: Column(children: [
          for (var i = 0; i < _items.length; i++) ...[
            if (i > 0) Divider(height: 1, thickness: 1, indent: 62, color: Tx.border),
            _row(_items[i]),
          ],
        ]),
      ),
      const SizedBox(height: 14),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Text(
          'Elegir fotos y videos para publicar no necesita permiso: usas el selector del ${DeviceAccess.phone}. '
          'Con la app cerrada, TREVIX revisa tus avisos cada cierto tiempo (el sistema decide cuándo, según la batería y la red).',
          style: Tx.body(12.5, color: Tx.subtle, height: 1.45),
        ),
      ),
    ]);

    if (!widget.onboarding) {
      return Scaffold(appBar: const GlassBar(title: 'Permisos'), body: list);
    }
    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          Expanded(child: list),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
            child: Column(children: [
              GradientButton(
                label: 'Permitir todo',
                icon: CupertinoIcons.checkmark_shield,
                loading: _requestingAll,
                onPressed: _states.values.any((s) => s == AccessState.unknown) ? _requestAll : null,
              ),
              CupertinoButton(
                onPressed: _requestingAll ? null : _finish,
                child: Text('Continuar', style: Tx.body(16, weight: FontWeight.w600, color: Tx.accent)),
              ),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _row(_Item item) {
    final state = _states[item.access];
    final busy = _busy.contains(item.access);
    Widget trailing;
    if (state == null || busy) {
      trailing = const CupertinoActivityIndicator();
    } else if (state == AccessState.granted) {
      trailing = Row(mainAxisSize: MainAxisSize.min, children: [
        const Icon(CupertinoIcons.checkmark_circle_fill, color: Tx.success, size: 18),
        const SizedBox(width: 4),
        Text('Activado', style: Tx.body(13, weight: FontWeight.w600, color: Tx.success)),
      ]);
    } else if (state == AccessState.denied) {
      trailing = SoftButton(label: 'Ajustes', height: 34, onPressed: () => _request(item.access));
    } else {
      trailing = SoftButton(label: 'Permitir', height: 34, color: Tx.accent, onPressed: () => _request(item.access));
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      child: Row(children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(color: Tx.alpha(item.color, .16), borderRadius: BorderRadius.circular(10)),
          child: Icon(item.icon, size: 19, color: item.color),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(item.title, style: Tx.body(15.5, weight: FontWeight.w600)),
            const SizedBox(height: 2),
            Text(item.text, style: Tx.body(12.5, color: Tx.muted, height: 1.35)),
            if (state == AccessState.denied)
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Text('Rechazado: actívalo en Ajustes del ${DeviceAccess.phone}.', style: Tx.body(12, color: Tx.warning)),
              ),
          ]),
        ),
        const SizedBox(width: 10),
        trailing,
      ]),
    );
  }
}

/// Invitar a contactos del iPhone a TREVIX por SMS (los contactos no salen del teléfono).
class InviteContactsScreen extends StatefulWidget {
  const InviteContactsScreen({super.key});

  @override
  State<InviteContactsScreen> createState() => _InviteContactsScreenState();
}

class _InviteContactsScreenState extends State<InviteContactsScreen> {
  List<Contact>? _contacts;
  String? _error;
  final _search = TextEditingController();

  static final String _message = 'Únete a mí en TREVIX, la red social para conectar, compartir y descubrir: ${AppConfig.web('register.php')}';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _error = null;
      _contacts = null;
    });
    try {
      final list = await DeviceAccess.contacts();
      if (mounted) setState(() => _contacts = list);
    } on DeviceException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'No se pudieron leer tus contactos.');
    }
  }

  Future<void> _invite(Contact c) async {
    final phone = c.phones.first.number.replaceAll(RegExp(r'[^0-9+]'), '');
    if (phone.isEmpty) return;
    final ok = await launchUrl(Uri.parse('sms:$phone&body=${Uri.encodeComponent(_message)}'));
    if (!ok && mounted) toast(context, 'No se pudo abrir Mensajes.', error: true);
  }

  @override
  Widget build(BuildContext context) {
    final contacts = _contacts;
    final q = _search.text.trim().toLowerCase();
    final shown = contacts == null ? const <Contact>[] : contacts.where((c) => q.isEmpty || (c.displayName ?? '').toLowerCase().contains(q)).toList();
    return Scaffold(
      appBar: GlassBar(
        title: 'Invitar contactos',
        actions: [
          IconButton(
            tooltip: 'Compartir enlace',
            onPressed: () => Share.share(_message),
            icon: Icon(CupertinoIcons.share, color: Tx.text),
          ),
        ],
      ),
      body: _error != null
          ? EmptyState(
              icon: CupertinoIcons.person_2,
              title: 'Sin acceso a contactos',
              message: _error,
              action: Row(mainAxisSize: MainAxisSize.min, children: [
                SoftButton(label: 'Ajustes', icon: CupertinoIcons.gear, onPressed: DeviceAccess.openSettings),
                const SizedBox(width: 10),
                SoftButton(label: 'Reintentar', icon: CupertinoIcons.refresh, onPressed: _load),
              ]),
            )
          : contacts == null
              ? const Loading()
              : Column(children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
                    child: TextField(
                      controller: _search,
                      onChanged: (_) => setState(() {}),
                      style: Tx.body(15),
                      decoration: fieldDecoration('Buscar contacto', prefix: Icon(CupertinoIcons.search, color: Tx.subtle, size: 20)),
                    ),
                  ),
                  Expanded(
                    child: shown.isEmpty
                        ? const EmptyState(icon: CupertinoIcons.person_2, title: 'Sin contactos', message: 'No hay contactos con teléfono que coincidan.')
                        : ListView.builder(
                            padding: const EdgeInsets.only(bottom: 30),
                            itemCount: shown.length,
                            itemBuilder: (_, i) {
                              final c = shown[i];
                              final display = (c.displayName ?? '').trim();
                              final name = display.isEmpty ? c.phones.first.number : display;
                              return ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: Tx.surface4,
                                  child: Text(name.isEmpty ? '#' : name.characters.first.toUpperCase(), style: Tx.body(16, weight: FontWeight.w700)),
                                ),
                                title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: Tx.body(15.5, weight: FontWeight.w600)),
                                subtitle: Text(c.phones.first.number, style: Tx.body(13, color: Tx.muted)),
                                trailing: SoftButton(label: 'Invitar', height: 34, color: Tx.accent, onPressed: () => _invite(c)),
                              );
                            },
                          ),
                  ),
                ]),
    );
  }
}
