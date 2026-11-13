import 'package:flutter/foundation.dart';

import '../models/models.dart';
import 'api.dart';

/// Lista paginada con meta.next ({before:N} o {page:N}). Ignora respuestas viejas tras un refresco.
class Paged<T> extends ChangeNotifier {
  Paged(this.path, this.parse, {Map<String, dynamic>? query, this.onMeta}) : query = query ?? {};

  final String path;
  final T Function(Json) parse;
  Map<String, dynamic> query;
  final void Function(Map<String, dynamic> meta)? onMeta;

  final List<T> items = [];
  Map<String, dynamic>? _next;
  bool loading = false;
  bool loaded = false;
  bool isPrivate = false;
  Object? error;
  int _generation = 0;
  Map<String, dynamic> meta = {};

  /// Índice del primer elemento de la última página recibida (para ubicar lo que trae su meta).
  int pageStart = 0;

  bool get hasMore => _next != null;
  bool get isEmpty => loaded && items.isEmpty;

  Future<void> refresh() async {
    final gen = ++_generation;
    loading = true;
    error = null;
    notifyListeners();
    try {
      final res = await api.get(path, query);
      if (gen != _generation) return;
      pageStart = 0;
      items
        ..clear()
        ..addAll(res.list.map(parse));
      _apply(res);
    } catch (e) {
      if (gen != _generation) return;
      error = e;
    }
    loading = false;
    loaded = true;
    notifyListeners();
  }

  Future<void> loadMore() async {
    final next = _next;
    if (loading || next == null || error != null) return;
    final gen = _generation;
    loading = true;
    notifyListeners();
    try {
      final res = await api.get(path, {...query, ...next});
      if (gen != _generation) return;
      pageStart = items.length;
      final page = res.list.map(parse).toList();
      // «Para ti» se ordena por intereses que cambian mientras se navega: no se repite una publicación ya cargada.
      if (page.isNotEmpty && page.first is Post) {
        final seen = {for (final item in items) (item as Post).id};
        page.removeWhere((item) => seen.contains((item as Post).id));
      }
      items.addAll(page);
      _apply(res);
    } catch (e) {
      if (gen != _generation) return;
      error = e;
    }
    loading = false;
    notifyListeners();
  }

  void _apply(ApiResponse res) {
    meta = res.meta;
    _next = res.next;
    isPrivate = asBool(res.meta['private']);
    onMeta?.call(res.meta);
  }

  void retry() {
    if (items.isEmpty) {
      refresh();
    } else {
      error = null;
      loadMore();
    }
  }

  void remove(bool Function(T) test) {
    items.removeWhere(test);
    notifyListeners();
  }

  void insert(T item) {
    items.insert(0, item);
    notifyListeners();
  }

  void changed() => notifyListeners();
}
