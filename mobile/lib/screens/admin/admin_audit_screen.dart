import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../models/models.dart';
import '../../core/i18n.dart';
import '../../core/paged.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';
import '../../widgets/paged_view.dart';

class AdminAuditScreen extends StatefulWidget {
  const AdminAuditScreen({super.key});

  @override
  State<AdminAuditScreen> createState() => _AdminAuditScreenState();
}

class _AdminAuditScreenState extends State<AdminAuditScreen> {
  String? _group;
  Map<String, String> _groups = {};
  late Paged<Json> _list = _make();

  Paged<Json> _make() => Paged<Json>(
        'admin/audit',
        (j) => j,
        query: {if (_group != null && _group!.isNotEmpty) 'group': _group!},
        onMeta: (meta) {
          final g = asMap(meta['groups']);
          Future.microtask(() {
            if (mounted) setState(() => _groups = g.map((k, v) => MapEntry(k, asStr(v))));
          });
        },
      );

  void _reload() {
    final old = _list;
    setState(() => _list = _make());
    WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
  }

  @override
  void dispose() {
    _list.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: GlassBar(title: tr('Auditoría')),
      body: PagedView<Json>(
        paged: _list,
        header: [
          SliverToBoxAdapter(
            child: SizedBox(
              height: 52,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
                children: [
                  PillChip(label: tr('Todo'), selected: _group == null, onTap: () {
                    _group = null;
                    _reload();
                  }),
                  for (final e in _groups.entries)
                    Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: PillChip(label: tr(e.value), selected: _group == e.key, onTap: () {
                        _group = e.key;
                        _reload();
                      }),
                    ),
                ],
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 8)),
        ],
        itemBuilder: (context, e, _) => Container(
          margin: const EdgeInsets.fromLTRB(14, 0, 14, 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: Tx.surface1, borderRadius: BorderRadius.circular(14), border: Border.all(color: Tx.border)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(asStr(e['label'], asStr(e['action'])), style: Tx.body(14.5, weight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(
              [if (asStrOrNull(e['admin_username']) != null) '@${e['admin_username']}', timeAgo(asDate(e['created_at']))].join(' · '),
              style: Tx.body(12.5, color: Tx.muted),
            ),
          ]),
        ),
      ),
    );
  }
}