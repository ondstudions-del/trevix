import 'dart:async';
import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../screens/browser/browser_screen.dart';
import 'api.dart';
import 'appearance.dart';
import 'config.dart';
import 'deeplinks.dart';
import 'i18n.dart';
import 'theme.dart';

Future<T?> push<T>(BuildContext context, Widget page, {bool fullscreen = false}) =>
    Navigator.of(context).push<T>(CupertinoPageRoute<T>(builder: (_) => page, fullscreenDialog: fullscreen));

/// Transición con fundido y escala (visor de historias e imágenes). Cierra antes el teclado: si sigue abierto mientras
/// se abre el visor, iOS recoloca el contenido a mitad de la transición.
Future<T?> pushFade<T>(BuildContext context, Widget page) {
  FocusManager.instance.primaryFocus?.unfocus();
  return _pushFadeRoute<T>(context, page);
}

Future<T?> _pushFadeRoute<T>(BuildContext context, Widget page) => Navigator.of(context).push<T>(PageRouteBuilder<T>(
      opaque: false,
      barrierColor: Colors.black,
      transitionDuration: const Duration(milliseconds: 260),
      reverseTransitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (_, __, ___) => page,
      transitionsBuilder: (context, anim, __, child) => FadeTransition(
        opacity: anim,
        child: Appearance.motionReduced(context)
            ? child
            : ScaleTransition(scale: Tween(begin: .96, end: 1.0).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)), child: child),
      ),
    ));

OverlayEntry? _toastEntry;
Timer? _toastTimer;

/// Aviso breve flotante en la parte superior.
void toast(BuildContext context, String message, {bool error = false}) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;
  _toastTimer?.cancel();
  _toastEntry?.remove();
  final entry = OverlayEntry(builder: (_) => _Toast(message: message, error: error));
  _toastEntry = entry;
  overlay.insert(entry);
  HapticFeedback.lightImpact();
  _toastTimer = Timer(Duration(milliseconds: 2600 + message.length * 20), () {
    if (_toastEntry == entry) {
      entry.remove();
      _toastEntry = null;
    }
  });
}

void toastError(BuildContext context, Object error) => toast(context, errorText(error), error: true);

class _Toast extends StatefulWidget {
  const _Toast({required this.message, required this.error});

  final String message;
  final bool error;

  @override
  State<_Toast> createState() => _ToastState();
}

class _ToastState extends State<_Toast> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 320))..forward();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top + 8;
    final anim = CurvedAnimation(parent: _c, curve: Curves.easeOutBack);
    return Positioned(
      top: top,
      left: 16,
      right: 16,
      child: IgnorePointer(
        child: FadeTransition(
          opacity: _c,
          child: SlideTransition(
            position: Tween(begin: const Offset(0, -.6), end: Offset.zero).animate(anim),
            child: Center(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: Tx.alpha(Tx.surface3, .86),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: widget.error ? Tx.alpha(Tx.danger, .5) : Tx.borderStrong),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(widget.error ? CupertinoIcons.exclamationmark_circle_fill : CupertinoIcons.checkmark_circle_fill,
                          size: 20, color: widget.error ? Tx.danger : Tx.success),
                      const SizedBox(width: 10),
                      Flexible(
                        child: Text(widget.message,
                            style: Tx.body(14, weight: FontWeight.w500).copyWith(decoration: TextDecoration.none)),
                      ),
                    ]),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Diálogo de confirmación al estilo iOS.
Future<bool> confirm(BuildContext context, String title, String message, {String? action, bool destructive = false}) async {
  final ok = await showCupertinoDialog<bool>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => CupertinoTheme(
      data: CupertinoThemeData(brightness: Tx.palette.brightness),
      child: CupertinoAlertDialog(
        title: Text(title),
        content: message.isEmpty ? null : Padding(padding: const EdgeInsets.only(top: 6), child: Text(message)),
        actions: [
          CupertinoDialogAction(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Cancelar'))),
          CupertinoDialogAction(
            isDestructiveAction: destructive,
            isDefaultAction: !destructive,
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(action ?? tr('Aceptar')),
          ),
        ],
      ),
    ),
  );
  return ok ?? false;
}

class SheetAction {
  const SheetAction(this.label, this.icon, this.onTap, {this.destructive = false});

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool destructive;
}

/// Hoja inferior con acciones.
Future<void> actionSheet(BuildContext context, List<SheetAction> actions, {String? title}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (ctx) => SheetFrame(
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (title != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
            child: Text(title, style: Tx.display(17), textAlign: TextAlign.center),
          ),
        for (final a in actions)
          InkWell(
            onTap: () {
              Navigator.pop(ctx);
              a.onTap();
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
              child: Row(children: [
                Icon(a.icon, size: 22, color: a.destructive ? Tx.danger : Tx.text),
                const SizedBox(width: 14),
                Expanded(child: Text(a.label, style: Tx.body(16, weight: FontWeight.w500, color: a.destructive ? Tx.danger : Tx.text))),
              ]),
            ),
          ),
      ]),
    ),
  );
}

/// Marco común de las hojas inferiores: vidrio oscuro, asa y bordes redondeados.
class SheetFrame extends StatelessWidget {
  const SheetFrame({super.key, required this.child, this.padding = const EdgeInsets.only(bottom: 12)});

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: Container(
            decoration: BoxDecoration(
              color: Tx.alpha(Tx.surface2, .94),
              border: Border(top: BorderSide(color: Tx.borderStrong)),
            ),
            padding: padding,
            child: SafeArea(
              top: false,
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Center(
                  child: Container(
                    margin: const EdgeInsets.only(top: 10, bottom: 10),
                    width: 38,
                    height: 5,
                    decoration: BoxDecoration(color: Tx.surface4, borderRadius: BorderRadius.circular(3)),
                  ),
                ),
                Flexible(child: child),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// Pide un texto en una hoja inferior. Devuelve null si se cancela.
Future<String?> prompt(
  BuildContext context,
  String title, {
  String hint = '',
  String initial = '',
  String? action,
  int maxLength = 500,
  bool multiline = false,
  bool obscure = false,
  bool required = true,
  String? message,
}) {
  final controller = TextEditingController(text: initial);
  return showModalBottomSheet<String>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (ctx) => SheetFrame(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      child: StatefulBuilder(builder: (ctx, setSheet) {
        final valid = !required || controller.text.trim().isNotEmpty;
        return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(title, style: Tx.display(18)),
          if (message != null) ...[
            const SizedBox(height: 6),
            Text(message, style: Tx.body(14, color: Tx.muted)),
          ],
          const SizedBox(height: 14),
          TextField(
            controller: controller,
            autofocus: true,
            obscureText: obscure,
            maxLength: maxLength,
            minLines: multiline ? 3 : 1,
            maxLines: multiline ? 6 : 1,
            onChanged: (_) => setSheet(() {}),
            style: Tx.body(16),
            decoration: fieldDecoration(hint),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 50,
            child: FilledButton(
              onPressed: valid ? () => Navigator.pop(ctx, controller.text.trim()) : null,
              style: FilledButton.styleFrom(backgroundColor: Tx.purple, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
              child: Text(action ?? tr('Guardar'), style: Tx.body(16, weight: FontWeight.w600)),
            ),
          ),
        ]);
      }),
    ),
  ).whenComplete(() => Future.delayed(const Duration(milliseconds: 400), controller.dispose));
}

/// Estilo de los campos de texto.
InputDecoration fieldDecoration(String hint, {String? error, Widget? prefix, Widget? suffix, String? label}) => InputDecoration(
      hintText: hint,
      labelText: label,
      errorText: error,
      errorMaxLines: 3,
      prefixIcon: prefix,
      suffixIcon: suffix,
      counterStyle: Tx.body(11, color: Tx.subtle),
      hintStyle: Tx.body(15, color: Tx.subtle),
      labelStyle: Tx.body(15, color: Tx.muted),
      filled: true,
      fillColor: Tx.surface3,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: Tx.border)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: Tx.border)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: Tx.purple500, width: 1.4)),
      errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: Tx.danger)),
      focusedErrorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: Tx.danger, width: 1.4)),
    );

/// Abre un enlace sin salir de la app: los de TREVIX (publicaciones, perfiles, canciones…) en su pantalla, las
/// páginas web en el navegador integrado y el resto (tel:, mailto:…) en la app que corresponda.
Future<void> openUrl(BuildContext context, String url) async {
  final uri = Uri.tryParse(url.trim());
  if (uri == null) return;
  if ((uri.host == Uri.parse(AppConfig.site).host || uri.scheme == 'trevix') && DeepLinks.open(context, uri)) return;
  if (uri.scheme == 'http' || uri.scheme == 'https') {
    await push(context, BrowserScreen(url: uri.toString()));
    return;
  }
  final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
  if (!ok && context.mounted) toast(context, tr('No se pudo abrir el enlace.'), error: true);
}

Future<void> openInApp(BuildContext context, String url) async {
  final uri = Uri.tryParse(url);
  if (uri == null) return;
  final ok = await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
  if (!ok && context.mounted) toast(context, tr('No se pudo abrir el enlace.'), error: true);
}
