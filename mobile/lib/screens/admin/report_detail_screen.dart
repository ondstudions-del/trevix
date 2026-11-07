import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/catalog.dart';
import '../../core/format.dart';
import '../../core/nav.dart';
import '../../core/routes.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';
import 'admin_screen.dart';

/// Ficha de un objetivo reportado: vista previa, reportes, historial y decisión.
class ReportDetailScreen extends StatefulWidget {
  const ReportDetailScreen({super.key, required this.type, required this.id});

  final String type;
  final int id;

  @override
  State<ReportDetailScreen> createState() => _ReportDetailScreenState();
}

class _ReportDetailScreenState extends State<ReportDetailScreen> {
  Json? _data;
  Object? _error;
  bool _busy = false;

  String get _base => 'admin/reports/${widget.type}/${widget.id}';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await api.get(_base);
      if (mounted) {
        setState(() {
          _data = res.map;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _post(String path, Json body) async {
    setState(() => _busy = true);
    try {
      final res = await api.post(path, body);
      if (!mounted) return;
      toast(context, '${res.map['message'] ?? 'Listo.'}');
      await _load();
    } catch (e) {
      if (mounted) toastError(context, e);
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _dismiss() async {
    final note = await prompt(context, 'Descartar reportes', hint: 'Nota interna (opcional)', action: 'Descartar', maxLength: 255, required: false,
        message: 'El contenido se mantiene y los reportes se cierran.');
    if (note == null || !mounted) return;
    await _post('$_base/dismiss', {if (note.isNotEmpty) 'note': note});
  }

  void _resolve(Json data) {
    final measures = asMap(data['measures']).map((k, v) => MapEntry(k, '$v'));
    actionSheet(context, [
      SheetAction('Resolver sin aplicar medidas', CupertinoIcons.checkmark_circle, () => _apply('none', 'Resolver sin medidas', data)),
      for (final m in measures.entries)
        SheetAction(m.value, _measureIcon(m.key), () => _apply(m.key, m.value, data), destructive: m.key != 'none'),
    ], title: 'Resolver');
  }

  IconData _measureIcon(String key) => switch (key) {
        'hide' => CupertinoIcons.eye_slash,
        'delete' || 'delete_community' => CupertinoIcons.trash,
        'suspend_user' => CupertinoIcons.person_crop_circle_badge_xmark,
        'suspend_community' => CupertinoIcons.pause_circle,
        _ => CupertinoIcons.hammer,
      };

  Future<void> _apply(String measure, String label, Json data) async {
    int? days;
    if (measure == 'suspend_user') {
      final durations = asMap(data['durations']).map((k, v) => MapEntry(int.tryParse(k) ?? 0, '$v'));
      if (durations.isEmpty) return;
      final picked = await showModalBottomSheet<int>(
        context: context,
        backgroundColor: Colors.transparent,
        builder: (ctx) => SheetFrame(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Padding(padding: const EdgeInsets.fromLTRB(20, 4, 20, 10), child: Text('Duración de la suspensión', textAlign: TextAlign.center, style: Tx.display(17))),
            for (final d in durations.entries)
              ListTile(
                leading: Icon(d.key == 0 ? CupertinoIcons.infinite : CupertinoIcons.timer, color: d.key == 0 ? Tx.danger : Tx.text),
                title: Text(d.value, style: Tx.body(16)),
                onTap: () => Navigator.pop(ctx, d.key),
              ),
          ]),
        ),
      );
      if (picked == null) return;
      days = picked;
    }
    if (!mounted) return;
    final needsReason = measure.startsWith('suspend') || measure == 'delete_community';
    final note = await prompt(
      context,
      label,
      hint: needsReason ? 'Motivo' : 'Nota interna (opcional)',
      action: 'Aplicar',
      maxLength: 255,
      required: needsReason,
      message: measure == 'none' ? 'Los reportes se marcarán como resueltos sin cambiar el contenido.' : 'Quedará registrado en la auditoría.',
    );
    if (note == null || !mounted) return;
    await _post('$_base/resolve', {
      'measure': measure,
      if (days != null) 'days': days,
      if (note.isNotEmpty) 'note': note,
    });
  }

  void _openTarget(Json preview) {
    final row = asMap(preview['row']);
    final author = asMap(preview['author']);
    switch (widget.type) {
      case 'post':
        if (asStr(preview['status']) == 'published') openPost(context, widget.id);
      case 'comment':
        if (asIntOrNull(row['post_id']) != null) openPost(context, asInt(row['post_id']));
      case 'user':
        openProfile(context, asStr(author['username']));
      case 'community':
        if (asStrOrNull(row['slug']) != null) openCommunity(context, asStr(row['slug']));
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    return Scaffold(
      appBar: GlassBar(title: reportTypes[widget.type] ?? 'Reporte'),
      body: data == null
          ? (_error != null ? ErrorState(error: _error!, onRetry: _load) : const Loading())
          : _content(data),
    );
  }

  Widget _content(Json data) {
    final preview = asMapOrNull(data['preview']);
    final reports = asList(data['reports'], (j) => j);
    final history = asList(data['history'], (j) => j);
    final pending = asInt(data['pending']);
    final reviewing = asBool(data['reviewing']);
    final author = preview == null ? null : asMap(preview['author']);
    final media = preview == null ? null : asStrOrNull(preview['media']);
    final canOpen = preview != null && (widget.type == 'post' || widget.type == 'comment' || widget.type == 'user' || widget.type == 'community');

    return RefreshIndicator(
      onRefresh: _load,
      color: Tx.purple400,
      child: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 60), children: [
        Panel(
          onTap: canOpen ? () => _openTarget(preview) : null,
          child: preview == null
              ? Text('Este contenido ya no existe.', style: Tx.body(14.5, color: Tx.muted))
              : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Icon(reportTypeIcon(widget.type), color: Tx.danger, size: 18),
                    const SizedBox(width: 8),
                    Expanded(child: Text(asStr(preview['title']), style: Tx.body(15.5, weight: FontWeight.w700))),
                    _StatusPill(status: asStr(preview['status'])),
                  ]),
                  if (asStr(preview['excerpt']).trim().isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text(asStr(preview['excerpt']).trim(), style: Tx.body(14.5, height: 1.45)),
                  ],
                  if (media != null && media.startsWith('http')) ...[
                    const SizedBox(height: 10),
                    NetImage(media, height: 200, width: double.infinity, radius: 14),
                  ],
                  if (author != null) ...[
                    const SizedBox(height: 12),
                    GestureDetector(
                      onTap: () => openProfile(context, asStr(author['username'])),
                      child: Row(children: [
                        Avatar(
                          user: User(
                            id: asInt(author['id']),
                            username: asStr(author['username']),
                            displayName: asStr(author['display_name'], asStr(author['username'])),
                            avatarUrl: asStrOrNull(author['avatar_path']),
                          ),
                          size: 26,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '${asStr(author['display_name'])} · @${author['username']}${asStr(author['role']) != 'user' ? ' · ${author['role']}' : ''}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Tx.body(13, color: Tx.muted),
                          ),
                        ),
                      ]),
                    ),
                  ],
                  if (asStrOrNull(preview['suspended_until']) != null || asStrOrNull(preview['suspension_reason']) != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Suspendida${asDate(preview['suspended_until']) != null ? ' hasta ${fullDate(asDate(preview['suspended_until']))}' : ''}'
                      '${asStrOrNull(preview['suspension_reason']) != null ? ': ${preview['suspension_reason']}' : ''}',
                      style: Tx.body(12.5, color: Tx.warning),
                    ),
                  ],
                  if (canOpen) ...[
                    const SizedBox(height: 10),
                    Text('Toca para abrir', style: Tx.body(12, color: Tx.purple300)),
                  ],
                ]),
        ),
        const SizedBox(height: 14),
        if (pending > 0)
          _busy
              ? const Padding(padding: EdgeInsets.all(14), child: Center(child: CupertinoActivityIndicator()))
              : Column(children: [
                  if (!reviewing)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: SoftButton(label: 'Marcar «en revisión»', icon: CupertinoIcons.eye, expand: true, height: 44, onPressed: () => _post('$_base/take', {})),
                    ),
                  Row(children: [
                    Expanded(child: SoftButton(label: 'Descartar', icon: CupertinoIcons.xmark, height: 46, onPressed: _dismiss)),
                    const SizedBox(width: 10),
                    Expanded(child: GradientButton(label: 'Resolver', icon: CupertinoIcons.hammer_fill, height: 46, onPressed: () => _resolve(data))),
                  ]),
                ])
        else
          Panel(
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              const Icon(CupertinoIcons.checkmark_shield_fill, color: Tx.success),
              const SizedBox(width: 10),
              Expanded(child: Text('No hay reportes pendientes para este objetivo.', style: Tx.body(13.5, color: Tx.muted))),
            ]),
          ),
        SectionTitle('Reportes (${reports.length})', padding: const EdgeInsets.fromLTRB(4, 22, 4, 8)),
        for (final r in reports)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Tx.surface1, borderRadius: BorderRadius.circular(16), border: Border.all(color: Tx.border)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(
                  child: Text(reportReasons[asStr(r['reason'])] ?? asStr(r['reason']), style: Tx.body(14, weight: FontWeight.w600)),
                ),
                _StatusPill(status: asStr(r['status'])),
              ]),
              if (asStr(r['details']).trim().isNotEmpty)
                Padding(padding: const EdgeInsets.only(top: 6), child: Text(asStr(r['details']).trim(), style: Tx.body(13.5, color: Tx.muted))),
              const SizedBox(height: 6),
              Text(
                [
                  if (asStrOrNull(r['reporter_username']) != null) 'por @${r['reporter_username']}',
                  timeAgo(asDate(r['created_at'])),
                  if (asStrOrNull(r['reviewer_username']) != null) 'revisó @${r['reviewer_username']}',
                ].join(' · '),
                style: Tx.body(12, color: Tx.subtle),
              ),
              if (asStr(r['resolution_note']).trim().isNotEmpty)
                Padding(padding: const EdgeInsets.only(top: 4), child: Text('Nota: ${asStr(r['resolution_note']).trim()}', style: Tx.body(12.5, color: Tx.muted))),
            ]),
          ),
        if (history.isNotEmpty) ...[
          SectionTitle('Historial', padding: const EdgeInsets.fromLTRB(4, 22, 4, 8)),
          for (final h in history)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Padding(padding: EdgeInsets.only(top: 3), child: Icon(CupertinoIcons.circle_fill, size: 8, color: Tx.purple400)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '${asStr(h['label'], asStr(h['action']))}${asStrOrNull(h['admin_username']) != null ? ' · @${h['admin_username']}' : ''} · ${timeAgo(asDate(h['created_at']))}',
                    style: Tx.body(13, color: Tx.muted),
                  ),
                ),
              ]),
            ),
        ],
      ]),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      'open' => ('Abierto', Tx.danger),
      'reviewing' => ('En revisión', Tx.warning),
      'resolved' => ('Resuelto', Tx.success),
      'dismissed' => ('Descartado', Tx.muted),
      'published' || 'active' => ('Visible', Tx.success),
      'hidden' => ('Oculto', Tx.warning),
      'suspended' => ('Suspendido', Tx.warning),
      'removed' || 'deleted' => ('Eliminado', Tx.muted),
      _ => (status, Tx.muted),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: Tx.alpha(color, .14), borderRadius: BorderRadius.circular(8)),
      child: Text(label, style: Tx.body(11.5, weight: FontWeight.w700, color: color)),
    );
  }
}
