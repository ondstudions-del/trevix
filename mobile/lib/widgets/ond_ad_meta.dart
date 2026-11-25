import '../core/paged.dart';
import '../models/models.dart';

/// Registra anuncios de OND-ADS tras una publicación (meta.sponsored de la API).
class OndAdBinding {
  final Map<int, Json> afterPostId = {};

  void onPagedMeta(Paged paged, Map<String, dynamic> meta, {bool clearOnFirstPage = true}) {
    if (clearOnFirstPage && paged.pageStart == 0) afterPostId.clear();
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