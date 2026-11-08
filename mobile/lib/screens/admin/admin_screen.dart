import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/audio.dart';
import '../../core/catalog.dart';
import '../../core/config.dart';
import '../../core/format.dart';
import '../../core/nav.dart';
import '../../core/paged.dart';
import '../../core/routes.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';
import '../../widgets/paged_view.dart';
import '../../widgets/song_chip.dart';
import 'report_detail_screen.dart';

const reportTypes = {
  'post': 'Publicación',
  'comment': 'Comentario',
  'user': 'Cuenta',
  'community': 'Comunidad',
  'message': 'Mensaje',
  'story': 'Historia',
};

IconData reportTypeIcon(String type) => switch (type) {
      'post' => CupertinoIcons.square_grid_2x2,
      'comment' => CupertinoIcons.chat_bubble,
      'user' => CupertinoIcons.person,
      'community' => CupertinoIcons.person_3,
      'message' => CupertinoIcons.envelope,
      'story' => CupertinoIcons.circle_grid_hex,
      _ => CupertinoIcons.flag,
    };

/// Panel de moderación para el equipo (resumen, reportes y revisión de música).
class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  String _tab = 'summary';

  @override
  void dispose() {
    if (songPlayer.currentKey?.startsWith('review:') ?? false) songPlayer.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final admin = context.read<AppState>().me?.isAdmin ?? false;
    final tabs = ['summary', 'reports', 'music', if (admin) 'verification'];
    return Scaffold(
      appBar: GlassBar(
        title: 'Moderación',
        actions: [
          IconButton(
            tooltip: 'Panel web',
            onPressed: () => openInApp(context, AppConfig.web('admin/')),
            icon: Icon(CupertinoIcons.globe, color: Tx.text),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(50),
          child: SizedBox(
            height: 50,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
              children: [
                PillChip(label: 'Resumen', icon: CupertinoIcons.chart_bar_alt_fill, selected: _tab == 'summary', onTap: () => setState(() => _tab = 'summary')),
                const SizedBox(width: 8),
                PillChip(label: 'Reportes', icon: CupertinoIcons.flag_fill, selected: _tab == 'reports', onTap: () => setState(() => _tab = 'reports')),
                const SizedBox(width: 8),
                PillChip(label: 'Música', icon: CupertinoIcons.music_note_2, selected: _tab == 'music', onTap: () => setState(() => _tab = 'music')),
                if (admin) ...[
                  const SizedBox(width: 8),
                  PillChip(
                    label: 'Verificado',
                    icon: CupertinoIcons.checkmark_seal_fill,
                    selected: _tab == 'verification',
                    onTap: () => setState(() => _tab = 'verification'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      body: IndexedStack(
        index: tabs.indexOf(_tab).clamp(0, tabs.length - 1),
        children: [
          _Summary(onOpen: (tab) => setState(() => _tab = tab)),
          const _Reports(),
          const _MusicReview(),
          if (admin) const _VerificationReview(),
        ],
      ),
    );
  }
}

class _Summary extends StatefulWidget {
  const _Summary({required this.onOpen});

  final ValueChanged<String> onOpen;

  @override
  State<_Summary> createState() => _SummaryState();
}

class _SummaryState extends State<_Summary> {
  Json? _data;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await api.get('admin/dashboard');
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

  @override
  Widget build(BuildContext context) {
    final data = _data;
    if (data == null) return _error != null ? ErrorState(error: _error!, onRetry: _load) : const Loading();
    final stats = asMap(data['stats']);
    final reports = asList(data['reports'], (j) => j);
    final audit = data['audit'] is List ? asList(data['audit'], (j) => j) : null;
    final cards = [
      ('Cuentas', 'users', CupertinoIcons.person_2_fill, Tx.accentSoft),
      ('Activas (7 días)', 'active_users', CupertinoIcons.bolt_fill, Tx.success),
      ('Publicaciones', 'posts', CupertinoIcons.square_grid_2x2_fill, Tx.blue400),
      ('Comunidades', 'communities', CupertinoIcons.person_3_fill, Tx.cyan),
      ('Reportes abiertos', 'open_reports', CupertinoIcons.flag_fill, Tx.danger),
      ('Reportes hoy', 'reports_today', CupertinoIcons.clock_fill, Tx.warning),
      ('Canciones en revisión', 'pending_songs', CupertinoIcons.music_note_2, Tx.pink),
      ('Canciones publicadas', 'published_songs', CupertinoIcons.music_albums_fill, Tx.accent),
      ('Cuentas suspendidas', 'suspended_users', CupertinoIcons.person_crop_circle_badge_xmark, Tx.muted),
      ('Publicaciones ocultas', 'hidden_posts', CupertinoIcons.eye_slash_fill, Tx.muted),
      if (data['pending_verifications'] != null) ('Verificados por revisar', 'pending_verifications', CupertinoIcons.checkmark_seal_fill, Tx.blue400),
    ];
    final values = {...stats, 'pending_verifications': data['pending_verifications']};
    return RefreshIndicator(
      onRefresh: _load,
      color: Tx.accentSoft,
      child: ListView(padding: const EdgeInsets.fromLTRB(14, 14, 14, 60), children: [
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 1.65,
          children: [
            for (final c in cards)
              GestureDetector(
                onTap: c.$2 == 'open_reports' || c.$2 == 'reports_today'
                    ? () => widget.onOpen('reports')
                    : c.$2 == 'pending_songs'
                        ? () => widget.onOpen('music')
                        : c.$2 == 'pending_verifications'
                            ? () => widget.onOpen('verification')
                            : null,
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: Tx.surface1, borderRadius: BorderRadius.circular(18), border: Border.all(color: Tx.border)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    Icon(c.$3, color: c.$4, size: 20),
                    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(compact(asInt(values[c.$2])), style: Tx.display(22)),
                      Text(c.$1, maxLines: 1, overflow: TextOverflow.ellipsis, style: Tx.body(12, color: Tx.muted)),
                    ]),
                  ]),
                ),
              ),
          ],
        ),
        SectionTitle('Últimos reportes', padding: const EdgeInsets.fromLTRB(4, 24, 4, 10),
            trailing: TextButton(onPressed: () => widget.onOpen('reports'), child: Text('Ver todos', style: Tx.body(13.5, color: Tx.accent)))),
        if (reports.isEmpty)
          Panel(child: Text('No hay reportes abiertos. ¡Todo en orden!', style: Tx.body(14, color: Tx.muted)))
        else
          for (final r in reports) ReportTargetTile(target: r, onChanged: _load),
        if (audit != null) ...[
          SectionTitle('Auditoría reciente', padding: const EdgeInsets.fromLTRB(4, 24, 4, 10)),
          Container(
            decoration: BoxDecoration(color: Tx.surface1, borderRadius: BorderRadius.circular(18), border: Border.all(color: Tx.border)),
            child: Column(children: [
              for (final a in audit)
                ListTile(
                  dense: true,
                  leading: Icon(CupertinoIcons.doc_text_search, color: Tx.subtle, size: 20),
                  title: Text(asStr(a['label'], asStr(a['action'])), maxLines: 2, overflow: TextOverflow.ellipsis, style: Tx.body(13.5)),
                  subtitle: Text(
                    [if (asStrOrNull(a['admin_username']) != null) '@${a['admin_username']}', timeAgo(asDate(a['created_at']))].join(' · '),
                    style: Tx.body(12, color: Tx.subtle),
                  ),
                ),
            ]),
          ),
        ],
      ]),
    );
  }
}

/// Fila de un objetivo reportado (agrupa todos sus reportes).
class ReportTargetTile extends StatelessWidget {
  const ReportTargetTile({super.key, required this.target, required this.onChanged});

  final Json target;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final type = asStr(target['type']);
    final id = asInt(target['id']);
    final preview = asMapOrNull(target['preview']);
    final rawReasons = target['reasons'];
    final reasons = (rawReasons is List ? rawReasons : const []).map((e) => reportReasons['$e'] ?? '$e').toList();
    final media = preview == null ? null : asStrOrNull(preview['media']);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Tx.surface1,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: asBool(target['reviewing']) ? Tx.alpha(Tx.warning, .5) : Tx.border),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () async {
            await push(context, ReportDetailScreen(type: type, id: id));
            onChanged();
          },
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: Tx.alpha(Tx.danger, .14), borderRadius: BorderRadius.circular(12)),
                child: Icon(reportTypeIcon(type), color: Tx.danger, size: 19),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Text(reportTypes[type] ?? type, style: Tx.body(12, weight: FontWeight.w700, color: Tx.danger)),
                    const SizedBox(width: 6),
                    Text('· ${plural(asInt(target['reports_count']), 'reporte', 'reportes')}', style: Tx.body(12, color: Tx.muted)),
                    if (asBool(target['reviewing'])) ...[
                      const SizedBox(width: 6),
                      Text('· En revisión', style: Tx.body(12, weight: FontWeight.w600, color: Tx.warning)),
                    ],
                  ]),
                  const SizedBox(height: 3),
                  Text(preview == null ? 'Ya no existe' : asStr(preview['title']), maxLines: 1, overflow: TextOverflow.ellipsis, style: Tx.body(14.5, weight: FontWeight.w600)),
                  if (preview != null && asStr(preview['excerpt']).trim().isNotEmpty)
                    Text(asStr(preview['excerpt']).trim(), maxLines: 2, overflow: TextOverflow.ellipsis, style: Tx.body(13, color: Tx.muted)),
                  const SizedBox(height: 4),
                  Text('${reasons.join(', ')} · ${timeAgo(asDate(target['last_reported_at']))}',
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: Tx.body(12, color: Tx.subtle)),
                ]),
              ),
              if (media != null && media.startsWith('http')) ...[
                const SizedBox(width: 10),
                NetImage(media, width: 52, height: 52, radius: 10),
              ],
            ]),
          ),
        ),
      ),
    );
  }
}

class _Reports extends StatefulWidget {
  const _Reports();

  @override
  State<_Reports> createState() => _ReportsState();
}

class _ReportsState extends State<_Reports> {
  String _status = 'open';
  String? _type;
  Map<String, int> _openByType = {};
  late Paged<Json> _list = _make();

  Paged<Json> _make() => Paged<Json>('admin/reports', (j) => j, query: {'status': _status, if (_type != null) 'type': _type}, onMeta: (meta) {
        final counts = asMap(meta['open_by_type']).map((k, v) => MapEntry(k, asInt(v)));
        Future.microtask(() {
          if (mounted) setState(() => _openByType = counts);
        });
      });

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
    return PagedView<Json>(
      paged: _list,
      header: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
            child: CupertinoSlidingSegmentedControl<String>(
              groupValue: _status,
              backgroundColor: Tx.surface3,
              thumbColor: Tx.purple700,
              children: {
                for (final e in const {'open': 'Abiertos', 'resolved': 'Resueltos', 'dismissed': 'Descartados'}.entries)
                  e.key: Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Text(e.value, style: Tx.body(13, weight: FontWeight.w600))),
              },
              onValueChanged: (v) {
                if (v == null || v == _status) return;
                _status = v;
                _reload();
              },
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: SizedBox(
            height: 52,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: PillChip(label: 'Todo', selected: _type == null, onTap: () {
                    _type = null;
                    _reload();
                  }),
                ),
                for (final e in reportTypes.entries)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: PillChip(
                      label: (_openByType[e.key] ?? 0) > 0 ? '${e.value} (${_openByType[e.key]})' : e.value,
                      selected: _type == e.key,
                      onTap: () {
                        _type = e.key;
                        _reload();
                      },
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 8)),
      ],
      empty: EmptyState(
        icon: CupertinoIcons.checkmark_shield,
        title: _status == 'open' ? 'Sin reportes abiertos' : 'Nada por aquí',
        message: _status == 'open' ? 'Cuando alguien reporte contenido aparecerá aquí.' : null,
      ),
      itemBuilder: (context, t, _) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: ReportTargetTile(target: t, onChanged: () => _list.refresh()),
      ),
    );
  }
}

class _MusicReview extends StatefulWidget {
  const _MusicReview();

  @override
  State<_MusicReview> createState() => _MusicReviewState();
}

class _MusicReviewState extends State<_MusicReview> {
  String _status = 'pending';
  Map<String, int> _counts = {};
  final Set<int> _busy = {};
  late Paged<Json> _list = _make();

  static const _statuses = {
    'pending': 'En revisión',
    'published': 'Publicadas',
    'rejected': 'Rechazadas',
    'withdrawn': 'Retiradas',
    'removed': 'Por moderación',
  };

  Paged<Json> _make() => Paged<Json>('admin/music', (j) => j, query: {'status': _status}, onMeta: (meta) {
        final counts = asMap(meta['counts']).map((k, v) => MapEntry(k, asInt(v)));
        Future.microtask(() {
          if (mounted) setState(() => _counts = counts);
        });
      });

  void _switch(String status) {
    if (status == _status) return;
    final old = _list;
    setState(() {
      _status = status;
      _list = _make();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
  }

  @override
  void dispose() {
    _list.dispose();
    super.dispose();
  }

  Future<void> _act(Json s, String action) async {
    final id = asInt(s['id']);
    final title = asStr(s['title']);
    final body = <String, dynamic>{};
    if (action == 'reject' || action == 'remove') {
      final reason = await prompt(
        context,
        action == 'reject' ? 'Rechazar «$title»' : 'Retirar «$title»',
        hint: 'Motivo (lo verá el artista)',
        action: action == 'reject' ? 'Rechazar' : 'Retirar',
        maxLength: 255,
      );
      if (reason == null) return;
      body['reason'] = reason;
    } else {
      final note = await prompt(
        context,
        action == 'approve' ? 'Aprobar «$title»' : 'Restaurar «$title»',
        hint: 'Nota para el artista (opcional)',
        action: action == 'approve' ? 'Aprobar' : 'Restaurar',
        maxLength: 255,
        required: false,
      );
      if (note == null) return;
      if (note.isNotEmpty) body['note'] = note;
    }
    if (!mounted) return;
    setState(() => _busy.add(id));
    try {
      final res = await api.post('admin/music/$id/$action', body);
      if (!mounted) return;
      toast(context, '${res.map['message'] ?? 'Listo.'}');
      songPlayer.stop('review:$id');
      _list.remove((x) => asInt(x['id']) == id);
      setState(() {
        _counts[_status] = ((_counts[_status] ?? 1) - 1).clamp(0, 1 << 30);
      });
    } catch (e) {
      if (mounted) toastError(context, e);
    }
    if (mounted) setState(() => _busy.remove(id));
  }

  @override
  Widget build(BuildContext context) {
    return PagedView<Json>(
      paged: _list,
      header: [
        SliverToBoxAdapter(
          child: SizedBox(
            height: 54,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
              children: [
                for (final e in _statuses.entries)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: PillChip(
                      label: (_counts[e.key] ?? 0) > 0 ? '${e.value} (${_counts[e.key]})' : e.value,
                      selected: _status == e.key,
                      onTap: () => _switch(e.key),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 6)),
      ],
      empty: EmptyState(
        icon: CupertinoIcons.music_note_list,
        title: _status == 'pending' ? 'No hay canciones por revisar' : 'Sin canciones',
      ),
      itemBuilder: (context, s, _) {
        final id = asInt(s['id']);
        final song = Song(
          id: id,
          title: asStr(s['title']),
          featuring: asStrOrNull(s['featuring']),
          genreLabel: songGenres[asStr(s['genre'])] ?? '',
          isExplicit: asBool(s['is_explicit']),
          duration: asInt(s['duration_seconds']),
          audioUrl: asStr(s['audio_path']),
          coverUrl: asStrOrNull(s['cover_path']),
        );
        final status = asStr(s['status']);
        final note = asStrOrNull(s['review_note']);
        return Container(
          margin: const EdgeInsets.fromLTRB(14, 0, 14, 10),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: Tx.surface1, borderRadius: BorderRadius.circular(18), border: Border.all(color: Tx.border)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              SongCover(url: song.coverUrl, size: 56, radius: 14),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Flexible(child: Text(song.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: Tx.body(15, weight: FontWeight.w600))),
                    if (song.isExplicit) ...[const SizedBox(width: 6), const ExplicitTag()],
                  ]),
                  GestureDetector(
                    onTap: () => openProfile(context, asStr(s['username'])),
                    child: Text(
                      '@${s['username']}${song.featuring != null && song.featuring!.isNotEmpty ? ' · feat. ${song.featuring}' : ''}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Tx.body(13, color: Tx.accent),
                    ),
                  ),
                  Text('${song.genreLabel} · ${clock(song.duration)} · ${fileSize(asInt(s['size_bytes']))} · ${timeAgo(asDate(s['created_at']))}',
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: Tx.body(12, color: Tx.subtle)),
                ]),
              ),
              if (song.audioUrl.startsWith('http')) PlayButton(playKey: 'review:$id', song: song, size: 40),
            ]),
            if (note != null && note.trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('Nota: ${note.trim()}${s['reviewer_username'] != null ? ' (@${s['reviewer_username']})' : ''}',
                    style: Tx.body(12.5, color: Tx.muted)),
              ),
            const SizedBox(height: 10),
            if (_busy.contains(id))
              const Center(child: CupertinoActivityIndicator())
            else
              Row(children: [
                if (status == 'pending') ...[
                  Expanded(child: SoftButton(label: 'Rechazar', icon: CupertinoIcons.xmark, color: Tx.danger, onPressed: () => _act(s, 'reject'))),
                  const SizedBox(width: 10),
                  Expanded(child: GradientButton(label: 'Aprobar', icon: CupertinoIcons.checkmark_alt, height: 40, onPressed: () => _act(s, 'approve'))),
                ],
                if (status == 'published' || status == 'withdrawn')
                  Expanded(child: SoftButton(label: 'Retirar de la biblioteca', icon: CupertinoIcons.eye_slash, color: Tx.danger, onPressed: () => _act(s, 'remove'))),
                if (status == 'removed')
                  Expanded(child: SoftButton(label: 'Restaurar', icon: CupertinoIcons.arrow_uturn_left, onPressed: () => _act(s, 'restore'))),
              ]),
          ]),
        );
      },
    );
  }
}

/// Solicitudes de verificado (solo administradores): datos al pedirlo y requisitos de ahora mismo.
class _VerificationReview extends StatefulWidget {
  const _VerificationReview();

  @override
  State<_VerificationReview> createState() => _VerificationReviewState();
}

class _VerificationReviewState extends State<_VerificationReview> {
  String _status = 'pending';
  Map<String, int> _counts = {};
  final Set<int> _busy = {};
  late Paged<Json> _list = _make();

  static const _statuses = {
    'pending': 'Pendientes',
    'approved': 'Aprobadas',
    'rejected': 'Rechazadas',
    'cancelled': 'Canceladas',
  };

  Paged<Json> _make() => Paged<Json>('admin/verification', (j) => j, query: {'status': _status}, onMeta: (meta) {
        final counts = asMap(meta['counts']).map((k, v) => MapEntry(k, asInt(v)));
        Future.microtask(() {
          if (mounted) setState(() => _counts = counts);
        });
      });

  void _switch(String status) {
    if (status == _status) return;
    final old = _list;
    setState(() {
      _status = status;
      _list = _make();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
  }

  @override
  void dispose() {
    _list.dispose();
    super.dispose();
  }

  Future<void> _act(Json r, bool approve) async {
    final id = asInt(r['id']);
    final who = '@${r['username']}';
    final text = await prompt(
      context,
      approve ? 'Verificar a $who' : 'Rechazar a $who',
      hint: approve ? 'Nota interna (opcional)' : 'Motivo (lo verá la persona)',
      action: approve ? 'Verificar' : 'Rechazar',
      maxLength: 255,
      required: !approve,
    );
    if (text == null) return;
    if (!mounted) return;
    setState(() => _busy.add(id));
    try {
      final res = await api.post('admin/verification/$id/${approve ? 'approve' : 'reject'}', {
        if (approve && text.isNotEmpty) 'note': text,
        if (!approve) 'reason': text,
      });
      if (!mounted) return;
      toast(context, '${res.map['message'] ?? 'Listo.'}');
      _list.remove((x) => asInt(x['id']) == id);
      setState(() => _counts['pending'] = ((_counts['pending'] ?? 1) - 1).clamp(0, 1 << 30));
    } catch (e) {
      if (mounted) toastError(context, e);
    }
    if (mounted) setState(() => _busy.remove(id));
  }

  @override
  Widget build(BuildContext context) {
    return PagedView<Json>(
      paged: _list,
      header: [
        SliverToBoxAdapter(
          child: SizedBox(
            height: 54,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
              children: [
                for (final e in _statuses.entries)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: PillChip(
                      label: (_counts[e.key] ?? 0) > 0 ? '${e.value} (${_counts[e.key]})' : e.value,
                      selected: _status == e.key,
                      onTap: () => _switch(e.key),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 6)),
      ],
      empty: EmptyState(
        icon: CupertinoIcons.checkmark_seal,
        title: _status == 'pending' ? 'No hay solicitudes por revisar' : 'Sin solicitudes',
      ),
      itemBuilder: (context, r, _) {
        final id = asInt(r['id']);
        final user = User.fromJson({...r, 'id': r['user_id'], 'avatar_url': r['avatar_path']});
        final checks = r['checks_now'] is List ? asList(r['checks_now'], (j) => j) : const <Json>[];
        final note = asStrOrNull(r['note']);
        final decision = asStrOrNull(r['decision_note']);
        final warnings = asInt(r['recent_warnings']);
        return Container(
          margin: const EdgeInsets.fromLTRB(14, 0, 14, 10),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: Tx.surface1, borderRadius: BorderRadius.circular(18), border: Border.all(color: Tx.border)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Avatar(user: user, size: 44, onTap: () => openProfile(context, user.username)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(asStr(r['full_name']), maxLines: 1, overflow: TextOverflow.ellipsis, style: Tx.body(15, weight: FontWeight.w600)),
                  GestureDetector(
                    onTap: () => openProfile(context, user.username),
                    child: Text('@${user.username} · ${asStr(r['category_label'])}',
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: Tx.body(13, color: Tx.accent)),
                  ),
                  Text(timeAgo(asDate(r['created_at'])), style: Tx.body(12, color: Tx.subtle)),
                ]),
              ),
            ]),
            if (note != null && note.trim().isNotEmpty)
              Padding(padding: const EdgeInsets.only(top: 8), child: Text(note.trim(), style: Tx.body(13.5, height: 1.35))),
            const SizedBox(height: 8),
            Text(
              'Al pedirlo: ${compact(asInt(r['followers_count']))} seguidores · '
              '${asInt(r['avg_likes'])} «Me gusta» de media en ${asInt(r['posts_counted'])} publicaciones'
              '${warnings > 0 ? ' · ${plural(warnings, 'advertencia reciente', 'advertencias recientes')}' : ''}',
              style: Tx.body(12.5, color: warnings > 0 ? Tx.warning : Tx.muted),
            ),
            if (checks.isNotEmpty) ...[
              const SizedBox(height: 6),
              for (final c in checks)
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Row(children: [
                    Icon(asBool(c['ok']) ? CupertinoIcons.checkmark_circle_fill : CupertinoIcons.xmark_circle_fill,
                        size: 15, color: asBool(c['ok']) ? Tx.success : Tx.danger),
                    const SizedBox(width: 6),
                    Expanded(child: Text('Ahora: ${asStr(c['detail'])}', style: Tx.body(12.5, color: Tx.muted))),
                  ]),
                ),
            ],
            if (decision != null && decision.trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('Nota: ${decision.trim()}${r['reviewer_username'] != null ? ' (@${r['reviewer_username']})' : ''}',
                    style: Tx.body(12.5, color: Tx.muted)),
              ),
            if (_status == 'pending') ...[
              const SizedBox(height: 10),
              if (_busy.contains(id))
                const Center(child: CupertinoActivityIndicator())
              else
                Row(children: [
                  Expanded(child: SoftButton(label: 'Rechazar', icon: CupertinoIcons.xmark, color: Tx.danger, onPressed: () => _act(r, false))),
                  const SizedBox(width: 10),
                  Expanded(child: GradientButton(label: 'Verificar', icon: CupertinoIcons.checkmark_seal_fill, height: 40, onPressed: () => _act(r, true))),
                ]),
            ],
          ]),
        );
      },
    );
  }
}
