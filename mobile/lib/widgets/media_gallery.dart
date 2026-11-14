import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:photo_manager/photo_manager.dart';

import '../core/i18n.dart';
import '../core/live_photo.dart';
import '../core/nav.dart';
import '../core/theme.dart';
import '../core/video_tools.dart';
import 'media.dart';

/// Foto o video elegido de la galería, listo para subir.
class GalleryPick {
  GalleryPick({required this.path, required this.isVideo, this.livePath, this.seconds});

  final String path;
  final bool isVideo;

  /// Video corto de la foto en movimiento (Live Photo de iPhone o foto en movimiento de Android), si tiene.
  final String? livePath;

  /// Duración del video (null si es una foto).
  final double? seconds;

  String get filename => path.split(RegExp(r'[\\/]')).last;
}

/// Galería del teléfono dentro de la app (sin abrir el selector del sistema): álbumes, cuadrícula con la duración
/// de los videos y la etiqueta LIVE de las fotos en movimiento. Si no hay permiso, ofrece abrir los ajustes o el
/// selector del sistema.
class PhoneGallery extends StatefulWidget {
  const PhoneGallery({
    super.key,
    required this.onPick,
    this.videosOnly = false,
    this.photosOnly = false,
    this.maxVideoSeconds,
    this.leading = const [],
    this.columns = 3,
    this.maxSelect,
    this.onPickMany,
  });

  final ValueChanged<GalleryPick> onPick;
  final bool videosOnly;
  final bool photosOnly;

  /// Con [maxSelect], cada toque marca o desmarca (con su número de orden) y «Añadir» entrega todas a [onPickMany].
  final int? maxSelect;
  final ValueChanged<List<GalleryPick>>? onPickMany;

  /// Los videos más largos se muestran atenuados y avisan al tocarlos.
  final int? maxVideoSeconds;

  /// Casillas fijas al comienzo de la cuadrícula (cámara, texto…).
  final List<Widget> leading;
  final int columns;

  @override
  State<PhoneGallery> createState() => _PhoneGalleryState();
}

class _PhoneGalleryState extends State<PhoneGallery> {
  static const _pageSize = 60;

  PermissionState? _permission;
  List<AssetPathEntity> _albums = [];
  AssetPathEntity? _album;
  final List<AssetEntity> _assets = [];
  int _page = 0;
  bool _hasMore = true;
  bool _loading = false;
  String? _resolving;
  final Map<String, Future<Uint8List?>> _thumbs = {};
  final _scroll = ScrollController();
  final List<AssetEntity> _chosen = [];

  bool get _multi => widget.maxSelect != null && widget.onPickMany != null;

  RequestType get _type => widget.videosOnly ? RequestType.video : (widget.photosOnly ? RequestType.image : RequestType.common);

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.extentAfter < 600) _loadMore();
    });
    _start();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    PermissionState state;
    try {
      state = await PhotoManager.requestPermissionExtend(
        requestOption: PermissionRequestOption(androidPermission: AndroidPermission(type: _type, mediaLocation: false)),
      );
    } catch (_) {
      state = PermissionState.denied;
    }
    if (!mounted) return;
    setState(() => _permission = state);
    if (!state.hasAccess) return;
    try {
      final albums = await PhotoManager.getAssetPathList(
        type: _type,
        filterOption: FilterOptionGroup(orders: [const OrderOption(type: OrderOptionType.createDate, asc: false)]),
      );
      if (!mounted) return;
      setState(() {
        _albums = albums;
        _album = albums.isEmpty ? null : albums.first;
      });
      await _reload();
    } catch (_) {
      if (mounted) setState(() => _hasMore = false);
    }
  }

  Future<void> _reload() async {
    setState(() {
      _assets.clear();
      _thumbs.clear();
      _page = 0;
      _hasMore = true;
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
    await _loadMore();
  }

  Future<void> _loadMore() async {
    final album = _album;
    if (album == null || _loading || !_hasMore) return;
    _loading = true;
    try {
      final items = await album.getAssetListPaged(page: _page, size: _pageSize);
      if (!mounted || album != _album) return;
      setState(() {
        _assets.addAll(items);
        _page++;
        _hasMore = items.length == _pageSize;
      });
    } catch (_) {
      if (mounted) setState(() => _hasMore = false);
    } finally {
      _loading = false;
    }
  }

  Future<Uint8List?> _thumb(AssetEntity a) =>
      _thumbs.putIfAbsent(a.id, () => a.thumbnailDataWithSize(const ThumbnailSize.square(260), quality: 80).catchError((_) => null));

  bool _tooLong(AssetEntity a) => a.type == AssetType.video && widget.maxVideoSeconds != null && a.duration > widget.maxVideoSeconds! + 0.5;

  Future<void> _pick(AssetEntity a) async {
    if (_resolving != null) return;
    if (_multi) {
      setState(() {
        if (!_chosen.remove(a)) {
          if (_chosen.length >= widget.maxSelect!) {
            toast(context, tr('Puedes elegir hasta {count} fotos.', {'count': '${widget.maxSelect}'}), error: true);
          } else {
            _chosen.add(a);
          }
        }
      });
      return;
    }
    if (_tooLong(a)) {
      toast(context, tr('El video puede durar como mucho {length}.', {'length': clockText(widget.maxVideoSeconds!)}), error: true);
      return;
    }
    setState(() => _resolving = a.id);
    try {
      final pick = await GalleryResolver.resolve(a);
      if (!mounted) return;
      if (pick == null) {
        toast(context, tr('No se pudo abrir ese archivo. Si está en iCloud, descárgalo primero en Fotos.'), error: true);
      } else {
        widget.onPick(pick);
      }
    } finally {
      if (mounted) setState(() => _resolving = null);
    }
  }

  /// Modo de varias: convierte las marcadas (en su orden) en archivos y las entrega juntas.
  Future<void> _confirmMany() async {
    if (_chosen.isEmpty || _resolving != null) return;
    setState(() => _resolving = '*');
    final picks = <GalleryPick>[];
    var failed = false;
    try {
      for (final a in _chosen) {
        final pick = await GalleryResolver.resolve(a);
        pick == null ? failed = true : picks.add(pick);
      }
    } finally {
      if (mounted) setState(() => _resolving = null);
    }
    if (!mounted) return;
    if (failed) toast(context, tr('No se pudo abrir ese archivo. Si está en iCloud, descárgalo primero en Fotos.'), error: true);
    if (picks.isNotEmpty) widget.onPickMany!(picks);
  }

  Future<void> _systemPicker() async {
    try {
      final picker = ImagePicker();
      if (_multi) {
        final files = await picker.pickMultiImage(maxWidth: 2048, imageQuality: 90, limit: widget.maxSelect! < 2 ? 2 : widget.maxSelect);
        if (files.isEmpty || !mounted) return;
        widget.onPickMany!([for (final f in files.take(widget.maxSelect!)) GalleryPick(path: f.path, isVideo: false)]);
        return;
      }
      if (widget.photosOnly) {
        final file = await picker.pickImage(source: ImageSource.gallery, maxWidth: 2048, imageQuality: 90);
        if (file != null && mounted) widget.onPick(GalleryPick(path: file.path, isVideo: false));
        return;
      }
      final XFile? file = widget.videosOnly ? await picker.pickVideo(source: ImageSource.gallery) : await picker.pickMedia(maxWidth: 2048, imageQuality: 90);
      if (file == null || !mounted) return;
      final isVideo = widget.videosOnly || GalleryResolver.looksLikeVideo(file.path);
      final seconds = isVideo ? (await VideoInfoReader.seconds(file.path)) : null;
      if (!mounted) return;
      if (isVideo && widget.maxVideoSeconds != null && seconds != null && seconds > widget.maxVideoSeconds! + 0.5) {
        toast(context, tr('El video puede durar como mucho {length}.', {'length': clockText(widget.maxVideoSeconds!)}), error: true);
        return;
      }
      widget.onPick(GalleryPick(path: file.path, isVideo: isVideo, seconds: seconds));
    } catch (_) {
      if (mounted) toast(context, tr('No se pudo abrir la galería. Revisa el permiso de Fotos.'), error: true);
    }
  }

  void _chooseAlbum() {
    if (_albums.length < 2) return;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: TxDark.surface2,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (ctx) => SafeArea(
        child: ListView(shrinkWrap: true, padding: const EdgeInsets.symmetric(vertical: 10), children: [
          for (final album in _albums)
            ListTile(
              title: Text(album.isAll ? tr('Recientes') : album.name, style: TxDark.body(15, weight: FontWeight.w600)),
              trailing: album == _album ? const Icon(CupertinoIcons.checkmark_alt, color: Colors.white) : null,
              onTap: () {
                Navigator.pop(ctx);
                if (album == _album) return;
                setState(() => _album = album);
                _reload();
              },
            ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final permission = _permission;
    if (permission == null) return const Center(child: CupertinoActivityIndicator(color: Colors.white));
    if (!permission.hasAccess) return _noAccess();
    final album = _album;
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(14, 4, 8, 8),
        child: Row(children: [
          GestureDetector(
            onTap: _chooseAlbum,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(album == null || album.isAll ? tr('Recientes') : album.name, style: TxDark.body(16, weight: FontWeight.w700)),
              if (_albums.length > 1) const Padding(padding: EdgeInsets.only(left: 4), child: Icon(CupertinoIcons.chevron_down, color: Colors.white, size: 16)),
            ]),
          ),
          const Spacer(),
          if (permission == PermissionState.limited)
            TextButton(
              onPressed: () async {
                await PhotoManager.presentLimited(type: _type);
                if (mounted) _reload();
              },
              child: Text(tr('Elegir más'), style: TxDark.body(13.5, weight: FontWeight.w700, color: Tx.purple300)),
            ),
          IconButton(
            tooltip: tr('Otras apps'),
            onPressed: _systemPicker,
            icon: const Icon(CupertinoIcons.folder, color: Colors.white, size: 21),
          ),
        ]),
      ),
      Expanded(
        child: _assets.isEmpty && !_hasMore && widget.leading.isEmpty
            ? Center(
                child: Text(
                  widget.videosOnly ? tr('No hay videos en tu galería.') : (widget.photosOnly ? tr('No hay fotos en tu galería.') : tr('No hay fotos ni videos en tu galería.')),
                  style: TxDark.body(14, color: Colors.white70),
                ),
              )
            : GridView.builder(
                controller: _scroll,
                padding: EdgeInsets.fromLTRB(2, 0, 2, MediaQuery.of(context).padding.bottom + 2),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: widget.columns, mainAxisSpacing: 2, crossAxisSpacing: 2, childAspectRatio: .72),
                itemCount: widget.leading.length + _assets.length + (_hasMore ? 1 : 0),
                itemBuilder: (context, i) {
                  if (i < widget.leading.length) return widget.leading[i];
                  final index = i - widget.leading.length;
                  if (index >= _assets.length) {
                    _loadMore();
                    return const Center(child: CupertinoActivityIndicator(color: Colors.white));
                  }
                  return _tile(_assets[index]);
                },
              ),
      ),
      if (_multi && _chosen.isNotEmpty)
        Container(
          color: TxDark.surface2,
          padding: EdgeInsets.fromLTRB(16, 10, 16, MediaQuery.of(context).padding.bottom + 10),
          child: Row(children: [
            Expanded(
              child: Text(tr('{count} de {max} fotos', {'count': '${_chosen.length}', 'max': '${widget.maxSelect}'}),
                  style: TxDark.body(14, weight: FontWeight.w600)),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.black),
              onPressed: _resolving == null ? _confirmMany : null,
              child: _resolving == '*' ? const CupertinoActivityIndicator() : Text(tr('Añadir')),
            ),
          ]),
        ),
    ]);
  }

  Widget _tile(AssetEntity a) {
    final video = a.type == AssetType.video;
    final live = !video && Platform.isIOS && a.isLivePhoto;
    final disabled = _tooLong(a);
    return GestureDetector(
      onTap: () => _pick(a),
      child: Stack(fit: StackFit.expand, children: [
        const ColoredBox(color: TxDark.surface3),
        FutureBuilder<Uint8List?>(
          future: _thumb(a),
          builder: (context, snap) => snap.data == null
              ? const SizedBox.shrink()
              : Image.memory(snap.data!, fit: BoxFit.cover, gaplessPlayback: true, opacity: AlwaysStoppedAnimation(disabled ? .35 : 1)),
        ),
        if (video)
          Positioned(
            right: 6,
            bottom: 5,
            child: Text(clockText(a.duration), style: TxDark.body(12, weight: FontWeight.w700).copyWith(shadows: const [Shadow(color: Color(0xCC000000), blurRadius: 4)])),
          ),
        if (live && !_multi) const Positioned(left: 6, top: 6, child: LiveBadge(small: true)),
        if (_multi) ...[
          if (_chosen.contains(a)) ColoredBox(color: Colors.white.withAlpha(60)),
          Positioned(
            right: 6,
            top: 6,
            child: Container(
              width: 24,
              height: 24,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _chosen.contains(a) ? Tx.purple500 : Colors.black.withAlpha(70),
                border: Border.all(color: Colors.white, width: 1.5),
              ),
              child: _chosen.contains(a) ? Text('${_chosen.indexOf(a) + 1}', style: TxDark.body(12, weight: FontWeight.w800)) : null,
            ),
          ),
        ],
        if (_resolving == a.id)
          const ColoredBox(color: Color(0x88000000), child: Center(child: CupertinoActivityIndicator(color: Colors.white))),
      ]),
    );
  }

  Widget _noAccess() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(CupertinoIcons.photo_on_rectangle, color: Colors.white, size: 46),
          const SizedBox(height: 14),
          Text(tr('Permite el acceso a tus fotos'), textAlign: TextAlign.center, style: TxDark.display(19)),
          const SizedBox(height: 8),
          Text(tr('Así verás tu galería aquí mismo para elegir fotos, videos y fotos en movimiento.'),
              textAlign: TextAlign.center, style: TxDark.body(14, color: Colors.white70)),
          const SizedBox(height: 18),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.black),
            onPressed: () async {
              await PhotoManager.openSetting();
            },
            child: Text(tr('Abrir ajustes')),
          ),
          TextButton(
            onPressed: _systemPicker,
            child: Text(tr('Elegir con el selector del sistema'), style: TxDark.body(14, weight: FontWeight.w600, color: Tx.purple300)),
          ),
          TextButton(onPressed: _start, child: Text(tr('Reintentar'), style: TxDark.body(14, color: Colors.white70))),
        ]),
      ),
    );
  }
}

/// Etiqueta «LIVE» de las fotos en movimiento.
class LiveBadge extends StatelessWidget {
  const LiveBadge({super.key, this.small = false, this.active = true});

  final bool small;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: small ? 5 : 8, vertical: small ? 2 : 4),
      decoration: BoxDecoration(color: Colors.black.withAlpha(115), borderRadius: BorderRadius.circular(small ? 5 : 8)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(active ? CupertinoIcons.circle_grid_hex_fill : CupertinoIcons.circle_grid_hex, color: Colors.white, size: small ? 10 : 14),
        SizedBox(width: small ? 3 : 5),
        Text('LIVE', style: TxDark.body(small ? 9.5 : 12, weight: FontWeight.w800, color: Colors.white).copyWith(letterSpacing: .8, decoration: active ? null : TextDecoration.lineThrough)),
      ]),
    );
  }
}

/// Convierte un elemento de la galería en archivos listos para subir.
class GalleryResolver {
  GalleryResolver._();

  /// Lado mayor de las fotos que se suben (el servidor reescala historias a 1920 y publicaciones a 2048).
  static const _maxSide = 2048;

  static bool looksLikeVideo(String path) => RegExp(r'\.(mp4|mov|m4v|3gp|webm|mkv)$', caseSensitive: false).hasMatch(path);

  static Future<GalleryPick?> resolve(AssetEntity a) async {
    try {
      if (a.type == AssetType.video) {
        final file = await a.loadFile(isOrigin: false, darwinFileType: PMDarwinAVFileType.mp4);
        if (file == null) return null;
        final seconds = a.duration > 0 ? a.duration.toDouble() : await VideoInfoReader.seconds(file.path);
        return GalleryPick(path: file.path, isVideo: true, seconds: seconds);
      }
      final image = await _jpeg(a);
      if (image == null) return null;
      String? live;
      if (Platform.isIOS && a.isLivePhoto) {
        final clip = await a.loadFile(isOrigin: false, withSubtype: true, darwinFileType: PMDarwinAVFileType.mp4);
        live = clip?.path;
      } else if (Platform.isAndroid) {
        final origin = await a.originFile;
        if (origin != null) live = await MotionPhoto.extract(origin.path);
      }
      return GalleryPick(path: image, isVideo: false, livePath: live);
    } catch (_) {
      return null;
    }
  }

  /// JPEG de lado mayor ≤ [_maxSide] con la orientación ya aplicada (también convierte HEIC).
  static Future<String?> _jpeg(AssetEntity a) async {
    final w = a.orientatedWidth;
    final h = a.orientatedHeight;
    if (w > 0 && h > 0) {
      final scale = math.min(1.0, _maxSide / math.max(w, h));
      final size = ThumbnailSize(math.max(1, (w * scale).round()), math.max(1, (h * scale).round()));
      final data = await a.thumbnailDataWithOption(
        Platform.isIOS
            ? ThumbnailOption.ios(size: size, quality: 90, deliveryMode: DeliveryMode.highQualityFormat, resizeMode: ResizeMode.exact)
            : ThumbnailOption(size: size, quality: 90),
      );
      if (data != null && data.length > 2048) {
        final dir = await getTemporaryDirectory();
        final out = File('${dir.path}/gallery_${DateTime.now().microsecondsSinceEpoch}.jpg');
        await out.writeAsBytes(data, flush: true);
        return out.path;
      }
    }
    final file = await a.file;
    return file?.path;
  }
}

/// Duración de un video local (null si el teléfono no puede leerla).
class VideoInfoReader {
  VideoInfoReader._();

  static Future<double?> seconds(String path) async => (await VideoTools.info(path)).seconds;
}
