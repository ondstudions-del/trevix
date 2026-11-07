import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../core/nav.dart';
import '../../core/theme.dart';

/// Fondo de las pantallas de acceso: halos de la marca sobre negro.
class AuthBackground extends StatelessWidget {
  const AuthBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(children: [
      Positioned(
        top: -160,
        left: -120,
        child: Container(
          width: 420,
          height: 420,
          decoration: const BoxDecoration(shape: BoxShape.circle, gradient: RadialGradient(colors: [Color(0x557C3AED), Color(0x007C3AED)])),
        ),
      ),
      Positioned(
        top: 120,
        right: -180,
        child: Container(
          width: 400,
          height: 400,
          decoration: const BoxDecoration(shape: BoxShape.circle, gradient: RadialGradient(colors: [Color(0x402563EB), Color(0x002563EB)])),
        ),
      ),
      Positioned.fill(child: child),
    ]);
  }
}

/// Campo de texto de los formularios de acceso con su error del servidor.
class AuthField extends StatefulWidget {
  const AuthField({
    super.key,
    required this.controller,
    required this.hint,
    required this.icon,
    this.error,
    this.password = false,
    this.keyboard,
    this.action = TextInputAction.next,
    this.onSubmit,
    this.autofill,
    this.capitalization = TextCapitalization.none,
    this.maxLength,
  });

  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final String? error;
  final bool password;
  final TextInputType? keyboard;
  final TextInputAction action;
  final VoidCallback? onSubmit;
  final Iterable<String>? autofill;
  final TextCapitalization capitalization;
  final int? maxLength;

  @override
  State<AuthField> createState() => _AuthFieldState();
}

class _AuthFieldState extends State<AuthField> {
  bool _hidden = true;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: widget.controller,
        obscureText: widget.password && _hidden,
        keyboardType: widget.keyboard,
        textInputAction: widget.action,
        autocorrect: false,
        enableSuggestions: !widget.password,
        textCapitalization: widget.capitalization,
        autofillHints: widget.autofill,
        maxLength: widget.maxLength,
        onSubmitted: (_) => widget.onSubmit?.call(),
        style: Tx.body(16),
        decoration: fieldDecoration(
          widget.hint,
          error: widget.error,
          prefix: Icon(widget.icon, color: Tx.subtle, size: 20),
          suffix: widget.password
              ? IconButton(
                  onPressed: () => setState(() => _hidden = !_hidden),
                  icon: Icon(_hidden ? CupertinoIcons.eye : CupertinoIcons.eye_slash, color: Tx.subtle, size: 20),
                )
              : null,
        ).copyWith(counterText: ''),
      ),
    );
  }
}

class FormBanner extends StatelessWidget {
  const FormBanner({super.key, required this.text, this.error = true});

  final String text;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final color = error ? Tx.danger : Tx.purple400;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Tx.alpha(color, .1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Tx.alpha(color, .35)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(error ? CupertinoIcons.exclamationmark_circle : CupertinoIcons.info_circle, color: color, size: 20),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: Tx.body(14, color: Tx.text, height: 1.4))),
      ]),
    );
  }
}
