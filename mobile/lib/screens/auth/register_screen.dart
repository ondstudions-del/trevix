import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/appearance.dart';
import '../../core/config.dart';
import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/nav.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';
import '../../widgets/logo.dart';
import 'auth_widgets.dart';

/// Crear cuenta: vista previa del perfil, datos en tres bloques, fuerza de la contraseña y términos.
/// Usa los colores del tema activo (claro u oscuro). Las reglas definitivas las valida el servidor.
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _name = TextEditingController();
  final _username = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  final _termsTap = TapGestureRecognizer();
  final _privacyTap = TapGestureRecognizer();
  DateTime? _birth;
  bool _terms = false;
  bool _busy = false;
  Map<String, String> _errors = {};

  @override
  void initState() {
    super.initState();
    _termsTap.onTap = () => openInApp(context, AppConfig.web('legal.php?doc=terminos'));
    _privacyTap.onTap = () => openInApp(context, AppConfig.web('legal.php?doc=privacidad'));
    for (final c in [_name, _username, _password, _confirm]) {
      c.addListener(_refresh);
    }
  }

  @override
  void dispose() {
    for (final c in [_name, _username, _email, _password, _confirm]) {
      c.dispose();
    }
    _termsTap.dispose();
    _privacyTap.dispose();
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  String get _birthText =>
      _birth == null ? '' : '${_birth!.year}-${_birth!.month.toString().padLeft(2, '0')}-${_birth!.day.toString().padLeft(2, '0')}';

  Future<void> _pickBirth() async {
    FocusScope.of(context).unfocus();
    final now = DateTime.now();
    var picked = _birth ?? DateTime(now.year - 18, now.month, now.day);
    await showCupertinoModalPopup<void>(
      context: context,
      builder: (ctx) => Container(
        height: 320,
        decoration: BoxDecoration(color: Tx.surface2, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        child: SafeArea(
          top: false,
          child: Column(children: [
            Row(children: [
              const SizedBox(width: 20),
              Text(tr('Fecha de nacimiento'), style: Tx.display(17)),
              const Spacer(),
              CupertinoButton(
                onPressed: () {
                  setState(() {
                    _birth = picked;
                    _errors.remove('birth_date');
                  });
                  Navigator.pop(ctx);
                },
                child: Text(tr('Listo'), style: Tx.body(16, weight: FontWeight.w700, color: Tx.accent)),
              ),
            ]),
            Expanded(
              child: CupertinoTheme(
                data: CupertinoThemeData(brightness: Tx.palette.brightness),
                child: CupertinoDatePicker(
                  mode: CupertinoDatePickerMode.date,
                  initialDateTime: picked,
                  minimumDate: DateTime(now.year - 120),
                  maximumDate: now,
                  onDateTimeChanged: (d) => picked = d,
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    final min = context.read<AppState>().passwordMin;
    final e = <String, String>{};
    final username = _username.text.trim().toLowerCase();
    if (_name.text.trim().length < 2) e['display_name'] = tr('El nombre debe tener al menos 2 caracteres.');
    if (!RegExp(r'^[a-z0-9_.]{3,30}$').hasMatch(username)) e['username'] = tr('Usa de 3 a 30 caracteres: minúsculas, números, punto o guion bajo.');
    if (!_email.text.contains('@')) e['email'] = tr('Escribe un correo electrónico válido.');
    if (_birth == null) e['birth_date'] = tr('Indica tu fecha de nacimiento.');
    if (_password.text.length < min) e['password'] = tr('La contraseña debe tener al menos {min} caracteres.', {'min': min});
    if (_confirm.text != _password.text) e['password_confirmation'] = tr('Las contraseñas no coinciden.');
    if (!_terms) e['terms'] = tr('Debes aceptar los términos y la política de privacidad.');
    setState(() => _errors = e);
    if (e.isNotEmpty) {
      HapticFeedback.mediumImpact();
      return;
    }
    setState(() => _busy = true);
    try {
      final data = await context.read<AppState>().register({
        'display_name': _name.text.trim(),
        'username': username,
        'email': _email.text.trim(),
        'birth_date': _birthText,
        'password': _password.text,
        'password_confirmation': _confirm.text,
      });
      if (mounted && asBool(data['verification_email_sent'])) {
        toast(context, tr('Te enviamos un enlace para confirmar tu correo.'));
      }
    } on ApiException catch (err) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _errors = {...err.fields};
        if (err.fields.isEmpty) _errors['form'] = err.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final min = context.watch<AppState>().passwordMin;
    final still = Appearance.motionReduced(context);
    final confirmed = _confirm.text.isNotEmpty && _confirm.text == _password.text;
    return Scaffold(
      body: AuthBackground(
        child: SafeArea(
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 16, 0),
              child: Row(children: [
                Semantics(
                  button: true,
                  label: tr('Volver'),
                  child: CupertinoButton(
                    padding: const EdgeInsets.all(8),
                    onPressed: () => Navigator.maybePop(context),
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(color: Tx.surface2, shape: BoxShape.circle, border: Border.all(color: Tx.border)),
                      child: Icon(CupertinoIcons.chevron_back, color: Tx.text, size: 20),
                    ),
                  ),
                ),
                const Spacer(),
                const Wordmark(size: 22),
                const Spacer(),
                const SizedBox(width: 56),
              ]),
            ),
            Expanded(
              child: SingleChildScrollView(
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                child: AutofillGroup(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    _Reveal(still: still, order: 0, child: _ProfilePreview(name: _name.text.trim(), username: _username.text.trim())),
                    const SizedBox(height: 18),
                    _Reveal(
                      still: still,
                      order: 1,
                      child: Column(children: [
                        GradientText(tr('Únete a TREVIX'), align: TextAlign.center, style: Tx.display(30)),
                        const SizedBox(height: 6),
                        Text(tr('Crea tu cuenta en menos de un minuto.'), textAlign: TextAlign.center, style: Tx.body(15, color: Tx.muted)),
                      ]),
                    ),
                    const SizedBox(height: 22),
                    if (_errors['form'] != null) FormBanner(text: _errors['form']!),
                    _Reveal(
                      still: still,
                      order: 2,
                      child: _Section(
                        icon: CupertinoIcons.person_crop_circle_fill,
                        title: tr('Tu perfil'),
                        caption: tr('Así te verán y te encontrarán en TREVIX.'),
                        children: [
                          AuthField(
                            controller: _name,
                            hint: tr('Nombre'),
                            icon: CupertinoIcons.person,
                            error: _errors['display_name'],
                            capitalization: TextCapitalization.words,
                            autofill: const [AutofillHints.name],
                            maxLength: 60,
                          ),
                          AuthField(
                            controller: _username,
                            hint: tr('Nombre de usuario'),
                            icon: CupertinoIcons.at,
                            error: _errors['username'],
                            autofill: const [AutofillHints.newUsername],
                            maxLength: 30,
                            formatters: [
                              FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9_.]')),
                              TextInputFormatter.withFunction((_, v) => v.copyWith(text: v.text.toLowerCase())),
                            ],
                          ),
                        ],
                      ),
                    ),
                    _Reveal(
                      still: still,
                      order: 3,
                      child: _Section(
                        icon: CupertinoIcons.envelope_fill,
                        title: tr('Tus datos'),
                        caption: tr('Tu correo no se muestra en tu perfil y tú eliges quién ve tu cumpleaños.'),
                        children: [
                          AuthField(
                            controller: _email,
                            hint: tr('Correo electrónico'),
                            icon: CupertinoIcons.mail,
                            error: _errors['email'],
                            keyboard: TextInputType.emailAddress,
                            autofill: const [AutofillHints.email],
                          ),
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: GestureDetector(
                              onTap: _pickBirth,
                              child: InputDecorator(
                                isEmpty: _birth == null,
                                decoration: fieldDecoration(
                                  tr('Fecha de nacimiento'),
                                  error: _errors['birth_date'],
                                  prefix: Icon(CupertinoIcons.calendar, color: Tx.subtle, size: 20),
                                  suffix: Icon(CupertinoIcons.chevron_down, color: Tx.subtle, size: 16),
                                ),
                                child: Text(_birth == null ? '' : birthday(_birth!.day, _birth!.month, _birth!.year), style: Tx.body(16)),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    _Reveal(
                      still: still,
                      order: 4,
                      child: _Section(
                        icon: CupertinoIcons.lock_shield_fill,
                        title: tr('Tu contraseña'),
                        caption: tr('Mínimo {min} caracteres. Mezcla letras, números y símbolos.', {'min': min}),
                        children: [
                          AuthField(
                            controller: _password,
                            hint: tr('Contraseña'),
                            icon: CupertinoIcons.lock,
                            password: true,
                            error: _errors['password'],
                            autofill: const [AutofillHints.newPassword],
                          ),
                          if (_password.text.isNotEmpty) _Strength(password: _password.text, min: min),
                          AuthField(
                            controller: _confirm,
                            hint: tr('Repite la contraseña'),
                            icon: CupertinoIcons.lock_shield,
                            password: true,
                            error: _errors['password_confirmation'],
                            action: TextInputAction.done,
                            autofill: const [AutofillHints.newPassword],
                          ),
                          if (confirmed && _errors['password_confirmation'] == null)
                            Padding(
                              padding: const EdgeInsets.only(left: 4, bottom: 10),
                              child: Row(children: [
                                const Icon(CupertinoIcons.checkmark_circle_fill, color: Tx.success, size: 16),
                                const SizedBox(width: 6),
                                Text(tr('Las contraseñas coinciden'), style: Tx.body(13, weight: FontWeight.w600, color: Tx.success)),
                              ]),
                            ),
                        ],
                      ),
                    ),
                    _Reveal(still: still, order: 5, child: _termsBox()),
                    const SizedBox(height: 22),
                    GradientButton(label: tr('Crear cuenta'), icon: CupertinoIcons.sparkles, loading: _busy, onPressed: _submit),
                    const SizedBox(height: 14),
                    Wrap(alignment: WrapAlignment.center, crossAxisAlignment: WrapCrossAlignment.center, children: [
                      Text(tr('¿Ya tienes cuenta?'), style: Tx.body(15, color: Tx.muted)),
                      CupertinoButton(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        onPressed: () => Navigator.maybePop(context),
                        child: Text(tr('Inicia sesión'), style: Tx.body(15, weight: FontWeight.w700, color: Tx.accent)),
                      ),
                    ]),
                  ]),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _termsBox() {
    final error = _errors['terms'];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      GestureDetector(
        onTap: () => setState(() {
          _terms = !_terms;
          _errors.remove('terms');
        }),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _terms ? Tx.alpha(Tx.purple500, Tx.isDark ? .14 : .08) : Tx.surface2,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: error != null ? Tx.danger : (_terms ? Tx.alpha(Tx.purple500, .45) : Tx.border)),
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 24,
              height: 24,
              margin: const EdgeInsets.only(top: 1),
              decoration: BoxDecoration(
                gradient: _terms ? Tx.brand : null,
                borderRadius: BorderRadius.circular(7),
                border: Border.all(color: _terms ? Colors.transparent : Tx.borderStrong, width: 1.5),
              ),
              child: _terms ? const Icon(CupertinoIcons.checkmark, size: 16, color: Colors.white) : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text.rich(
                TextSpan(style: Tx.body(14, color: Tx.muted, height: 1.45), children: [
                  TextSpan(text: '${tr('Acepto los')} '),
                  TextSpan(text: tr('Términos'), style: TextStyle(color: Tx.accent, fontWeight: FontWeight.w600), recognizer: _termsTap),
                  TextSpan(text: ' ${tr('y la')} '),
                  TextSpan(text: tr('Política de privacidad'), style: TextStyle(color: Tx.accent, fontWeight: FontWeight.w600), recognizer: _privacyTap),
                  TextSpan(text: ' ${tr('de TREVIX.')}'),
                ]),
              ),
            ),
          ]),
        ),
      ),
      if (error != null) Padding(padding: const EdgeInsets.only(top: 8, left: 6), child: Text(error, style: Tx.body(12.5, color: Tx.danger))),
    ]);
  }
}

/// Cómo se verá la cuenta: iniciales del nombre y @usuario mientras se escriben.
class _ProfilePreview extends StatelessWidget {
  const _ProfilePreview({required this.name, required this.username});

  final String name;
  final String username;

  String get _initials {
    final parts = name.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '';
    return (parts.first.characters.first + (parts.length > 1 ? parts.last.characters.first : '')).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final initials = _initials;
    return Column(children: [
      Container(
        width: 92,
        height: 92,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const SweepGradient(colors: [Tx.purple500, Tx.blue, Tx.cyan, Color(0xFFA855F7), Tx.purple500]),
          boxShadow: [BoxShadow(color: Tx.alpha(Tx.purple500, Tx.isDark ? .45 : .25), blurRadius: 28, offset: const Offset(0, 10))],
        ),
        child: Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(shape: BoxShape.circle, color: Tx.bg),
          child: Container(
            decoration: const BoxDecoration(shape: BoxShape.circle, gradient: Tx.brand),
            alignment: Alignment.center,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: initials.isEmpty
                  ? const Icon(CupertinoIcons.person_fill, key: ValueKey('icon'), color: Colors.white, size: 36)
                  : Text(initials, key: ValueKey(initials), style: Tx.display(30, color: Colors.white)),
            ),
          ),
        ),
      ),
      const SizedBox(height: 10),
      Text(
        name.isEmpty ? tr('Tu nombre') : name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Tx.body(17, weight: FontWeight.w700, color: name.isEmpty ? Tx.subtle : Tx.text),
      ),
      const SizedBox(height: 2),
      Text(
        '@${username.isEmpty ? tr('usuario') : username.toLowerCase()}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Tx.body(14, weight: FontWeight.w600, color: username.isEmpty ? Tx.subtle : Tx.accent),
      ),
    ]);
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.icon, required this.title, required this.children, this.caption});

  final IconData icon;
  final String title;
  final String? caption;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
      decoration: BoxDecoration(
        color: Tx.surface1,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Tx.border),
        boxShadow: Tx.isDark ? null : [BoxShadow(color: Colors.black.withAlpha(10), blurRadius: 18, offset: const Offset(0, 6))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(gradient: Tx.brand, borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, color: Colors.white, size: 17),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: Tx.body(15.5, weight: FontWeight.w700)),
              if (caption != null) Text(caption!, style: Tx.body(12.5, color: Tx.muted, height: 1.35)),
            ]),
          ),
        ]),
        const SizedBox(height: 14),
        ...children,
      ]),
    );
  }
}

/// Indicador de la fuerza de la contraseña (orientativo).
class _Strength extends StatelessWidget {
  const _Strength({required this.password, required this.min});

  final String password;
  final int min;

  int get _score {
    if (password.length < min) return 0;
    var s = 1;
    if (RegExp(r'[a-z]').hasMatch(password) && RegExp(r'[A-Z]').hasMatch(password)) s++;
    if (RegExp(r'\d').hasMatch(password)) s++;
    if (RegExp(r'[^A-Za-z0-9]').hasMatch(password)) s++;
    if (password.length >= 12 && s < 4) s++;
    return s.clamp(0, 4);
  }

  @override
  Widget build(BuildContext context) {
    final score = _score;
    final (label, color) = switch (score) {
      0 => (tr('Muy corta'), Tx.danger),
      1 => (tr('Débil'), Tx.danger),
      2 => (tr('Aceptable'), Tx.warning),
      3 => (tr('Buena'), Tx.blue),
      _ => (tr('Fuerte'), Tx.success),
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
      child: Row(children: [
        for (var i = 0; i < 4; i++)
          Expanded(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              height: 5,
              margin: EdgeInsets.only(right: i == 3 ? 0 : 5),
              decoration: BoxDecoration(color: i < score ? color : Tx.surface3, borderRadius: BorderRadius.circular(3)),
            ),
          ),
        const SizedBox(width: 10),
        SizedBox(
          width: 74,
          child: Text(label, textAlign: TextAlign.right, style: Tx.body(12.5, weight: FontWeight.w700, color: color)),
        ),
      ]),
    );
  }
}

/// Entrada suave de cada bloque (sin animación con «Reducir movimiento»).
class _Reveal extends StatelessWidget {
  const _Reveal({required this.child, required this.order, required this.still});

  final Widget child;
  final int order;
  final bool still;

  @override
  Widget build(BuildContext context) {
    if (still) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 420 + order * 90),
      curve: Curves.easeOutCubic,
      child: child,
      builder: (_, v, c) => Opacity(opacity: v, child: Transform.translate(offset: Offset(0, 18 * (1 - v)), child: c)),
    );
  }
}
