import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/nav.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';
import '../../widgets/logo.dart';
import 'auth_widgets.dart';
import 'forgot_screen.dart';
import 'register_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _identifier = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  Map<String, String> _errors = {};

  @override
  void dispose() {
    _identifier.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    final errors = <String, String>{};
    if (_identifier.text.trim().isEmpty) errors['identifier'] = 'Escribe tu usuario o correo.';
    if (_password.text.isEmpty) errors['password'] = 'Escribe tu contraseña.';
    setState(() => _errors = errors);
    if (errors.isNotEmpty) return;
    setState(() => _busy = true);
    try {
      final data = await context.read<AppState>().login(_identifier.text.trim(), _password.text);
      TextInput.finishAutofillContext();
      if (asBool(data['reactivated']) && mounted) toast(context, '¡Qué bueno verte de nuevo! Tu cuenta se reactivó.');
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _errors = {...e.fields};
        if (!_errors.containsKey('form') && e.fields.isEmpty) _errors['form'] = e.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return Scaffold(
      body: AuthBackground(
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
              child: AutofillGroup(
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  const Center(child: TrevixLogo(size: 76, glow: true)),
                  const SizedBox(height: 26),
                  Text('Bienvenido de nuevo', textAlign: TextAlign.center, style: Tx.display(30)),
                  const SizedBox(height: 8),
                  Text('Inicia sesión para seguir conectando.', textAlign: TextAlign.center, style: Tx.body(15.5, color: Tx.muted)),
                  const SizedBox(height: 30),
                  if (state.announcement.isNotEmpty) FormBanner(text: state.announcement, error: false),
                  if (state.maintenance)
                    const FormBanner(text: 'TREVIX está en mantenimiento. Volveremos en breve.', error: false),
                  if (_errors['form'] != null) FormBanner(text: _errors['form']!),
                  AuthField(
                    controller: _identifier,
                    hint: 'Usuario o correo',
                    icon: CupertinoIcons.person,
                    error: _errors['identifier'],
                    keyboard: TextInputType.emailAddress,
                    autofill: const [AutofillHints.username, AutofillHints.email],
                  ),
                  AuthField(
                    controller: _password,
                    hint: 'Contraseña',
                    icon: CupertinoIcons.lock,
                    password: true,
                    error: _errors['password'],
                    action: TextInputAction.done,
                    onSubmit: _submit,
                    autofill: const [AutofillHints.password],
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: CupertinoButton(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      onPressed: () => push(context, const ForgotScreen()),
                      child: Text('¿Olvidaste tu contraseña?', style: Tx.body(14, weight: FontWeight.w600, color: Tx.accent)),
                    ),
                  ),
                  const SizedBox(height: 10),
                  GradientButton(label: 'Iniciar sesión', loading: _busy, onPressed: _submit),
                  const SizedBox(height: 26),
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Text('¿No tienes cuenta?', style: Tx.body(15, color: Tx.muted)),
                    CupertinoButton(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      onPressed: state.registrationOpen
                          ? () => push(context, const RegisterScreen())
                          : () => toast(context, 'El registro está cerrado por ahora.', error: true),
                      child: Text('Regístrate', style: Tx.body(15, weight: FontWeight.w700, color: Tx.accent)),
                    ),
                  ]),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
