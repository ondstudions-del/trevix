import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../core/catalog.dart';
import '../../core/i18n.dart';
import '../../core/nav.dart';
import '../../core/paged.dart';
import '../../core/routes.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';
import '../../widgets/paged_view.dart';
import 'community_form_screen.dart';
import 'community_widgets.dart';

class CommunitiesScreen extends StatefulWidget {
  const CommunitiesScreen({super.key});

  @override
  State<CommunitiesScreen> createState() => _CommunitiesScreenState();
}

class _CommunitiesScreenState extends State<CommunitiesScreen> {
  String _tab = 'discover';
  String? _category;
  final _search = TextEditingController();
  Timer? _debounce;
  late Paged<Community> _list = _make();

  Paged<Community> _make() => Paged<Community>('communities', Community.fromJson, query: {
        'tab': _tab,
        if (_tab == 'discover' && _category != null) 'category': _category,
        if (_tab == 'discover' && _search.text.trim().isNotEmpty) 'q': _search.text.trim(),
      });

  void _reload() {
    final old = _list;
    setState(() => _list = _make());
    WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    _list.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: GlassBar(
        title: tr('Comunidades'),
        actions: [
          IconButton(
            onPressed: () async {
              final created = await push<Community>(context, const CommunityFormScreen(), fullscreen: true);
              if (created != null && context.mounted) {
                openCommunity(context, created.slug);
                _reload();
              }
            },
            icon: Icon(CupertinoIcons.add_circled, color: Tx.text),
          ),
        ],
      ),
      body: PagedView<Community>(
        paged: _list,
        header: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              child: Row(children: [
                PillChip(label: tr('Descubrir'), icon: CupertinoIcons.compass, selected: _tab == 'discover', onTap: () {
                  _tab = 'discover';
                  _reload();
                }),
                const SizedBox(width: 8),
                PillChip(label: tr('Mis comunidades'), icon: CupertinoIcons.person_3, selected: _tab == 'mine', onTap: () {
                  _tab = 'mine';
                  _reload();
                }),
              ]),
            ),
          ),
          if (_tab == 'discover') ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                child: TextField(
                  controller: _search,
                  onChanged: (_) {
                    _debounce?.cancel();
                    _debounce = Timer(const Duration(milliseconds: 400), _reload);
                  },
                  style: Tx.body(15),
                  decoration: fieldDecoration(tr('Buscar comunidades'), prefix: Icon(CupertinoIcons.search, color: Tx.subtle, size: 20)),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: SizedBox(
                height: 50,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: PillChip(label: tr('Todas'), selected: _category == null, onTap: () {
                        _category = null;
                        _reload();
                      }),
                    ),
                    for (final c in communityCategories)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: PillChip(label: tr(c), selected: _category == c, onTap: () {
                          _category = c;
                          _reload();
                        }),
                      ),
                  ],
                ),
              ),
            ),
          ],
          const SliverToBoxAdapter(child: SizedBox(height: 6)),
        ],
        empty: EmptyState(
          icon: CupertinoIcons.person_3,
          title: _tab == 'mine' ? tr('Aún no te uniste a ninguna') : tr('Sin comunidades'),
          message: _tab == 'mine' ? tr('Descubre comunidades o crea la tuya.') : tr('Prueba con otra búsqueda o categoría.'),
        ),
        itemBuilder: (context, c, _) => CommunityTile(community: c),
      ),
    );
  }
}
