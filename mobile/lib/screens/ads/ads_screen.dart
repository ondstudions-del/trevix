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
import '../../widgets/ond_ad_chrome.dart';
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
  final _ctaTarget = TextEditingController();
  String _cta = 'learn_more';
  String _creativeType = 'website';
  final Set<String> _placements = {'feed', 'profile', 'stories', 'reels', 'community'};
  final _productLabel = TextEditingController();
  XFile? _image;
  XFile? _video;
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
    _productLabel.dispose();
    super.dispose();
  }

  Future<void> _pickVideo() async {
    try {
      final file = await ImagePicker().pickVideo(source: ImageSource.gallery, maxDuration: const Duration(seconds: 60));
      if (file != null && mounted) setState(() => (_video = file, _errors.remove('video')));
    } catch (e) {
      if (mounted) toastError(context, e);
    }
  }

  static const _creativeTypes = {
    'website': 'Sitio web',
    'app': 'Aplicación',
    'product': 'Producto / venta',
    'video': 'Video',
  };

  static const _placementLabels = {
    'feed': 'Feed',
    'profile': 'Perfiles',
    'stories': 'Historias',
    'reels': 'Reels',
    'community': 'Comunidades',
  };

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
        'placements': _placements.join(','),
        if (_kind != 'custom') 'target_id': '${_target[_kind]}',
        if (_kind == 'custom') ...{
          'title': _title.text.trim(),
          'body': _body.text.trim(),
          'link_url': _link.text.trim(),
          'cta': _cta,
        },
        if (_kind == 'custom') ...{
          'creative_type': _creativeType,
          'placements': _placements.join(','),
          if (_productLabel.text.trim().isNotEmpty) 'product_label': _productLabel.text.trim(),
        },
      }, files: [
        if (_kind == 'custom' && _creativeType != 'video' && _image != null) Upload('image', _image!.path, filename: _image!.name),
        if (_kind == 'custom' && _creativeType == 'video' && _video != null) Upload('video', _video!.path, filename: _video!.name),
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
              decoration: BoxDecoration(gradient: Tx.brand, shape: BoxShape.circle),
              child: const Icon(CupertinoIcons.speaker_2_fill, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(tr('Llega a más personas en TREVIX'), style: Tx.body(16, weight: FontWeight.w700))),
          ]),
          const SizedBox(height: 10),
          Text(
            tr('{price} por día · se muestra a {min}–{max} personas por día en el feed, perfiles, historias, reels y comunidades. Si un día no llega al mínimo, te devolvemos la parte.', {
              'price': _daily.formatted,
              'min': asInt(s['reach_min']),
              'max': asInt(s['reach_max']),
            }),
            style: Tx.body(13.5, color: Tx.muted, height: 1.4),
          ),
          const SizedBox(height: 8),
          if (asBool(s['infinite'])) ...[
            Text('∞', style: Tx.body(15, weight: FontWeight.w800, color: Tx.accent)),
            Text(
              tr('Modo demostración: los anuncios no consumen saldo real.'),
              style: Tx.body(12.5, color: Tx.muted, height: 1.35),
            ),
          ] else
            Text(tr('Saldo: {amount}', {'amount': _balance.formatted}), style: Tx.body(13.5, weight: FontWeight.w700)),
        ]),
      ),
      SectionTitle(tr('¿Qué quieres anunciar?'), padding: const EdgeInsets.fromLTRB(4, 22, 4, 10)),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final k in _kinds.entries)
          PillChip(label: tr(k.value), selected: _kind == k.key, onTap: () => setState(() => (_kind = k.key, _errors = {}))),
      ]),
      if (_kind == 'custom') ..._customFields() else _targetList(),
      if (_kind != 'custom')
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 18, 4, 0),
          child: Text(
            tr('Se mostrará como una publicación, comunidad o grupo nativo en feed, perfiles, historias, reels y comunidades.'),
            style: Tx.body(12.5, color: Tx.muted, height: 1.4),
          ),
        ),
      SectionTitle(tr('Dónde se muestra'), padding: const EdgeInsets.fromLTRB(4, 22, 4, 10)),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final e in _placementLabels.entries)
            PillChip(
              label: tr(e.value),
              selected: _placements.contains(e.key),
              onTap: () => setState(() {
                if (_placements.contains(e.key)) {
                  if (_placements.length > 1) _placements.remove(e.key);
                } else {
                  _placements.add(e.key);
                }
              }),
            ),
        ],
      ),
      if (_errors['placements'] != null) _Error(_errors['placements']!),
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
      Text(tr('Tipo de anuncio'), style: Tx.body(13, weight: FontWeight.w600, color: Tx.muted)),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final e in _creativeTypes.entries)
            PillChip(
              label: tr(e.value),
              selected: _creativeType == e.key,
              onTap: () => setState(() => _creativeType = e.key),
            ),
        ],
      ),
      if (_errors['creative_type'] != null) _Error(_errors['creative_type']!),
      const SizedBox(height: 14),
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
      if (_creativeType == 'product') ...[
        const SizedBox(height: 12),
        TextField(
          controller: _productLabel,
          maxLength: 60,
          style: Tx.body(15),
          decoration: fieldDecoration(tr('Ej. \$120.000 · 2 unidades'), label: tr('Precio o etiqueta'), error: _errors['product_label']),
        ),
      ],
      const SizedBox(height: 14),
      if (_creativeType == 'video')
        GestureDetector(
          onTap: _sending ? null : _pickVideo,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Tx.surface1,
              borderRadius: BorderRadius.circular(Tx.radiusLg),
              border: Border.all(color: _errors['video'] != null ? Tx.danger : Tx.borderStrong),
            ),
            child: Row(children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(color: Tx.surface3, borderRadius: BorderRadius.circular(10)),
                child: Icon(_video != null ? CupertinoIcons.videocam_fill : CupertinoIcons.film, color: Tx.subtle),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(_video != null ? tr('Video elegido') : tr('Subir video'), style: Tx.body(15, weight: FontWeight.w600)),
                  Text(tr('Formato vertical o cuadrado, hasta 60 s.'), style: Tx.body(12.5, color: Tx.muted)),
                ]),
              ),
              if (_video != null)
                IconButton(onPressed: () => setState(() => _video = null), icon: Icon(CupertinoIcons.xmark_circle_fill, color: Tx.subtle)),
            ]),
          ),
        )
      else
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
      if (_errors['video'] != null) _Error(_errors['video']!),
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

  Widget _label(BuildContext context, String action) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
      child: Row(children: [
        ondAdSponsorBadge(fontSize: 10),
        if (action.isNotEmpty) ...[
          const Spacer(),
          Flexible(child: Text(action, maxLines: 1, overflow: TextOverflow.ellipsis, style: Tx.body(12.5, weight: FontWeight.w700, color: Tx.accent))),
        ],
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final kind = asStr(ad['kind']);
    final post = asMapOrNull(ad['post']);
    if (kind == 'post' && post != null && postCard != null) {
      return SponsoredPostChrome(ad: ad, child: postCard!(Post.fromJson(post)));
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
          [asStr(custom['body']), asStrOrNull(custom['product_label']) ?? ''].where((x) => x.isNotEmpty).join(' · '),
          asStrOrNull(custom['video_url']) ?? asStrOrNull(custom['image_url']),
          ondAdActionLabel(ad),
          asStr(ad['creative_type']) == 'app'
              ? CupertinoIcons.app
              : asStr(ad['creative_type']) == 'product'
                  ? CupertinoIcons.cart
                  : asStr(ad['creative_type']) == 'video'
                      ? CupertinoIcons.videocam_fill
                      : CupertinoIcons.link,
        ),
      _ => ('', '', null, '', CupertinoIcons.speaker_2),
    };
    if (title.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _label(context, kind == 'custom' ? '' : action),
      Panel(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 14),
        padding: EdgeInsets.zero,
        onTap: () => followOndAdClick(context, ad),
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
              const SizedBox(height: 12),
              OndAdActionFooter(ad: ad, compact: true),
            ]),
          ),
        ]),
      ),
    ]);
  }
}

/// Anillo ámbar distinto de historias normales; miniatura a ancho completo dentro del círculo.
class SponsoredStoryBubble extends StatelessWidget {
  const SponsoredStoryBubble({super.key, required this.ad});

  static const _adRing = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFFBBF24), Color(0xFFF97316), Color(0xFFEA580C)],
  );

  final Json ad;

  @override
  Widget build(BuildContext context) {
    final sponsor = User.fromJson(asMap(ad['sponsor']));
    final custom = asMapOrNull(ad['custom']);
    final promotedPost = asMapOrNull(ad['post']);
    final mediaRaw = promotedPost?['media'];
    final firstMedia = mediaRaw is List && mediaRaw.isNotEmpty ? asMapOrNull(mediaRaw.first) : null;
    final image = asStrOrNull(custom?['image_url']) ??
        asStrOrNull(firstMedia?['url']) ??
        asStrOrNull(firstMedia?['poster_url']) ??
        sponsor.avatarUrl;
    final thumb = image ?? '';
    final title = asStr(
      custom?['title'],
      promotedPost != null ? asStr(promotedPost['body']).replaceAll('\n', ' ').trim() : sponsor.displayName.split(' ').first,
    );
  return GestureDetector(
      onTap: () => openOndAdStorySheet(context, ad),
      child: SizedBox(
        width: 86,
        child: Column(children: [
          SizedBox(
            height: 118,
            child: Stack(alignment: Alignment.topCenter, children: [
              Positioned(
                top: 38,
                child: Stack(alignment: Alignment.center, clipBehavior: Clip.none, children: [
                  Container(
                    width: 70,
                    height: 70,
                    padding: const EdgeInsets.all(3.2),
                    decoration: const BoxDecoration(shape: BoxShape.circle, gradient: _adRing),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Tx.bg, width: 2),
                        boxShadow: [BoxShadow(color: const Color(0xFFF97316).withValues(alpha: .22), blurRadius: 10, offset: const Offset(0, 3))],
                      ),
                      child: ClipOval(
                        child: thumb.isNotEmpty
                            ? NetImage(thumb, fit: BoxFit.cover)
                            : Avatar(user: sponsor, size: 64),
                      ),
                    ),
                  ),
                  Positioned(
                    top: -2,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        gradient: _adRing,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Tx.bg, width: 1.5),
                        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: .12), blurRadius: 4, offset: const Offset(0, 2))],
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(CupertinoIcons.speaker_2_fill, size: 9, color: Colors.white),
                        const SizedBox(width: 4),
                        Text(tr('Patrocinador'), style: Tx.body(8.5, weight: FontWeight.w900, color: Colors.white)),
                      ]),
                    ),
                  ),
                ]),
              ),
            ]),
          ),
          const SizedBox(height: 2),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Tx.body(12, weight: FontWeight.w700, color: const Color(0xFFC2410C)),
          ),
        ]),
      ),
    );
  }
}

Future<void> openOndAd(BuildContext context, Json ad) => followOndAdClick(context, ad);

/// Reel patrocinado a pantalla completa entre videos.
class SponsoredReelPage extends StatelessWidget {
  const SponsoredReelPage({super.key, required this.ad, required this.active});

  final Json ad;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final sponsor = User.fromJson(asMap(ad['sponsor']));
    final post = asMapOrNull(ad['post']);
    final custom = asMapOrNull(ad['custom']);
    final video = asStrOrNull(custom?['video_url']);
    final image = asStrOrNull(custom?['image_url']) ?? asStrOrNull(post?['media']?[0]?['poster_url']);
    final title = asStr(custom?['title'], post != null ? asStr(asMap(post['user'])['display_name']) : sponsor.displayName);
    final body = asStr(custom?['body'], post != null ? asStr(post['body']) : '');
    return ColoredBox(
        color: Colors.black,
        child: Stack(fit: StackFit.expand, children: [
          if (video != null && video.isNotEmpty)
            NetImage(video, fit: BoxFit.cover)
          else if (image != null && image.isNotEmpty)
            NetImage(image, fit: BoxFit.cover)
          else
            Center(child: Avatar(user: sponsor, size: 96)),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [Colors.black.withValues(alpha: .75), Colors.transparent],
                stops: const [.0, .55],
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Avatar(user: sponsor, size: 40),
                    const SizedBox(width: 10),
                    Expanded(child: Text(sponsor.displayName, style: Tx.body(15, weight: FontWeight.w700, color: Colors.white))),
                    ondAdSponsorBadge(fontSize: 10, onDark: true),
                  ]),
                  const Spacer(),
                  Text(title, style: Tx.body(18, weight: FontWeight.w800, color: Colors.white)),
                  if (body.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(body, maxLines: 3, overflow: TextOverflow.ellipsis, style: Tx.body(14, color: Colors.white70, height: 1.35)),
                    ),
                  const SizedBox(height: 16),
                  OndAdActionFooter(ad: ad, onDark: true),
                ],
              ),
            ),
          ),
        ]),
    );
  }
}
