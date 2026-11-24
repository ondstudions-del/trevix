import 'package:flutter/cupertino.dart';

import '../screens/livekit/livekit_room_screen.dart';
import 'i18n.dart';
import 'livekit_api.dart';
import 'nav.dart';
import 'theme.dart';

/// Advertencia antes de entrar a un live +18 (mayores de edad).
Future<bool> confirmAdultLiveEntry(BuildContext context) async {
  final ok = await showCupertinoDialog<bool>(
    context: context,
    builder: (ctx) => CupertinoAlertDialog(
      title: Text(tr('Contenido para adultos (+18)')),
      content: Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Text(
          tr('Este live puede contener contenido +18 u otro material sensible. ¿Quieres continuar?'),
          style: Tx.body(14, height: 1.35),
        ),
      ),
      actions: [
        CupertinoDialogAction(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(tr('Cancelar')),
        ),
        CupertinoDialogAction(
          isDefaultAction: true,
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(tr('Entrar al live')),
        ),
      ],
    ),
  );
  return ok == true;
}

/// Abre una sesión live (espectador o reentrada del host).
Future<void> openLiveSession(BuildContext context, int sessionId, {String? title, bool video = true}) async {
  LiveKitSession preview;
  try {
    preview = await liveKitShow(sessionId);
  } catch (e) {
    if (context.mounted) toastError(context, e);
    return;
  }
  if (!context.mounted) return;
  if (preview.isAdult && !preview.isHost) {
    final ok = await confirmAdultLiveEntry(context);
    if (!ok || !context.mounted) return;
  }
  try {
    final join = await liveKitJoinToken(sessionId);
    if (!context.mounted) return;
    await push(
      context,
      LiveKitRoomScreen(
        join: join,
        title: title ?? join.session.title ?? tr('En vivo'),
        video: join.session.liveMode != 'voice_chat',
        mode: LiveKitRoomMode.live,
      ),
    );
  } catch (e) {
    if (context.mounted) toastError(context, e);
  }
}