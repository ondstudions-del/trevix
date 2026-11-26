import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

/// Conectividad real: la app puede usarse sin red y muestra «Offline» hasta recuperar Internet.
class NetworkStatus extends ChangeNotifier {
  NetworkStatus._();

  static final NetworkStatus instance = NetworkStatus._();

  final _connectivity = Connectivity();
  StreamSubscription<List<ConnectivityResult>>? _sub;
  bool _online = true;

  bool get online => _online;

  Future<void> start() async {
    final first = await _connectivity.checkConnectivity();
    _online = _hasLink(first);
    _sub ??= _connectivity.onConnectivityChanged.listen((r) {
      final next = _hasLink(r);
      if (next == _online) return;
      _online = next;
      notifyListeners();
    });
    notifyListeners();
  }

  bool _hasLink(List<ConnectivityResult> results) {
    if (results.isEmpty) return false;
    return results.any((r) => r != ConnectivityResult.none);
  }

  void dispose() {
    _sub?.cancel();
    _sub = null;
  }
}