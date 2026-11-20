import 'package:flutter/material.dart';

import '../../app.dart';
import '../../core/api.dart';
import '../../core/i18n.dart';
import '../../core/livekit_api.dart';
import '../../core/livekit_incoming.dart';
import '../../core/nav.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';
import 'livekit_room_screen.dart';

Future<void> showIncomingLiveKitCall(BuildContext context, LiveKitSession session) async {
  final name = session.hostName ?? tr('Alguien');
  final kind = session.kind;
  if (!context.mounted) return;
  await showModalBottomSheet<void>(
    context: context,
    isDismissible: false,
    enableDrag: false,
    backgroundColor: Colors.transparent,
    builder: (ctx) => SheetFrame(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            kind == 'video' ? tr('Videollamada entrante') : tr('Llamada entrante'),
            style: Tx.display(18),
          ),
          const SizedBox(height: 8),
          Text(name, style: Tx.body(16, weight: FontWeight.w600)),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () async {
                    Navigator.pop(ctx);
                    await liveKitDecline(session.id);
                    await LiveKitIncoming.instance.dismissed(session.id);
                  },
                  child: Text(tr('Rechazar')),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: () async {
                    Navigator.pop(ctx);
                    try {
                      await api.post('livekit/calls/${session.id}/accept', {});
                      final join = await liveKitJoinToken(session.id);
                      await LiveKitIncoming.instance.dismissed(session.id);
                      if (!context.mounted) return;
                      await push(
                        context,
                        LiveKitRoomScreen(
                          join: join,
                          title: kind == 'video' ? tr('Videollamada') : tr('Llamada'),
                          video: kind == 'video',
                        ),
                      );
                    } catch (e) {
                      if (context.mounted) toastError(context, e);
                    }
                  },
                  child: Text(tr('Aceptar')),
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

/// Escucha llamadas entrantes y muestra la hoja de aceptar.
class LiveKitCallListener extends StatefulWidget {
  const LiveKitCallListener({super.key, required this.child});

  final Widget child;

  @override
  State<LiveKitCallListener> createState() => _LiveKitCallListenerState();
}

class _LiveKitCallListenerState extends State<LiveKitCallListener> {
  LiveKitSession? _shown;

  @override
  void initState() {
    super.initState();
    LiveKitIncoming.instance.addListener(_onRing);
  }

  @override
  void dispose() {
    LiveKitIncoming.instance.removeListener(_onRing);
    super.dispose();
  }

  void _onRing() {
    final s = LiveKitIncoming.instance.ringing;
    if (s == null || s.id == _shown?.id) return;
    _shown = s;
    final nav = navigatorKey.currentContext;
    if (nav == null || !nav.mounted) return;
    showIncomingLiveKitCall(nav, s);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}