import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/catalog.dart';
import '../../core/events.dart';
import '../../core/i18n.dart';
import '../../core/nav.dart';
import '../../core/paged.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';
import '../../widgets/logo.dart';
import '../../widgets/paged_view.dart';
import '../../widgets/post_card.dart';
import '../ads/ads_screen.dart';
import '../home/home_shell.dart';
import '../explore/search_screen.dart';
import '../messages/inbox_screen.dart';
import '../reels/reels_screen.dart';
import '../stories/stories_bar.dart';

class FeedScreen extends StatefulWidget {
  const FeedScreen({super.key});

  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen> with WidgetsBindingObserver {
  String _tab = 'foryou';
  final Map<String, Paged<Post>> _feeds = {};
  final _scroll = ScrollController();
  final _stories = StoriesController();
  bool _dismissedNotice = false;

  /// Anuncios de OND-ADS (meta.sponsored): van después de la publicación con ese id.
  final Map<String, Map<int, Json>> _ads = {};

  /// Primera publicación de «Sugerencias para ti» (cuando se acaba la pestaña, el feed sigue con todo lo demás).
  final Map<String, int> _suggestedFrom = {};

  /// Publicaciones nuevas sobre la más reciente que se ve (GET feed/newer cada 30 s y al volver a la app).
  int _newer = 0;
  Timer? _newerTimer;

  Paged<Post> get _feed => _feeds.putIfAbsent(_tab, () {
        final tab = _tab;
        late final Paged<Post> paged;
        paged = Paged<Post>('feed', Post.fromJson, query: {'tab': tab}, onMeta: (meta) => _onMeta(tab, paged, meta));
        return paged;
      });

  void _onMeta(String tab, Paged<Post> paged, Map<String, dynamic> meta) {
    final page = paged.items.sublist(paged.pageStart.clamp(0, paged.items.length));
    if (paged.pageStart == 0) {
      _ads.remove(tab);
      _suggestedFrom.remove(tab);
      if (tab == _tab) _newer = 0;
    }
    if (page.isEmpty) return;
    if (asBool(meta['suggested']) && !_suggestedFrom.containsKey(tab)) _suggestedFrom[tab] = page.first.id;
    final sponsored = asMapOrNull(meta['sponsored']);
    final ad = asMapOrNull(sponsored?['ad']);
    if (ad != null) {
      final position = asInt(sponsored!['position'], 3).clamp(1, page.length);
      _ads.putIfAbsent(tab, () => {})[page[position - 1].id] = ad;
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    tabReselect.addListener(_onReselect);
    postCreated.addListener(_onCreated);
    storiesChanged.addListener(_stories.load);
    notesChanged.addListener(_stories.load);
    _stories.load();
    _newerTimer = Timer.periodic(const Duration(seconds: 30), (_) => _checkNewer());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _newerTimer?.cancel();
    tabReselect.removeListener(_onReselect);
    postCreated.removeListener(_onCreated);
    storiesChanged.removeListener(_stories.load);
    notesChanged.removeListener(_stories.load);
    _scroll.dispose();
    _stories.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _checkNewer();
  }

  Future<void> _checkNewer() async {
    final feed = _feed;
    if (!mounted || _tab == 'trending' || !feed.loaded || feed.loading || feed.items.isEmpty) return;
    final tab = _tab;
    final after = feed.items.take(25).fold<int>(0, (m, p) => p.id > m ? p.id : m);
    try {
      final count = asInt((await api.get('feed/newer', {'tab': tab, 'after': after})).map['count']);
      if (mounted && tab == _tab && count != _newer) setState(() => _newer = count);
    } catch (_) {
      // Sin conexión: se vuelve a intentar en el siguiente ciclo.
    }
  }

  Future<void> _showNewer() async {
    setState(() => _newer = 0);
    if (_scroll.hasClients) await _scroll.animateTo(0, duration: const Duration(milliseconds: 400), curve: Curves.easeOutCubic);
    await _feed.refresh();
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

  Widget Function(BuildContext, Post, int) _itemBuilder(Paged<Post> feed) {
    final base = postBuilder(feed);
    return (context, post, i) {
      final card = base(context, post, i);
      final ad = _ads[_tab]?[post.id];
      final suggested = _suggestedFrom[_tab] == post.id;
      if (ad == null && !suggested) return card;
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (suggested) const _SuggestedDivider(),
        card,
        if (ad != null)
          SponsoredCard(
            key: ValueKey('ad-${ad['id']}-${post.id}'),
            ad: ad,
            postCard: (p) => PostCard(key: ValueKey('ad-post-${p.id}'), post: p),
          ),
      ]);
    };
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
      if (mounted) toast(context, '${res.map['message'] ?? tr('Te enviamos un nuevo enlace de verificación.')}');
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
          IconBadgeButton(glyph: TxGlyph.reels, onTap: () => openReels(context)),
          Semantics(
            label: tr('Buscar personas, grupos o comunidades'),
            button: true,
            child: IconBadgeButton(glyph: TxGlyph.search, onTap: () => push(context, const SearchScreen())),
          ),
          IconBadgeButton(
            glyph: TxGlyph.send,
            count: state.counts.messages,
            onTap: () => push(context, const InboxScreen()),
          ),
        ],
      ),
      body: Stack(children: [
        PagedView<Post>(
        paged: feed,
        controller: _scroll,
        onRefresh: _stories.load,
        itemBuilder: _itemBuilder(feed),
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
                text: tr('Confirma tu correo ({email}) para publicar música y usar todas las funciones.', {'email': me.email}),
                actionLabel: tr('Reenviar enlace'),
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
                        label: tr(e.value),
                        selected: _tab == e.key,
                        onTap: () => setState(() => (_tab = e.key, _newer = 0)),
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
            'following' => tr('Aún no sigues a nadie'),
            'friends' => tr('Todavía no tienes amigos aquí'),
            'trending' => tr('Nada en tendencia por ahora'),
            _ => tr('Tu inicio está listo'),
          },
          message: switch (_tab) {
            'following' => tr('Sigue a personas desde Explorar y verás aquí lo que publican.'),
            'friends' => tr('Los amigos son las personas que sigues y que te siguen.'),
            'trending' => tr('Vuelve más tarde para ver lo más popular.'),
            _ => tr('Publica algo o explora para descubrir personas.'),
          },
        ),
      ),
        if (_newer > 0)
          Positioned(
            top: 10,
            left: 0,
            right: 0,
            child: Center(child: _NewPostsPill(count: _newer, onTap: _showNewer)),
          ),
      ]),
    );
  }
}

/// «N publicaciones nuevas»: sube al inicio y carga lo nuevo.
class _NewPostsPill extends StatelessWidget {
  const _NewPostsPill({required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        decoration: BoxDecoration(
          gradient: Tx.brand,
          borderRadius: BorderRadius.circular(22),
          boxShadow: [BoxShadow(color: Tx.alpha(Tx.purple, .4), blurRadius: 18, offset: const Offset(0, 6))],
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(CupertinoIcons.arrow_up, size: 15, color: Colors.white),
          const SizedBox(width: 6),
          Text(
            count == 1 ? tr('1 publicación nueva') : tr('{n} publicaciones nuevas', {'n': count > 98 ? '99+' : count}),
            style: Tx.body(13.5, weight: FontWeight.w700, color: Colors.white),
          ),
        ]),
      ),
    );
  }
}

/// Separador antes de «Sugerencias para ti» (el feed continúa con todo lo demás, del más reciente al más antiguo).
class _SuggestedDivider extends StatelessWidget {
  const _SuggestedDivider();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
      child: Column(children: [
        Row(children: [
          Expanded(child: Divider(color: Tx.border)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(CupertinoIcons.sparkles, size: 14, color: Tx.accent),
              const SizedBox(width: 6),
              Text(tr('Sugerencias para ti'), style: Tx.body(13, weight: FontWeight.w700, color: Tx.muted)),
            ]),
          ),
          Expanded(child: Divider(color: Tx.border)),
        ]),
        const SizedBox(height: 4),
        Text(tr('Ya viste lo más reciente. Sigue con más publicaciones de TREVIX.'), style: Tx.body(12.5, color: Tx.subtle)),
      ]),
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
