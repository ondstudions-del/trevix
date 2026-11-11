import 'package:flutter/cupertino.dart';
import '../core/i18n.dart';
import '../core/paged.dart';
import '../models/models.dart';
import '../widgets/post_card.dart';
import 'common.dart';

/// Lista paginada con «tirar para actualizar» al estilo iOS y carga automática al llegar al final.
class PagedView<T> extends StatefulWidget {
  const PagedView({
    super.key,
    required this.paged,
    required this.itemBuilder,
    this.header = const [],
    this.empty,
    this.privateState,
    this.controller,
    this.padding = const EdgeInsets.only(bottom: 120),
    this.onRefresh,
  });

  final Paged<T> paged;
  final Widget Function(BuildContext context, T item, int index) itemBuilder;
  final List<Widget> header;
  final Widget? empty;
  final Widget? privateState;
  final ScrollController? controller;
  final EdgeInsets padding;
  final Future<void> Function()? onRefresh;

  @override
  State<PagedView<T>> createState() => _PagedViewState<T>();
}

class _PagedViewState<T> extends State<PagedView<T>> {
  @override
  void initState() {
    super.initState();
    _ensureLoaded();
  }

  @override
  void didUpdateWidget(covariant PagedView<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.paged != widget.paged) _ensureLoaded();
  }

  void _ensureLoaded() {
    final paged = widget.paged;
    if (!paged.loaded && !paged.loading) Future.microtask(paged.refresh);
  }

  Future<void> _refresh() async {
    await Future.wait([widget.paged.refresh(), if (widget.onRefresh != null) widget.onRefresh!()]);
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        if (n.metrics.extentAfter < 700) widget.paged.loadMore();
        return false;
      },
      child: CustomScrollView(
        controller: widget.controller,
        physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
        slivers: [
          CupertinoSliverRefreshControl(onRefresh: _refresh),
          ...widget.header,
          ListenableBuilder(
            listenable: widget.paged,
            builder: (context, _) => PagedSliver<T>(
              paged: widget.paged,
              itemBuilder: widget.itemBuilder,
              empty: widget.empty,
              privateState: widget.privateState,
            ),
          ),
          SliverPadding(padding: widget.padding),
        ],
      ),
    );
  }
}

/// Elementos de un Paged dentro de un CustomScrollView ajeno (perfil, comunidad…).
class PagedSliver<T> extends StatelessWidget {
  const PagedSliver({super.key, required this.paged, required this.itemBuilder, this.empty, this.privateState});

  final Paged<T> paged;
  final Widget Function(BuildContext context, T item, int index) itemBuilder;
  final Widget? empty;
  final Widget? privateState;

  @override
  Widget build(BuildContext context) {
    if (paged.isPrivate && paged.items.isEmpty && privateState != null) {
      return SliverToBoxAdapter(child: privateState);
    }
    if (paged.items.isEmpty) {
      if (paged.error != null) {
        return SliverToBoxAdapter(child: ErrorState(error: paged.error!, onRetry: paged.retry));
      }
      if (!paged.loaded || paged.loading) return const SliverToBoxAdapter(child: Loading(padding: 60));
      return SliverToBoxAdapter(
        child: empty ?? EmptyState(icon: CupertinoIcons.tray, title: tr('Nada por aquí'), message: tr('Todavía no hay contenido.')),
      );
    }
    final count = paged.items.length;
    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, i) {
          if (i < count) return itemBuilder(context, paged.items[i], i);
          if (paged.error != null) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Center(child: SoftButton(label: tr('Reintentar'), icon: CupertinoIcons.refresh, onPressed: paged.retry)),
            );
          }
          return paged.hasMore ? const Loading(padding: 24) : const _EndMark();
        },
        childCount: count + 1,
      ),
    );
  }
}

class _EndMark extends StatelessWidget {
  const _EndMark();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 26),
      child: Center(child: Container(width: 6, height: 6, decoration: const BoxDecoration(color: Color(0xFF3F3F46), shape: BoxShape.circle))),
    );
  }
}

/// Builder estándar de publicaciones para un Paged<Post>.
Widget Function(BuildContext, Post, int) postBuilder(Paged<Post> paged) => (context, post, i) => PostCard(
      key: ValueKey('post-${post.id}'),
      post: post,
      onRemoved: () => paged.remove((x) => x.id == post.id),
      onReplaced: (updated) {
        final index = paged.items.indexWhere((x) => x.id == post.id);
        if (index >= 0) {
          paged.items[index] = updated;
          paged.changed();
        }
      },
    );
