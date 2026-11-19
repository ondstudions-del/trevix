import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../models/models.dart';
import '../../core/i18n.dart';
import '../../core/nav.dart';
import '../../core/paged.dart';
import '../../core/routes.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';
import '../../widgets/paged_view.dart';

class AdminContentScreen extends StatefulWidget {
  const AdminContentScreen({super.key});

  @override
  State<AdminContentScreen> createState() => _AdminContentScreenState();
}

class _AdminContentScreenState extends State<AdminContentScreen> {
  String _kind = 'posts';
  String? _postStatus;
  final _q = TextEditingController();
  late Paged<Json> _posts = _makePosts();
  late Paged<Json> _comments = _makeComments();

  Paged<Json> _makePosts() => Paged<Json>(
        'admin/posts',
        (j) => j,
        query: {
          if (_q.text.trim().isNotEmpty) 'q': _q.text.trim(),
          if (_postStatus != null) 'status': _postStatus!,
        },
      );

  Paged<Json> _makeComments() => Paged<Json>(
        'admin/comments',
        (j) => j,
        query: {if (_q.text.trim().isNotEmpty) 'q': _q.text.trim()},
      );

  Paged<Json> get _active => _kind == 'posts' ? _posts : _comments;

  void _reload() {
    final oldP = _posts;
    final oldC = _comments;
    setState(() {
      _posts = _makePosts();
      _comments = _makeComments();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      oldP.dispose();
      oldC.dispose();
    });
  }

  @override
  void dispose() {
    _q.dispose();
    _posts.dispose();
    _comments.dispose();
    super.dispose();
  }

  Future<void> _postAct(Json p, String action) async {
    final id = asInt(p['id']);
    try {
      ApiResponse res;
      if (action == 'delete') {
        res = await api.delete('admin/posts/$id');
      } else {
        res = await api.post('admin/posts/$id/$action', {});
      }
      if (!mounted) return;
      toast(context, asStr(res.map['message'], tr('Listo.')));
      _posts.refresh();
    } catch (e) {
      if (mounted) toastError(context, e);
    }
  }

  Future<void> _feature(Json p, bool on) async {
    final id = asInt(p['id']);
    try {
      final res = on ? await api.post('admin/posts/$id/feature', {}) : await api.delete('admin/posts/$id/feature');
      if (!mounted) return;
      toast(context, asStr(res.map['message'], tr('Listo.')));
      _posts.refresh();
    } catch (e) {
      if (mounted) toastError(context, e);
    }
  }

  Future<void> _deleteComment(Json c) async {
    try {
      final res = await api.delete('admin/comments/${asInt(c['id'])}');
      if (!mounted) return;
      toast(context, asStr(res.map['message'], tr('Listo.')));
      _comments.refresh();
    } catch (e) {
      if (mounted) toastError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = context.watch<AppState>().me?.isAdmin ?? false;
    return Scaffold(
      appBar: GlassBar(title: tr('Contenido')),
      body: PagedView<Json>(
        paged: _active,
        header: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
              child: CupertinoSlidingSegmentedControl<String>(
                groupValue: _kind,
                backgroundColor: Tx.surface3,
                thumbColor: Tx.purple700,
                children: {
                  'posts': Padding(padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12), child: Text(tr('Publicaciones'), style: Tx.body(13, weight: FontWeight.w600))),
                  'comments': Padding(padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12), child: Text(tr('Comentarios'), style: Tx.body(13, weight: FontWeight.w600))),
                },
                onValueChanged: (v) {
                  if (v == null) return;
                  setState(() => _kind = v);
                },
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
              child: TextField(
                controller: _q,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => _reload(),
                decoration: fieldDecoration(tr('Buscar')).copyWith(
                  suffixIcon: IconButton(icon: const Icon(CupertinoIcons.search), onPressed: _reload),
                ),
              ),
            ),
          ),
          if (_kind == 'posts')
            SliverToBoxAdapter(
              child: SizedBox(
                height: 48,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
                  children: [
                    PillChip(label: tr('Todas'), selected: _postStatus == null, onTap: () {
                      _postStatus = null;
                      _reload();
                    }),
                    PillChip(label: tr('Publicadas'), selected: _postStatus == 'published', onTap: () {
                      _postStatus = 'published';
                      _reload();
                    }),
                    PillChip(label: tr('Ocultas'), selected: _postStatus == 'hidden', onTap: () {
                      _postStatus = 'hidden';
                      _reload();
                    }),
                  ],
                ),
              ),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 8)),
        ],
        itemBuilder: (context, item, _) {
          if (_kind == 'posts') {
            final status = asStr(item['status']);
            return Container(
              margin: const EdgeInsets.fromLTRB(14, 0, 14, 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Tx.surface1, borderRadius: BorderRadius.circular(16), border: Border.all(color: Tx.border)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(asStr(item['caption']).trim().isEmpty ? tr('(sin texto)') : asStr(item['caption']), maxLines: 3, overflow: TextOverflow.ellipsis, style: Tx.body(14.5)),
                const SizedBox(height: 4),
                Text('@${item['username']} · $status · ${timeAgo(asDate(item['created_at']))}', style: Tx.body(12, color: Tx.muted)),
                const SizedBox(height: 10),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  if (status == 'published')
                    SoftButton(label: tr('Ocultar'), height: 36, onPressed: () => _postAct(item, 'hide'))
                  else if (status == 'hidden')
                    SoftButton(label: tr('Restaurar'), height: 36, onPressed: () => _postAct(item, 'restore')),
                  SoftButton(label: tr('Eliminar'), height: 36, color: Tx.danger, onPressed: () => _postAct(item, 'delete')),
                  TextButton(onPressed: () => openPost(context, asInt(item['id'])), child: Text(tr('Abrir'), style: Tx.body(13, color: Tx.accent))),
                  if (isAdmin)
                    SoftButton(
                      label: asBool(item['is_featured']) ? tr('Quitar destacado') : tr('Destacar'),
                      height: 36,
                      onPressed: () => _feature(item, !asBool(item['is_featured'])),
                    ),
                ]),
              ]),
            );
          }
          return Container(
            margin: const EdgeInsets.fromLTRB(14, 0, 14, 10),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Tx.surface1, borderRadius: BorderRadius.circular(16), border: Border.all(color: Tx.border)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(asStr(item['body']), maxLines: 4, overflow: TextOverflow.ellipsis, style: Tx.body(14.5)),
              const SizedBox(height: 4),
              Text('@${item['username']} · ${timeAgo(asDate(item['created_at']))}', style: Tx.body(12, color: Tx.muted)),
              const SizedBox(height: 10),
              Row(children: [
                SoftButton(label: tr('Eliminar'), height: 36, color: Tx.danger, onPressed: () => _deleteComment(item)),
                const SizedBox(width: 8),
                if (item['post_id'] != null)
                  TextButton(onPressed: () => openPost(context, asInt(item['post_id'])), child: Text(tr('Ver publicación'), style: Tx.body(13, color: Tx.accent))),
              ]),
            ]),
          );
        },
      ),
    );
  }
}