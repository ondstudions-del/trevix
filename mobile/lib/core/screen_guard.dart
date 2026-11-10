import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:screen_protector/screen_protector.dart';

import 'theme.dart';

/// Protege lo que muestra [child] mientras está en pantalla: en iPhone las capturas y grabaciones salen en negro y,
/// si se está grabando o duplicando la pantalla, el contenido se oculta; en Android la ventana se marca como segura
/// (no hay capturas, grabación ni vista previa en apps recientes).
class ScreenGuard extends StatefulWidget {
  const ScreenGuard({super.key, required this.child, this.onScreenshot});

  final Widget child;

  /// Alguien hizo una captura (solo iPhone; la captura sale en negro igualmente).
  final VoidCallback? onScreenshot;

  @override
  State<ScreenGuard> createState() => _ScreenGuardState();
}

class _ScreenGuardState extends State<ScreenGuard> {
  bool _recording = false;

  @override
  void initState() {
    super.initState();
    _on();
  }

  Future<void> _on() async {
    try {
      await ScreenProtector.preventScreenshotOn();
      if (Platform.isAndroid) await ScreenProtector.protectDataLeakageOn();
      if (Platform.isIOS) {
        ScreenProtector.addListener(() => widget.onScreenshot?.call(), (recording) {
          if (mounted) setState(() => _recording = recording);
        });
        final recording = await ScreenProtector.isRecording();
        if (mounted && recording) setState(() => _recording = true);
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    () async {
      try {
        if (Platform.isIOS) ScreenProtector.removeListener();
        if (Platform.isAndroid) await ScreenProtector.protectDataLeakageOff();
        await ScreenProtector.preventScreenshotOff();
      } catch (_) {}
    }();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_recording) return widget.child;
    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(CupertinoIcons.eye_slash_fill, color: Colors.white70, size: 40),
            const SizedBox(height: 14),
            Text('Contenido protegido', style: TxDark.body(17, weight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text('Detén la grabación o la duplicación de pantalla para verlo.',
                textAlign: TextAlign.center, style: TxDark.body(14, color: TxDark.muted)),
          ]),
        ),
      ),
    );
  }
}
