import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/e2ee.dart';
import '../../core/i18n.dart';
import '../../core/nav.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';
import '../../widgets/settings_tiles.dart';

enum PinMode { create, recover, change }

bool _offered = false;

/// Carga la clave del cifrado en este teléfono. Si falta, abre la pantalla del PIN (crear o recuperar).
/// Devuelve true cuando el teléfono ya puede cifrar y descifrar.
Future<bool> ensureE2ee(BuildContext context, {bool optional = false}) async {
  final uid = context.read<AppState>().me?.user.id;
  if (uid == null) return false;
  try {
    await e2ee.load(uid);
  } catch (e) {
    if (e2ee.ready) return true;
    if (context.mounted) toastError(context, e);
    return false;
  }
  if (e2ee.ready) return true;
  if (!context.mounted) return false;
  final s = e2ee.status;
  final mode = s != null && s.configured && s.hasBackup ? PinMode.recover : PinMode.create;
  final ok = await push<bool>(context, PinScreen(mode: mode, optional: optional), fullscreen: true);
  return ok == true && e2ee.ready;
}

/// Al abrir Mensajes por primera vez en la sesión: pide crear o recuperar el PIN (con «Más tarde»).
Future<void> offerE2ee(BuildContext context) async {
  if (_offered) return;
  _offered = true;
  final uid = context.read<AppState>().me?.user.id;
  if (uid == null) return;
  try {
    await e2ee.load(uid);
  } catch (_) {
    return;
  }
  if (e2ee.ready || !context.mounted) return;
  await ensureE2ee(context, optional: true);
}

bool _weak(String pin) {
  if (RegExp(r'^(\d)\1{5}$').hasMatch(pin)) return true;
  const runs = '0123456789012345';
  const back = '9876543210987654';
  return runs.contains(pin) || back.contains(pin);
}

/// PIN de 6 dígitos del cifrado: crear (y confirmar), recuperar la clave en este teléfono o cambiarlo.
class PinScreen extends StatefulWidget {
  const PinScreen({super.key, required this.mode, this.optional = false});

  final PinMode mode;

  /// Muestra «Más tarde» (la primera vez que se abre Mensajes).
  final bool optional;

  @override
  State<PinScreen> createState() => _PinScreenState();
}

class _PinScreenState extends State<PinScreen> with SingleTickerProviderStateMixin {
  late PinMode _mode = widget.mode;
  String _pin = '';
  String? _first;
  String? _error;
  bool _busy = false;
  bool _reset = false;
  late final AnimationController _shake = AnimationController(vsync: this, duration: const Duration(milliseconds: 380));

  @override
  void dispose() {
    _shake.dispose();
    super.dispose();
  }

  String get _title {
    if (_busy) return _mode == PinMode.recover ? tr('Recuperando tus chats…') : tr('Preparando el cifrado…');
    return switch (_mode) {
      PinMode.recover => tr('Escribe tu PIN'),
      PinMode.change => _first == null ? tr('Elige un PIN nuevo') : tr('Confirma el PIN nuevo'),
      PinMode.create => _first == null ? (_reset ? tr('Crea un PIN nuevo') : tr('Crea tu PIN')) : tr('Confirma tu PIN'),
    };
  }

  String get _subtitle => switch (_mode) {
        PinMode.recover =>
          tr('Tus chats están cifrados de extremo a extremo. Escribe el PIN de 6 dígitos que creaste para leerlos en este teléfono.'),
        PinMode.change => tr('El PIN protege la copia de tu clave. Lo necesitarás al instalar la app en otro teléfono.'),
        PinMode.create => _reset
            ? tr('Se creará una clave nueva. Los mensajes cifrados anteriores no se podrán leer en este teléfono.')
            : tr('Tus mensajes se cifran en tu teléfono: nadie fuera del chat, ni siquiera TREVIX, puede leerlos. Con este PIN recuperas tus chats en otro teléfono.'),
      };

  void _fail(String message) {
    HapticFeedback.heavyImpact();
    _shake.forward(from: 0);
    setState(() {
      _error = message;
      _pin = '';
    });
  }

  void _tap(String digit) {
    if (_busy || _pin.length >= 6) return;
    HapticFeedback.selectionClick();
    setState(() {
      _pin += digit;
      _error = null;
    });
    if (_pin.length == 6) Future.delayed(const Duration(milliseconds: 120), _submit);
  }

  void _back() {
    if (_busy || _pin.isEmpty) return;
    setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  Future<void> _submit() async {
    final pin = _pin;
    if (_mode != PinMode.recover && _first == null) {
      if (_weak(pin)) return _fail(tr('Ese PIN es muy fácil de adivinar. Elige otro.'));
      setState(() {
        _first = pin;
        _pin = '';
      });
      return;
    }
    if (_mode != PinMode.recover && pin != _first) {
      setState(() => _first = null);
      return _fail(tr('Los PIN no coinciden. Vuelve a crearlo.'));
    }
    setState(() => _busy = true);
    try {
      switch (_mode) {
        case PinMode.recover:
          await e2ee.recover(pin);
        case PinMode.change:
          await e2ee.changePin(pin);
        case PinMode.create:
          await e2ee.create(pin);
      }
      if (!mounted) return;
      toast(context, switch (_mode) {
        PinMode.recover => tr('Listo: ya puedes leer tus chats cifrados.'),
        PinMode.change => tr('Cambiaste tu PIN.'),
        PinMode.create => tr('Cifrado activado.'),
      });
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        if (_mode != PinMode.recover) _first = null;
      });
      _fail(e.field('pin') ?? e.message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      _fail(errorText(e));
    }
  }

  Future<void> _forgot() async {
    final ok = await confirm(
      context,
      tr('¿Olvidaste tu PIN?'),
      tr('Puedes crear una clave nueva con otro PIN. Los mensajes cifrados que recibiste antes ya no se podrán leer, y tus chats mostrarán que cambió tu código de seguridad.'),
      action: tr('Crear clave nueva'),
      destructive: true,
    );
    if (!ok || !mounted) return;
    setState(() {
      _mode = PinMode.create;
      _reset = true;
      _pin = '';
      _first = null;
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: Tx.overlay,
      child: Scaffold(
        backgroundColor: Tx.bg,
        body: SafeArea(
          child: Column(
            children: [
              SizedBox(
                height: 52,
                child: Row(
                  children: [
                    if (!widget.optional)
                      CupertinoButton(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        onPressed: _busy ? null : () => Navigator.of(context).pop(false),
                        child: Icon(CupertinoIcons.xmark, color: Tx.text, size: 22),
                      ),
                    const Spacer(),
                    if (widget.optional)
                      CupertinoButton(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        onPressed: _busy ? null : () => Navigator.of(context).pop(false),
                        child: Text(tr('Más tarde'), style: Tx.body(16, weight: FontWeight.w600, color: Tx.accent)),
                      ),
                  ],
                ),
              ),
              const Spacer(),
              Container(
                width: 72,
                height: 72,
                decoration: const BoxDecoration(gradient: Tx.brand, shape: BoxShape.circle),
                child: _busy
                    ? const Center(child: CupertinoActivityIndicator(color: Colors.white, radius: 14))
                    : const Icon(CupertinoIcons.lock_fill, color: Colors.white, size: 32),
              ),
              const SizedBox(height: 22),
              Text(_title, style: Tx.display(24), textAlign: TextAlign.center),
              Padding(
                padding: const EdgeInsets.fromLTRB(36, 10, 36, 0),
                child: Text(_subtitle, style: Tx.body(14.5, color: Tx.muted, height: 1.4), textAlign: TextAlign.center),
              ),
              const SizedBox(height: 30),
              AnimatedBuilder(
                animation: _shake,
                builder: (context, child) {
                  final t = _shake.value;
                  final dx = t == 0 ? 0.0 : 10 * (1 - t) * (((t * 8).floor() % 2 == 0) ? 1 : -1);
                  return Transform.translate(offset: Offset(dx, 0), child: child);
                },
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (var i = 0; i < 6; i++)
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 140),
                        margin: const EdgeInsets.symmetric(horizontal: 9),
                        width: 16,
                        height: 16,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: i < _pin.length ? Tx.brand : null,
                          border: i < _pin.length ? null : Border.all(color: Tx.borderStrong, width: 2),
                        ),
                      ),
                  ],
                ),
              ),
              SizedBox(
                height: 44,
                child: Center(
                  child: _error == null
                      ? null
                      : Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 28),
                          child: Text(_error!, style: Tx.body(13.5, color: Tx.danger), textAlign: TextAlign.center),
                        ),
                ),
              ),
              const Spacer(),
              _Keypad(onDigit: _tap, onBack: _back),
              SizedBox(
                height: 54,
                child: _mode == PinMode.recover
                    ? CupertinoButton(
                        onPressed: _busy ? null : _forgot,
                        child: Text(tr('Olvidé mi PIN'), style: Tx.body(15, weight: FontWeight.w600, color: Tx.accent)),
                      )
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Keypad extends StatelessWidget {
  const _Keypad({required this.onDigit, required this.onBack});

  final ValueChanged<String> onDigit;
  final VoidCallback onBack;

  Widget _key(Widget child, VoidCallback onTap) => Expanded(
        child: Padding(
          padding: const EdgeInsets.all(7),
          child: Material(
            color: Tx.surface2,
            shape: const StadiumBorder(),
            child: InkWell(
              customBorder: const StadiumBorder(),
              onTap: onTap,
              child: SizedBox(height: 58, child: Center(child: child)),
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    Widget digit(String d) => _key(Text(d, style: Tx.display(26, weight: FontWeight.w500)), () => onDigit(d));
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 34),
      child: Column(
        children: [
          for (final row in const [
            ['1', '2', '3'],
            ['4', '5', '6'],
            ['7', '8', '9'],
          ])
            Row(children: [for (final d in row) digit(d)]),
          Row(
            children: [
              const Expanded(child: SizedBox()),
              digit('0'),
              Expanded(
                child: CupertinoButton(
                  onPressed: onBack,
                  child: Icon(CupertinoIcons.delete_left, color: Tx.text, size: 26),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Código de seguridad del chat: igual en los teléfonos de todos mientras nadie cambie de clave.
class SecurityCodeScreen extends StatefulWidget {
  const SecurityCodeScreen({super.key, required this.conversationId, required this.title});

  final int conversationId;
  final String title;

  @override
  State<SecurityCodeScreen> createState() => _SecurityCodeScreenState();
}

class _SecurityCodeScreenState extends State<SecurityCodeScreen> {
  String? _code;
  Object? _error;
  int _members = 0;
  int _missing = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final keys = await e2ee.chatKeys(widget.conversationId, refresh: true);
      final code = await e2ee.securityCode(keys.publicKeys);
      if (!mounted) return;
      setState(() {
        _code = code;
        _members = keys.members.length;
        _missing = keys.members.where((m) => m.publicKey == null).length;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final code = _code;
    return Scaffold(
      appBar: GlassBar(title: tr('Cifrado de extremo a extremo')),
      body: _error != null
          ? ErrorState(error: _error!, onRetry: _load)
          : code == null
              ? const Loading()
              : ListView(
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
                  children: [
                    Center(
                      child: Container(
                        width: 64,
                        height: 64,
                        decoration: const BoxDecoration(gradient: Tx.brand, shape: BoxShape.circle),
                        child: const Icon(CupertinoIcons.lock_shield_fill, color: Colors.white, size: 30),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(tr('Código de seguridad'), style: Tx.display(22), textAlign: TextAlign.center),
                    const SizedBox(height: 8),
                    Text(
                      tr('Los mensajes y archivos de «{chat}» se cifran en los teléfonos. Para comprobarlo, comparen este código en persona o por otro medio: si es el mismo en todos los teléfonos, nadie más puede leerlos.', {'chat': widget.title}),
                      style: Tx.body(14.5, color: Tx.muted, height: 1.4),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 22),
                    Panel(
                      padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 12),
                      child: Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 18,
                        runSpacing: 14,
                        children: [
                          for (final g in code.split(' '))
                            Text(g, style: Tx.display(22, weight: FontWeight.w600).copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    SoftButton(
                      label: tr('Copiar código'),
                      icon: CupertinoIcons.doc_on_doc,
                      expand: true,
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: code));
                        toast(context, tr('Código copiado.'));
                      },
                    ),
                    if (_missing > 0) ...[
                      const SizedBox(height: 18),
                      Text(
                        _missing == _members - 1 && _members == 2
                            ? tr('La otra persona aún no activó el cifrado en la app: los mensajes se enviarán sin cifrar hasta que lo haga.')
                            : _missing == 1
                                ? tr('1 participante aún no activó el cifrado en la app.')
                                : tr('{n} participantes aún no activaron el cifrado en la app.', {'n': _missing}),
                        style: Tx.body(13.5, color: Tx.warning, height: 1.4),
                        textAlign: TextAlign.center,
                      ),
                    ],
                    const SizedBox(height: 14),
                    Text(
                      tr('El código cambia si alguien del chat instala la app de nuevo sin su PIN o crea una clave nueva.'),
                      style: Tx.body(12.5, color: Tx.subtle, height: 1.4),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
    );
  }
}

/// Ajustes › Cifrado de los chats: estado, cambiar el PIN o activarlo.
class E2eeSettingsScreen extends StatefulWidget {
  const E2eeSettingsScreen({super.key});

  @override
  State<E2eeSettingsScreen> createState() => _E2eeSettingsScreenState();
}

class _E2eeSettingsScreenState extends State<E2eeSettingsScreen> {
  bool _loading = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final uid = context.read<AppState>().me?.user.id;
    if (uid == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await e2ee.load(uid);
    } catch (e) {
      _error = e;
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _open(PinMode mode) async {
    await push<bool>(context, PinScreen(mode: mode), fullscreen: true);
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    final s = e2ee.status;
    return Scaffold(
      appBar: GlassBar(title: tr('Cifrado de los chats')),
      body: _loading
          ? const Loading()
          : _error != null
              ? ErrorState(error: _error!, onRetry: _load)
              : ListView(
                  padding: const EdgeInsets.only(top: 12, bottom: 40),
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
                      child: Row(
                        children: [
                          Container(
                            width: 46,
                            height: 46,
                            decoration: BoxDecoration(
                              gradient: e2ee.ready ? Tx.brand : null,
                              color: e2ee.ready ? null : Tx.surface3,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(e2ee.ready ? CupertinoIcons.lock_fill : CupertinoIcons.lock_open,
                                color: e2ee.ready ? Colors.white : Tx.muted, size: 22),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(e2ee.ready ? tr('Activado en este teléfono') : tr('Sin activar en este teléfono'), style: Tx.body(16, weight: FontWeight.w700)),
                                const SizedBox(height: 3),
                                Text(
                                  e2ee.ready
                                      ? tr('Tus chats con otras personas que usan la app se cifran de extremo a extremo.')
                                      : s?.configured == true
                                          ? tr('Escribe tu PIN para leer tus chats cifrados aquí.')
                                          : tr('Crea un PIN para cifrar tus chats.'),
                                  style: Tx.body(13.5, color: Tx.muted, height: 1.35),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: SettingsGroup(children: [
                      if (e2ee.ready)
                        SettingsRow(
                          icon: CupertinoIcons.number_circle_fill,
                          color: Tx.purple,
                          label: tr('Cambiar PIN'),
                          onTap: () => _open(PinMode.change),
                        )
                      else if (s?.configured == true && s?.hasBackup == true)
                        SettingsRow(
                          icon: CupertinoIcons.lock_rotation,
                          color: Tx.purple,
                          label: tr('Recuperar con mi PIN'),
                          onTap: () => _open(PinMode.recover),
                        )
                      else
                        SettingsRow(
                          icon: CupertinoIcons.lock_fill,
                          color: Tx.purple,
                          label: tr('Activar el cifrado'),
                          onTap: () => _open(PinMode.create),
                        ),
                      ]),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 10, 24, 0),
                      child: Text(
                        tr('La web de TREVIX no puede leer los chats cifrados: ábrelos en la app. En cada chat, «Cifrado de extremo a extremo» muestra el código de seguridad para comprobarlo con la otra persona.'),
                        style: Tx.body(12.5, color: Tx.subtle, height: 1.4),
                      ),
                    ),
                  ],
                ),
    );
  }
}
