import 'dart:ui' show ImageFilter;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/i18n.dart';
import '../core/nav.dart';
import '../core/theme.dart';
import '../models/models.dart';
import 'common.dart';

/// Filtros de color de las historias (mismas claves y efecto aproximado que la web).
Map<String, String> get storyFilterNames => {
      'vivid': tr('Vívido'),
      'warm': tr('Cálido'),
      'cool': tr('Frío'),
      'mono': tr('Blanco y negro'),
      'vintage': tr('Vintage'),
      'fade': tr('Suave'),
      'dramatic': tr('Dramático'),
      'smooth': tr('Rejuvenecer'),
      'glow': tr('Brillo'),
      'rose': tr('Rosa'),
      'neon': tr('Neón'),
      'noir': tr('Noir'),
    };

const storyTextColors = ['#FFFFFF', '#000000', '#F43F5E', '#F59E0B', '#FACC15', '#10B981', '#22D3EE', '#3B82F6', '#8B5CF6', '#EC4899'];

Color hexColor(String hex) {
  final value = int.tryParse(hex.replaceFirst('#', ''), radix: 16) ?? 0xFFFFFF;
  return Color(0xFF000000 | value);
}

// Matrices 4×5 de ColorFilter.matrix (desplazamientos en 0–255). _then(a, b) aplica a y después b.
List<double> _then(List<double> a, List<double> b) {
  final out = List<double>.filled(20, 0);
  for (var r = 0; r < 4; r++) {
    for (var c = 0; c < 5; c++) {
      var v = c == 4 ? b[r * 5 + 4] : 0.0;
      for (var k = 0; k < 4; k++) {
        v += b[r * 5 + k] * a[k * 5 + c];
      }
      out[r * 5 + c] = v;
    }
  }
  return out;
}

List<double> _saturation(double s) {
  const lr = .2126, lg = .7152, lb = .0722;
  return [
    lr * (1 - s) + s, lg * (1 - s), lb * (1 - s), 0, 0,
    lr * (1 - s), lg * (1 - s) + s, lb * (1 - s), 0, 0,
    lr * (1 - s), lg * (1 - s), lb * (1 - s) + s, 0, 0,
    0, 0, 0, 1, 0,
  ];
}

List<double> _contrast(double c) {
  final o = 128 * (1 - c);
  return [c, 0, 0, 0, o, 0, c, 0, 0, o, 0, 0, c, 0, o, 0, 0, 0, 1, 0];
}

List<double> _brightness(double b) => [b, 0, 0, 0, 0, 0, b, 0, 0, 0, 0, 0, b, 0, 0, 0, 0, 0, 1, 0];

List<double> _shift(double r, double g, double b) => [1, 0, 0, 0, r, 0, 1, 0, 0, g, 0, 0, 1, 0, b, 0, 0, 0, 1, 0];

List<double> _sepia(double a) => [
      1 - .607 * a, .769 * a, .189 * a, 0, 0,
      .349 * a, 1 - .314 * a, .168 * a, 0, 0,
      .272 * a, .534 * a, 1 - .869 * a, 0, 0,
      0, 0, 0, 1, 0,
    ];

ColorFilter? storyFilter(String? key) {
  final m = storyFilterMatrix(key);
  return m == null ? null : ColorFilter.matrix(m);
}

/// Matriz 4×5 del filtro (también la usa la edición nativa al grabarlo en el video descargado).
List<double>? storyFilterMatrix(String? key) {
  return switch (key) {
    'vivid' => _then(_saturation(1.45), _contrast(1.08)),
    'warm' => _then(_saturation(1.2), _shift(14, 4, -14)),
    'cool' => _then(_saturation(1.05), _shift(-10, 0, 16)),
    'mono' => _then(_saturation(0), _contrast(1.1)),
    'vintage' => _then(_then(_sepia(.55), _contrast(.92)), _brightness(1.05)),
    'fade' => _then(_then(_contrast(.82), _brightness(1.08)), _saturation(.8)),
    'dramatic' => _then(_then(_contrast(1.35), _brightness(.92)), _saturation(1.15)),
    'smooth' => _then(_then(_then(_brightness(1.08), _contrast(.9)), _saturation(1.06)), _shift(8, 3, -2)),
    'glow' => _then(_then(_brightness(1.15), _contrast(1.05)), _saturation(1.2)),
    'rose' => _then(_then(_sepia(.2), _saturation(1.25)), _shift(16, -4, 6)),
    'neon' => _then(_then(_saturation(1.9), _contrast(1.15)), _shift(6, -6, 14)),
    'noir' => _then(_then(_saturation(0), _contrast(1.45)), _brightness(.9)),
    _ => null,
  };
}

/// Aplica el filtro (si hay) a la foto, el video o la vista de la cámara. «Rejuvenecer» suma una copia desenfocada
/// encima (enfoque suave) que disimula arrugas y marcas de la piel.
Widget filtered(String? filter, Widget child) {
  final f = storyFilter(filter);
  if (f == null) return child;
  if (filter == 'smooth') {
    return ColorFiltered(
      colorFilter: f,
      child: Stack(fit: StackFit.passthrough, children: [
        child,
        Positioned.fill(
          child: IgnorePointer(
            child: Opacity(opacity: .45, child: ImageFiltered(imageFilter: ImageFilter.blur(sigmaX: 6, sigmaY: 6), child: child)),
          ),
        ),
      ]),
    );
  }
  return ColorFiltered(colorFilter: f, child: child);
}

/// Coloca una capa en el lienzo: centro en (x, y), con su giro y escala.
class PlacedLayer extends StatelessWidget {
  const PlacedLayer({super.key, required this.layer, required this.size, required this.child});

  final StoryLayer layer;
  final Size size;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: layer.x * size.width,
      top: layer.y * size.height,
      child: FractionalTranslation(
        translation: const Offset(-.5, -.5),
        child: Transform.rotate(angle: layer.rotation, child: Transform.scale(scale: layer.scale, child: child)),
      ),
    );
  }
}

/// Contenido de una capa, con medidas proporcionales al ancho del lienzo [w] (como las unidades cqw de la web).
class LayerContent extends StatelessWidget {
  const LayerContent({super.key, required this.layer, required this.w, this.poll, this.onVote, this.onTapChip});

  final StoryLayer layer;
  final double w;
  final StoryPoll? poll;
  final ValueChanged<int>? onVote;
  final VoidCallback? onTapChip;

  @override
  Widget build(BuildContext context) {
    switch (layer.type) {
      case 'text':
        final color = hexColor(layer.color);
        final size = w * .065;
        final isBox = layer.style == 'box';
        final text = Text(
          layer.text,
          textAlign: TextAlign.center,
          style: TxDark.display(size, color: isBox ? (color.computeLuminance() > .5 ? Colors.black : Colors.white) : color, height: 1.2).copyWith(
            shadows: layer.style == 'neon'
                ? [Shadow(color: color, blurRadius: size * .3), Shadow(color: color, blurRadius: size * .8)]
                : isBox
                    ? null
                    : [const Shadow(color: Color(0x73000000), blurRadius: 6, offset: Offset(0, 1))],
          ),
        );
        return ConstrainedBox(
          constraints: BoxConstraints(maxWidth: w * .8),
          child: isBox
              ? Container(
                  padding: EdgeInsets.symmetric(horizontal: size * .5, vertical: size * .25),
                  decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(size * .35)),
                  child: text,
                )
              : text,
        );
      case 'sticker':
        final ratio = layer.width > 0 && layer.height > 0 ? layer.height / layer.width : 1.0;
        return NetImage(layer.url, width: w * .35, height: w * .35 * ratio, fit: BoxFit.contain);
      case 'location':
        return _chip(CupertinoIcons.location_solid, layer.name);
      case 'mention':
        return _chip(null, '@${layer.username}');
      case 'link':
        return _chip(CupertinoIcons.link, layer.label.isNotEmpty ? layer.label : (layer.url ?? ''), color: Tx.purple700);
      case 'poll':
        return _PollCard(layer: layer, w: w, poll: poll, onVote: onVote);
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _chip(IconData? icon, String label, {Color color = const Color(0xFF111111)}) {
    final size = w * .042;
    return GestureDetector(
      onTap: onTapChip,
      child: Container(
        constraints: BoxConstraints(maxWidth: w * .8),
        padding: EdgeInsets.symmetric(horizontal: size * .8, vertical: size * .45),
        decoration: BoxDecoration(
          color: Colors.white.withAlpha(242),
          borderRadius: BorderRadius.circular(size * .6),
          boxShadow: const [BoxShadow(color: Color(0x40000000), blurRadius: 14, offset: Offset(0, 4))],
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[Icon(icon, size: size * 1.1, color: color), SizedBox(width: size * .35)],
          Flexible(
            child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TxDark.body(size, weight: FontWeight.w700, color: color)),
          ),
        ]),
      ),
    );
  }
}

class _PollCard extends StatelessWidget {
  const _PollCard({required this.layer, required this.w, this.poll, this.onVote});

  final StoryLayer layer;
  final double w;
  final StoryPoll? poll;
  final ValueChanged<int>? onVote;

  @override
  Widget build(BuildContext context) {
    final counts = poll?.counts;
    final total = (poll?.total ?? 0) < 1 ? 1 : poll!.total;
    final unit = w / 100;
    return Container(
      width: w * .7,
      padding: EdgeInsets.all(unit * 4),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(248),
        borderRadius: BorderRadius.circular(unit * 4),
        boxShadow: const [BoxShadow(color: Color(0x4D000000), blurRadius: 24, offset: Offset(0, 8))],
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(layer.question.isEmpty ? tr('Haz una pregunta…') : layer.question,
            textAlign: TextAlign.center, style: TxDark.display(unit * 5, color: layer.question.isEmpty ? Colors.black38 : Colors.black)),
        for (var i = 0; i < 2; i++)
          Padding(
            padding: EdgeInsets.only(top: unit * 2),
            child: GestureDetector(
              onTap: onVote == null || poll?.viewerChoice != null ? null : () => onVote!(i),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(unit * 2.6),
                child: Stack(children: [
                  Positioned.fill(child: Container(color: const Color(0xFFF1F1F4))),
                  if (counts != null)
                    Positioned.fill(
                      child: FractionallySizedBox(
                        alignment: Alignment.centerLeft,
                        widthFactor: counts[i] / total,
                        child: Container(decoration: const BoxDecoration(gradient: LinearGradient(colors: [Color(0xFFC4B5FD), Color(0xFF93C5FD)]))),
                      ),
                    ),
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: unit * 3.4, vertical: unit * 2.6),
                    decoration: poll?.viewerChoice == i
                        ? BoxDecoration(border: Border.all(color: const Color(0xFF7C3AED), width: 2), borderRadius: BorderRadius.circular(unit * 2.6))
                        : null,
                    child: Row(children: [
                      Expanded(
                        child: Text(
                          i < layer.options.length && layer.options[i].isNotEmpty ? layer.options[i] : (i == 0 ? tr('Sí') : tr('No')),
                          style: TxDark.body(unit * 4.2, weight: FontWeight.w700, color: Colors.black),
                        ),
                      ),
                      if (counts != null)
                        Text('${(counts[i] * 100 / total).round()}%', style: TxDark.body(unit * 4, weight: FontWeight.w700, color: Colors.black87)),
                    ]),
                  ),
                ]),
              ),
            ),
          ),
        if (counts != null && onVote == null && poll?.viewerChoice == null)
          Padding(
            padding: EdgeInsets.only(top: unit * 2.4),
            child: Text(poll!.total == 1 ? tr('1 voto') : tr('{n} votos', {'n': poll!.total}), style: TxDark.body(unit * 3.4, color: Colors.black54)),
          ),
      ]),
    );
  }
}

/// Capas en el visor: los textos y stickers dejan pasar los toques (para avanzar); ubicación, menciones,
/// enlace y encuesta responden al toque. [onHold] pausa la historia mientras se abre algo encima.
class StoryLayersView extends StatefulWidget {
  const StoryLayersView({super.key, required this.item, required this.own, required this.onHold, required this.openProfile});

  final StoryItem item;
  final bool own;
  final ValueChanged<bool> onHold;
  final Future<void> Function(String username) openProfile;

  @override
  State<StoryLayersView> createState() => _StoryLayersViewState();
}

class _StoryLayersViewState extends State<StoryLayersView> {
  bool _voting = false;

  Future<void> _vote(int choice) async {
    if (_voting || widget.own) return;
    setState(() => _voting = true);
    try {
      final res = await api.post('stories/${widget.item.id}/poll', {'choice': choice});
      final poll = widget.item.poll;
      if (poll != null && mounted) {
        setState(() {
          poll.counts = (res.map['counts'] as List?)?.map((c) => asInt(c)).toList();
          poll.total = asInt(res.map['total']);
          poll.viewerChoice = asIntOrNull(res.map['viewer_choice']);
        });
      }
    } catch (e) {
      if (mounted) toastError(context, e);
    }
    if (mounted) setState(() => _voting = false);
  }

  Future<void> _tap(StoryLayer layer) async {
    widget.onHold(true);
    try {
      switch (layer.type) {
        case 'mention':
          await widget.openProfile(layer.username);
        case 'link':
          if (layer.url != null) await openUrl(context, layer.url!);
        case 'location':
          await openUrl(context, 'https://www.openstreetmap.org/search?query=${Uri.encodeQueryComponent(layer.name)}');
      }
    } finally {
      widget.onHold(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final layers = widget.item.layers;
    if (layers.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(builder: (context, box) {
      final size = Size(box.maxWidth, box.maxHeight);
      return Stack(clipBehavior: Clip.hardEdge, children: [
        for (final layer in layers)
          PlacedLayer(
            layer: layer,
            size: size,
            child: IgnorePointer(
              ignoring: layer.type == 'text' || layer.type == 'sticker',
              child: LayerContent(
                layer: layer,
                w: size.width,
                poll: widget.item.poll,
                onVote: widget.own ? null : _vote,
                onTapChip: () => _tap(layer),
              ),
            ),
          ),
      ]);
    });
  }
}
