import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/catalog.dart';
import '../../core/events.dart';
import '../../core/nav.dart';
import '../../core/paged.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';
import '../../widgets/logo.dart';
import '../../widgets/paged_view.dart';
import '../home/home_shell.dart';
import '../messages/inbox_screen.dart';
import '../music/music_screen.dart';
import '../stories/stories_bar.dart';

class FeedScreen extends StatefulWidget {
  const FeedScreen({super.key});

  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen> {
  String _tab = 'foryou';
  final Map<String, Paged<Post>> _feeds = {};
  final _scroll = ScrollController();
  final _stories = StoriesController();
  bool _dismissedNotice = false;

  Paged<Post> get _feed => _feeds.putIfAbsent(_tab, () => Paged<Post>('feed', Post.fromJson, query: {'tab': _tab}));

  @override
  void initState() {
    super.initState();
    tabReselect.addListener(_onReselect);
    postCreated.addListener(_onCreated);
    storiesChanged.addListener(_stories.load);
    _stories.load();
  }

  @override
  void dispose() {
    tabReselect.removeListener(_onReselect);
    postCreated.removeListener(_onCreated);
    storiesChanged.removeListener(_stories.load);
    _scroll.dispose();
    _stories.dispose();
    super.dispose();
  }

  void _onReselect() {
    if (tabReselect.value != 0 || !_scroll.hasClients) return;
    if (_scroll.offset > 10) {
      _scroll.animateTo(0, duration: const Duration(milliseconds: 450), curve: Curves.easeOutCubic);
    } else {
      _feed.refresh();
      _stories.load();
    }
  }

  void _onCreated() {
    final post = postCreated.value;
    if (post == null || post.community != null) return;
    for (final entry in _feeds.entries) {
      if (entry.key != 'trending' && entry.value.loaded && !entry.value.items.any((p) => p.id == post.id)) {
        entry.value.insert(post);
      }
    }
    if (_scroll.hasClients) _scroll.animateTo(0, duration: const Duration(milliseconds: 400), curve: Curves.easeOutCubic);
  }

  Future<void> _resendVerification() async {
    try {
      final res = await api.post('me/email/verification');
      if (mounted) toast(context, '${res.map['message'] ?? 'Te enviamos un nuevo enlace de verificación.'}');
    } catch (e) {
      if (mounted) toastError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final me = state.me!;
    final feed = _feed;
    return Scaffold(
      appBar: GlassBar(
        showBack: false,
        leading: const Padding(padding: EdgeInsets.only(left: 16, right: 8), child: Wordmark(size: 30, gradientText: true)),
        actions: [
          IconBadgeButton(glyph: TxGlyph.music, onTap: () => push(context, const MusicScreen())),
          IconBadgeButton(
            glyph: TxGlyph.send,
            count: state.counts.messages,
            onTap: () => push(context, const InboxScreen()),
          ),
        ],
      ),
      body: PagedView<Post>(
        paged: feed,
        controller: _scroll,
        onRefresh: _stories.load,
        itemBuilder: postBuilder(feed),
        header: [
          SliverToBoxAdapter(child: StoriesBar(controller: _stories)),
          if (!_dismissedNotice && state.announcement.isNotEmpty)
            SliverToBoxAdapter(
              child: _Notice(
                icon: CupertinoIcons.speaker_2_fill,
                text: state.announcement,
                onClose: () => setState(() => _dismissedNotice = true),
              ),
            ),
          if (!me.emailVerified)
            SliverToBoxAdapter(
              child: _Notice(
                icon: CupertinoIcons.mail,
                text: 'Confirma tu correo (${me.email}) para publicar música y usar todas las funciones.',
                actionLabel: 'Reenviar enlace',
                onAction: _resendVerification,
              ),
            ),
          SliverToBoxAdapter(
            child: SizedBox(
              height: 54,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
                children: [
                  for (final e in feedTabs.entries)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: PillChip(
                        label: e.value,
                        selected: _tab == e.key,
                        onTap: () => setState(() => _tab = e.key),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
        empty: EmptyState(
          glyph: _tab == 'following' || _tab == 'friends' ? TxGlyph.users : TxGlyph.sparkles,
          title: switch (_tab) {
            'following' => 'Aún no sigues a nadie',
            'friends' => 'Todavía no tienes amigos aquí',
            'trending' => 'Nada en tendencia por ahora',
            _ => 'Tu inicio está listo',
          },
          message: switch (_tab) {
            'following' => 'Sigue a personas desde Explorar y verás aquí lo que publican.',
            'friends' => 'Los amigos son las personas que sigues y que te siguen.',
            'trending' => 'Vuelve más tarde para ver lo más popular.',
            _ => 'Publica algo o explora para descubrir personas.',
          },
        ),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.text, this.onClose, this.actionLabel, this.onAction});

  final IconData icon;
  final String text;
  final VoidCallback? onClose;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Panel(
      gradient: true,
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
      child: Row(children: [
        Icon(icon, color: Tx.accent, size: 20),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(text, style: Tx.body(13.5, height: 1.4)),
            if (actionLabel != null)
              GestureDetector(
                onTap: onAction,
                child: Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(actionLabel!, style: Tx.body(13.5, weight: FontWeight.w700, color: Tx.accent)),
                ),
              ),
          ]),
        ),
        if (onClose != null)
          IconButton(onPressed: onClose, icon: Icon(CupertinoIcons.xmark, size: 16, color: Tx.muted))
        else
          const SizedBox(width: 8),
      ]),
    );
  }
}
