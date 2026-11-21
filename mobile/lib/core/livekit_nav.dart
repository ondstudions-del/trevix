import 'package:flutter/widgets.dart';

import '../screens/livekit/livekit_room_screen.dart';
import 'i18n.dart';
import 'livekit_api.dart';
import 'nav.dart';

/// Abre una sesión live (espectador o reentrada del host).
Future<void> openLiveSession(BuildContext context, int sessionId, {String? title, bool video = true}) async {
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
}
