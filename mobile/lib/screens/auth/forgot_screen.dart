import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';
import 'auth_widgets.dart';

/// Pide el enlace para restablecer la contraseña (se completa en la web desde el correo).
class ForgotScreen extends StatefulWidget {
  const ForgotScreen({super.key});

  @override
  State<ForgotScreen> createState() => _ForgotScreenState();
}

class _ForgotScreenState extends State<ForgotScreen> {
  final _email = TextEditingController();
  bool _busy = false;
  String? _error;
  String? _sent;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!_email.text.contains('@')) {
      setState(() => _error = 'Escribe un correo electrónico válido.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final res = await api.post('auth/password/forgot', {'email': _email.text.trim()});
      setState(() => _sent = '${res.map['message'] ?? 'Si el correo está registrado, te enviaremos un enlace.'}');
    } on ApiException catch (e) {
      setState(() => _error = e.fields['email'] ?? e.message);
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const GlassBar(title: 'Recuperar contraseña'),
      body: AuthBackground(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(
              width: 72,
              height: 72,
              alignment: Alignment.center,
              decoration: BoxDecoration(gradient: Tx.brandSoft, shape: BoxShape.circle, border: Border.all(color: Tx.alpha(Tx.purple500, .35))),
              child: Icon(CupertinoIcons.lock_rotation, color: Tx.accent, size: 32),
            ),
            const SizedBox(height: 22),
            Text('¿Olvidaste tu contraseña?', style: Tx.display(26)),
            const SizedBox(height: 8),
            Text('Escribe el correo de tu cuenta y te enviaremos un enlace para crear una nueva.',
                style: Tx.body(15, color: Tx.muted, height: 1.45)),
            const SizedBox(height: 24),
            if (_sent != null) FormBanner(text: _sent!, error: false),
            AuthField(
              controller: _email,
              hint: 'Correo electrónico',
              icon: CupertinoIcons.mail,
              error: _error,
              keyboard: TextInputType.emailAddress,
              action: TextInputAction.done,
              onSubmit: _submit,
            ),
            const SizedBox(height: 8),
            GradientButton(label: _sent == null ? 'Enviar enlace' : 'Enviar de nuevo', loading: _busy, onPressed: _submit),
          ]),
        ),
      ),
    );
  }
}
