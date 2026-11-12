import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import '../models/models.dart';
import 'api.dart';
import 'i18n.dart';

enum PlayEventKind { credited, pending, failed, cancelled }

/// Lo que pasó con una compra de Google Play, para avisarlo en la pantalla abierta.
class PlayEvent {
  const PlayEvent(this.kind, this.message);

  final PlayEventKind kind;
  final String message;
}

/// Google Play Billing (solo Android): paquetes de saldo del monedero. Cada compra se envía al servidor
/// (me/wallet/play-purchases), que la comprueba con Google, la acredita una sola vez y la consume; la app solo la
/// cierra cuando el servidor respondió. Las que quedaron sin acreditar se reenvían con [recover].
class PlayBilling {
  PlayBilling._();

  static final instance = PlayBilling._();

  static bool get supported => !kIsWeb && Platform.isAndroid;

  final _events = StreamController<PlayEvent>.broadcast();
  final _inFlight = <String>{};
  StreamSubscription<List<PurchaseDetails>>? _sub;

  Stream<PlayEvent> get events => _events.stream;

  void _listen() {
    _sub ??= InAppPurchase.instance.purchaseStream.listen(
      _onPurchases,
      onError: (Object _) => _events.add(PlayEvent(PlayEventKind.failed, tr('No se pudo completar la compra con Google Play.'))),
    );
  }

  Future<bool> available() async {
    if (!supported) return false;
    _listen();
    try {
      return await InAppPurchase.instance.isAvailable();
    } catch (_) {
      return false;
    }
  }

  /// Paquetes publicados en Play Console, del más barato al más caro (con el precio en la moneda de la persona).
  Future<List<ProductDetails>> products(Iterable<String> ids) async {
    final res = await InAppPurchase.instance.queryProductDetails(ids.toSet());
    return res.productDetails.toList()..sort((a, b) => a.rawPrice.compareTo(b.rawPrice));
  }

  /// [accountId] viaja con la compra para que el servidor solo la acredite a esta cuenta.
  Future<bool> buy(ProductDetails product, String accountId) {
    _listen();
    return InAppPurchase.instance.buyConsumable(
      purchaseParam: PurchaseParam(productDetails: product, applicationUserName: accountId),
      autoConsume: false,
    );
  }

  /// Reenvía al servidor las compras pagadas que no se alcanzaron a acreditar (sin conexión, app cerrada…).
  Future<void> recover() async {
    if (!await available()) return;
    try {
      await InAppPurchase.instance.restorePurchases();
    } catch (_) {}
  }

  Future<void> _onPurchases(List<PurchaseDetails> purchases) async {
    for (final p in purchases) {
      switch (p.status) {
        case PurchaseStatus.pending:
          _events.add(PlayEvent(PlayEventKind.pending, tr('Google Play está procesando el pago. El saldo se acreditará cuando se complete.')));
        case PurchaseStatus.canceled:
          _events.add(PlayEvent(PlayEventKind.cancelled, tr('Cancelaste la compra.')));
          await _complete(p);
        case PurchaseStatus.error:
          _events.add(PlayEvent(PlayEventKind.failed, tr('No se pudo completar la compra con Google Play.')));
          await _complete(p);
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          await _deliver(p);
      }
    }
  }

  Future<void> _deliver(PurchaseDetails p) async {
    final token = p.verificationData.serverVerificationData;
    if (token.isEmpty || !_inFlight.add(token)) return;
    try {
      final res = await api.post('me/wallet/play-purchases', {'product_id': p.productID, 'purchase_token': token});
      await _complete(p);
      if (!asBool(res.map['already_credited'])) {
        _events.add(PlayEvent(PlayEventKind.credited, asStr(res.map['message'], tr('Se acreditó el saldo.'))));
      }
    } on ApiException catch (e) {
      _events.add(PlayEvent(e.status == 409 ? PlayEventKind.pending : PlayEventKind.failed, e.message));
    } catch (_) {
      _events.add(PlayEvent(PlayEventKind.failed, tr('No se pudo acreditar la compra. Se intentará de nuevo al abrir el monedero.')));
    } finally {
      _inFlight.remove(token);
    }
  }

  Future<void> _complete(PurchaseDetails p) async {
    if (!p.pendingCompletePurchase) return;
    try {
      await InAppPurchase.instance.completePurchase(p);
    } catch (_) {}
  }
}
