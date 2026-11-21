import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../core/i18n.dart';
import '../../core/livekit_api.dart';
import '../../core/nav.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../core/api.dart';
import '../../widgets/common.dart';
import '../livekit/livekit_room_screen.dart';

/// Abre el visor vertical de lives (estilo reels).
Future<void> openExploreLives(
  BuildContext context, {
  required List<LiveKitSession> sessions,
  int initialIndex = 0,
}) {
  if (sessions.isEmpty) return Future.value();
  return push(
    context,
    ExploreLivesViewer(sessions: sessions, initialIndex: initialIndex.clamp(0, sessions.length - 1)),
  );
}

class ExploreLivesViewer extends StatefulWidget {
  const ExploreLivesViewer({super.key, required this.sessions, this.initialIndex = 0});

  final List<LiveKitSession> sessions;
  final int initialIndex;

  @override
  State<ExploreLivesViewer> createState() => _ExploreLivesViewerState();
}

class _ExploreLivesViewerState extends State<ExploreLivesViewer> {
  late final PageController _page;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex;
    _page = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _page.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: PageView.builder(
        controller: _page,
        scrollDirection: Axis.vertical,
        itemCount: widget.sessions.length,
        onPageChanged: (i) => setState(() => _index = i),
        itemBuilder: (context, i) {
          final s = widget.sessions[i];
          final active = (i - _index).abs() <= 1;
          return _ExploreLivePage(
            key: ValueKey('explore-live-${s.id}'),
            session: s,
            active: active && i == _index,
          );
        },
      ),
    );
  }
}

class _ExploreLivePage extends StatefulWidget {
  const _ExploreLivePage({super.key, required this.session, required this.active});

  final LiveKitSession session;
  final bool active;

  @override
  State<_ExploreLivePage> createState() => _ExploreLivePageState();
}

class _ExploreLivePageState extends State<_ExploreLivePage> {
  LiveKitJoin? _join;
  bool _busy = false;
  Object? _error;

  @override
  void didUpdateWidget(covariant _ExploreLivePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) {
      _connect();
    } else if (!widget.active && oldWidget.active) {
      setState(() {
        _join = null;
        _busy = false;
      });
    }
  }

  @override
  void initState() {
    super.initState();
    if (widget.active) _connect();
  }

  Future<void> _connect() async {
    if (_join != null || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final join = await liveKitJoinToken(widget.session.id);
      if (!mounted || !widget.active) return;
      setState(() {
        _join = join;
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _busy = false;
      });
    }
  }

  User _host() {
    return widget.session.hostUser ??
        User(
          id: widget.session.hostId ?? 0,
          username: widget.session.hostUsername ?? '',
          displayName: widget.session.hostName ?? tr('En vivo'),
          avatarUrl: widget.session.hostAvatar,
        );
  }

  Widget _placeholder() {
    final cover = widget.session.coverUrl ?? _host().avatarUrl;
    return Stack(fit: StackFit.expand, children: [
      if (cover != null)
        NetImage(cover, fit: BoxFit.cover)
      else
        const ColoredBox(color: Color(0xFF14141F)),
      DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.black.withAlpha(100), Colors.transparent, Colors.black.withAlpha(180)],
          ),
        ),
      ),
      SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.topLeft,
              child: IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(CupertinoIcons.chevron_down, color: Colors.white, size: 28),
              ),
            ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Avatar(user: _host(), size: 40),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      widget.session.title ?? _host().displayName,
                      style: Tx.body(16, weight: FontWeight.w800, color: Colors.white),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ]),
                if (_busy) ...[
                  const SizedBox(height: 20),
                  const Center(child: CupertinoActivityIndicator(color: Colors.white)),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(errorText(_error!), style: Tx.body(13, color: Colors.white70)),
                  const SizedBox(height: 10),
                  SoftButton(label: tr('Reintentar'), onPressed: _connect),
                ],
              ]),
            ),
          ],
        ),
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.active && _join != null) {
      final j = _join!;
      return LiveKitRoomScreen(
        join: j,
        title: j.session.title ?? widget.session.title ?? tr('En vivo'),
        video: !j.session.isVoiceChat,
        mode: LiveKitRoomMode.live,
      );
    }
    return _placeholder();
  }
}