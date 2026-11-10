import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import '../../core/api.dart';
import '../../core/audio.dart';
import '../../core/events.dart';
import '../../core/format.dart';
import '../../core/nav.dart';
import '../../core/routes.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';
import '../../widgets/note_bubble.dart';
import '../../widgets/report_sheet.dart';
import '../../widgets/song_chip.dart';
import '../../widgets/story_layers.dart';
import '../../widgets/user_tile.dart';
import '../notes/note_sheets.dart';

/// Visor de historias: deslizar entre personas, tocar para avanzar o retroceder, mantener para pausar.
class StoryViewer extends StatefulWidget {
  const StoryViewer({super.key, required this.groups, this.initialGroup = 0});

  final List<StoryGroup> groups;
  final int initialGroup;

  @override
  State<StoryViewer> createState() => _StoryViewerState();
}

class _StoryViewerState extends State<StoryViewer> {
  late final PageController _page = PageController(initialPage: widget.initialGroup);
  late int _current = widget.initialGroup;
  double _drag = 0;
  bool _closing = false;

  @override
  void dispose() {
    _page.dispose();
    songPlayer.stop();
    super.dispose();
  }

  /// Cierra el visor una sola vez, aunque coincidan el fin de la última historia, el gesto y la X.
  void _close() {
    if (_closing || !mounted) return;
    final route = ModalRoute.of(context);
    if (route == null || !route.isCurrent) return;
    _closing = true;
    songPlayer.stop();
    setState(() {});
    Navigator.of(context).pop();
  }

  void _nextGroup() {
    if (_closing) return;
    if (_current < widget.groups.length - 1) {
      _page.nextPage(duration: const Duration(milliseconds: 380), curve: Curves.easeOutCubic);
    } else {
      _close();
    }
  }

  void _prevGroup() {
    if (_current > 0) {
      _page.previousPage(duration: const Duration(milliseconds: 380), curve: Curves.easeOutCubic);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: Tx.immersive,
      child: Scaffold(
        backgroundColor: Colors.black,
        resizeToAvoidBottomInset: false,
        body: GestureDetector(
          onVerticalDragUpdate: (d) {
            if (d.delta.dy > 0 || _drag > 0) setState(() => _drag = (_drag + d.delta.dy).clamp(0.0, 600.0));
          },
          onVerticalDragEnd: (d) {
            if (_drag > 140 || d.velocity.pixelsPerSecond.dy > 900) {
              _close();
            } else {
              setState(() => _drag = 0);
            }
          },
          child: Transform.translate(
            offset: Offset(0, _drag),
            child: Transform.scale(
              scale: 1 - (_drag / 3000),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(_drag > 0 ? 24 : 0),
                child: PageView.builder(
                  controller: _page,
                  itemCount: widget.groups.length,
                  onPageChanged: (i) => setState(() => _current = i),
                  itemBuilder: (_, i) => _GroupView(
                    key: ValueKey('group-$i'),
                    group: widget.groups[i],
                    active: i == _current && !_closing,
                    onNextGroup: _nextGroup,
                    onPrevGroup: _prevGroup,
                    onClose: _close,
                    onEmpty: () {
                      widget.groups.removeAt(i);
                      if (widget.groups.isEmpty) {
                        _close();
                      } else {
                        setState(() => _current = _current.clamp(0, widget.groups.length - 1));
                      }
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GroupView extends StatefulWidget {
  const _GroupView({
    super.key,
    required this.group,
    required this.active,
    required this.onNextGroup,
    required this.onPrevGroup,
    required this.onClose,
    required this.onEmpty,
  });

  final StoryGroup group;
  final bool active;
  final VoidCallback onNextGroup;
  final VoidCallback onPrevGroup;
  final VoidCallback onClose;
  final VoidCallback onEmpty;

  @override
  State<_GroupView> createState() => _GroupViewState();
}

class _GroupViewState extends State<_GroupView> with SingleTickerProviderStateMixin {
  /// Marca cuánto dura cada historia: con «Quitar animaciones» o «Reducir movimiento» no debe acelerarse.
  late final AnimationController _progress = AnimationController(vsync: this, animationBehavior: AnimationBehavior.preserve);
  late int _index = widget.group.own ? 0 : widget.group.firstUnseen;
  VideoPlayerController? _video;
  bool _paused = false;
  bool _holding = false;
  final _reply = TextEditingController();
  final _replyFocus = FocusNode();
  bool _sending = false;

  /// Emoji que se anima en el centro al reaccionar (la clave reinicia la animación).
  String? _burst;
  int _burstKey = 0;

  static const _quickReactions = ['😂', '😮', '😍', '😢', '👏', '🔥', '🎉', '💯'];

  StoryGroup get g => widget.group;
  StoryItem get item => g.items[_index];

  @override
  void initState() {
    super.initState();
    _progress.addStatusListener(_onProgress);
    _replyFocus.addListener(_onFocus);
    if (widget.active) _show();
  }

  void _onProgress(AnimationStatus s) {
    if (s == AnimationStatus.completed && mounted && widget.active) _next();
  }

  void _onFocus() {
    if (mounted) _setPaused(_replyFocus.hasFocus);
  }

  @override
  void didUpdateWidget(covariant _GroupView old) {
    super.didUpdateWidget(old);
    if (widget.active && !old.active) {
      _show();
    } else if (!widget.active && old.active) {
      _stopMedia();
      _progress.stop();
    }
  }

  @override
  void dispose() {
    _progress.removeStatusListener(_onProgress);
    _progress.dispose();
    _replyFocus.removeListener(_onFocus);
    _replyFocus.dispose();
    _reply.dispose();
    _releaseVideo(_video);
    _video = null;
    super.dispose();
  }

  String get _songKey => 'story:${item.id}';

  /// El reproductor nativo se libera cuando su VideoPlayer ya no se dibuja: liberarlo antes cierra la app en iOS.
  static void _releaseVideo(VideoPlayerController? v) {
    if (v == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        if (v.value.isInitialized) await v.pause();
      } catch (_) {}
      await Future<void>.delayed(const Duration(milliseconds: 300));
      try {
        await v.dispose();
      } catch (_) {}
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  void _stopMedia() {
    final v = _video;
    if (v != null) {
      _video = null;
      if (mounted) setState(() {});
      _releaseVideo(v);
    }
    songPlayer.stop();
  }

  Future<void> _show() async {
    _stopMedia();
    _progress.stop();
    _progress.value = 0;
    if (g.items.isEmpty) return;
    final current = item;
    if (!current.seen && !g.own) {
      current.seen = true;
      api.post('stories/${current.id}/view').catchError((_) => ApiResponse(null, {}));
    }
    if (current.isVideo && current.mediaUrl != null) {
      final v = VideoPlayerController.networkUrl(Uri.parse(current.mediaUrl!));
      _video = v;
      setState(() {});
      try {
        await v.initialize();
        if (_video != v || !mounted) return;
        _progress.duration = v.value.duration > Duration.zero ? v.value.duration : const Duration(seconds: 15);
        if (current.song != null && current.song!.available) {
          await v.setVolume(0);
          songPlayer.play(_songKey, current.song!, clip: true, loop: true);
        }
        if (!_paused) {
          await v.play();
          _progress.forward(from: 0);
        }
        setState(() {});
      } catch (_) {
        if (_video == v && mounted) {
          _progress.duration = const Duration(seconds: 5);
          _progress.forward(from: 0);
        }
      }
    } else {
      _progress.duration = Duration(seconds: current.seconds > 0 ? current.seconds : 6);
      if (current.song != null && current.song!.available) {
        songPlayer.play(_songKey, current.song!, clip: true, loop: true);
      }
      if (!_paused) _progress.forward(from: 0);
      setState(() {});
    }
  }

  void _next() {
    if (_index < g.items.length - 1) {
      setState(() => _index++);
      _show();
    } else {
      widget.onNextGroup();
    }
  }

  void _prev() {
    if (_index > 0) {
      setState(() => _index--);
      _show();
    } else {
      _progress.value = 0;
      widget.onPrevGroup();
      if (widget.active) _show();
    }
  }

  void _setPaused(bool paused) {
    if (!mounted) return;
    _paused = paused;
    if (paused) {
      _progress.stop();
      _video?.pause();
      songPlayer.pause();
    } else if (widget.active) {
      _progress.forward();
      _video?.play();
      if (item.song != null && songPlayer.currentKey == _songKey) {
        songPlayer.toggle(_songKey, item.song!, clip: true);
      }
    }
    setState(() {});
  }

  Future<void> _sendReply() async {
    final text = _reply.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      final res = await api.post('stories/${item.id}/reply', {'body': text});
      _reply.clear();
      _replyFocus.unfocus();
      if (mounted) toast(context, '${res.map['message'] ?? 'Respuesta enviada.'}');
    } catch (e) {
      if (mounted) toastError(context, e);
    }
    if (mounted) setState(() => _sending = false);
  }

  /// Reacciona con un emoji (null quita la reacción). Al autor también le llega por mensaje privado.
  Future<void> _react(String? emoji) async {
    final story = item;
    final previous = story.myReaction;
    HapticFeedback.lightImpact();
    setState(() {
      story.myReaction = emoji;
      if (emoji != null) {
        _burst = emoji;
        _burstKey++;
      }
    });
    if (_replyFocus.hasFocus) _replyFocus.unfocus();
    try {
      if (emoji == null) {
        await api.delete('stories/${story.id}/reaction');
      } else {
        await api.post('stories/${story.id}/reaction', {'emoji': emoji});
      }
    } catch (e) {
      if (mounted) {
        setState(() => story.myReaction = previous);
        toastError(context, e);
      }
    }
  }

  Future<void> _openNote(Note note) async {
    _setPaused(true);
    await openNote(context, note);
    if (mounted && !_replyFocus.hasFocus) _setPaused(false);
  }

  Future<void> _viewers() async {
    _setPaused(true);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ViewersSheet(storyId: item.id),
    );
    if (mounted) _setPaused(false);
  }

  Future<void> _delete() async {
    _setPaused(true);
    final ok = await confirm(context, 'Eliminar historia', 'Se eliminará para todos.', action: 'Eliminar', destructive: true);
    if (!ok || !mounted) {
      if (mounted) _setPaused(false);
      return;
    }
    try {
      await api.delete('stories/${item.id}');
      storiesChanged.value++;
      if (!mounted) return;
      toast(context, 'Eliminaste la historia.');
      _stopMedia();
      setState(() {
        g.items.removeAt(_index);
        if (_index >= g.items.length) _index = g.items.length - 1;
      });
      if (g.items.isEmpty) {
        widget.onEmpty();
      } else {
        _paused = false;
        _show();
      }
    } catch (e) {
      if (mounted) {
        toastError(context, e);
        _setPaused(false);
      }
    }
  }

  void _menu() {
    _setPaused(true);
    final actions = <SheetAction>[
      if (g.own) SheetAction('Eliminar historia', CupertinoIcons.trash, _delete, destructive: true),
      if (!g.own) SheetAction('Ver perfil', CupertinoIcons.person, () => openProfile(context, g.user.username)),
      if (!g.own) SheetAction('Reportar historia', CupertinoIcons.flag, () => showReportSheet(context, 'story', item.id), destructive: true),
    ];
    actionSheet(context, actions).then((_) {
      if (mounted && !_replyFocus.hasFocus) _setPaused(false);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (g.items.isEmpty) return const SizedBox.shrink();
    final current = item;
    final top = MediaQuery.of(context).padding.top;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final safeBottom = MediaQuery.of(context).padding.bottom;

    return Stack(fit: StackFit.expand, children: [
      _content(current),
      Positioned.fill(
        child: Row(children: [
          Expanded(
            flex: 1,
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: _prev,
              onLongPressStart: (_) {
                _holding = true;
                _setPaused(true);
              },
              onLongPressEnd: (_) {
                _holding = false;
                _setPaused(false);
              },
            ),
          ),
          Expanded(
            flex: 2,
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: _next,
              onLongPressStart: (_) {
                _holding = true;
                _setPaused(true);
              },
              onLongPressEnd: (_) {
                _holding = false;
                _setPaused(false);
              },
            ),
          ),
        ]),
      ),
      if (!current.isText && current.layers.isNotEmpty)
        Positioned.fill(
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 200),
            opacity: _holding ? 0 : 1,
            child: StoryLayersView(
              key: ValueKey('layers-${current.id}'),
              item: current,
              own: g.own,
              onHold: _setPaused,
              openProfile: (u) => openProfile(context, u),
            ),
          ),
        ),
      Positioned(
        top: 0,
        left: 0,
        right: 0,
        child: IgnorePointer(
          child: Container(
            height: top + 110,
            decoration: const BoxDecoration(
              gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x99000000), Color(0x00000000)]),
            ),
          ),
        ),
      ),
      Positioned(
        top: top + 8,
        left: 10,
        right: 10,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 200),
          opacity: _holding ? 0 : 1,
          child: Column(children: [
            Row(children: [
              for (var i = 0; i < g.items.length; i++)
                Expanded(
                  child: Container(
                    height: 3,
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    decoration: BoxDecoration(color: Colors.white.withAlpha(70), borderRadius: BorderRadius.circular(2)),
                    child: i < _index
                        ? Container(decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(2)))
                        : i == _index
                            ? AnimatedBuilder(
                                animation: _progress,
                                builder: (_, __) => FractionallySizedBox(
                                  alignment: Alignment.centerLeft,
                                  widthFactor: _progress.value,
                                  child: Container(decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(2))),
                                ),
                              )
                            : null,
                  ),
                ),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              GestureDetector(
                onTap: () => openProfile(context, g.user.username),
                child: Avatar(user: g.user, size: 36),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Flexible(child: Text(g.own ? 'Tu historia' : g.user.displayName, maxLines: 1, overflow: TextOverflow.ellipsis, style: TxDark.body(14.5, weight: FontWeight.w600, color: Colors.white))),
                    if (g.user.isVerified && !g.own) ...[const SizedBox(width: 4), const VerifiedBadge(size: 14)],
                    const SizedBox(width: 8),
                    Text(timeAgo(current.createdAt), style: TxDark.body(13, color: Colors.white.withAlpha(180))),
                  ]),
                  if (current.song != null && current.song!.available)
                    Row(children: [
                      const Icon(CupertinoIcons.music_note, size: 12, color: Colors.white),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text('${current.song!.title} · ${current.song!.artist?.displayName ?? ''}',
                            maxLines: 1, overflow: TextOverflow.ellipsis, style: TxDark.body(12, color: Colors.white.withAlpha(220))),
                      ),
                    ]),
                ]),
              ),
              if (_paused && !_holding) const Icon(CupertinoIcons.pause_fill, color: Colors.white, size: 18),
              IconButton(onPressed: _menu, icon: const Icon(CupertinoIcons.ellipsis, color: Colors.white)),
              IconButton(
                onPressed: widget.onClose,
                icon: const Icon(CupertinoIcons.xmark, color: Colors.white, size: 22),
              ),
            ]),
            if (g.note != null && !g.note!.expired)
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.only(left: 6, top: 2),
                  child: NoteCloud(
                    text: g.note!.label,
                    sticker: g.note!.sticker,
                    dark: true,
                    tailUp: true,
                    maxWidth: 230,
                    fontSize: 13,
                    onTap: () => _openNote(g.note!),
                  ),
                ),
              ),
          ]),
        ),
      ),
      Positioned(
        left: 0,
        right: 0,
        bottom: bottomInset > 0 ? bottomInset : 0,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 200),
          opacity: _holding ? 0 : 1,
          child: Container(
            padding: EdgeInsets.fromLTRB(12, 30, 12, (bottomInset > 0 ? 8 : safeBottom) + 8),
            decoration: const BoxDecoration(
              gradient: LinearGradient(begin: Alignment.bottomCenter, end: Alignment.topCenter, colors: [Color(0x99000000), Color(0x00000000)]),
            ),
            child: g.own ? _ownBar(current) : _replyBar(current),
          ),
        ),
      ),
      if (_burst != null)
        Positioned.fill(
          child: IgnorePointer(
            child: Center(
              child: TweenAnimationBuilder<double>(
                key: ValueKey(_burstKey),
                tween: Tween(begin: 0, end: 1),
                duration: const Duration(milliseconds: 950),
                onEnd: () {
                  if (mounted) setState(() => _burst = null);
                },
                builder: (_, t, child) => Opacity(
                  opacity: t < .7 ? 1 : (1 - (t - .7) / .3).clamp(0.0, 1.0),
                  child: Transform.translate(
                    offset: Offset(0, -60 * t),
                    child: Transform.scale(scale: .3 + Curves.elasticOut.transform((t / .55).clamp(0.0, 1.0)) * .9, child: child),
                  ),
                ),
                child: Text(_burst!, style: const TextStyle(fontSize: 110)),
              ),
            ),
          ),
        ),
    ]);
  }

  Widget _content(StoryItem current) {
    if (current.isText) {
      return Container(
        decoration: BoxDecoration(gradient: Tx.storyBackground(current.background)),
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Text(
          current.body,
          textAlign: TextAlign.center,
          style: TxDark.display(current.body.length > 120 ? 24 : 32, color: Colors.white, height: 1.25),
        ),
      );
    }
    final caption = current.body.trim();
    Widget media;
    if (current.isVideo) {
      final v = _video;
      media = v != null && v.value.isInitialized
          ? Center(child: AspectRatio(aspectRatio: v.value.aspectRatio, child: filtered(current.filter, VideoPlayer(v))))
          : const Center(child: CupertinoActivityIndicator(color: Colors.white, radius: 14));
    } else {
      media = filtered(
        current.filter,
        Stack(fit: StackFit.expand, children: [
          ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
            child: Opacity(opacity: .5, child: NetImage(current.mediaUrl, fit: BoxFit.cover)),
          ),
          NetImage(current.mediaUrl, fit: BoxFit.contain),
        ]),
      );
    }
    return Stack(fit: StackFit.expand, children: [
      media,
      if (caption.isNotEmpty)
        Positioned(
          left: 24,
          right: 24,
          bottom: 140,
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              decoration: BoxDecoration(color: Colors.black.withAlpha(130), borderRadius: BorderRadius.circular(14)),
              child: Text(caption, textAlign: TextAlign.center, style: TxDark.body(16, weight: FontWeight.w500, color: Colors.white)),
            ),
          ),
        ),
    ]);
  }

  Widget _ownBar(StoryItem current) {
    return Row(children: [
      GestureDetector(
        onTap: _viewers,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(color: Colors.white.withAlpha(36), borderRadius: BorderRadius.circular(20)),
          child: Row(children: [
            const Icon(CupertinoIcons.eye, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Text(plural(current.views ?? 0, 'vista', 'vistas'), style: TxDark.body(14, weight: FontWeight.w600, color: Colors.white)),
            if ((current.reactions ?? 0) > 0) ...[
              const SizedBox(width: 10),
              const Icon(CupertinoIcons.heart_fill, color: Tx.like, size: 16),
              const SizedBox(width: 5),
              Text(compact(current.reactions!), style: TxDark.body(14, weight: FontWeight.w600, color: Colors.white)),
            ],
          ]),
        ),
      ),
      const Spacer(),
      if (current.song != null) PlayButton(playKey: _songKey, song: current.song!, clip: true, size: 40),
      const SizedBox(width: 10),
      GestureDetector(
        onTap: _delete,
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: Colors.white.withAlpha(36), shape: BoxShape.circle),
          child: const Icon(CupertinoIcons.trash, color: Colors.white, size: 20),
        ),
      ),
    ]);
  }

  Widget _replyBar(StoryItem current) {
    final blocked = g.replyBlocked;
    final mine = current.myReaction;
    final heart = GestureDetector(
      onTap: () => _react(mine == null ? '❤️' : null),
      child: SizedBox(
        width: 46,
        height: 46,
        child: Center(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            transitionBuilder: (child, a) => ScaleTransition(scale: a, child: child),
            child: mine == null
                ? const Icon(CupertinoIcons.heart, key: ValueKey('off'), color: Colors.white, size: 28)
                : mine == '❤️'
                    ? const Icon(CupertinoIcons.heart_fill, key: ValueKey('heart'), color: Tx.like, size: 28)
                    : Text(mine, key: ValueKey(mine), style: const TextStyle(fontSize: 26)),
          ),
        ),
      ),
    );
    return Column(mainAxisSize: MainAxisSize.min, children: [
      if (_replyFocus.hasFocus && _reply.text.isEmpty)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
            for (final e in _quickReactions)
              GestureDetector(
                onTap: () => _react(e),
                child: AnimatedScale(
                  scale: mine == e ? 1.25 : 1,
                  duration: const Duration(milliseconds: 150),
                  child: Text(e, style: const TextStyle(fontSize: 30)),
                ),
              ),
          ]),
        ),
      Row(children: [
        Expanded(
          child: blocked != null
              ? Text(blocked, style: TxDark.body(13, color: Colors.white.withAlpha(200)))
              : _replyField(),
        ),
        const SizedBox(width: 4),
        heart,
        if (blocked == null) ...[
          const SizedBox(width: 4),
          _sendButton(),
        ],
      ]),
    ]);
  }

  Widget _replyField() {
    return TextField(
          controller: _reply,
          focusNode: _replyFocus,
          maxLength: 2000,
          textInputAction: TextInputAction.send,
          onChanged: (_) => setState(() {}),
          onSubmitted: (_) => _sendReply(),
          style: TxDark.body(15, color: Colors.white),
          decoration: InputDecoration(
            counterText: '',
            hintText: 'Responder a ${g.user.displayName.split(' ').first}…',
            hintStyle: TxDark.body(15, color: Colors.white.withAlpha(170)),
            filled: true,
            fillColor: Colors.white.withAlpha(26),
            contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(26), borderSide: BorderSide(color: Colors.white.withAlpha(90))),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(26), borderSide: BorderSide(color: Colors.white.withAlpha(90))),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(26), borderSide: const BorderSide(color: Colors.white)),
          ),
        );
  }

  Widget _sendButton() {
    return GestureDetector(
      onTap: _sendReply,
      child: Container(
        width: 46,
        height: 46,
        decoration: const BoxDecoration(gradient: Tx.brand, shape: BoxShape.circle),
        child: _sending
            ? const Padding(padding: EdgeInsets.all(13), child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : const Icon(CupertinoIcons.paperplane_fill, color: Colors.white, size: 20),
      ),
    );
  }
}

class _ViewersSheet extends StatefulWidget {
  const _ViewersSheet({required this.storyId});

  final int storyId;

  @override
  State<_ViewersSheet> createState() => _ViewersSheetState();
}

class _ViewersSheetState extends State<_ViewersSheet> {
  List<User>? _users;
  Map<int, String> _reactions = {};
  int _count = 0;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await api.get('stories/${widget.storyId}/viewers');
      setState(() {
        _users = res.list.map(User.fromJson).toList();
        _reactions = {
          for (final j in res.list)
            if (asStrOrNull(j['reaction']) != null) asInt(j['id']): asStr(j['reaction']),
        };
        _count = asInt(res.meta['count'], _users!.length);
      });
    } catch (e) {
      setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final users = _users;
    return SheetFrame(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * .6),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(users == null ? 'Vistas' : plural(_count, 'vista', 'vistas'), style: Tx.display(19)),
          ),
          if (_error != null)
            ErrorState(error: _error!, onRetry: () {
              setState(() => _error = null);
              _load();
            })
          else if (users == null)
            const Loading()
          else if (users.isEmpty)
            const EmptyState(icon: CupertinoIcons.eye, title: 'Aún nadie la vio', message: 'Te avisaremos aquí cuando alguien la vea.')
          else
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: users.length,
                itemBuilder: (_, i) {
                  final reaction = _reactions[users[i].id];
                  return UserTile(
                    user: users[i],
                    subtitle: reaction != null ? 'Reaccionó · vista ${timeAgo(users[i].extraDate)}' : 'Vista ${timeAgo(users[i].extraDate)}',
                    showFollow: false,
                    trailing: reaction != null ? Text(reaction, style: const TextStyle(fontSize: 24)) : null,
                  );
                },
              ),
            ),
        ]),
      ),
    );
  }
}
