import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart';

import '../../core/api.dart';
import '../../core/i18n.dart';
import '../../core/livekit_api.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';

/// Conecta a una sala LiveKit ya creada en el servidor (tras obtener el token).
class LiveKitRoomScreen extends StatefulWidget {
  const LiveKitRoomScreen({
    super.key,
    required this.join,
    required this.title,
    required this.video,
  });

  final LiveKitJoin join;
  final String title;
  final bool video;

  @override
  State<LiveKitRoomScreen> createState() => _LiveKitRoomScreenState();
}

class _LiveKitRoomScreenState extends State<LiveKitRoomScreen> {
  Room? _room;
  EventsListener<RoomEvent>? _listener;
  String? _error;
  bool _busy = true;

  @override
  void initState() {
    super.initState();
    _connect();
  }

  Future<void> _connect() async {
    try {
      final room = Room(
        roomOptions: const RoomOptions(
          adaptiveStream: true,
          dynacast: true,
          defaultCameraCaptureOptions: CameraCaptureOptions(),
          defaultAudioPublishOptions: AudioPublishOptions(),
          defaultVideoPublishOptions: VideoPublishOptions(simulcast: true),
        ),
      );
      _listener = room.createListener();
      _listener!.on<RoomDisconnectedEvent>((_) {
        if (mounted) Navigator.maybePop(context);
      });
      await room.connect(widget.join.url, widget.join.token);
      await room.localParticipant?.setMicrophoneEnabled(true);
      if (widget.video) {
        await room.localParticipant?.setCameraEnabled(true);
      }
      if (!mounted) return;
      setState(() {
        _room = room;
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = errorText(e);
        _busy = false;
      });
    }
  }

  Future<void> _hangUp() async {
    try {
      await liveKitEnd(widget.join.session.id);
    } catch (_) {}
    await _room?.disconnect();
    if (mounted) Navigator.pop(context);
  }

  @override
  void dispose() {
    _listener?.dispose();
    _room?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: GlassBar(
        title: widget.title,
        actions: [
          IconButton(
            onPressed: _busy ? null : _hangUp,
            icon: Icon(CupertinoIcons.phone_down_fill, color: Tx.danger, size: 28),
            tooltip: tr('Colgar'),
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_busy) {
      return const Center(child: CupertinoActivityIndicator(color: Colors.white));
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(_error!, style: Tx.body(15, color: Colors.white70), textAlign: TextAlign.center),
        ),
      );
    }
    final room = _room;
    if (room == null) return const SizedBox.shrink();

    final tiles = <Widget>[];
    final local = room.localParticipant;
    if (local != null && widget.video) {
      tiles.add(_ParticipantTile(participant: local, local: true));
    }
    for (final p in room.remoteParticipants.values) {
      tiles.add(_ParticipantTile(participant: p, local: false, video: widget.video));
    }
  if (tiles.isEmpty) {
      return Center(child: Text(tr('Conectado. Esperando a la otra persona…'), style: Tx.body(15, color: Colors.white70)));
    }
    return GridView.count(
      crossAxisCount: tiles.length == 1 ? 1 : 2,
      padding: const EdgeInsets.all(8),
      children: tiles,
    );
  }
}

class _ParticipantTile extends StatelessWidget {
  const _ParticipantTile({required this.participant, required this.local, this.video = true});

  final Participant participant;
  final bool local;
  final bool video;

  @override
  Widget build(BuildContext context) {
    VideoTrack? track;
    if (video) {
      for (final pub in participant.videoTrackPublications) {
        if (pub.track != null && !pub.muted) {
          track = pub.track as VideoTrack?;
          break;
        }
      }
    }
    final name = participant.name.isNotEmpty ? participant.name : (local ? tr('Tú') : tr('Participante'));
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: ColoredBox(
        color: const Color(0xFF1a1a1a),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (track != null)
              VideoTrackRenderer(track)
            else
              Center(child: Icon(CupertinoIcons.person_fill, color: Colors.white24, size: 48)),
            Positioned(
              left: 8,
              bottom: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(8)),
                child: Text(name, style: Tx.body(12, color: Colors.white)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}