import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/nav.dart';
import '../../core/paged.dart';
import '../../core/routes.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';
import '../../widgets/paged_view.dart';
import '../../widgets/settings_tiles.dart';
import 'wallet_screen.dart';

/// Compra (o extiende) la suscripción a [user] con el saldo del monedero. Devuelve hasta cuándo hay acceso.
/// Sin saldo suficiente (402) ofrece ir al monedero.
Future<DateTime?> subscribeTo(BuildContext context, User user, Money price, int days) async {
  if (!walletAvailable) return null;
  final ok = await confirm(
    context,
    tr('Suscribirte a {name}', {'name': user.displayName}),
    tr('Pagarás {price} de tu monedero por {days} días de acceso a su contenido exclusivo. Si ya tienes acceso, los días se suman.',
        {'price': price.formatted, 'days': days}),
    action: tr('Pagar {price}', {'price': price.formatted}),
  );
  if (!ok || !context.mounted) return null;
  try {
    final res = await api.post('users/${user.id}/subscribe');
    if (context.mounted) toast(context, asStr(res.map['message'], tr('Listo: ya tienes acceso.')));
    return asDate(res.map['access_until']);
  } on ApiException catch (e) {
    if (!context.mounted) return null;
    if (e.status == 402) {
      if (await confirm(context, tr('Saldo insuficiente'), e.message, action: tr('Ir al monedero'))) {
        if (context.mounted) push(context, const WalletScreen());
      }
    } else {
      toastError(context, e);
    }
  } catch (e) {
    if (context.mounted) toastError(context, e);
  }
  return null;
}

/// Ajustes › Colaborador: requisitos, plan (precio en USD y días), pausa, cifras y suscriptores (me/collaborator).
class CollaboratorScreen extends StatefulWidget {
  const CollaboratorScreen({super.key});

  @override
  State<CollaboratorScreen> createState() => _CollaboratorScreenState();
}

class _CollaboratorScreenState extends State<CollaboratorScreen> {
  final _price = TextEditingController();
  final _days = TextEditingController(text: '30');
  final _description = TextEditingController();
  Json? _data;
  Object? _error;
  bool _saving = false;
  bool _toggling = false;
  Map<String, String> _errors = {};

  @override
  void initState() {
    super.initState();
    _price.addListener(() => setState(() {}));
    _load();
  }

  @override
  void dispose() {
    _price.dispose();
    _days.dispose();
    _description.dispose();
    super.dispose();
  }

  void _apply(Json data, {bool fillForm = false}) {
    final plan = asMapOrNull(data['plan']);
    if (fillForm && plan != null) {
      _price.text = Money.fromJson(plan['price']).plain;
      _days.text = '${asInt(plan['days'], 30)}';
      _description.text = asStr(plan['description']);
    }
    _data = data;
    _error = null;
  }

  Future<void> _load() async {
    try {
      final res = await api.get('me/collaborator');
      if (mounted) setState(() => _apply(res.map, fillForm: _data == null));
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    final data = _data;
    if (data == null) return;
    final firstTime = data['plan'] == null;
    setState(() {
      _saving = true;
      _errors = {};
    });
    try {
      final res = await api.put('me/collaborator', {
        'price': _price.text.trim(),
        'days': int.tryParse(_days.text.trim()) ?? 0,
        'description': _description.text.trim(),
      });
      if (!mounted) return;
      toast(context, asStr(res.map['message'], tr('Guardamos tu plan de colaborador.')));
      setState(() => _apply(res.map, fillForm: true));
      if (firstTime) context.read<AppState>().refreshMe();
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
    if (mounted) setState(() => _saving = false);
  }

  Future<void> _setActive(bool active) async {
    if (!active &&
        !await confirm(context, tr('Pausar plan'), tr('Nadie podrá suscribirse mientras esté en pausa. Quien ya pagó conserva su acceso hasta que termine.'),
            action: tr('Pausar'))) {
      return;
    }
    setState(() => _toggling = true);
    try {
      final res = await api.post(active ? 'me/collaborator/resume' : 'me/collaborator/pause');
      if (!mounted) return;
      toast(context, asStr(res.map['message']));
      setState(() => _apply(res.map));
      context.read<AppState>().refreshMe();
    } catch (e) {
      if (mounted) toastError(context, e);
    }
    if (mounted) setState(() => _toggling = false);
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    return Scaffold(
      appBar: GlassBar(title: tr('Colaborador')),
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
    final plan = asMapOrNull(data['plan']);
    final active = asBool(data['active']);
    final canActivate = asBool(data['can_activate']);
    final checks = asList(data['checks'], (j) => j);
    final rules = asMap(data['rules']);
    final stats = asMap(data['stats']);
    final commission = asInt(rules['commission'], 20);
    final cents = Money.parseCents(_price.text);

    return [
      Panel(
        gradient: true,
        padding: const EdgeInsets.all(18),
        child: Row(children: [
          Container(
            width: 52,
            height: 52,
            decoration: const BoxDecoration(gradient: Tx.brand, shape: BoxShape.circle),
            child: const Icon(CupertinoIcons.star_circle_fill, color: Colors.white, size: 28),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                plan == null ? tr('Contenido para suscriptores') : (active ? tr('Tu plan está activo') : tr('Tu plan está en pausa')),
                style: Tx.body(17, weight: FontWeight.w700),
              ),
              const SizedBox(height: 3),
              Text(
                tr('Publica contenido que solo ven quienes se suscriben a tu cuenta. Tú eliges el precio en dólares y los días; TREVIX se queda con el {pct} % de cada compra.',
                    {'pct': commission}),
                style: Tx.body(13.5, color: Tx.muted, height: 1.35),
              ),
            ]),
          ),
        ]),
      ),
      if (plan != null) ...[
        const SizedBox(height: 14),
        Row(children: [
          _StatBox(value: '${asInt(stats['subscribers'])}', label: tr('suscriptores activos')),
          _StatBox(value: '${asInt(stats['sales'])}', label: tr('ventas')),
          _StatBox(value: Money.fromJson(stats['earned']).formatted, label: tr('ganado')),
        ]),
        SettingsGroup(title: tr('Tu plan'), children: [
          SettingsRow(
            icon: active ? CupertinoIcons.play_circle_fill : CupertinoIcons.pause_circle_fill,
            color: active ? Tx.success : Tx.warning,
            label: tr('Aceptar suscripciones'),
            subtitle: active ? tr('Cualquiera puede suscribirse desde tu perfil.') : tr('En pausa: quien ya pagó conserva su acceso.'),
            trailing: _toggling ? const CupertinoActivityIndicator() : TxSwitch(value: active, onChanged: _setActive),
          ),
          SettingsRow(
            icon: CupertinoIcons.doc_richtext,
            color: Tx.accentSoft,
            label: tr('Publicaciones exclusivas'),
            value: '${asInt(stats['exclusive_posts'])}',
            subtitle: tr('Al publicar, elige «Suscriptores» en ¿Quién puede verla?'),
          ),
          SettingsRow(
            icon: CupertinoIcons.person_2_fill,
            color: Tx.blue400,
            label: tr('Suscriptores'),
            onTap: () => push(context, const SubscribersScreen()),
          ),
          SettingsRow(icon: CupertinoIcons.creditcard_fill, color: Tx.cyan, label: tr('Monedero y retiros'), onTap: () => push(context, const WalletScreen())),
        ]),
      ],
      if (plan == null)
        SettingsGroup(
          title: tr('Requisitos'),
          footer: tr('Solo se piden para activar el plan por primera vez.'),
          children: [
            for (final c in checks)
              SettingsRow(
                icon: asBool(c['ok']) ? CupertinoIcons.checkmark_circle_fill : CupertinoIcons.circle,
                color: asBool(c['ok']) ? Tx.success : Tx.subtle,
                label: asStr(c['label']),
                subtitle: asStr(c['detail']),
              ),
          ],
        ),
      if (plan == null && !canActivate)
        Padding(
          padding: const EdgeInsets.fromLTRB(6, 16, 6, 0),
          child: Text(
            tr('Cuando cumplas todos los requisitos podrás activar tu plan aquí.'),
            textAlign: TextAlign.center,
            style: Tx.body(13.5, color: Tx.muted, height: 1.4),
          ),
        ),
      if (canActivate) ...[
        SectionTitle(plan == null ? tr('Activar mi plan') : tr('Precio y duración'), padding: const EdgeInsets.fromLTRB(4, 24, 4, 10)),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            flex: 3,
            child: TextField(
              controller: _price,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')), LengthLimitingTextInputFormatter(10)],
              style: Tx.body(15),
              decoration: fieldDecoration(
                Money.fromJson(rules['min_price']).plain,
                label: tr('Precio (USD)'),
                error: _errors['price'],
                prefix: Padding(padding: const EdgeInsets.only(left: 14, right: 6), child: Text('US\$', style: Tx.body(15, color: Tx.muted))),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 2,
            child: TextField(
              controller: _days,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(4)],
              style: Tx.body(15),
              decoration: fieldDecoration('30', label: tr('Días'), error: _errors['days']),
            ),
          ),
        ]),
        Padding(
          padding: const EdgeInsets.fromLTRB(6, 8, 6, 12),
          child: Text(
            [
              tr('De {min} a {max}, hasta {days} días.', {
                'min': Money.fromJson(rules['min_price']).formatted,
                'max': Money.fromJson(rules['max_price']).formatted,
                'days': asInt(rules['max_days']),
              }),
              if (cents != null && cents > 0)
                tr('Recibirás {amount} por cada compra.', {'amount': Money.local(cents - Money.commission(cents, commission)).formatted}),
            ].join(' '),
            style: Tx.body(12.5, color: Tx.muted, height: 1.4),
          ),
        ),
        TextField(
          controller: _description,
          maxLength: 300,
          minLines: 2,
          maxLines: 4,
          style: Tx.body(15),
          decoration: fieldDecoration(tr('Qué recibirán tus suscriptores (opcional)'), label: tr('Descripción'), error: _errors['description']),
        ),
        const SizedBox(height: 12),
        GradientButton(
          label: plan == null ? tr('Activar plan') : tr('Guardar cambios'),
          icon: plan == null ? CupertinoIcons.star_fill : CupertinoIcons.checkmark_alt,
          loading: _saving,
          onPressed: _saving ? null : _save,
        ),
        if (plan != null)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(
              tr('Los cambios de precio valen para las compras nuevas; quien ya pagó conserva sus días.'),
              textAlign: TextAlign.center,
              style: Tx.body(12.5, color: Tx.subtle, height: 1.4),
            ),
          ),
      ],
    ];
  }
}

class _StatBox extends StatelessWidget {
  const _StatBox({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
        decoration: BoxDecoration(color: Tx.surface1, borderRadius: BorderRadius.circular(16), border: Border.all(color: Tx.border)),
        child: Column(children: [
          FittedBox(child: Text(value, style: Tx.display(18))),
          const SizedBox(height: 2),
          Text(label, textAlign: TextAlign.center, style: Tx.body(11.5, color: Tx.muted)),
        ]),
      ),
    );
  }
}

/// Quienes compraron el plan, con el acceso vigente primero.
class SubscribersScreen extends StatefulWidget {
  const SubscribersScreen({super.key});

  @override
  State<SubscribersScreen> createState() => _SubscribersScreenState();
}

class _SubscribersScreenState extends State<SubscribersScreen> {
  final _list = Paged<Json>('me/collaborator/subscribers', (j) => j);

  @override
  void dispose() {
    _list.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: GlassBar(title: tr('Suscriptores')),
      body: PagedView<Json>(
        paged: _list,
        empty: EmptyState(icon: CupertinoIcons.person_2, title: tr('Aún no tienes suscriptores'), message: tr('Comparte tu perfil y publica contenido exclusivo.')),
        itemBuilder: (context, j, _) {
          final user = User.fromJson(j);
          final active = asBool(j['active']);
          final purchases = asInt(j['purchases']);
          return _AccessTile(
            user: user,
            active: active,
            detail: [
              active
                  ? tr('Acceso hasta el {date}', {'date': fullDate(asDate(j['access_until']))})
                  : tr('Venció el {date}', {'date': fullDate(asDate(j['access_until']))}),
              purchases == 1 ? tr('1 compra') : tr('{n} compras', {'n': purchases}),
            ].join(' · '),
          );
        },
      ),
    );
  }
}

/// Colaboradores a los que estoy suscrito. En iOS se puede extender o renovar.
class SubscriptionsScreen extends StatefulWidget {
  const SubscriptionsScreen({super.key});

  @override
  State<SubscriptionsScreen> createState() => _SubscriptionsScreenState();
}

class _SubscriptionsScreenState extends State<SubscriptionsScreen> {
  final _list = Paged<Json>('me/subscriptions', (j) => j);

  @override
  void dispose() {
    _list.dispose();
    super.dispose();
  }

  Future<void> _renew(Json j) async {
    final price = Money.maybe(j['price']);
    final days = asIntOrNull(j['days']);
    if (price == null || days == null) return;
    final until = await subscribeTo(context, User.fromJson(j), price, days);
    if (until != null) _list.refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: GlassBar(title: tr('Mis suscripciones')),
      body: PagedView<Json>(
        paged: _list,
        empty: EmptyState(
          icon: CupertinoIcons.star,
          title: tr('No tienes suscripciones'),
          message: tr('Cuando te suscribas a un colaborador, verás aquí hasta cuándo tienes acceso.'),
        ),
        itemBuilder: (context, j, _) {
          final user = User.fromJson(j);
          final active = asBool(j['active']);
          final price = Money.maybe(j['price']);
          final canBuy = walletAvailable && asBool(j['accepting']) && price != null;
          return _AccessTile(
            user: user,
            active: active,
            detail: [
              active
                  ? tr('Acceso hasta el {date}', {'date': fullDate(asDate(j['access_until']))})
                  : tr('Venció el {date}', {'date': fullDate(asDate(j['access_until']))}),
              if (canBuy) tr('{price} por {days} días', {'price': price.formatted, 'days': asInt(j['days'])}),
            ].join(' · '),
            action: canBuy ? SoftButton(label: active ? tr('Extender') : tr('Renovar'), height: 34, onPressed: () => _renew(j)) : null,
          );
        },
      ),
    );
  }
}

class _AccessTile extends StatelessWidget {
  const _AccessTile({required this.user, required this.active, required this.detail, this.action});

  final User user;
  final bool active;
  final String detail;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => openProfile(context, user.username),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(children: [
          Avatar(user: user, size: 46),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              NameLine(user: user),
              const SizedBox(height: 2),
              Text(detail, style: Tx.body(12.5, color: active ? Tx.muted : Tx.subtle, height: 1.35)),
            ]),
          ),
          if (action != null) ...[const SizedBox(width: 8), action!],
        ]),
      ),
    );
  }
}
