import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/config.dart';
import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/nav.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';
import 'auth_widgets.dart';

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
                  setState(() => _birth = picked);
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
    if (e.isNotEmpty) return;
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
    return Scaffold(
      appBar: GlassBar(title: tr('Crear cuenta')),
      body: AuthBackground(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 40),
          child: AutofillGroup(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(tr('Únete a TREVIX'), style: Tx.display(28)),
              const SizedBox(height: 6),
              Text(tr('Crea tu cuenta en menos de un minuto.'), style: Tx.body(15, color: Tx.muted)),
              const SizedBox(height: 24),
              if (_errors['form'] != null) FormBanner(text: _errors['form']!),
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
              ),
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
                      prefix: Icon(CupertinoIcons.gift, color: Tx.subtle, size: 20),
                    ),
                    child: Text(_birth == null ? '' : birthday(_birth!.day, _birth!.month, _birth!.year), style: Tx.body(16)),
                  ),
                ),
              ),
              AuthField(
                controller: _password,
                hint: tr('Contraseña'),
                icon: CupertinoIcons.lock,
                password: true,
                error: _errors['password'],
                autofill: const [AutofillHints.newPassword],
              ),
              AuthField(
                controller: _confirm,
                hint: tr('Repite la contraseña'),
                icon: CupertinoIcons.lock_shield,
                password: true,
                error: _errors['password_confirmation'],
                action: TextInputAction.done,
                autofill: const [AutofillHints.newPassword],
              ),
              const SizedBox(height: 4),
              GestureDetector(
                onTap: () => setState(() => _terms = !_terms),
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
              if (_errors['terms'] != null)
                Padding(padding: const EdgeInsets.only(top: 8, left: 36), child: Text(_errors['terms']!, style: Tx.body(12.5, color: Tx.danger))),
              const SizedBox(height: 26),
              GradientButton(label: tr('Crear cuenta'), loading: _busy, onPressed: _submit),
            ]),
          ),
        ),
      ),
    );
  }
}
