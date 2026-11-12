import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/i18n.dart';
import '../core/nav.dart';
import '../core/paged.dart';
import '../core/theme.dart';
import '../models/models.dart';
import 'common.dart';

/// GIF o sticker de GIPHY con su proporción real (los stickers sin fondo).
class GifView extends StatelessWidget {
  const GifView({super.key, required this.gif, this.maxWidth = 220, this.maxHeight = 220});

  final Gif gif;
  final double maxWidth;
  final double maxHeight;

  @override
  Widget build(BuildContext context) {
    var width = maxWidth;
    var height = width / gif.aspect;
    if (height > maxHeight) {
      height = maxHeight;
      width = height * gif.aspect;
    }
    final image = NetImage(gif.url, width: width, height: height, fit: BoxFit.contain, radius: gif.isSticker ? 0 : 14);
    return Semantics(label: gif.title.isEmpty ? (gif.isSticker ? 'Sticker' : 'GIF') : gif.title, image: true, child: image);
  }
}

/// Buscador de GIF y stickers (a través del servidor de TREVIX; la clave de GIPHY no está en la app).
Future<Gif?> pickGif(BuildContext context, {String kind = 'sticker'}) {
  return showModalBottomSheet<Gif>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _GifPicker(initialKind: kind),
  );
}

/// Hoja de stickers de las historias: [header] arriba (stickers especiales, que cierran la hoja con su clave)
/// y debajo el buscador de stickers de GIPHY. Devuelve un [Gif], la clave elegida en el encabezado o null.
Future<Object?> pickStorySticker(BuildContext context, {required Widget Function(BuildContext sheet) header}) {
  return showModalBottomSheet<Object>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheet) => _GifPicker(initialKind: 'sticker', header: header(sheet), stickersOnly: true),
  );
}

class _GifPicker extends StatefulWidget {
  const _GifPicker({required this.initialKind, this.header, this.stickersOnly = false});

  final String initialKind;
  final Widget? header;
  final bool stickersOnly;

  @override
  State<_GifPicker> createState() => _GifPickerState();
}

class _GifPickerState extends State<_GifPicker> {
  late String _kind = widget.initialKind;
  final _search = TextEditingController();
  Timer? _debounce;
  late Paged<Gif> _list = _make();

  /// Stickers y GIF guardados en favoritos (ids de GIPHY), para marcarlos con la estrella.
  final Set<String> _favorites = {};

  bool get _onFavorites => _kind == 'favorites';

  Paged<Gif> _make() => _onFavorites
      ? Paged<Gif>('me/stickers/favorites', Gif.fromJson)
      : Paged<Gif>('gifs/$_kind', Gif.fromJson, query: {if (_search.text.trim().isNotEmpty) 'q': _search.text.trim()});

  @override
  void initState() {
    super.initState();
    _list.refresh();
    _loadFavorites();
  }

  Future<void> _loadFavorites() async {
    try {
      final res = await api.get('me/stickers/favorites');
      if (!mounted) return;
      setState(() => _favorites
        ..clear()
        ..addAll(res.list.map((j) => asStr(j['id'])).where((id) => id.isNotEmpty)));
    } catch (_) {}
  }

  Future<void> _toggleFavorite(Gif gif) async {
    if (gif.id.isEmpty) return;
    final saved = _favorites.contains(gif.id);
    setState(() => saved ? _favorites.remove(gif.id) : _favorites.add(gif.id));
    try {
      if (saved) {
        await api.delete('me/stickers/favorites/${Uri.encodeComponent(gif.id)}');
        if (_onFavorites && mounted) setState(() => _list.items.removeWhere((g) => g.id == gif.id));
      } else {
        await api.post('me/stickers/favorites', {'id': gif.id, 'kind': gif.kind});
      }
      if (mounted) toast(context, saved ? tr('Quitado de favoritos.') : tr('Guardado en favoritos.'));
    } catch (e) {
      if (!mounted) return;
      setState(() => saved ? _favorites.add(gif.id) : _favorites.remove(gif.id));
      toastError(context, e);
    }
  }

  Future<void> _itemMenu(Gif gif) async {
    final saved = _favorites.contains(gif.id);
    await actionSheet(context, [
      SheetAction(saved ? tr('Quitar de favoritos') : tr('Guardar en favoritos'), saved ? CupertinoIcons.star_slash : CupertinoIcons.star, () => _toggleFavorite(gif)),
    ]);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    _list.dispose();
    super.dispose();
  }

  void _reload() {
    final old = _list;
    setState(() => _list = _make());
    _list.refresh();
    WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    return SheetFrame(
      padding: EdgeInsets.zero,
      child: SizedBox(
        height: (mq.size.height - mq.viewInsets.bottom - mq.padding.top - 60).clamp(260.0, mq.size.height * .78),
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: Row(children: [
              Expanded(
                child: CupertinoSlidingSegmentedControl<String>(
                  groupValue: _kind,
                  backgroundColor: Tx.surface3,
                  thumbColor: Tx.purple700,
                  children: {
                    'favorites': Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Icon(CupertinoIcons.star_fill, size: 17, color: Tx.text, semanticLabel: tr('Favoritos')),
                    ),
                    'sticker': Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Text('Stickers', style: Tx.body(14, weight: FontWeight.w600))),
                    if (!widget.stickersOnly)
                      'gif': Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Text('GIF', style: Tx.body(14, weight: FontWeight.w600))),
                  },
                  onValueChanged: (v) {
                    if (v == null || v == _kind) return;
                    _kind = v;
                    _reload();
                  },
                ),
              ),
              CupertinoButton(
                padding: const EdgeInsets.only(left: 12),
                onPressed: () => Navigator.pop(context),
                child: Text(tr('Cerrar'), style: Tx.body(15, weight: FontWeight.w600, color: Tx.muted)),
              ),
            ]),
          ),
          if (widget.header != null) widget.header!,
          if (_onFavorites)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(tr('Mantén presionado un sticker o GIF para guardarlo o quitarlo de favoritos.'), style: Tx.body(12.5, color: Tx.muted)),
            )
          else
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _search,
              textInputAction: TextInputAction.search,
              onChanged: (_) {
                _debounce?.cancel();
                _debounce = Timer(const Duration(milliseconds: 400), _reload);
              },
              style: Tx.body(15),
              decoration: fieldDecoration(_kind == 'gif' ? tr('Buscar GIF') : tr('Buscar stickers'),
                  prefix: Icon(CupertinoIcons.search, color: Tx.subtle, size: 20)),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListenableBuilder(
              listenable: _list,
              builder: (context, _) {
                if (_list.items.isEmpty) {
                  if (_list.error != null) return ErrorState(error: _list.error!, onRetry: _list.retry);
                  if (_list.loading || !_list.loaded) return const Loading();
                  if (_onFavorites) {
                    return EmptyState(
                      icon: CupertinoIcons.star,
                      title: tr('Sin favoritos'),
                      message: tr('Mantén presionado un sticker o GIF para guardarlo aquí.'),
                    );
                  }
                  return EmptyState(icon: CupertinoIcons.smiley, title: tr('Sin resultados'), message: tr('Prueba con otra palabra.'));
                }
                return NotificationListener<ScrollNotification>(
                  onNotification: (n) {
                    if (n.metrics.extentAfter < 500) _list.loadMore();
                    return false;
                  },
                  child: GridView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: _kind == 'gif' ? 2 : 3,
                      mainAxisSpacing: 8,
                      crossAxisSpacing: 8,
                    ),
                    itemCount: _list.items.length,
                    itemBuilder: (_, i) {
                      final gif = _list.items[i];
                      return GestureDetector(
                        onTap: () => Navigator.pop(context, gif),
                        onLongPress: () => _itemMenu(gif),
                        child: Stack(fit: StackFit.expand, children: [
                          Container(
                            decoration: BoxDecoration(
                              color: gif.isSticker ? Colors.transparent : Tx.surface3,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: NetImage(gif.url, fit: gif.isSticker ? BoxFit.contain : BoxFit.cover),
                          ),
                          if (_favorites.contains(gif.id))
                            const Positioned(
                              top: 4,
                              right: 4,
                              child: Icon(CupertinoIcons.star_fill, size: 15, color: Color(0xFFFFC53D), shadows: [Shadow(blurRadius: 3, color: Colors.black54)]),
                            ),
                        ]),
                      );
                    },
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text('Powered by GIPHY', style: Tx.body(11.5, weight: FontWeight.w600, color: Tx.subtle)),
          ),
        ]),
      ),
    );
  }
}

/// Vista previa del GIF elegido antes de enviarlo, con botón para quitarlo.
class GifAttachment extends StatelessWidget {
  const GifAttachment({super.key, required this.gif, required this.onRemove});

  final Gif gif;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        GifView(gif: gif, maxWidth: 110, maxHeight: 90),
        const Spacer(),
        IconButton(onPressed: onRemove, icon: Icon(CupertinoIcons.xmark_circle_fill, color: Tx.muted)),
      ]),
    );
  }
}
