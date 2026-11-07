import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../core/theme.dart';

/// Iconos SVG de TREVIX. Trazos basados en Lucide (licencia ISC, https://lucide.dev); las variantes
/// rellenas («solid») son propias. Todo se dibuja en blanco y se tiñe con [TxIcon.color] o [TxIcon.gradient].
enum TxGlyph {
  home(
    '<path d="M15 21v-8a1 1 0 0 0-1-1h-4a1 1 0 0 0-1 1v8"/><path d="M3 10a2 2 0 0 1 .709-1.528l7-5.999a2 2 0 0 1 2.582 0l7 5.999A2 2 0 0 1 21 10v9a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z"/>',
    solid:
        '<path fill="#FFFFFF" d="M9 21H5a2 2 0 0 1-2-2V10a2 2 0 0 1 .709-1.528l7-5.999a2 2 0 0 1 2.582 0l7 5.999A2 2 0 0 1 21 10v9a2 2 0 0 1-2 2h-4v-8a1 1 0 0 0-1-1h-4a1 1 0 0 0-1 1z"/>',
  ),
  explore(
    '<path d="m16.24 7.76-1.804 5.411a2 2 0 0 1-1.265 1.265L7.76 16.24l1.804-5.411a2 2 0 0 1 1.265-1.265z"/><circle cx="12" cy="12" r="10"/>',
    solid:
        '<path fill="#FFFFFF" fill-rule="evenodd" d="M12 2a10 10 0 1 0 0 20a10 10 0 1 0 0-20z M16.24 7.76l-1.804 5.411a2 2 0 0 1-1.265 1.265L7.76 16.24l1.804-5.411a2 2 0 0 1 1.265-1.265z"/>',
  ),
  plus('<path d="M5 12h14"/><path d="M12 5v14"/>'),
  bell(
    '<path d="M6 8a6 6 0 0 1 12 0c0 7 3 9 3 9H3s3-2 3-9"/><path d="M10.3 21a1.94 1.94 0 0 0 3.4 0"/>',
    solid: '<path fill="#FFFFFF" d="M6 8a6 6 0 0 1 12 0c0 7 3 9 3 9H3s3-2 3-9"/><path d="M10.3 21a1.94 1.94 0 0 0 3.4 0"/>',
  ),
  music('<path d="M9 18V5l12-2v13"/><circle cx="6" cy="18" r="3"/><circle cx="18" cy="16" r="3"/>',
      solid: '<path d="M9 18V5l12-2v13"/><circle fill="#FFFFFF" cx="6" cy="18" r="3"/><circle fill="#FFFFFF" cx="18" cy="16" r="3"/>'),
  note('<circle cx="8" cy="18" r="4"/><path d="M12 18V2l7 4"/>', solid: '<circle fill="#FFFFFF" cx="8" cy="18" r="4"/><path d="M12 18V2l7 4"/>'),
  send(
    '<path d="M14.536 21.686a.5.5 0 0 0 .937-.024l6.5-19a.496.496 0 0 0-.635-.635l-19 6.5a.5.5 0 0 0-.024.937l7.93 3.18a2 2 0 0 1 1.112 1.11z"/><path d="m21.854 2.147-10.94 10.939"/>',
  ),
  heart(
    '<path d="M19 14c1.49-1.46 3-3.21 3-5.5A5.5 5.5 0 0 0 16.5 3c-1.76 0-3 .5-4.5 2-1.5-1.5-2.74-2-4.5-2A5.5 5.5 0 0 0 2 8.5c0 2.3 1.5 4.05 3 5.5l7 7Z"/>',
    solid:
        '<path fill="#FFFFFF" d="M19 14c1.49-1.46 3-3.21 3-5.5A5.5 5.5 0 0 0 16.5 3c-1.76 0-3 .5-4.5 2-1.5-1.5-2.74-2-4.5-2A5.5 5.5 0 0 0 2 8.5c0 2.3 1.5 4.05 3 5.5l7 7Z"/>',
  ),
  comment('<path d="M7.9 20A9 9 0 1 0 4 16.1L2 22Z"/>', solid: '<path fill="#FFFFFF" d="M7.9 20A9 9 0 1 0 4 16.1L2 22Z"/>'),
  repost('<path d="m2 9 3-3 3 3"/><path d="M13 18H7a2 2 0 0 1-2-2V6"/><path d="m22 15-3 3-3-3"/><path d="M11 6h6a2 2 0 0 1 2 2v10"/>'),
  bookmark(
    '<path d="m19 21-7-4-7 4V5a2 2 0 0 1 2-2h10a2 2 0 0 1 2 2v16z"/>',
    solid: '<path fill="#FFFFFF" d="m19 21-7-4-7 4V5a2 2 0 0 1 2-2h10a2 2 0 0 1 2 2v16z"/>',
  ),
  more('<circle fill="#FFFFFF" cx="12" cy="12" r="1"/><circle fill="#FFFFFF" cx="19" cy="12" r="1"/><circle fill="#FFFFFF" cx="5" cy="12" r="1"/>'),
  compose(
    '<path d="M12 3H5a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2v-7"/><path d="M18.375 2.625a1 1 0 0 1 3 3l-9.013 9.014a2 2 0 0 1-.853.505l-2.873.84a.5.5 0 0 1-.62-.62l.84-2.873a2 2 0 0 1 .506-.852z"/>',
  ),
  thread('<path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z"/><path d="M13 8H7"/><path d="M17 12H7"/>'),
  quote(
    '<path d="M16 3a2 2 0 0 0-2 2v6a2 2 0 0 0 2 2 1 1 0 0 1 1 1v1a2 2 0 0 1-2 2 1 1 0 0 0-1 1v2a1 1 0 0 0 1 1 6 6 0 0 0 6-6V5a2 2 0 0 0-2-2z"/><path d="M5 3a2 2 0 0 0-2 2v6a2 2 0 0 0 2 2 1 1 0 0 1 1 1v1a2 2 0 0 1-2 2 1 1 0 0 0-1 1v2a1 1 0 0 0 1 1 6 6 0 0 0 6-6V5a2 2 0 0 0-2-2z"/>',
  ),
  camera('<path d="M14.5 4h-5L7 7H4a2 2 0 0 0-2 2v9a2 2 0 0 0 2 2h16a2 2 0 0 0 2-2V9a2 2 0 0 0-2-2h-3l-2.5-3z"/><circle cx="12" cy="13" r="3"/>'),
  sparkles(
    '<path d="M9.937 15.5A2 2 0 0 0 8.5 14.063l-6.135-1.582a.5.5 0 0 1 0-.962L8.5 9.936A2 2 0 0 0 9.937 8.5l1.582-6.135a.5.5 0 0 1 .963 0L14.063 8.5A2 2 0 0 0 15.5 9.937l6.135 1.581a.5.5 0 0 1 0 .964L15.5 14.063a2 2 0 0 0-1.437 1.437l-1.582 6.135a.5.5 0 0 1-.963 0z"/><path d="M20 3v4"/><path d="M22 5h-4"/><path d="M4 17v2"/><path d="M5 18H3"/>',
    solid:
        '<path fill="#FFFFFF" d="M9.937 15.5A2 2 0 0 0 8.5 14.063l-6.135-1.582a.5.5 0 0 1 0-.962L8.5 9.936A2 2 0 0 0 9.937 8.5l1.582-6.135a.5.5 0 0 1 .963 0L14.063 8.5A2 2 0 0 0 15.5 9.937l6.135 1.581a.5.5 0 0 1 0 .964L15.5 14.063a2 2 0 0 0-1.437 1.437l-1.582 6.135a.5.5 0 0 1-.963 0z"/><path d="M20 3v4"/><path d="M22 5h-4"/><path d="M4 17v2"/><path d="M5 18H3"/>',
  ),
  search('<circle cx="11" cy="11" r="8"/><path d="m21 21-4.3-4.3"/>'),
  back('<path d="m15 18-6-6 6-6"/>'),
  arrowRight('<path d="M5 12h14"/><path d="m12 5 7 7-7 7"/>'),
  user(
    '<path d="M19 21v-2a4 4 0 0 0-4-4H9a4 4 0 0 0-4 4v2"/><circle cx="12" cy="7" r="4"/>',
    solid: '<path fill="#FFFFFF" d="M19 21v-2a4 4 0 0 0-4-4H9a4 4 0 0 0-4 4v2z"/><circle fill="#FFFFFF" cx="12" cy="7" r="4"/>',
  ),
  users('<path d="M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2"/><circle cx="9" cy="7" r="4"/><path d="M22 21v-2a4 4 0 0 0-3-3.87"/><path d="M16 3.13a4 4 0 0 1 0 7.75"/>'),
  image('<rect width="18" height="18" x="3" y="3" rx="2" ry="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/>'),
  play('<polygon points="6 3 20 12 6 21 6 3"/>', solid: '<polygon fill="#FFFFFF" points="6 3 20 12 6 21 6 3"/>'),
  text('<polyline points="4 7 4 4 20 4 20 7"/><line x1="9" x2="15" y1="20" y2="20"/><line x1="12" x2="12" y1="4" y2="20"/>'),
  mic('<path d="M12 2a3 3 0 0 0-3 3v7a3 3 0 0 0 6 0V5a3 3 0 0 0-3-3Z"/><path d="M19 10v2a7 7 0 0 1-14 0v-2"/><line x1="12" x2="12" y1="19" y2="22"/>'),
  close('<path d="M18 6 6 18"/><path d="m6 6 12 12"/>'),
  share('<path d="M4 12v8a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2v-8"/><polyline points="16 6 12 2 8 6"/><line x1="12" x2="12" y1="2" y2="15"/>');

  const TxGlyph(this.outline, {this.solid});

  final String outline;
  final String? solid;
}

/// Icono vectorial nítido a cualquier tamaño. Con [filled] usa la variante rellena si existe.
class TxIcon extends StatelessWidget {
  const TxIcon(this.glyph, {super.key, this.size = 24, this.color = Tx.text, this.gradient, this.filled = false, this.stroke = 1.9});

  final TxGlyph glyph;
  final double size;
  final Color color;
  final Gradient? gradient;
  final bool filled;
  final double stroke;

  static final Map<String, String> _cache = {};

  String _svg() {
    final body = filled ? (glyph.solid ?? glyph.outline) : glyph.outline;
    return _cache.putIfAbsent(
      '${glyph.name}|$filled|$stroke',
      () => '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="#FFFFFF" '
          'stroke-width="$stroke" stroke-linecap="round" stroke-linejoin="round">$body</svg>',
    );
  }

  @override
  Widget build(BuildContext context) {
    final g = gradient;
    final picture = SvgPicture.string(
      _svg(),
      width: size,
      height: size,
      colorFilter: ColorFilter.mode(g == null ? color : Colors.white, BlendMode.srcIn),
    );
    if (g == null) return picture;
    return ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: (b) => g.createShader(Offset.zero & b.size),
      child: picture,
    );
  }
}
