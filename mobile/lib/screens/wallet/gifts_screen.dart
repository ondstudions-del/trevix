import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/nav.dart';
import '../../core/paged.dart';
import '../../core/routes.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';
import '../../widgets/gif_picker.dart';
import '../../widgets/paged_view.dart';
import 'wallet_screen.dart';

/// Hoja para enviarle un regalo a [to]: lo guardado en «Mis regalos» y el catálogo (se paga con el monedero).
/// [where] es desde dónde se envía (profile, message, post o story) y [refId] la publicación o la historia.
/// Devuelve la respuesta de gifts/{id}/send (con conversation_id en el chat) o null si no se envió.
Future<Json?> sendGift(BuildContext context, User to, {String where = 'profile', int? refId}) => showModalBottomSheet<Json>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _GiftSheet(to: to, where: where, refId: refId),
    );

/// Saldo insuficiente (402): ofrece ir al monedero a recargar.
Future<void> _lowBalance(BuildContext context, ApiException e) async {
  if (await confirm(context, tr('Saldo insuficiente'), e.message, action: tr('Ir al monedero')) && context.mounted) {
    push(context, const WalletScreen());
  }
}

class _GiftSheet extends StatefulWidget {
  const _GiftSheet({required this.to, required this.where, this.refId});

  final User to;
  final String where;
  final int? refId;

  @override
  State<_GiftSheet> createState() => _GiftSheetState();
}

class _GiftSheetState extends State<_GiftSheet> {
  Json? _data;
  Object? _error;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await api.get('gifts');
      if (mounted) setState(() => _data = res.map);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _send(GiftItem gift, {required bool fromInventory}) async {
    final name = widget.to.displayName;
    final ok = await confirm(
      context,
      tr('Enviar {gift}', {'gift': gift.name}),
      fromInventory
          ? tr('Se enviará a {name} una unidad de Mis regalos.', {'name': name})
          : tr('¿Enviar {gift} a {name} por {price}? Se descuenta de tu monedero.', {'gift': gift.name, 'name': name, 'price': gift.price?.formatted ?? ''}),
      action: fromInventory ? tr('Enviar') : tr('Pagar {price}', {'price': gift.price?.formatted ?? ''}),
    );
    if (!ok || !mounted) return;
    setState(() => _sending = true);
    try {
      final res = await api.post('gifts/${gift.id}/send', {
        'to': widget.to.username,
        'source': fromInventory ? 'inventory' : 'buy',
        'context': widget.where,
        if (widget.refId != null) 'ref_id': widget.refId,
      });
      if (!mounted) return;
      toast(context, asStr(res.map['message'], tr('Listo.')));
      Navigator.pop(context, res.map);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _sending = false);
      if (e.status == 402) {
        await _lowBalance(context, e);
      } else {
        toastError(context, e);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _sending = false);
      toastError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    final maxHeight = MediaQuery.of(context).size.height * .78;
    return SheetFrame(
      padding: const EdgeInsets.only(bottom: 8),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
            child: Row(children: [
              const _GiftBadge(size: 34),
              const SizedBox(width: 12),
              Expanded(
                child: Text(tr('Enviar un regalo a {name}', {'name': widget.to.displayName}), maxLines: 2, overflow: TextOverflow.ellipsis, style: Tx.display(17)),
              ),
              if (data != null) _BalanceChip(Money.fromJson(data['balance'])),
            ]),
          ),
          if (data != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                tr('Recibirá el valor del regalo menos la comisión de TREVIX ({pct} %). Los regalos no son reembolsables.', {'pct': asInt(data['commission'])}),
                style: Tx.body(12.5, color: Tx.muted, height: 1.35),
              ),
            ),
          Flexible(
            child: Stack(children: [
              if (data == null)
                _error != null
                    ? SingleChildScrollView(child: ErrorState(error: _error!, onRetry: _load))
                    : const SizedBox(height: 220, child: Loading())
              else
                _content(data),
              if (_sending) Positioned.fill(child: ColoredBox(color: Tx.alpha(Tx.surface2, .6), child: const Loading())),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _content(Json data) {
    final inventory = asList(data['inventory'], GiftItem.fromJson);
    final categories = asList(data['categories'], GiftCategory.fromJson);
    if (inventory.isEmpty && categories.isEmpty) {
      return SingleChildScrollView(
        child: EmptyState(icon: CupertinoIcons.gift, title: tr('Todavía no hay regalos'), message: tr('Pronto habrá regalos para enviar.')),
      );
    }
    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      children: [
        if (inventory.isNotEmpty) ...[
          _SectionLabel(tr('Mis regalos')),
          GiftGrid(
            gifts: inventory,
            caption: (g) => '×${g.quantity}',
            onTap: (g) => _send(g, fromInventory: true),
          ),
        ],
        for (final c in categories) ...[
          _SectionLabel(c.name),
          GiftGrid(gifts: c.gifts, caption: (g) => g.price?.formatted ?? '', onTap: (g) => _send(g, fromInventory: false)),
        ],
      ],
    );
  }
}

/// Rejilla de regalos: imagen, nombre y [caption] (precio o unidades).
class GiftGrid extends StatelessWidget {
  const GiftGrid({super.key, required this.gifts, required this.caption, required this.onTap});

  final List<GiftItem> gifts;
  final String Function(GiftItem) caption;
  final void Function(GiftItem) onTap;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final columns = box.maxWidth > 520 ? 5 : 4;
      final width = (box.maxWidth - (columns - 1) * 8) / columns;
      return Wrap(spacing: 8, runSpacing: 8, children: [
        for (final g in gifts)
          SizedBox(
            width: width,
            child: Material(
              color: Tx.surface3,
              borderRadius: BorderRadius.circular(16),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => onTap(g),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(6, 10, 6, 8),
                  child: Column(children: [
                    SizedBox(height: width * .62, child: Center(child: GifView(gif: g.media, maxWidth: width * .7, maxHeight: width * .62))),
                    const SizedBox(height: 6),
                    Text(g.name, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: Tx.body(12.5, weight: FontWeight.w600)),
                    Text(caption(g), maxLines: 1, overflow: TextOverflow.ellipsis, style: Tx.body(11.5, weight: FontWeight.w700, color: Tx.accent)),
                  ]),
                ),
              ),
            ),
          ),
      ]);
    });
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 14, 6, 8),
      child: Text(text, style: Tx.body(14, weight: FontWeight.w700, color: Tx.muted)),
    );
  }
}

class _GiftBadge extends StatelessWidget {
  const _GiftBadge({this.size = 40});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(gradient: LinearGradient(colors: [Color(0xFFF59E0B), Color(0xFFDB2777)]), shape: BoxShape.circle),
      child: Icon(CupertinoIcons.gift_fill, color: Colors.white, size: size * .5),
    );
  }
}

class _BalanceChip extends StatelessWidget {
  const _BalanceChip(this.balance);

  final Money balance;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: Tx.surface3, borderRadius: BorderRadius.circular(14), border: Border.all(color: Tx.border)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(CupertinoIcons.creditcard, size: 14, color: Tx.muted),
        const SizedBox(width: 5),
        Text(balance.formatted, style: Tx.body(12.5, weight: FontWeight.w700)),
      ]),
    );
  }
}

/// Ajustes › Regalos: tienda (comprar para guardar), «Mis regalos», recibidos (solo los ve quien los recibe) y enviados.
class GiftsScreen extends StatefulWidget {
  const GiftsScreen({super.key, this.tab = 'shop'});

  final String tab;

  @override
  State<GiftsScreen> createState() => _GiftsScreenState();
}

class _GiftsScreenState extends State<GiftsScreen> {
  late String _tab = const ['shop', 'mine', 'received', 'sent'].contains(widget.tab) ? widget.tab : 'shop';
  final _received = Paged<Json>('me/gifts/received', (j) => j);
  final _sent = Paged<Json>('me/gifts/sent', (j) => j);
  Json? _summary;
  Object? _error;

  static Map<String, String> get _tabs => {'shop': tr('Tienda'), 'mine': tr('Mis regalos'), 'received': tr('Recibidos'), 'sent': tr('Enviados')};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _received.dispose();
    _sent.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final res = await api.get('gifts');
      if (mounted) {
        setState(() {
          _summary = res.map;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _buy(GiftItem gift) async {
    final summary = _summary;
    if (summary == null || gift.price == null) return;
    final quantity = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _BuySheet(gift: gift, max: asInt(summary['max_quantity'], 20), balance: Money.fromJson(summary['balance'])),
    );
    if (quantity == null || !mounted) return;
    try {
      final res = await api.post('gifts/${gift.id}/buy', {'quantity': quantity});
      if (!mounted) return;
      toast(context, asStr(res.map['message'], tr('Listo.')));
      setState(() {
        _summary = {...summary, 'balance': res.map['balance'], 'inventory': res.map['inventory']};
        _tab = 'mine';
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.status == 402) {
        await _lowBalance(context, e);
      } else {
        toastError(context, e);
      }
    } catch (e) {
      if (mounted) toastError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: GlassBar(
        title: tr('Regalos'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(50),
          child: SizedBox(
            height: 50,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
              children: [
                for (final e in _tabs.entries)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: PillChip(label: e.value, selected: _tab == e.key, onTap: () => setState(() => _tab = e.key)),
                  ),
              ],
            ),
          ),
        ),
      ),
      body: switch (_tab) {
        'received' => _history(_received, received: true),
        'sent' => _history(_sent, received: false),
        _ => _shop(),
      },
    );
  }

  Widget _shop() {
    final summary = _summary;
    if (summary == null) return _error != null ? ErrorState(error: _error!, onRetry: _load) : const Loading();
    final mine = _tab == 'mine';
    final inventory = asList(summary['inventory'], GiftItem.fromJson);
    final categories = asList(summary['categories'], GiftCategory.fromJson);
    return CustomScrollView(
      physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
      slivers: [
        CupertinoSliverRefreshControl(onRefresh: _load),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(12, 14, 12, 120),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              Panel(
                gradient: true,
                child: Row(children: [
                  const _GiftBadge(),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(tr('Saldo disponible'), style: Tx.body(13, color: Tx.muted, weight: FontWeight.w600)),
                      Text(Money.fromJson(summary['balance']).formatted, style: Tx.display(24)),
                    ]),
                  ),
                  SoftButton(label: tr('Recargar'), icon: CupertinoIcons.plus, height: 36, onPressed: () => push(context, const WalletScreen()).then((_) => _load())),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 12, 4, 0),
                child: Text(
                  mine
                      ? tr('Para enviar uno, abre el perfil, el chat, la publicación o la historia de la persona y toca el regalo.')
                      : tr('Compra regalos para guardarlos en Mis regalos o envíalos al momento desde un perfil, el chat, una publicación, un reel o una historia.'),
                  style: Tx.body(13, color: Tx.muted, height: 1.4),
                ),
              ),
              if (mine && inventory.isEmpty)
                EmptyState(
                  icon: CupertinoIcons.tray,
                  title: tr('No tienes regalos guardados'),
                  message: tr('Compra regalos en la tienda y envíalos cuando quieras desde un perfil, el chat, una publicación o una historia.'),
                )
              else if (mine) ...[
                const SizedBox(height: 8),
                GiftGrid(gifts: inventory, caption: (g) => '×${g.quantity}', onTap: _buy),
              ] else if (categories.isEmpty)
                EmptyState(icon: CupertinoIcons.gift, title: tr('Todavía no hay regalos'), message: tr('Pronto habrá regalos para enviar.'))
              else
                for (final c in categories) ...[
                  _SectionLabel(c.name),
                  GiftGrid(gifts: c.gifts, caption: (g) => g.price?.formatted ?? '', onTap: _buy),
                ],
            ]),
          ),
        ),
      ],
    );
  }

  Widget _history(Paged<Json> paged, {required bool received}) {
    return PagedView<Json>(
      key: ValueKey('gifts-$received'),
      paged: paged,
      header: [
        if (received)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
              child: Text(tr('Solo tú ves tus regalos recibidos. Lo ganado se puede retirar desde tu monedero.'), style: Tx.body(13, color: Tx.muted, height: 1.4)),
            ),
          ),
      ],
      empty: received
          ? EmptyState(
              icon: CupertinoIcons.gift,
              title: tr('Todavía no recibiste regalos'),
              message: tr('Cuando alguien te envíe uno, lo verás aquí y su valor llegará a tu monedero. Solo tú ves tus regalos recibidos.'),
            )
          : EmptyState(icon: CupertinoIcons.paperplane, title: tr('Todavía no enviaste regalos'), message: tr('Envía uno desde el perfil, el chat, una publicación o una historia.')),
      itemBuilder: (context, s, _) => _SendTile(send: s, received: received),
    );
  }
}

class _SendTile extends StatelessWidget {
  const _SendTile({required this.send, required this.received});

  final Json send;
  final bool received;

  @override
  Widget build(BuildContext context) {
    final gift = GiftItem.fromJson(asMap(send['gift']));
    final userJson = asMapOrNull(send['user']);
    final user = userJson != null ? User.fromJson(userJson) : null;
    final amount = Money.fromJson(send['amount']);
    final who = user?.displayName ?? tr('Cuenta no disponible');
    final where = switch (asStr(send['context'])) {
      'message' => tr('en el chat'),
      'post' => tr('por su publicación'),
      'story' => tr('por su historia'),
      _ => tr('en su perfil'),
    };
    return InkWell(
      onTap: user != null ? () => openProfile(context, user.username) : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(children: [
          SizedBox(width: 52, height: 52, child: Center(child: GifView(gif: gift.media, maxWidth: 52, maxHeight: 52))),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(gift.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: Tx.body(14.5, weight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text(
                '${received ? tr('De {name}', {'name': who}) : tr('Para {name}', {'name': who})} · $where · ${timeAgo(asDate(send['created_at']))}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Tx.body(12.5, color: Tx.subtle),
              ),
            ]),
          ),
          const SizedBox(width: 10),
          Text(
            received ? '+${amount.formatted}' : '−${amount.formatted}',
            style: Tx.body(14.5, weight: FontWeight.w700, color: received ? Tx.success : Tx.text),
          ),
        ]),
      ),
    );
  }
}

/// Comprar unidades de un regalo para «Mis regalos».
class _BuySheet extends StatefulWidget {
  const _BuySheet({required this.gift, required this.max, required this.balance});

  final GiftItem gift;
  final int max;
  final Money balance;

  @override
  State<_BuySheet> createState() => _BuySheetState();
}

class _BuySheetState extends State<_BuySheet> {
  int _quantity = 1;

  @override
  Widget build(BuildContext context) {
    final price = widget.gift.price!;
    final total = Money.local(price.cents * _quantity);
    final enough = widget.balance.cents >= total.cents;
    Widget step(IconData icon, VoidCallback? onTap) => IconButton.filledTonal(
          onPressed: onTap,
          icon: Icon(icon, size: 18),
          style: IconButton.styleFrom(backgroundColor: Tx.surface3, foregroundColor: Tx.text),
        );
    return SheetFrame(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Center(child: GifView(gif: widget.gift.media, maxWidth: 120, maxHeight: 120)),
        const SizedBox(height: 10),
        Text(widget.gift.name, textAlign: TextAlign.center, style: Tx.display(18)),
        Text(tr('{price} cada uno', {'price': price.formatted}), textAlign: TextAlign.center, style: Tx.body(13.5, color: Tx.muted)),
        const SizedBox(height: 16),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          step(CupertinoIcons.minus, _quantity > 1 ? () => setState(() => _quantity--) : null),
          SizedBox(width: 64, child: Text('$_quantity', textAlign: TextAlign.center, style: Tx.display(26))),
          step(CupertinoIcons.plus, _quantity < widget.max ? () => setState(() => _quantity++) : null),
        ]),
        const SizedBox(height: 8),
        Text(
          enough ? tr('Saldo disponible: {amount}', {'amount': widget.balance.formatted}) : tr('Tu saldo ({amount}) no alcanza. Recarga tu monedero.', {'amount': widget.balance.formatted}),
          textAlign: TextAlign.center,
          style: Tx.body(12.5, color: enough ? Tx.subtle : Tx.warning),
        ),
        const SizedBox(height: 14),
        GradientButton(
          label: tr('Comprar por {price}', {'price': total.formatted}),
          icon: CupertinoIcons.gift_fill,
          onPressed: () => Navigator.pop(context, _quantity),
        ),
        const SizedBox(height: 6),
        Text(tr('Se guardan en Mis regalos. Los regalos no son reembolsables.'), textAlign: TextAlign.center, style: Tx.body(12, color: Tx.subtle)),
      ]),
    );
  }
}
