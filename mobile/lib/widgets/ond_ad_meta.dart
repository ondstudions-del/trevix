import '../core/format.dart';
import '../core/paged.dart';
import '../models/models.dart';

/// Registra anuncios de OND-ADS tras una publicación (meta.sponsored de la API).
class OndAdBinding {
  final Map<int, Json> afterPostId = {};

  /// Publicación promocionada (kind=post) que lleva etiqueta Patrocinador en la lista.
  final Map<int, Json> labeledPost = {};

  /// Si la publicación promocionada ya está en el lote cargado, no hace falta tarjeta duplicada.
  bool promotedOnLastPage = false;

  static int? promotedPostId(Json ad) {
    if (asStr(ad['kind']) != 'post') return null;
    final id = asInt(asMapOrNull(ad['post'])?['id']);
    return id > 0 ? id : null;
  }

  /// true = la publicación promocionada ya va en la lista con etiqueta; omitir SponsoredCard extra.
  bool skipStandaloneCard(Json ad) => promotedOnLastPage && promotedPostId(ad) != null;

  void onPagedMeta(Paged paged, Map<String, dynamic> meta, {bool clearOnFirstPage = true}) {
    if (clearOnFirstPage && paged.pageStart == 0) {
      afterPostId.clear();
      labeledPost.clear();
      promotedOnLastPage = false;
    }
    final page = paged.items;
    if (page.isEmpty) return;
    final slice = page.sublist(paged.pageStart.clamp(0, page.length));
    if (slice.isEmpty) return;
    final sponsored = asMapOrNull(meta['sponsored']);
    final ad = asMapOrNull(sponsored?['ad']);
    if (ad == null) return;
    if (slice.first is! Post) return;
    final position = asInt(sponsored!['position'], 3).clamp(1, slice.length);
    afterPostId[(slice[position - 1] as Post).id] = ad;
    final pid = promotedPostId(ad);
    if (pid != null) {
      labeledPost[pid] = ad;
      promotedOnLastPage = slice.cast<Post>().any((p) => p.id == pid);
    }
  }

  static SponsoredSlot? slotFromMeta(Map<String, dynamic> meta) {
    final sponsored = asMapOrNull(meta['sponsored']);
    final ad = asMapOrNull(sponsored?['ad']);
    if (ad == null) return null;
    return SponsoredSlot(asInt(sponsored!['position'], 3), ad);
  }
}

class SponsoredSlot {
  const SponsoredSlot(this.position, this.ad);
  final int position;
  final Json ad;
}