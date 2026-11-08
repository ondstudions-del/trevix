import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/nav.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';
import '../../widgets/settings_tiles.dart';
import 'account_status_screen.dart';

/// Verificado: requisitos (seguidores, promedio de «Me gusta», sin advertencias recientes), estado de la
/// solicitud y formulario para pedirlo (me/verification). El servidor vuelve a comprobar todo al enviarla.
class VerificationScreen extends StatefulWidget {
  const VerificationScreen({super.key});

  @override
  State<VerificationScreen> createState() => _VerificationScreenState();
}

class _VerificationScreenState extends State<VerificationScreen> {
  final _name = TextEditingController();
  final _note = TextEditingController();
  Json? _data;
  Object? _error;
  String? _category;
  bool _sending = false;
  Map<String, String> _errors = {};

  @override
  void initState() {
    super.initState();
    _name.text = context.read<AppState>().me?.user.displayName ?? '';
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final res = await api.get('me/verification');
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

  List<Choice> get _categories => asList(_data?['categories'], Choice.fromJson);

  void _pickCategory() {
    actionSheet(context, [
      for (final c in _categories)
        SheetAction(c.label, _category == c.key ? CupertinoIcons.checkmark_circle_fill : CupertinoIcons.circle, () => setState(() => _category = c.key)),
    ], title: '¿Qué te describe mejor?');
  }

  Future<void> _send() async {
    final errors = <String, String>{};
    if (_category == null) errors['category'] = 'Elige la categoría que mejor te describe.';
    if (_name.text.trim().length < 2) errors['full_name'] = 'Escribe tu nombre real o el de tu marca.';
    if (errors.isNotEmpty) {
      setState(() => _errors = errors);
      return;
    }
    setState(() {
      _sending = true;
      _errors = {};
    });
    try {
      final res = await api.post('me/verification', {'category': _category, 'full_name': _name.text.trim(), 'note': _note.text.trim()});
      if (!mounted) return;
      toast(context, '${res.map['message'] ?? 'Solicitud enviada.'}');
      setState(() => _data = res.map);
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.fields.isNotEmpty && !e.fields.containsKey('form')) {
        setState(() => _errors = e.fields);
      } else {
        toastError(context, e);
        _load();
      }
    } catch (e) {
      if (mounted) toastError(context, e);
    }
    if (mounted) setState(() => _sending = false);
  }

  Future<void> _cancel() async {
    if (!await confirm(context, 'Cancelar solicitud', '¿Quieres cancelar tu solicitud de verificado? Podrás volver a pedirlo cuando quieras.',
        action: 'Cancelar solicitud', destructive: true)) {
      return;
    }
    try {
      final res = await api.delete('me/verification');
      if (!mounted) return;
      toast(context, '${res.map['message'] ?? 'Solicitud cancelada.'}');
      setState(() => _data = res.map);
    } catch (e) {
      if (mounted) toastError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    return Scaffold(
      appBar: const GlassBar(title: 'Verificación'),
      body: data == null
          ? (_error != null ? ErrorState(error: _error!, onRetry: _load) : const Loading())
          : RefreshIndicator(
              onRefresh: _load,
              color: Tx.accentSoft,
              child: ListView(padding: const EdgeInsets.fromLTRB(16, 14, 16, 60), children: _content(data)),
            ),
    );
  }

  List<Widget> _content(Json data) {
    final verified = asBool(data['verified']);
    final checks = asList(data['checks'], (j) => j);
    final request = asMapOrNull(data['request']);
    final canApply = asBool(data['can_apply']);
    final blocked = asStrOrNull(data['blocked_reason']);
    final pending = request != null && request['status'] == 'pending';
    final category = _categories.where((c) => c.key == _category).firstOrNull;

    return [
      Panel(
        gradient: true,
        padding: const EdgeInsets.all(18),
        child: Row(children: [
          Container(
            width: 52,
            height: 52,
            decoration: const BoxDecoration(gradient: Tx.brand, shape: BoxShape.circle),
            child: const Icon(CupertinoIcons.checkmark_seal_fill, color: Colors.white, size: 28),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(verified ? 'Tu cuenta está verificada' : 'Insignia de verificado', style: Tx.body(17, weight: FontWeight.w700)),
              const SizedBox(height: 3),
              Text(
                verified
                    ? 'La insignia aparece junto a tu nombre en tu perfil, publicaciones y comentarios.'
                    : 'Muestra que tu cuenta es auténtica y relevante. El equipo de TREVIX revisa cada solicitud.',
                style: Tx.body(13.5, color: Tx.muted, height: 1.35),
              ),
            ]),
          ),
        ]),
      ),
      if (!verified) ...[
        SettingsGroup(title: 'Requisitos', children: [
          for (final c in checks)
            SettingsRow(
              icon: asBool(c['ok']) ? CupertinoIcons.checkmark_circle_fill : CupertinoIcons.circle,
              color: asBool(c['ok']) ? Tx.success : Tx.subtle,
              label: asStr(c['label']),
              subtitle: asStr(c['detail']),
              onTap: c['key'] == 'warnings' && !asBool(c['ok']) ? () => push(context, const AccountStatusScreen()) : null,
            ),
        ]),
      ],
      if (request != null) ...[
        SettingsGroup(title: 'Tu solicitud', children: [
          SettingsRow(
            icon: switch (request['status']) {
              'approved' => CupertinoIcons.checkmark_seal_fill,
              'rejected' => CupertinoIcons.xmark_circle_fill,
              'cancelled' => CupertinoIcons.minus_circle,
              _ => CupertinoIcons.clock_fill,
            },
            color: switch (request['status']) {
              'approved' => Tx.success,
              'rejected' => Tx.danger,
              'cancelled' => Tx.subtle,
              _ => Tx.warning,
            },
            label: asStr(request['status_label']),
            subtitle: '${asStr(request['category_label'])} · ${asStr(request['full_name'])} · ${timeAgo(asDate(request['created_at']))}',
          ),
          if (request['status'] == 'rejected' && asStrOrNull(request['decision_note']) != null)
            SettingsRow(icon: CupertinoIcons.text_bubble, color: Tx.muted, label: 'Motivo', subtitle: asStr(request['decision_note'])),
          if (pending) SettingsRow(icon: CupertinoIcons.xmark, color: Tx.danger, label: 'Cancelar solicitud', destructive: true, onTap: _cancel),
        ]),
      ],
      if (!verified && !canApply && !pending && blocked != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(6, 16, 6, 0),
          child: Text(blocked, textAlign: TextAlign.center, style: Tx.body(13.5, color: Tx.muted, height: 1.4)),
        ),
      if (canApply) ...[
        const SectionTitle('Pedir el verificado', padding: EdgeInsets.fromLTRB(4, 24, 4, 10)),
        GestureDetector(
          onTap: _pickCategory,
          child: InputDecorator(
            decoration: fieldDecoration('Categoría', label: 'Categoría', error: _errors['category'], suffix: Icon(CupertinoIcons.chevron_down, size: 16, color: Tx.subtle)),
            isEmpty: category == null,
            child: Text(category?.label ?? '', style: Tx.body(15)),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _name,
          maxLength: 80,
          textCapitalization: TextCapitalization.words,
          style: Tx.body(15),
          decoration: fieldDecoration('Nombre real o de tu marca', label: 'Nombre', error: _errors['full_name']),
        ),
        const SizedBox(height: 4),
        TextField(
          controller: _note,
          maxLength: 500,
          minLines: 3,
          maxLines: 6,
          style: Tx.body(15),
          decoration: fieldDecoration('¿Por qué deberíamos verificar tu cuenta? (opcional)', label: 'Cuéntanos', error: _errors['note']),
        ),
        const SizedBox(height: 12),
        GradientButton(label: 'Enviar solicitud', icon: CupertinoIcons.paperplane_fill, loading: _sending, onPressed: _sending ? null : _send),
      ],
    ];
  }
}
