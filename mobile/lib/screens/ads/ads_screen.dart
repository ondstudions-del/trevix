import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/nav.dart';
import '../../core/paged.dart';
import '../../core/routes.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';
import '../../widgets/paged_view.dart';
import '../../widgets/settings_tiles.dart';
import '../wallet/wallet_screen.dart';

const _kinds = {
  'post': 'Publicación',
  'community': 'Comunidad',
  'group': 'Grupo',
  'custom': 'Anuncio libre',
};

/// OND-ADS: anuncios y promociones pagadas con el monedero (GET/POST ads, GET me/ads). Cada día cuesta el precio
/// configurado y se muestra a entre reach_min y reach_max personas en el feed; el equipo los revisa antes de empezar
/// y, si los rechaza, devuelve todo.
class AdsScreen extends StatefulWidget {
  const AdsScreen({super.key, this.kind, this.targetId, this.mine = false});

  final String? kind;
  final int? targetId;
  final bool mine;

  @override
  State<AdsScreen> createState() => _AdsScreenState();
}

class _AdsScreenState extends State<AdsScreen> {
  late bool _mine = widget.mine;
  final _campaigns = Paged<Json>('me/ads', (j) => j);
  Json? _summary;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _campaigns.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final res = await api.get('ads');
      if (mounted) setState(() => (_summary = res.map, _error = null));
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _created() async {
    await _load();
    if (!mounted) return;
    setState(() => _mine = true);
    _campaigns.refresh();
  }

  @override
  Widget build(BuildContext context) {
    final summary = _summary;
    return Scaffold(
      appBar: GlassBar(title: 'OND-ADS'),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
          child: Row(children: [
            PillChip(label: tr('Crear anuncio'), icon: CupertinoIcons.add, selected: !_mine, onTap: () => setState(() => _mine = false)),
            const SizedBox(width: 8),
            PillChip(label: tr('Mis anuncios'), icon: CupertinoIcons.chart_bar_alt_fill, selected: _mine, onTap: () => setState(() => _mine = true)),
          ]),
        ),
        Expanded(
          child: _mine
              ? PagedView<Json>(
                  paged: _campaigns,
                  onRefresh: _load,
                  empty: EmptyState(
                    icon: CupertinoIcons.speaker_2,
                    title: tr('Aún no tienes anuncios'),
                    message: tr('Promociona una publicación, comunidad o grupo, o crea un anuncio libre.'),
                  ),
                  itemBuilder: (context, a, _) => _CampaignTile(a, onChanged: () {
                    _load();
                    _campaigns.refresh();
                  }),
                )
              : summary == null
                  ? (_error != null ? ErrorState(error: _error!, onRetry: _load) : const Loading())
                  : _CreateForm(summary: summary, kind: widget.kind, targetId: widget.targetId, onCreated: _created),
        ),
      ]),
    );
  }
}

class _CreateForm extends StatefulWidget {
  const _CreateForm({required this.summary, this.kind, this.targetId, required this.onCreated});

  final Json summary;
  final String? kind;
  final int? targetId;
  final Future<void> Function() onCreated;

  @override
  State<_CreateForm> createState() => _CreateFormState();
}

class _CreateFormState extends State<_CreateForm> {
  late String _kind = _kinds.containsKey(widget.kind) ? widget.kind! : 'post';
  late final Map<String, int?> _target = {'post': null, 'community': null, 'group': null}
    ..[_kind] = widget.targetId;
  int _days = 1;
  final _title = TextEditingController();
  final _body = TextEditingController();
  final _link = TextEditingController();
  String _cta = 'learn_more';
  XFile? _image;
  bool _sending = false;
  Map<String, String> _errors = {};

  Json get s => widget.summary;
  Money get _daily => Money.fromJson(s['daily_price']);
  Money get _balance => Money.fromJson(s['balance']);
  int get _maxDays => asInt(s['max_days'], 30);
  Json get _targets => asMap(s['targets']);

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    _link.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    try {
      final file = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 88, maxWidth: 2000);
      if (file != null && mounted) setState(() => (_image = file, _errors.remove('image')));
    } catch (e) {
      if (mounted) toastError(context, e);
    }
  }

  Future<void> _send() async {
    FocusScope.of(context).unfocus();
    final errors = <String, String>{};
    if (_kind != 'custom' && _target[_kind] == null) errors['target_id'] = tr('Elige qué quieres promocionar.');
    if (_kind == 'custom') {
      if (_title.text.trim().isEmpty) errors['title'] = tr('Escribe el título del anuncio.');
      if (!RegExp(r'^https?://', caseSensitive: false).hasMatch(_link.text.trim())) {
        errors['link_url'] = tr('Escribe el enlace completo (https://…).');
      }
    }
    if (errors.isNotEmpty) {
      setState(() => _errors = errors);
      return;
    }
    final total = Money.local(_daily.cents * _days);
    if (!await confirm(
      context,
      tr('Pagar {amount}', {'amount': total.formatted}),
      tr('Se descuenta de tu monedero ahora. El equipo revisa el anuncio y, si lo rechaza, te devolvemos todo.'),
      action: tr('Pagar y enviar'),
    )) {
      return;
    }
    setState(() => (_sending = true, _errors = {}));
    try {
      final res = await api.upload('ads', fields: {
        'kind': _kind,
        'days': '$_days',
        if (_kind != 'custom') 'target_id': '${_target[_kind]}',
        if (_kind == 'custom') ...{
          'title': _title.text.trim(),
          'body': _body.text.trim(),
          'link_url': _link.text.trim(),
          'cta': _cta,
        },
      }, files: [
        if (_kind == 'custom' && _image != null) Upload('image', _image!.path, filename: _image!.name),
      ]);
      if (!mounted) return;
      toast(context, asStr(res.map['message'], tr('Tu anuncio quedó en revisión.')));
      setState(() => _sending = false);
      await widget.onCreated();
      return;
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.status == 402) {
        toast(context, e.message, error: true);
        await push(context, const WalletScreen());
      } else if (e.fields.isNotEmpty && !e.fields.containsKey('form')) {
        setState(() => _errors = e.fields);
      } else {
        toastError(context, e);
      }
    } catch (e) {
      if (mounted) toastError(context, e);
    }
    if (mounted) setState(() => _sending = false);
  }

  @override
  Widget build(BuildContext context) {
    if (!asBool(s['enabled'])) {
      return EmptyState(icon: CupertinoIcons.speaker_slash, title: tr('OND-ADS no está disponible'), message: tr('Vuelve a intentarlo más tarde.'));
    }
    final total = Money.local(_daily.cents * _days);
    return ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 80), children: [
      Panel(
        gradient: true,
        padding: const EdgeInsets.all(18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              width: 40,
              height: 40,
              decoration: const BoxDecoration(gradient: Tx.brand, shape: BoxShape.circle),
              child: const Icon(CupertinoIcons.speaker_2_fill, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(tr('Llega a más personas en TREVIX'), style: Tx.body(16, weight: FontWeight.w700))),
          ]),
          const SizedBox(height: 10),
          Text(
            tr('{price} por día · se muestra a {min}–{max} personas por día en el feed. Si un día no llega al mínimo, te devolvemos la parte.', {
              'price': _daily.formatted,
              'min': asInt(s['reach_min']),
              'max': asInt(s['reach_max']),
            }),
            style: Tx.body(13.5, color: Tx.muted, height: 1.4),
          ),
          const SizedBox(height: 8),
          Text(tr('Saldo: {amount}', {'amount': _balance.formatted}), style: Tx.body(13.5, weight: FontWeight.w700)),
        ]),
      ),
      SectionTitle(tr('¿Qué quieres anunciar?'), padding: const EdgeInsets.fromLTRB(4, 22, 4, 10)),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final k in _kinds.entries)
          PillChip(label: tr(k.value), selected: _kind == k.key, onTap: () => setState(() => (_kind = k.key, _errors = {}))),
      ]),
      if (_kind == 'custom') ..._customFields() else _targetList(),
      SectionTitle(tr('Duración'), padding: const EdgeInsets.fromLTRB(4, 22, 4, 10)),
      Panel(
        padding: const EdgeInsets.fromLTRB(16, 10, 10, 10),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_days == 1 ? tr('1 día') : tr('{n} días', {'n': _days}), style: Tx.body(17, weight: FontWeight.w700)),
              Text(
                tr('{min}–{max} personas en total', {'min': compact(asInt(s['reach_min']) * _days), 'max': compact(asInt(s['reach_max']) * _days)}),
                style: Tx.body(12.5, color: Tx.muted),
              ),
            ]),
          ),
          IconButton(
            onPressed: _days > 1 ? () => setState(() => _days--) : null,
            icon: Icon(CupertinoIcons.minus_circle, color: _days > 1 ? Tx.accent : Tx.subtle),
          ),
          IconButton(
            onPressed: _days < _maxDays ? () => setState(() => _days++) : null,
            icon: Icon(CupertinoIcons.plus_circle, color: _days < _maxDays ? Tx.accent : Tx.subtle),
          ),
        ]),
      ),
      if (_errors['days'] != null) _Error(_errors['days']!),
      const SizedBox(height: 20),
      GradientButton(
        label: tr('Pagar {amount} y enviar a revisión', {'amount': total.formatted}),
        icon: CupertinoIcons.checkmark_seal_fill,
        loading: _sending,
        onPressed: _send,
      ),
      if (_errors['kind'] != null) _Error(_errors['kind']!),
      const SizedBox(height: 10),
      Text(
        tr('El equipo revisa cada anuncio antes de mostrarlo. Puedes cancelarlo cuando quieras: devolvemos los días que no se usaron.'),
        textAlign: TextAlign.center,
        style: Tx.body(12.5, color: Tx.subtle, height: 1.4),
      ),
    ]);
  }

  Widget _targetList() {
    final items = switch (_kind) {
      'post' => asList(_targets['posts'], (j) => j),
      'community' => asList(_targets['communities'], (j) => j),
      _ => asList(_targets['groups'], (j) => j),
    };
    if (items.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 14),
        child: Panel(
          child: Text(
            switch (_kind) {
              'post' => tr('No tienes publicaciones públicas para promocionar.'),
              'community' => tr('No administras ninguna comunidad pública.'),
              _ => tr('No administras ningún grupo público.'),
            },
            style: Tx.body(13.5, color: Tx.muted),
          ),
        ),
      );
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SettingsGroup(children: [
        for (final item in items)
          _TargetRow(
            item: item,
            kind: _kind,
            selected: _target[_kind] == asInt(item['id']),
            onTap: () => setState(() => (_target[_kind] = asInt(item['id']), _errors.remove('target_id'))),
          ),
      ]),
      if (_errors['target_id'] != null) _Error(_errors['target_id']!),
    ]);
  }

  List<Widget> _customFields() {
    final ctas = asList(s['ctas'], (j) => j);
    return [
      const SizedBox(height: 16),
      TextField(
        controller: _title,
        maxLength: 80,
        style: Tx.body(15),
        decoration: fieldDecoration(tr('Lo que verá la gente primero'), label: tr('Título'), error: _errors['title']),
      ),
      TextField(
        controller: _body,
        maxLength: 300,
        minLines: 2,
        maxLines: 5,
        style: Tx.body(15),
        decoration: fieldDecoration(tr('Cuenta de qué se trata (opcional)'), label: tr('Texto'), error: _errors['body']),
      ),
      TextField(
        controller: _link,
        maxLength: 500,
        keyboardType: TextInputType.url,
        autocorrect: false,
        style: Tx.body(15),
        decoration: fieldDecoration('https://', label: tr('Enlace del botón'), error: _errors['link_url']),
      ),
      Text(tr('Botón'), style: Tx.body(13, weight: FontWeight.w600, color: Tx.muted)),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final c in ctas)
          PillChip(label: asStr(c['label']), selected: _cta == asStr(c['id']), onTap: () => setState(() => _cta = asStr(c['id']))),
      ]),
      const SizedBox(height: 14),
      GestureDetector(
        onTap: _sending ? null : _pickImage,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Tx.surface1,
            borderRadius: BorderRadius.circular(Tx.radiusLg),
            border: Border.all(color: _errors['image'] != null ? Tx.danger : Tx.borderStrong),
          ),
          child: Row(children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: _image != null
                  ? Image.file(File(_image!.path), width: 64, height: 64, fit: BoxFit.cover)
                  : Container(width: 64, height: 64, color: Tx.surface3, child: Icon(CupertinoIcons.photo, color: Tx.subtle)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_image != null ? tr('Imagen elegida') : tr('Añadir imagen (opcional)'), style: Tx.body(15, weight: FontWeight.w600)),
                Text(tr('JPG, PNG o WEBP. Se muestra arriba del anuncio.'), style: Tx.body(12.5, color: Tx.muted)),
              ]),
            ),
            if (_image != null)
              IconButton(onPressed: () => setState(() => _image = null), icon: Icon(CupertinoIcons.xmark_circle_fill, color: Tx.subtle)),
          ]),
        ),
      ),
      if (_errors['image'] != null) _Error(_errors['image']!),
    ];
  }
}

class _TargetRow extends StatelessWidget {
  const _TargetRow({required this.item, required this.kind, required this.selected, required this.onTap});

  final Json item;
  final String kind;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final image = asStrOrNull(kind == 'post' ? item['thumb_url'] : item['avatar_url']);
    final title = asStr(kind == 'post' ? item['excerpt'] : (kind == 'community' ? item['name'] : item['title']));
    final subtitle = kind == 'post'
        ? timeAgo(asDate(item['created_at']))
        : plural(asInt(item['members_count']), 'miembro', 'miembros');
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(children: [
          image != null
              ? NetImage(image, width: 44, height: 44, radius: 10)
              : Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(color: Tx.surface3, borderRadius: BorderRadius.circular(10)),
                  child: Icon(kind == 'post' ? CupertinoIcons.text_alignleft : CupertinoIcons.person_3_fill, color: Tx.subtle, size: 20),
                ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: Tx.body(14.5, weight: FontWeight.w600)),
              Text(subtitle, style: Tx.body(12.5, color: Tx.muted)),
            ]),
          ),
          Icon(selected ? CupertinoIcons.checkmark_circle_fill : CupertinoIcons.circle, color: selected ? Tx.accentSoft : Tx.subtle),
        ]),
      ),
    );
  }
}

class _CampaignTile extends StatelessWidget {
  const _CampaignTile(this.a, {required this.onChanged});

  final Json a;
  final VoidCallback onChanged;

  Color get _color => switch (asStr(a['status'])) {
        'active' => Tx.success,
        'pending' => Tx.warning,
        'rejected' || 'removed' => Tx.danger,
        _ => Tx.subtle,
      };

  Future<void> _cancel(BuildContext context) async {
    if (!await confirm(
      context,
      tr('Cancelar anuncio'),
      asStr(a['status']) == 'pending'
          ? tr('Te devolvemos todo lo que pagaste.')
          : tr('Deja de mostrarse ahora y te devolvemos los días que faltan.'),
      action: tr('Cancelar anuncio'),
      destructive: true,
    )) {
      return;
    }
    try {
      final res = await api.post('me/ads/${a['id']}/cancel');
      if (context.mounted) toast(context, asStr(res.map['message'], tr('Cancelaste el anuncio.')));
      onChanged();
    } catch (e) {
      if (context.mounted) toastError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final refunded = Money.fromJson(a['refunded']);
    final daysLeft = asIntOrNull(a['days_left']);
    final note = asStrOrNull(a['review_note']);
    final postId = asIntOrNull(a['post_id']);
    final slug = asStrOrNull(a['community_slug']);
    return Panel(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      onTap: postId != null
          ? () => openPost(context, postId)
          : (slug != null ? () => openCommunity(context, slug) : null),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
            decoration: BoxDecoration(color: Tx.alpha(_color, .16), borderRadius: BorderRadius.circular(20)),
            child: Text(asStr(a['status_label']), style: Tx.body(12, weight: FontWeight.w700, color: _color)),
          ),
          const SizedBox(width: 8),
          Text(asStr(a['kind_label']), style: Tx.body(12.5, color: Tx.muted)),
          const Spacer(),
          Text(Money.fromJson(a['total']).formatted, style: Tx.body(14, weight: FontWeight.w700)),
        ]),
        const SizedBox(height: 8),
        Text(asStr(a['target']), maxLines: 2, overflow: TextOverflow.ellipsis, style: Tx.body(15, weight: FontWeight.w600)),
        const SizedBox(height: 4),
        Text(
          [
            asInt(a['days']) == 1 ? tr('1 día') : tr('{n} días', {'n': asInt(a['days'])}),
            if (daysLeft != null) tr('quedan {n}', {'n': daysLeft}),
            timeAgo(asDate(a['created_at'])),
          ].join(' · '),
          style: Tx.body(12.5, color: Tx.muted),
        ),
        const SizedBox(height: 10),
        Row(children: [
          _Stat(CupertinoIcons.eye, tr('{n} personas', {'n': compact(asInt(a['impressions']))})),
          const SizedBox(width: 14),
          _Stat(CupertinoIcons.hand_point_right, tr('{n} toques', {'n': compact(asInt(a['clicks']))})),
          if (refunded.cents > 0) ...[
            const SizedBox(width: 14),
            _Stat(CupertinoIcons.arrow_uturn_left, tr('Devuelto {amount}', {'amount': refunded.formatted})),
          ],
        ]),
        if (note != null && const {'rejected', 'removed'}.contains(asStr(a['status']))) ...[
          const SizedBox(height: 8),
          Text(tr('Motivo: {note}', {'note': note}), style: Tx.body(13, color: Tx.danger)),
        ],
        if (asBool(a['can_cancel'])) ...[
          const SizedBox(height: 10),
          SoftButton(label: tr('Cancelar anuncio'), icon: CupertinoIcons.xmark_circle, color: Tx.danger, onPressed: () => _cancel(context)),
        ],
      ]),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.icon, this.text);

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 14, color: Tx.subtle),
        const SizedBox(width: 4),
        Text(text, style: Tx.body(12.5, color: Tx.muted)),
      ]);
}

class _Error extends StatelessWidget {
  const _Error(this.text);

  final String text;

  @override
  Widget build(BuildContext context) =>
      Padding(padding: const EdgeInsets.fromLTRB(6, 6, 6, 0), child: Text(text, style: Tx.body(12.5, color: Tx.danger)));
}

/// Anuncio de OND-ADS dentro del feed (meta.sponsored de GET feed). Al tocarlo se cuenta el toque
/// (POST ads/{id}/click) y se abre la publicación, la comunidad, el grupo o el enlace del anuncio libre.
class SponsoredCard extends StatelessWidget {
  const SponsoredCard({super.key, required this.ad, required this.postCard});

  final Json ad;

  /// Tarjeta de la publicación promocionada (la arma el feed con su propio builder).
  final Widget Function(Post post)? postCard;

  int get id => asInt(ad['id']);

  Future<void> _open(BuildContext context) async {
    try {
      final res = (await api.post('ads/$id/click')).map;
      if (!context.mounted) return;
      switch (asStr(res['kind'])) {
        case 'post':
          openPost(context, asInt(res['post_id']));
        case 'community':
          openCommunity(context, asStr(res['community_slug']));
        case 'group':
          openGroupInvite(context, asStr(res['invite_code']));
        default:
          openUrl(context, asStr(res['url']));
      }
    } catch (e) {
      if (context.mounted) toastError(context, e);
    }
  }

  Widget _label(BuildContext context, String action) {
    final sponsor = User.fromJson(asMap(ad['sponsor']));
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _open(context),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
        child: Row(children: [
          Icon(CupertinoIcons.speaker_2_fill, size: 13, color: Tx.accent),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              '${tr('Patrocinado')} · ${sponsor.displayName}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Tx.body(12.5, weight: FontWeight.w600, color: Tx.muted),
            ),
          ),
          const Spacer(),
          Text(action, style: Tx.body(12.5, weight: FontWeight.w700, color: Tx.accent)),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final kind = asStr(ad['kind']);
    final post = asMapOrNull(ad['post']);
    if (kind == 'post' && post != null && postCard != null) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _label(context, tr('Ver publicación')),
        postCard!(Post.fromJson(post)),
      ]);
    }
    final community = asMapOrNull(ad['community']);
    final group = asMapOrNull(ad['group']);
    final custom = asMapOrNull(ad['custom']);
    final (String title, String body, String? image, String action, IconData icon) = switch (kind) {
      'community' when community != null => (
          asStr(community['name']),
          [plural(asInt(community['members_count']), 'miembro', 'miembros'), asStr(community['description'])].where((x) => x.isNotEmpty).join(' · '),
          asStrOrNull(community['cover_url']) ?? asStrOrNull(community['avatar_url']),
          tr('Ver comunidad'),
          CupertinoIcons.person_3_fill,
        ),
      'group' when group != null => (
          asStr(group['title']),
          [plural(asInt(group['members_count']), 'participante', 'participantes'), asStr(group['description'])].where((x) => x.isNotEmpty).join(' · '),
          asStrOrNull(group['avatar_url']),
          asBool(group['is_member']) ? tr('Ver grupo') : tr('Unirme al grupo'),
          CupertinoIcons.chat_bubble_2_fill,
        ),
      _ when custom != null => (
          asStr(custom['title']),
          asStr(custom['body']),
          asStrOrNull(custom['image_url']),
          asStr(custom['cta_label'], tr('Más información')),
          CupertinoIcons.link,
        ),
      _ => ('', '', null, '', CupertinoIcons.speaker_2),
    };
    if (title.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _label(context, ''),
      Panel(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 14),
        padding: EdgeInsets.zero,
        onTap: () => _open(context),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (image != null)
            ClipRRect(
              borderRadius: BorderRadius.vertical(top: Radius.circular(Tx.radiusLg)),
              child: AspectRatio(aspectRatio: kind == 'custom' ? 1.91 : 2.6, child: NetImage(image)),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(icon, size: 16, color: Tx.accent),
                const SizedBox(width: 8),
                Expanded(child: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: Tx.body(16, weight: FontWeight.w700))),
              ]),
              if (body.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(body, maxLines: 3, overflow: TextOverflow.ellipsis, style: Tx.body(13.5, color: Tx.muted, height: 1.4)),
              ],
              if (kind == 'custom' && asStr(custom?['domain']).isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(asStr(custom?['domain']), style: Tx.body(12, color: Tx.subtle)),
              ],
              const SizedBox(height: 12),
              GradientButton(label: action, height: 42, onPressed: () => _open(context)),
            ]),
          ),
        ]),
      ),
    ]);
  }
}
