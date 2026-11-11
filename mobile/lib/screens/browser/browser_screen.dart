import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../core/config.dart';
import '../../core/deeplinks.dart';
import '../../core/i18n.dart';
import '../../core/nav.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';

final _scheme = RegExp(r'^https?://', caseSensitive: false);
final _host = RegExp(r'^[^\s/@]+\.[a-z]{2,}(?::\d+)?(?:[/?#]\S*)?$', caseSensitive: false);

/// ¿Es una dirección web («google.com», «www.x.co/y», «https://…») y no una búsqueda?
bool looksLikeUrl(String input) {
  final text = input.trim();
  if (text.isEmpty || text.contains(' ')) return false;
  final uri = Uri.tryParse(_scheme.hasMatch(text) ? text : 'https://$text');
  return uri != null && uri.host.contains('.') && (_scheme.hasMatch(text) || _host.hasMatch(text));
}

/// Lo escrito en la barra: la dirección o, si no lo parece, una búsqueda en Google.
Uri browserTarget(String input) {
  final text = input.trim();
  if (looksLikeUrl(text)) return Uri.parse(_scheme.hasMatch(text) ? text : 'https://$text');
  return Uri.https('www.google.com', '/search', {'q': text, 'hl': Lang.instance.code});
}

/// Navegador dentro de la app: abre enlaces y búsquedas sin salir a Safari o Chrome. Los enlaces de TREVIX
/// (publicaciones, perfiles…) se abren en su pantalla de la app y los de llamadas, correo o tiendas en su app.
class BrowserScreen extends StatefulWidget {
  const BrowserScreen({super.key, this.url});

  /// null: página de inicio con la barra lista para escribir.
  final String? url;

  @override
  State<BrowserScreen> createState() => _BrowserScreenState();
}

class _BrowserScreenState extends State<BrowserScreen> {
  late final WebViewController _web;
  final _address = TextEditingController();
  final _focus = FocusNode();
  bool _started = false;
  int _progress = 0;
  bool _loading = false;
  bool _canBack = false;
  bool _canForward = false;
  String _url = '';
  String _title = '';
  String? _error;

  List<(String, String, IconData)> get _shortcuts => [
        ('Google', 'https://www.google.com', CupertinoIcons.search),
        ('Wikipedia', 'https://${Lang.instance.code}.wikipedia.org', CupertinoIcons.book),
        ('YouTube', 'https://m.youtube.com', CupertinoIcons.play_rectangle),
        (tr('Mapas'), 'https://www.google.com/maps', CupertinoIcons.map),
      ];

  @override
  void initState() {
    super.initState();
    _web = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.white)
      ..setNavigationDelegate(NavigationDelegate(
        onNavigationRequest: _onRequest,
        onPageStarted: (url) => _update(url: url, loading: true, error: null),
        onProgress: (p) => _update(progress: p),
        onPageFinished: (url) => _update(url: url, loading: false),
        onUrlChange: (change) => _update(url: change.url),
        onWebResourceError: (e) {
          if (e.isForMainFrame ?? true) _update(loading: false, error: e.description);
        },
      ));
    _focus.addListener(() {
      if (!mounted) return;
      if (_focus.hasFocus) {
        _address.text = _url;
        _address.selection = TextSelection(baseOffset: 0, extentOffset: _address.text.length);
      }
      setState(() {});
    });
    final start = widget.url;
    if (start != null && start.trim().isNotEmpty) {
      _go(browserTarget(start));
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focus.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    _address.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<NavigationDecision> _onRequest(NavigationRequest request) async {
    final uri = Uri.tryParse(request.url);
    if (uri == null) return NavigationDecision.prevent;
    if (uri.scheme == 'http' || uri.scheme == 'https' || uri.scheme == 'about' || uri.scheme == 'data' || uri.scheme == 'blob') {
      if (request.isMainFrame && uri.host == Uri.parse(AppConfig.site).host && mounted && DeepLinks.open(context, uri)) {
        return NavigationDecision.prevent;
      }
      return NavigationDecision.navigate;
    }
    // tel:, mailto:, whatsapp:, intent:… los abre la app que corresponde.
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication).catchError((_) => false);
    if (!ok && mounted) toast(context, tr('Ninguna app de este teléfono puede abrir este enlace.'), error: true);
    return NavigationDecision.prevent;
  }

  Future<void> _update({String? url, int? progress, bool? loading, Object? error = _keep}) async {
    if (!mounted) return;
    final back = await _web.canGoBack();
    final forward = await _web.canGoForward();
    final title = await _web.getTitle() ?? '';
    if (!mounted) return;
    setState(() {
      if (url != null && url.isNotEmpty) _url = url;
      if (progress != null) _progress = progress;
      if (loading != null) _loading = loading;
      if (!identical(error, _keep)) _error = error as String?;
      _canBack = back;
      _canForward = forward;
      _title = title;
    });
  }

  static const _keep = Object();

  void _go(Uri uri) {
    _started = true;
    _url = uri.toString();
    _error = null;
    _web.loadRequest(uri);
  }

  void _submit(String text) {
    if (text.trim().isEmpty) return;
    _focus.unfocus();
    setState(() => _go(browserTarget(text)));
  }

  String get _site {
    final uri = Uri.tryParse(_url);
    final host = uri?.host ?? '';
    return host.startsWith('www.') ? host.substring(4) : host;
  }

  bool get _secure => _url.startsWith('https://');

  Future<void> _openOutside() async {
    final uri = Uri.tryParse(_url);
    if (uri == null) return;
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) toast(context, tr('No se pudo abrir el enlace.'), error: true);
  }

  void _menu() {
    actionSheet(context, [
      SheetAction(tr('Compartir'), CupertinoIcons.share, () => Share.share(_url)),
      SheetAction(tr('Copiar enlace'), CupertinoIcons.doc_on_doc, () {
        Clipboard.setData(ClipboardData(text: _url));
        toast(context, tr('Enlace copiado.'));
      }),
      SheetAction(tr('Abrir en el navegador del teléfono'), CupertinoIcons.compass, _openOutside),
    ], title: _site);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // Con historial, el gesto o botón «atrás» del sistema vuelve a la página anterior en vez de cerrar.
      canPop: !_canBack,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _web.canGoBack()) {
          await _web.goBack();
        } else if (context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: GlassBar(
          leading: IconButton(
            tooltip: tr('Cerrar'),
            icon: Icon(CupertinoIcons.xmark, color: Tx.text, size: 21),
            onPressed: () => Navigator.of(context).pop(),
          ),
          titleWidget: _addressBar(),
          actions: [
            if (_started)
              IconButton(
                tooltip: tr('Más opciones'),
                icon: Icon(CupertinoIcons.ellipsis_circle, color: Tx.text, size: 22),
                onPressed: _menu,
              ),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(2),
            child: SizedBox(
              height: 2,
              child: _loading && _progress < 100
                  ? LinearProgressIndicator(value: _progress / 100, backgroundColor: Colors.transparent, color: Tx.accent, minHeight: 2)
                  : null,
            ),
          ),
        ),
        body: Column(children: [
          Expanded(child: _started ? _page() : _home()),
          if (_started) _toolbar(),
        ]),
      ),
    );
  }

  Widget _addressBar() {
    final editing = _focus.hasFocus || !_started;
    return SizedBox(
      height: 40,
      child: editing
          ? TextField(
              controller: _address,
              focusNode: _focus,
              autocorrect: false,
              keyboardType: TextInputType.url,
              textInputAction: TextInputAction.go,
              onSubmitted: _submit,
              style: Tx.body(15),
              decoration: fieldDecoration(
                tr('Busca o escribe una dirección'),
                prefix: Icon(CupertinoIcons.search, color: Tx.subtle, size: 18),
                suffix: _address.text.isEmpty
                    ? null
                    : GestureDetector(
                        onTap: () => setState(_address.clear),
                        child: Icon(CupertinoIcons.xmark_circle_fill, color: Tx.subtle, size: 18),
                      ),
              ).copyWith(contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 12)),
              onChanged: (_) => setState(() {}),
            )
          : GestureDetector(
              onTap: _focus.requestFocus,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(color: Tx.surface3, borderRadius: BorderRadius.circular(16), border: Border.all(color: Tx.border)),
                child: Row(children: [
                  Icon(_secure ? CupertinoIcons.lock_fill : CupertinoIcons.exclamationmark_triangle, size: 13, color: _secure ? Tx.muted : Tx.warning),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(_site, maxLines: 1, overflow: TextOverflow.ellipsis, style: Tx.body(14.5, weight: FontWeight.w600)),
                      if (_title.isNotEmpty && _title != _url)
                        Text(_title, maxLines: 1, overflow: TextOverflow.ellipsis, style: Tx.body(11, color: Tx.subtle)),
                    ]),
                  ),
                ]),
              ),
            ),
    );
  }

  Widget _page() {
    if (_error != null) {
      return EmptyState(
        icon: CupertinoIcons.wifi_exclamationmark,
        title: tr('No se pudo cargar la página'),
        message: _error!,
        action: SizedBox(
          width: 200,
          child: GradientButton(label: tr('Reintentar'), icon: CupertinoIcons.refresh, onPressed: () => setState(() {
                _error = null;
                _web.reload();
              })),
        ),
      );
    }
    return WebViewWidget(controller: _web);
  }

  Widget _home() {
    return ListView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(20, 40, 20, 40),
      children: [
        Icon(CupertinoIcons.globe, size: 54, color: Tx.accent),
        const SizedBox(height: 14),
        Text(tr('Navegador de TREVIX'), textAlign: TextAlign.center, style: Tx.display(20)),
        const SizedBox(height: 6),
        Text(tr('Escribe una dirección como «google.com» o lo que quieras buscar en la web.'),
            textAlign: TextAlign.center, style: Tx.body(14, color: Tx.muted, height: 1.4)),
        const SizedBox(height: 28),
        Wrap(alignment: WrapAlignment.center, spacing: 14, runSpacing: 14, children: [
          for (final s in _shortcuts)
            GestureDetector(
              onTap: () => setState(() => _go(Uri.parse(s.$2))),
              child: SizedBox(
                width: 72,
                child: Column(children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(color: Tx.surface3, borderRadius: BorderRadius.circular(18), border: Border.all(color: Tx.border)),
                    child: Icon(s.$3, color: Tx.text, size: 24),
                  ),
                  const SizedBox(height: 6),
                  Text(s.$1, maxLines: 1, overflow: TextOverflow.ellipsis, style: Tx.body(12, color: Tx.muted)),
                ]),
              ),
            ),
        ]),
      ],
    );
  }

  Widget _toolbar() {
    final bottom = MediaQuery.viewPaddingOf(context).bottom;
    Widget button(IconData icon, String tip, VoidCallback? onTap) => IconButton(
          tooltip: tip,
          onPressed: onTap,
          icon: Icon(icon, size: 22, color: onTap == null ? Tx.subtle.withAlpha(110) : Tx.text),
        );
    return Container(
      padding: EdgeInsets.only(bottom: bottom, top: 2),
      decoration: BoxDecoration(color: Tx.surface1, border: Border(top: BorderSide(color: Tx.border))),
      child: SizedBox(
        height: 46,
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
          button(CupertinoIcons.chevron_back, tr('Atrás'), _canBack ? () => _web.goBack() : null),
          button(CupertinoIcons.chevron_forward, tr('Adelante'), _canForward ? () => _web.goForward() : null),
          _loading
              ? button(CupertinoIcons.xmark, tr('Detener'), () {
                  _web.runJavaScript('window.stop();');
                  setState(() => _loading = false);
                })
              : button(CupertinoIcons.refresh, tr('Recargar'), () {
                  setState(() => _error = null);
                  _web.reload();
                }),
          button(CupertinoIcons.share, tr('Compartir'), () => Share.share(_url)),
          button(CupertinoIcons.compass, tr('Abrir en el navegador del teléfono'), _openOutside),
        ]),
      ),
    );
  }
}
