import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../models/models.dart';
import '../../core/i18n.dart';
import '../../core/nav.dart';
import '../../core/paged.dart';
import '../../core/routes.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';
import '../../widgets/paged_view.dart';

class AdminCommunitiesScreen extends StatefulWidget {
  const AdminCommunitiesScreen({super.key});

  @override
  State<AdminCommunitiesScreen> createState() => _AdminCommunitiesScreenState();
}

class _AdminCommunitiesScreenState extends State<AdminCommunitiesScreen> {
  final _q = TextEditingController();
  String? _status;
  late Paged<Json> _list = _make();

  Paged<Json> _make() => Paged<Json>(
        'admin/communities',
        (j) => j,
        query: {
          if (_q.text.trim().isNotEmpty) 'q': _q.text.trim(),
          if (_status != null) 'status': _status!,
        },
      );

  void _reload() {
    final old = _list;
    setState(() => _list = _make());
    WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
  }

  @override
  void dispose() {
    _q.dispose();
    _list.dispose();
    super.dispose();
  }

  Future<void> _act(Json c, String action) async {
    final id = asInt(c['id']);
    final name = asStr(c['name']);
    String? note;
    if (action == 'suspend' || action == 'delete') {
      note = await prompt(context, action == 'suspend' ? tr('Suspender «{name}»', {'name': name}) : tr('Eliminar «{name}»', {'name': name}), hint: tr('Motivo'), action: action == 'suspend' ? tr('Suspender') : tr('Eliminar'), maxLength: 255);
      if (note == null) return;
    }
    try {
      final res = switch (action) {
        'suspend' => await api.post('admin/communities/$id/suspend', {'reason': note}),
        'restore' => await api.post('admin/communities/$id/restore', {}),
        'delete' => await api.delete('admin/communities/$id', {'reason': note}),
        _ => throw StateError(action),
      };
      if (!mounted) return;
      toast(context, asStr(res.map['message'], tr('Listo.')));
      _list.refresh();
    } catch (e) {
      if (mounted) toastError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: GlassBar(title: tr('Comunidades')),
      body: PagedView<Json>(
        paged: _list,
        header: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
              child: TextField(
                controller: _q,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => _reload(),
                decoration: fieldDecoration(tr('Buscar comunidad')).copyWith(
                  suffixIcon: IconButton(icon: const Icon(CupertinoIcons.search), onPressed: _reload),
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: SizedBox(
              height: 48,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
                children: [
                  PillChip(label: tr('Activas'), selected: _status == null, onTap: () {
                    _status = null;
                    _reload();
                  }),
                  PillChip(label: tr('Suspendidas'), selected: _status == 'suspended', onTap: () {
                    _status = 'suspended';
                    _reload();
                  }),
                ],
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 8)),
        ],
        itemBuilder: (context, c, _) {
          final status = asStr(c['status']);
          return Container(
            margin: const EdgeInsets.fromLTRB(14, 0, 14, 10),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Tx.surface1, borderRadius: BorderRadius.circular(16), border: Border.all(color: Tx.border)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(asStr(c['name']), style: Tx.body(16, weight: FontWeight.w600)),
              Text('@${c['slug']} · $status · ${compact(asInt(c['members_count']))} ${tr('miembros')}', style: Tx.body(12.5, color: Tx.muted)),
              const SizedBox(height: 10),
              Wrap(spacing: 8, runSpacing: 8, children: [
                TextButton(onPressed: () => openCommunity(context, asStr(c['slug'])), child: Text(tr('Abrir'), style: Tx.body(13, color: Tx.accent))),
                if (status == 'active')
                  SoftButton(label: tr('Suspender'), height: 36, color: Tx.danger, onPressed: () => _act(c, 'suspend'))
                else if (status == 'suspended')
                  SoftButton(label: tr('Reactivar'), height: 36, onPressed: () => _act(c, 'restore')),
                SoftButton(label: tr('Eliminar'), height: 36, color: Tx.danger, onPressed: () => _act(c, 'delete')),
              ]),
            ]),
          );
        },
      ),
    );
  }
}