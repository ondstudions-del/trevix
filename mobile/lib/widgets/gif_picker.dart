import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

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

class _GifPicker extends StatefulWidget {
  const _GifPicker({required this.initialKind});

  final String initialKind;

  @override
  State<_GifPicker> createState() => _GifPickerState();
}

class _GifPickerState extends State<_GifPicker> {
  late String _kind = widget.initialKind;
  final _search = TextEditingController();
  Timer? _debounce;
  late Paged<Gif> _list = _make();

  Paged<Gif> _make() => Paged<Gif>('gifs/$_kind', Gif.fromJson, query: {if (_search.text.trim().isNotEmpty) 'q': _search.text.trim()});

  @override
  void initState() {
    super.initState();
    _list.refresh();
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
    return SheetFrame(
      padding: EdgeInsets.zero,
      child: SizedBox(
        height: MediaQuery.of(context).size.height * .78,
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
                    'sticker': Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Text('Stickers', style: Tx.body(14, weight: FontWeight.w600))),
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
                child: Text('Cerrar', style: Tx.body(15, weight: FontWeight.w600, color: Tx.muted)),
              ),
            ]),
          ),
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
              decoration: fieldDecoration(_kind == 'gif' ? 'Buscar GIF' : 'Buscar stickers',
                  prefix: const Icon(CupertinoIcons.search, color: Tx.subtle, size: 20)),
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
                  return const EmptyState(icon: CupertinoIcons.smiley, title: 'Sin resultados', message: 'Prueba con otra palabra.');
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
                        child: Container(
                          decoration: BoxDecoration(
                            color: gif.isSticker ? Colors.transparent : Tx.surface3,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: NetImage(gif.url, fit: gif.isSticker ? BoxFit.contain : BoxFit.cover),
                        ),
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
        IconButton(onPressed: onRemove, icon: const Icon(CupertinoIcons.xmark_circle_fill, color: Tx.muted)),
      ]),
    );
  }
}
