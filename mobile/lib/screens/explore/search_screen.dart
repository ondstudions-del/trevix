import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../core/i18n.dart';
import '../../core/nav.dart';
import '../../core/paged.dart';
import '../../core/recent_searches.dart';
import '../../core/routes.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';
import '../../widgets/paged_view.dart';
import '../../widgets/user_tile.dart';
import '../communities/community_widgets.dart';
import '../messages/group_screens.dart';

/// Buscar personas, grupos públicos o comunidades (botón de búsqueda del inicio; search?type=…).
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _search = TextEditingController();
  Timer? _debounce;
  String _query = '';
  String _type = 'people';
  final Map<String, Paged<dynamic>> _results = {};

  static Map<String, String> get _types => {'people': tr('Personas'), 'groups': tr('Grupos'), 'communities': tr('Comunidades')};

  @override
  void initState() {
    super.initState();
    recentSearches.load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    for (final p in _results.values) {
      p.dispose();
    }
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      final q = value.trim();
      if (q == _query || !mounted) return;
      for (final p in _results.values) {
        p.dispose();
      }
      _results.clear();
      setState(() => _query = q);
    });
  }

  Paged<dynamic> _paged(String type) => _results.putIfAbsent(type, () {
        dynamic parse(Json j) => switch (type) {
              'people' => User.fromJson(j),
              'groups' => j,
              _ => Community.fromJson(j),
            };
        return Paged<dynamic>('search', parse, query: {'q': _query, 'type': type});
      });

  void _openUser(User user) {
    recentSearches.add(user);
    openProfile(context, user.username);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: GlassBar(
        titleWidget: SizedBox(
          height: 40,
          child: TextField(
            controller: _search,
            autofocus: true,
            onChanged: (v) {
              setState(() {});
              _onChanged(v);
            },
            textInputAction: TextInputAction.search,
            style: Tx.body(15),
            decoration: fieldDecoration(
              tr('Buscar personas, grupos o comunidades'),
              prefix: Icon(CupertinoIcons.search, color: Tx.subtle, size: 19),
              suffix: _search.text.isEmpty
                  ? null
                  : GestureDetector(
                      onTap: () {
                        _search.clear();
                        _onChanged('');
                        setState(() {});
                      },
                      child: Icon(CupertinoIcons.xmark_circle_fill, color: Tx.subtle, size: 18),
                    ),
            ).copyWith(contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 12)),
          ),
        ),
      ),
      body: Column(children: [
        SizedBox(
          height: 52,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
            children: [
              for (final e in _types.entries)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: PillChip(label: e.value, selected: _type == e.key, onTap: () => setState(() => _type = e.key)),
                ),
            ],
          ),
        ),
        Expanded(child: _query.isEmpty ? _idle() : _resultsView()),
      ]),
    );
  }

  Widget _idle() {
    if (_type != 'people') {
      return EmptyState(
        icon: _type == 'groups' ? CupertinoIcons.person_3 : CupertinoIcons.person_2_square_stack,
        title: _type == 'groups' ? tr('Encuentra grupos') : tr('Encuentra comunidades'),
        message: _type == 'groups' ? tr('Escribe el nombre de un grupo público.') : tr('Escribe el nombre o el tema de una comunidad.'),
      );
    }
    return ValueListenableBuilder<List<User>>(
      valueListenable: recentSearches,
      builder: (context, users, _) {
        if (users.isEmpty) {
          return EmptyState(
            icon: CupertinoIcons.search,
            title: tr('Encuentra personas'),
            message: tr('Busca por nombre, usuario, ciudad o intereses.'),
          );
        }
        return ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.only(bottom: 40),
          children: [
            SectionTitle(
              tr('Recientes'),
              trailing: GestureDetector(
                onTap: recentSearches.clear,
                child: Text(tr('Borrar todo'), style: Tx.body(14, weight: FontWeight.w600, color: Tx.accent)),
              ),
            ),
            for (final u in users)
              UserTile(
                key: ValueKey('search-recent-${u.id}'),
                user: u,
                subtitle: '@${u.username}',
                onTap: () => _openUser(u),
                trailing: IconButton(
                  tooltip: tr('Quitar'),
                  icon: Icon(CupertinoIcons.xmark, size: 17, color: Tx.subtle),
                  onPressed: () => recentSearches.remove(u.id),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _resultsView() {
    return PagedView<dynamic>(
      key: ValueKey('search-$_type-$_query'),
      paged: _paged(_type),
      empty: EmptyState(icon: CupertinoIcons.search, title: tr('Sin resultados'), message: tr('No encontramos nada para «{query}».', {'query': _query})),
      itemBuilder: (context, item, i) {
        if (item is User) return UserTile(user: item, onTap: () => _openUser(item));
        if (item is Community) return CommunityTile(community: item);
        if (item is Map<String, dynamic>) return PublicGroupTile(group: item);
        return const SizedBox.shrink();
      },
    );
  }
}
