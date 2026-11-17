import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/app_lock.dart';
import '../../core/i18n.dart';
import '../../core/nav.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';
import '../../widgets/settings_tiles.dart';

/// Ajustes › Privacidad › Bloqueo de app.
class AppLockSettingsScreen extends StatefulWidget {
  const AppLockSettingsScreen({super.key});

  @override
  State<AppLockSettingsScreen> createState() => _AppLockSettingsScreenState();
}

class _AppLockSettingsScreenState extends State<AppLockSettingsScreen> {
  final _lock = AppLock.instance;
  bool _busy = false;

  Future<void> _toggle(bool on) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      if (!on) {
        await _lock.disable(confirm: () async {
          final ok = await _confirmIdentity();
          return ok;
        });
        return;
      }
      final method = await _pickMethod();
      if (method == null || !mounted) return;
      if (method == AppLockMethod.biometrics) {
        final ok = await _lock.authenticateBiometrics();
        if (!ok) {
          if (mounted) toast(context, tr('No se pudo verificar tu identidad.'));
          return;
        }
        await _lock.enable(AppLockMethod.biometrics);
      } else if (method == AppLockMethod.pin) {
        final saved = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => const _AppLockPinScreen(create: true)));
        if (saved != true) return;
        await _lock.enable(AppLockMethod.pin);
      } else {
        final saved = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => const _AppLockPatternScreen(create: true)));
        if (saved != true) return;
        await _lock.enable(AppLockMethod.pattern);
      }
      if (mounted) toast(context, tr('Bloqueo de app activado.'));
    } catch (e) {
      if (mounted) toast(context, tr('No se pudo activar el bloqueo.'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _confirmIdentity() async {
    if (_lock.method == AppLockMethod.biometrics) {
      return _lock.authenticateBiometrics();
    }
    if (_lock.method == AppLockMethod.pin) {
      return await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => const _AppLockPinScreen(create: false))) ?? false;
    }
    return await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => const _AppLockPatternScreen(create: false))) ?? false;
  }

  Future<AppLockMethod?> _pickMethod() async {
    await _lock.refreshBiometrics();
    if (!mounted) return null;
    return showCupertinoModalPopup<AppLockMethod>(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        title: Text(tr('Cómo quieres desbloquear')),
        message: Text(tr('Face ID o huella si tu teléfono lo permite, o un PIN o patrón.')),
        actions: [
          if (_lock.biometricsAvailable)
            CupertinoActionSheetAction(
              onPressed: () => Navigator.pop(ctx, AppLockMethod.biometrics),
              child: Text(Platform.isIOS ? 'Face ID' : tr('Huella')),
            ),
          CupertinoActionSheetAction(onPressed: () => Navigator.pop(ctx, AppLockMethod.pin), child: Text(tr('PIN'))),
          CupertinoActionSheetAction(onPressed: () => Navigator.pop(ctx, AppLockMethod.pattern), child: Text(tr('Patrón'))),
        ],
        cancelButton: CupertinoActionSheetAction(onPressed: () => Navigator.pop(ctx), child: Text(tr('Cancelar'))),
      ),
    );
  }

  Future<void> _changeMethod() async {
    final method = await _pickMethod();
    if (method == null || !mounted) return;
    if (!await _confirmIdentity()) return;
    if (!mounted) return;
    if (method == AppLockMethod.biometrics) {
      if (!await _lock.authenticateBiometrics()) return;
      await _lock.enable(AppLockMethod.biometrics);
    } else if (method == AppLockMethod.pin) {
      final saved = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => const _AppLockPinScreen(create: true)));
      if (saved != true) return;
      await _lock.enable(AppLockMethod.pin);
    } else {
      final saved = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => const _AppLockPatternScreen(create: true)));
      if (saved != true) return;
      await _lock.enable(AppLockMethod.pattern);
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _lock,
      builder: (context, _) => Scaffold(
        appBar: GlassBar(title: tr('Bloqueo de app')),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 60),
          children: [
            SettingsGroup(
              title: tr('Seguridad'),
              footer: tr('Con el bloqueo activo, TREVIX pedirá tu identidad cada vez que abras la app o vuelvas a ella.'),
              children: [
                SettingsRow(
                  icon: CupertinoIcons.lock_shield_fill,
                  color: Tx.accentSoft,
                  label: tr('Bloqueo de app'),
                  subtitle: _lock.enabled ? tr('Activado · {method}', {'method': _lock.methodLabel()}) : tr('Desactivado'),
                  trailing: _busy
                      ? const CupertinoActivityIndicator()
                      : TxSwitch(value: _lock.enabled, onChanged: _toggle),
                ),
                if (_lock.enabled)
                  SettingsRow(
                    icon: CupertinoIcons.hand_raised_fill,
                    color: Tx.blue400,
                    label: tr('Método de desbloqueo'),
                    value: _lock.methodLabel(),
                    onTap: _changeMethod,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Pantalla a pantalla completa cuando la app está bloqueada.
class AppLockGate extends StatefulWidget {
  const AppLockGate({super.key, required this.child});

  final Widget child;

  @override
  State<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends State<AppLockGate> {
  final _lock = AppLock.instance;
  bool _triedBio = false;

  @override
  void initState() {
    super.initState();
    _lock.addListener(_onLock);
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeBio());
  }

  @override
  void dispose() {
    _lock.removeListener(_onLock);
    super.dispose();
  }

  void _onLock() {
    setState(() {});
    if (_lock.locked) {
      _triedBio = false;
      WidgetsBinding.instance.addPostFrameCallback((_) => _maybeBio());
    }
  }

  Future<void> _maybeBio() async {
    if (!_lock.locked || _lock.method != AppLockMethod.biometrics || _triedBio) return;
    _triedBio = true;
    await _lock.authenticateBiometrics();
  }

  @override
  Widget build(BuildContext context) {
    if (!_lock.enabled || !_lock.locked) return widget.child;
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        Positioned.fill(
          child: Material(
            color: Tx.bg,
            child: switch (_lock.method) {
              AppLockMethod.biometrics => _BiometricUnlock(onRetry: () {
                  _triedBio = false;
                  _maybeBio();
                }),
              AppLockMethod.pin => const _AppLockPinScreen(create: false, gate: true),
              AppLockMethod.pattern => const _AppLockPatternScreen(create: false, gate: true),
            },
          ),
        ),
      ],
    );
  }
}

class _BiometricUnlock extends StatelessWidget {
  const _BiometricUnlock({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final lock = AppLock.instance;
    return SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 78,
              height: 78,
              decoration: BoxDecoration(gradient: Tx.brand, shape: BoxShape.circle),
              child: Icon(Platform.isIOS ? CupertinoIcons.person_crop_circle_badge_checkmark : Icons.fingerprint, color: Colors.white, size: 36),
            ),
            const SizedBox(height: 22),
            Text(tr('App bloqueada'), style: Tx.display(24), textAlign: TextAlign.center),
            const SizedBox(height: 10),
            Text(tr('Usa {method} para entrar en TREVIX.', {'method': lock.biometricLabel}), style: Tx.body(15, color: Tx.muted, height: 1.4), textAlign: TextAlign.center),
            const SizedBox(height: 28),
            GradientButton(label: tr('Desbloquear'), icon: CupertinoIcons.lock_open_fill, onPressed: onRetry),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () async {
                final usePin = await showCupertinoModalPopup<AppLockMethod>(
                  context: context,
                  builder: (ctx) => CupertinoActionSheet(
                    title: Text(tr('Otro método')),
                    actions: [
                      CupertinoActionSheetAction(onPressed: () => Navigator.pop(ctx, AppLockMethod.pin), child: Text(tr('Usar PIN'))),
                      CupertinoActionSheetAction(onPressed: () => Navigator.pop(ctx, AppLockMethod.pattern), child: Text(tr('Usar patrón'))),
                    ],
                    cancelButton: CupertinoActionSheetAction(onPressed: () => Navigator.pop(ctx), child: Text(tr('Cancelar'))),
                  ),
                );
                if (usePin == null || !context.mounted) return;
                if (usePin == AppLockMethod.pin && await lock.hasPin()) {
                  await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const _AppLockPinScreen(create: false)));
                } else if (usePin == AppLockMethod.pattern && await lock.hasPattern()) {
                  await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const _AppLockPatternScreen(create: false)));
                } else if (context.mounted) {
                  toast(context, tr('Primero configura ese método en Ajustes.'));
                }
              },
              child: Text(tr('PIN o patrón'), style: Tx.body(15, weight: FontWeight.w600, color: Tx.accent)),
            ),
          ]),
        ),
      ),
    );
  }
}

class _AppLockPinScreen extends StatefulWidget {
  const _AppLockPinScreen({required this.create, this.gate = false});

  final bool create;
  final bool gate;

  @override
  State<_AppLockPinScreen> createState() => _AppLockPinScreenState();
}

class _AppLockPinScreenState extends State<_AppLockPinScreen> with SingleTickerProviderStateMixin {
  String _pin = '';
  String? _first;
  String? _error;
  late final AnimationController _shake = AnimationController(vsync: this, duration: const Duration(milliseconds: 420));

  @override
  void dispose() {
    _shake.dispose();
    super.dispose();
  }

  Future<void> _submit(String pin) async {
    if (widget.create) {
      if (_first == null) {
        setState(() {
          _first = pin;
          _pin = '';
          _error = null;
        });
        return;
      }
      if (pin != _first) {
        setState(() {
          _error = tr('Los PIN no coinciden.');
          _first = null;
          _pin = '';
        });
        _shake.forward(from: 0);
        return;
      }
      await AppLock.instance.setPin(pin);
      if (mounted) Navigator.of(context).pop(true);
      return;
    }
    final ok = await AppLock.instance.verifyPin(pin);
    if (ok) {
      if (widget.gate) return;
      if (mounted) Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _error = tr('PIN incorrecto.');
      _pin = '';
    });
    _shake.forward(from: 0);
    HapticFeedback.heavyImpact();
  }

  void _tap(String d) {
    if (_pin.length >= 6) return;
    setState(() {
      _pin += d;
      _error = null;
    });
    if (_pin.length == 6) _submit(_pin);
  }

  void _back() {
    if (_pin.isEmpty) return;
    setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.create
        ? (_first == null ? tr('Crea un PIN') : tr('Confirma tu PIN'))
        : tr('Escribe tu PIN');
    final body = Scaffold(
      body: SafeArea(
        child: Column(children: [
          if (!widget.gate)
            Align(
              alignment: Alignment.centerLeft,
              child: CupertinoButton(
                onPressed: () => Navigator.pop(context, false),
                child: Icon(CupertinoIcons.xmark, color: Tx.text),
              ),
            ),
          const Spacer(),
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(gradient: Tx.brand, shape: BoxShape.circle),
            child: const Icon(CupertinoIcons.lock_fill, color: Colors.white, size: 32),
          ),
          const SizedBox(height: 20),
          Text(title, style: Tx.display(24), textAlign: TextAlign.center),
          Padding(
            padding: const EdgeInsets.fromLTRB(36, 10, 36, 0),
            child: Text(tr('6 dígitos para desbloquear TREVIX.'), style: Tx.body(14.5, color: Tx.muted), textAlign: TextAlign.center),
          ),
          const SizedBox(height: 28),
          AnimatedBuilder(
            animation: _shake,
            builder: (context, child) {
              final t = _shake.value;
              final dx = t == 0 ? 0.0 : 10 * (1 - t) * (((t * 8).floor() % 2 == 0) ? 1 : -1);
              return Transform.translate(offset: Offset(dx, 0), child: child);
            },
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              for (var i = 0; i < 6; i++)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 140),
                  margin: const EdgeInsets.symmetric(horizontal: 8),
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: i < _pin.length ? Tx.brand : null,
                    border: i < _pin.length ? null : Border.all(color: Tx.borderStrong, width: 2),
                  ),
                ),
            ]),
          ),
          SizedBox(
            height: 40,
            child: Center(child: _error == null ? null : Text(_error!, style: Tx.body(13.5, color: Tx.danger))),
          ),
          const Spacer(),
          _PinKeypad(onDigit: _tap, onBack: _back),
          const SizedBox(height: 18),
        ]),
      ),
    );
    return body;
  }
}

class _PinKeypad extends StatelessWidget {
  const _PinKeypad({required this.onDigit, required this.onBack});

  final ValueChanged<String> onDigit;
  final VoidCallback onBack;

  Widget _key(Widget child, VoidCallback onTap) => Expanded(
        child: Padding(
          padding: const EdgeInsets.all(7),
          child: Material(
            color: Tx.surface2,
            shape: const StadiumBorder(),
            child: InkWell(customBorder: const StadiumBorder(), onTap: onTap, child: SizedBox(height: 56, child: Center(child: child))),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    Widget digit(String d) => _key(Text(d, style: Tx.display(26, weight: FontWeight.w500)), () => onDigit(d));
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 34),
      child: Column(children: [
        Row(children: [digit('1'), digit('2'), digit('3')]),
        Row(children: [digit('4'), digit('5'), digit('6')]),
        Row(children: [digit('7'), digit('8'), digit('9')]),
        Row(children: [
          const Expanded(child: SizedBox()),
          digit('0'),
          _key(Icon(CupertinoIcons.delete_left, color: Tx.text), onBack),
        ]),
      ]),
    );
  }
}

class _AppLockPatternScreen extends StatefulWidget {
  const _AppLockPatternScreen({required this.create, this.gate = false});

  final bool create;
  final bool gate;

  @override
  State<_AppLockPatternScreen> createState() => _AppLockPatternScreenState();
}

class _AppLockPatternScreenState extends State<_AppLockPatternScreen> {
  final _dots = <int>[];
  List<int>? _first;
  String? _error;

  Future<void> _finish(List<int> pattern) async {
    if (pattern.length < 4) {
      setState(() {
        _error = tr('Une al menos 4 puntos.');
        _dots.clear();
      });
      return;
    }
    if (widget.create) {
      if (_first == null) {
        setState(() {
          _first = List.of(pattern);
          _dots.clear();
          _error = null;
        });
        return;
      }
      if (!_listEq(_first!, pattern)) {
        setState(() {
          _error = tr('Los patrones no coinciden.');
          _first = null;
          _dots.clear();
        });
        return;
      }
      await AppLock.instance.setPattern(pattern);
      if (mounted) Navigator.of(context).pop(true);
      return;
    }
    final ok = await AppLock.instance.verifyPattern(pattern);
    if (ok) {
      if (widget.gate) {
        setState(() => _dots.clear());
        return;
      }
      if (mounted) Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _error = tr('Patrón incorrecto.');
      _dots.clear();
    });
    HapticFeedback.heavyImpact();
  }

  bool _listEq(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.create
        ? (_first == null ? tr('Dibuja un patrón') : tr('Confirma el patrón'))
        : tr('Dibuja tu patrón');
    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          if (!widget.gate)
            Align(
              alignment: Alignment.centerLeft,
              child: CupertinoButton(
                onPressed: () => Navigator.pop(context, false),
                child: Icon(CupertinoIcons.xmark, color: Tx.text),
              ),
            ),
          const Spacer(),
          Text(title, style: Tx.display(24), textAlign: TextAlign.center),
          Padding(
            padding: const EdgeInsets.fromLTRB(36, 10, 36, 20),
            child: Text(tr('Conecta los puntos para desbloquear la app.'), style: Tx.body(14.5, color: Tx.muted), textAlign: TextAlign.center),
          ),
          if (_error != null) Text(_error!, style: Tx.body(13.5, color: Tx.danger)),
          SizedBox(
            height: 320,
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: _PatternPad(
                selected: _dots,
                onChange: (v) => setState(() {
                  _dots
                    ..clear()
                    ..addAll(v);
                  _error = null;
                }),
                onComplete: _finish,
              ),
            ),
          ),
          const Spacer(),
        ]),
      ),
    );
  }
}

class _PatternPad extends StatefulWidget {
  const _PatternPad({required this.selected, required this.onChange, required this.onComplete});

  final List<int> selected;
  final ValueChanged<List<int>> onChange;
  final ValueChanged<List<int>> onComplete;

  @override
  State<_PatternPad> createState() => _PatternPadState();
}

class _PatternPadState extends State<_PatternPad> {
  final _path = <int>[];
  Offset? _finger;

  int? _hit(Offset local, Size size) {
    final cell = size.width / 3;
    for (var i = 0; i < 9; i++) {
      final cx = (i % 3) * cell + cell / 2;
      final cy = (i ~/ 3) * cell + cell / 2;
      if ((local - Offset(cx, cy)).distance <= cell * .28) return i;
    }
    return null;
  }

  void _add(int i) {
    if (_path.contains(i)) return;
    setState(() => _path.add(i));
    widget.onChange(List.of(_path));
    HapticFeedback.selectionClick();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final size = Size(c.maxWidth, c.maxWidth);
      return GestureDetector(
        onPanStart: (d) {
          _path.clear();
          final i = _hit(d.localPosition, size);
          if (i != null) _add(i);
          setState(() => _finger = d.localPosition);
        },
        onPanUpdate: (d) {
          final i = _hit(d.localPosition, size);
          if (i != null) _add(i);
          setState(() => _finger = d.localPosition);
        },
        onPanEnd: (_) {
          final done = List<int>.of(_path);
          setState(() {
            _finger = null;
            _path.clear();
          });
          widget.onComplete(done);
        },
        child: CustomPaint(
          size: size,
          painter: _PatternPainter(path: _path.isEmpty ? widget.selected : _path, finger: _finger, color: Tx.accentSoft),
        ),
      );
    });
  }
}

class _PatternPainter extends CustomPainter {
  _PatternPainter({required this.path, required this.finger, required this.color});

  final List<int> path;
  final Offset? finger;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final cell = size.width / 3;
    Offset center(int i) => Offset((i % 3) * cell + cell / 2, (i ~/ 3) * cell + cell / 2);
    final line = Paint()
      ..color = color.withAlpha(180)
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    if (path.isNotEmpty) {
      final p = Path()..moveTo(center(path.first).dx, center(path.first).dy);
      for (var i = 1; i < path.length; i++) {
        p.lineTo(center(path[i]).dx, center(path[i]).dy);
      }
      if (finger != null) p.lineTo(finger!.dx, finger!.dy);
      canvas.drawPath(p, line);
    }
    for (var i = 0; i < 9; i++) {
      final c = center(i);
      final selected = path.contains(i);
      canvas.drawCircle(c, 14, Paint()..color = selected ? color : Tx.surface3);
      canvas.drawCircle(c, 14, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = selected ? color : Tx.borderStrong);
      if (selected) canvas.drawCircle(c, 5, Paint()..color = Colors.white);
    }
  }

  @override
  bool shouldRepaint(covariant _PatternPainter oldDelegate) =>
      !listEquals(oldDelegate.path, path) || oldDelegate.finger != finger || oldDelegate.color != color;
}

bool listEquals(List<int> a, List<int> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
