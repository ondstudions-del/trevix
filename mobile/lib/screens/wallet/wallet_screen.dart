import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/api.dart';
import '../../core/config.dart';
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

/// Ajustes › Monedero: saldo en USD, recargas con comprobante, retiros de lo ganado y movimientos (me/wallet).
class WalletScreen extends StatefulWidget {
  const WalletScreen({super.key});

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen> {
  final _transactions = Paged<Json>('me/wallet/transactions', (j) => j);
  Json? _summary;
  List<Json> _topups = [];
  List<Json> _withdrawals = [];
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _transactions.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final res = await Future.wait([api.get('me/wallet'), api.get('me/wallet/topups'), api.get('me/wallet/withdrawals')]);
      if (!mounted) return;
      setState(() {
        _summary = res[0].map;
        _topups = res[1].list;
        _withdrawals = res[2].list;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _reloadAll() async {
    await Future.wait([_load(), _transactions.refresh()]);
  }

  Future<void> _topup() async {
    final summary = _summary;
    if (summary == null) return;
    final sent = await push<bool>(context, TopupScreen(summary: summary));
    if (sent == true) _load();
  }

  Future<void> _withdraw() async {
    final summary = _summary;
    if (summary == null) return;
    final sent = await push<bool>(context, WithdrawScreen(summary: summary));
    if (sent == true) _reloadAll();
  }

  Future<void> _cancel(String kind, Json item) async {
    final topup = kind == 'topups';
    if (!await confirm(
      context,
      topup ? tr('Cancelar recarga') : tr('Cancelar retiro'),
      topup ? tr('El equipo ya no revisará esta recarga.') : tr('El dinero vuelve a tu monedero.'),
      action: topup ? tr('Cancelar recarga') : tr('Cancelar retiro'),
      destructive: true,
    )) {
      return;
    }
    try {
      final res = await api.delete('me/wallet/$kind/${item['id']}');
      if (mounted) toast(context, asStr(res.map['message'], tr('Listo.')));
      _reloadAll();
    } catch (e) {
      if (mounted) toastError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final summary = _summary;
    return Scaffold(
      appBar: GlassBar(title: tr('Monedero')),
      body: summary == null
          ? (_error != null ? ErrorState(error: _error!, onRetry: _load) : const Loading())
          : PagedView<Json>(
              paged: _transactions,
              onRefresh: _load,
              header: [SliverPadding(padding: const EdgeInsets.fromLTRB(16, 14, 16, 0), sliver: SliverList(delegate: SliverChildListDelegate(_header(summary))))],
              empty: EmptyState(icon: CupertinoIcons.list_bullet, title: tr('Sin movimientos'), message: tr('Aquí verás tus recargas, compras, ingresos y retiros.')),
              itemBuilder: (context, t, _) => _TransactionTile(t),
            ),
    );
  }

  List<Widget> _header(Json summary) {
    final balance = Money.fromJson(summary['balance']);
    final withdrawable = Money.fromJson(summary['withdrawable']);
    final minWithdrawal = Money.fromJson(summary['min_withdrawal']);
    final pendingWithdrawal = asMapOrNull(summary['pending_withdrawal']);
    final pendingTopups = asInt(summary['pending_topups']);
    final requests = [
      for (final t in _topups.take(5)) ('topups', t),
      for (final w in _withdrawals.take(5)) ('withdrawals', w),
    ]..sort((a, b) => asStr(b.$2['created_at']).compareTo(asStr(a.$2['created_at'])));

    return [
      Panel(
        gradient: true,
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              width: 40,
              height: 40,
              decoration: const BoxDecoration(gradient: Tx.brand, shape: BoxShape.circle),
              child: const Icon(CupertinoIcons.creditcard_fill, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 12),
            Text(tr('Saldo disponible'), style: Tx.body(14.5, color: Tx.muted, weight: FontWeight.w600)),
          ]),
          const SizedBox(height: 14),
          Text(balance.formatted, style: Tx.display(34)),
          const SizedBox(height: 4),
          Text(
            withdrawable.cents > 0
                ? tr('Puedes retirar {amount} de lo ganado como colaborador.', {'amount': withdrawable.formatted})
                : tr('Recarga para suscribirte a colaboradores. El saldo de recargas no se puede retirar.'),
            style: Tx.body(13, color: Tx.muted, height: 1.35),
          ),
          if (pendingTopups > 0) ...[
            const SizedBox(height: 10),
            Row(children: [
              const Icon(CupertinoIcons.clock_fill, size: 15, color: Tx.warning),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  pendingTopups == 1 ? tr('1 recarga en revisión.') : tr('{n} recargas en revisión.', {'n': pendingTopups}),
                  style: Tx.body(13, color: Tx.warning, weight: FontWeight.w600),
                ),
              ),
            ]),
          ],
          const SizedBox(height: 16),
          Row(children: [
            Expanded(child: GradientButton(label: tr('Recargar saldo'), icon: CupertinoIcons.plus_circle_fill, height: 46, onPressed: _topup)),
            if (withdrawable.cents > 0 && pendingWithdrawal == null) ...[
              const SizedBox(width: 10),
              Expanded(
                child: SoftButton(
                  label: tr('Retirar'),
                  icon: CupertinoIcons.arrow_up_circle,
                  height: 46,
                  expand: true,
                  onPressed: withdrawable.cents >= minWithdrawal.cents
                      ? _withdraw
                      : () => toast(context, tr('El retiro mínimo es {amount}.', {'amount': minWithdrawal.formatted}), error: true),
                ),
              ),
            ],
          ]),
        ]),
      ),
      if (requests.isNotEmpty)
        SettingsGroup(title: tr('Solicitudes'), children: [
          for (final r in requests) _requestRow(r.$1, r.$2),
        ]),
      SectionTitle(tr('Movimientos'), padding: const EdgeInsets.fromLTRB(4, 24, 4, 6)),
    ];
  }

  Widget _requestRow(String kind, Json item) {
    final topup = kind == 'topups';
    final status = asStr(item['status']);
    final amount = Money.fromJson(item['amount']);
    final credited = Money.maybe(item['credited']);
    final note = asStrOrNull(item['decision_note']);
    final reference = asStrOrNull(item['payout_reference']);
    final detail = [
      asStr(item['status_label']),
      asStr(item['method']),
      timeAgo(asDate(item['created_at'])),
      if (credited != null && credited.cents != amount.cents) tr('Acreditado: {amount}', {'amount': credited.formatted}),
      if (reference != null) tr('Referencia: {ref}', {'ref': reference}),
      if (note != null && status != 'pending') note,
    ].where((s) => s.isNotEmpty).join(' · ');
    return SettingsRow(
      icon: topup ? CupertinoIcons.arrow_down_circle_fill : CupertinoIcons.arrow_up_circle_fill,
      color: _statusColor(status),
      label: topup ? tr('Recarga de {amount}', {'amount': amount.formatted}) : tr('Retiro de {amount}', {'amount': amount.formatted}),
      subtitle: detail,
      trailing: status == 'pending'
          ? IconButton(
              tooltip: tr('Cancelar'),
              onPressed: () => _cancel(kind, item),
              icon: Icon(CupertinoIcons.xmark_circle, color: Tx.subtle, size: 22),
            )
          : null,
    );
  }
}

Color _statusColor(String status) => switch (status) {
      'approved' || 'paid' => Tx.success,
      'rejected' => Tx.danger,
      'cancelled' => Tx.subtle,
      _ => Tx.warning,
    };

class _TransactionTile extends StatelessWidget {
  const _TransactionTile(this.t);

  final Json t;

  static IconData _icon(String type) => switch (type) {
        'topup' => CupertinoIcons.arrow_down_circle_fill,
        'subscription' => CupertinoIcons.star_circle_fill,
        'earning' => CupertinoIcons.money_dollar_circle_fill,
        'withdrawal' => CupertinoIcons.arrow_up_circle_fill,
        'withdrawal_refund' => CupertinoIcons.arrow_uturn_left_circle_fill,
        _ => CupertinoIcons.slider_horizontal_3,
      };

  @override
  Widget build(BuildContext context) {
    final amount = Money.fromJson(t['amount']);
    final after = Money.fromJson(t['balance_after']);
    final counterpart = asMapOrNull(t['counterpart']);
    final user = counterpart != null ? User.fromJson(counterpart) : null;
    final positive = amount.cents > 0;
    return InkWell(
      onTap: user != null ? () => openProfile(context, user.username) : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        child: Row(children: [
          if (user != null)
            Avatar(user: user, size: 40)
          else
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: Tx.alpha(positive ? Tx.success : Tx.accentSoft, .16), shape: BoxShape.circle),
              child: Icon(_icon(asStr(t['type'])), color: positive ? Tx.success : Tx.accentSoft, size: 21),
            ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(asStr(t['label']), maxLines: 2, overflow: TextOverflow.ellipsis, style: Tx.body(14.5, weight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text(fullDate(asDate(t['created_at'])), style: Tx.body(12.5, color: Tx.subtle)),
            ]),
          ),
          const SizedBox(width: 10),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(
              positive ? '+${amount.formatted}' : amount.formatted,
              style: Tx.body(15, weight: FontWeight.w700, color: positive ? Tx.success : Tx.text),
            ),
            Text(tr('Saldo: {amount}', {'amount': after.formatted}), style: Tx.body(11.5, color: Tx.subtle)),
          ]),
        ]),
      ),
    );
  }
}

/// Recargar: el pago se hace por fuera con el medio que configuró el equipo y se envía el comprobante.
/// El saldo se acredita cuando el equipo lo revisa.
class TopupScreen extends StatefulWidget {
  const TopupScreen({super.key, required this.summary});

  final Json summary;

  @override
  State<TopupScreen> createState() => _TopupScreenState();
}

class _TopupScreenState extends State<TopupScreen> {
  final _amount = TextEditingController();
  final _reference = TextEditingController();
  final _note = TextEditingController();
  late final List<Json> _methods = asList(widget.summary['methods'], (j) => j);
  late Json? _method = _methods.length == 1 ? _methods.first : null;
  XFile? _proof;
  bool _sending = false;
  Map<String, String> _errors = {};

  @override
  void dispose() {
    _amount.dispose();
    _reference.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _pickProof() async {
    try {
      final file = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 88, maxWidth: 2200);
      if (file != null && mounted) {
        setState(() {
          _proof = file;
          _errors.remove('proof');
        });
      }
    } catch (e) {
      if (mounted) toastError(context, e);
    }
  }

  Future<void> _send() async {
    FocusScope.of(context).unfocus();
    final errors = <String, String>{};
    if (_method == null) errors['method_id'] = tr('Elige un medio de pago.');
    if (_amount.text.trim().isEmpty) errors['amount'] = tr('Escribe el monto que pagaste, en dólares (por ejemplo 10 o 12.50).');
    if (_reference.text.trim().length < 3) errors['reference'] = tr('Escribe el número de transacción o la referencia del pago.');
    if (_proof == null) errors['proof'] = tr('Adjunta la captura o foto del comprobante.');
    if (errors.isNotEmpty) {
      setState(() => _errors = errors);
      return;
    }
    setState(() {
      _sending = true;
      _errors = {};
    });
    try {
      final res = await api.upload('me/wallet/topups', fields: {
        'method_id': '${_method!['id']}',
        'amount': _amount.text.trim(),
        'reference': _reference.text.trim(),
        'note': _note.text.trim(),
      }, files: [
        Upload('proof', _proof!.path, filename: _proof!.name),
      ]);
      if (!mounted) return;
      toast(context, asStr(res.map['message'], tr('Enviamos tu recarga a revisión.')));
      Navigator.of(context).pop(true);
      return;
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.fields.isNotEmpty && !e.fields.containsKey('form')) {
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
    final method = _method;
    final max = Money.fromJson(widget.summary['max_topup']);
    return Scaffold(
      appBar: GlassBar(title: tr('Recargar saldo')),
      body: _methods.isEmpty
          ? EmptyState(
              icon: CupertinoIcons.creditcard,
              title: tr('Aún no hay medios de pago'),
              message: tr('El equipo de TREVIX todavía no configuró cómo recargar. Inténtalo más tarde.'),
            )
          : ListView(padding: const EdgeInsets.fromLTRB(16, 14, 16, 60), children: [
              _Step(n: 1, text: tr('Elige el medio de pago y paga el monto que quieras recargar.')),
              _Step(n: 2, text: tr('Guarda la captura del comprobante y el número de transacción.')),
              _Step(n: 3, text: tr('Envíalo aquí. Cuando el equipo lo revise, el saldo aparecerá en tu monedero.')),
              const _RefundNote(),
              SettingsGroup(title: tr('Medio de pago'), children: [
                for (final m in _methods)
                  SettingsRow(
                    icon: identical(m, method) ? CupertinoIcons.checkmark_circle_fill : CupertinoIcons.circle,
                    color: identical(m, method) ? Tx.accentSoft : Tx.subtle,
                    label: asStr(m['name']),
                    subtitle: tr('Mínimo {amount}', {'amount': Money.fromJson(m['min_amount']).formatted}),
                    trailing: const SizedBox.shrink(),
                    onTap: () => setState(() {
                      _method = m;
                      _errors.remove('method_id');
                    }),
                  ),
              ]),
              if (_errors['method_id'] != null) _FieldError(_errors['method_id']!),
              if (method != null) ...[
                const SizedBox(height: 12),
                Panel(
                  padding: const EdgeInsets.all(16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Expanded(child: Text(tr('Cómo pagar con {method}', {'method': asStr(method['name'])}), style: Tx.body(15, weight: FontWeight.w700))),
                      IconButton(
                        tooltip: tr('Copiar'),
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: asStr(method['instructions'])));
                          toast(context, tr('Copiado.'));
                        },
                        icon: Icon(CupertinoIcons.doc_on_doc, size: 19, color: Tx.accent),
                      ),
                    ]),
                    SelectableText(asStr(method['instructions']), style: Tx.body(14, height: 1.45, color: Tx.muted)),
                  ]),
                ),
              ],
              SectionTitle(tr('Comprobante'), padding: const EdgeInsets.fromLTRB(4, 24, 4, 10)),
              TextField(
                controller: _amount,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')), LengthLimitingTextInputFormatter(10)],
                style: Tx.body(15),
                decoration: fieldDecoration(
                  tr('Hasta {amount}', {'amount': max.formatted}),
                  label: tr('Monto pagado (USD)'),
                  error: _errors['amount'],
                  prefix: Padding(padding: const EdgeInsets.only(left: 14, right: 6), child: Text('US\$', style: Tx.body(15, color: Tx.muted))),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _reference,
                maxLength: 120,
                style: Tx.body(15),
                decoration: fieldDecoration(tr('Número de transacción o referencia'), label: tr('Referencia'), error: _errors['reference']),
              ),
              const SizedBox(height: 4),
              TextField(
                controller: _note,
                maxLength: 500,
                minLines: 2,
                maxLines: 4,
                style: Tx.body(15),
                decoration: fieldDecoration(tr('Algo que el equipo deba saber (opcional)'), label: tr('Nota'), error: _errors['note']),
              ),
              const SizedBox(height: 8),
              GestureDetector(
                onTap: _sending ? null : _pickProof,
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Tx.surface1,
                    borderRadius: BorderRadius.circular(Tx.radiusLg),
                    border: Border.all(color: _errors['proof'] != null ? Tx.danger : Tx.borderStrong),
                  ),
                  child: Row(children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: _proof != null
                          ? Image.file(File(_proof!.path), width: 64, height: 64, fit: BoxFit.cover)
                          : Container(width: 64, height: 64, color: Tx.surface3, child: Icon(CupertinoIcons.photo, color: Tx.subtle)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(_proof != null ? tr('Comprobante adjunto') : tr('Adjuntar comprobante'), style: Tx.body(15, weight: FontWeight.w600)),
                        const SizedBox(height: 2),
                        Text(
                          _proof != null ? tr('Toca para cambiarlo.') : tr('Captura o foto donde se vean el monto, la fecha y la referencia.'),
                          style: Tx.body(12.5, color: Tx.muted, height: 1.35),
                        ),
                      ]),
                    ),
                    Icon(CupertinoIcons.chevron_right, size: 15, color: Tx.subtle),
                  ]),
                ),
              ),
              if (_errors['proof'] != null) _FieldError(_errors['proof']!),
              const SizedBox(height: 18),
              GradientButton(label: tr('Enviar a revisión'), icon: CupertinoIcons.paperplane_fill, loading: _sending, onPressed: _sending ? null : _send),
              const SizedBox(height: 10),
              Text(
                tr('Solo verá el comprobante el equipo de TREVIX. Si el monto no coincide, se acredita lo que muestre el comprobante.'),
                textAlign: TextAlign.center,
                style: Tx.body(12.5, color: Tx.subtle, height: 1.4),
              ),
            ]),
    );
  }
}

/// Retirar lo ganado como colaborador: se descuenta ya y el equipo lo paga por fuera.
class WithdrawScreen extends StatefulWidget {
  const WithdrawScreen({super.key, required this.summary});

  final Json summary;

  @override
  State<WithdrawScreen> createState() => _WithdrawScreenState();
}

class _WithdrawScreenState extends State<WithdrawScreen> {
  late final Money _withdrawable = Money.fromJson(widget.summary['withdrawable']);
  late final Money _min = Money.fromJson(widget.summary['min_withdrawal']);
  late final _amount = TextEditingController(text: _withdrawable.plain);
  final _method = TextEditingController();
  final _account = TextEditingController();
  bool _sending = false;
  Map<String, String> _errors = {};

  @override
  void dispose() {
    _amount.dispose();
    _method.dispose();
    _account.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    FocusScope.of(context).unfocus();
    final errors = <String, String>{};
    if (_amount.text.trim().isEmpty) errors['amount'] = tr('Escribe el monto en dólares (por ejemplo 25 o 25.50).');
    if (_method.text.trim().length < 2) errors['method'] = tr('Escribe por dónde quieres recibirlo (por ejemplo PayPal o Llave Bre-B).');
    if (_account.text.trim().length < 3) errors['account'] = tr('Escribe la cuenta, el correo o la llave donde quieres recibirlo.');
    if (errors.isNotEmpty) {
      setState(() => _errors = errors);
      return;
    }
    if (!await confirm(context, tr('Pedir retiro'), tr('Se descontará de tu monedero ahora. Si el equipo lo rechaza o lo cancelas, el dinero vuelve.'),
        action: tr('Pedir retiro'))) {
      return;
    }
    setState(() {
      _sending = true;
      _errors = {};
    });
    try {
      final res = await api.post('me/wallet/withdrawals', {'amount': _amount.text.trim(), 'method': _method.text.trim(), 'account': _account.text.trim()});
      if (!mounted) return;
      toast(context, asStr(res.map['message'], tr('Pediste el retiro.')));
      Navigator.of(context).pop(true);
      return;
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.fields.isNotEmpty && !e.fields.containsKey('form')) {
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
    return Scaffold(
      appBar: GlassBar(title: tr('Retirar')),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 14, 16, 60), children: [
        Panel(
          gradient: true,
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tr('Puedes retirar'), style: Tx.body(13.5, color: Tx.muted, weight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(_withdrawable.formatted, style: Tx.display(28)),
            const SizedBox(height: 6),
            Text(
              tr('Solo lo ganado con tus suscripciones. Mínimo {amount} por retiro. El equipo te paga por fuera y te avisamos al hacerlo.', {'amount': _min.formatted}),
              style: Tx.body(13, color: Tx.muted, height: 1.4),
            ),
          ]),
        ),
        const SizedBox(height: 18),
        TextField(
          controller: _amount,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')), LengthLimitingTextInputFormatter(10)],
          style: Tx.body(15),
          decoration: fieldDecoration(
            _withdrawable.plain,
            label: tr('Monto (USD)'),
            error: _errors['amount'],
            prefix: Padding(padding: const EdgeInsets.only(left: 14, right: 6), child: Text('US\$', style: Tx.body(15, color: Tx.muted))),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _method,
          maxLength: 60,
          style: Tx.body(15),
          decoration: fieldDecoration(tr('PayPal, Llave Bre-B, transferencia…'), label: tr('Medio para recibirlo'), error: _errors['method']),
        ),
        const SizedBox(height: 4),
        TextField(
          controller: _account,
          maxLength: 255,
          style: Tx.body(15),
          decoration: fieldDecoration(tr('Correo, número de cuenta o llave'), label: tr('Cuenta'), error: _errors['account']),
        ),
        const SizedBox(height: 14),
        GradientButton(label: tr('Pedir retiro'), icon: CupertinoIcons.arrow_up_circle_fill, loading: _sending, onPressed: _sending ? null : _send),
      ]),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.n, required this.text});

  final int n;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 26,
          height: 26,
          alignment: Alignment.center,
          decoration: const BoxDecoration(gradient: Tx.brand, shape: BoxShape.circle),
          child: Text('$n', style: Tx.body(13, weight: FontWeight.w700, color: Colors.white)),
        ),
        const SizedBox(width: 10),
        Expanded(child: Padding(padding: const EdgeInsets.only(top: 3), child: Text(text, style: Tx.body(14, height: 1.4)))),
      ]),
    );
  }
}

class _RefundNote extends StatelessWidget {
  const _RefundNote();

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(Tx.radiusSm),
      onTap: () => openInApp(context, AppConfig.web('legal.php?doc=reembolsos')),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(2, 2, 2, 6),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(CupertinoIcons.arrow_uturn_left_circle, size: 18, color: Tx.accentSoft),
          const SizedBox(width: 8),
          Expanded(
            child: Text.rich(
              TextSpan(children: [
                TextSpan(text: '${tr('El saldo recargado que no uses se puede devolver si lo pides dentro de los 30 días.')} '),
                TextSpan(text: tr('Política de reembolsos'), style: Tx.body(13, color: Tx.accentSoft, weight: FontWeight.w600)),
              ]),
              style: Tx.body(13, color: Tx.muted, height: 1.4),
            ),
          ),
        ]),
      ),
    );
  }
}

class _FieldError extends StatelessWidget {
  const _FieldError(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
      child: Text(text, style: Tx.body(12.5, color: Tx.danger)),
    );
  }
}
