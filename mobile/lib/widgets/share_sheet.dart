import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/nav.dart';
import '../core/theme.dart';

/// Compartir un enlace de TREVIX en X, WhatsApp, TikTok, Facebook, Telegram, correo o el menú del sistema.
/// [extra] añade acciones propias arriba (p. ej. «Compartir en TREVIX» en las publicaciones).
Future<void> showShareSheet(BuildContext context, {required String url, String title = '', List<SheetAction> extra = const []}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => _ShareSheet(url: url, title: title, extra: extra),
  );
}

class _Net {
  const _Net(this.label, this.color, this.glyph, this.open);

  final String label;
  final Color color;
  final Widget glyph;
  final Future<void> Function(BuildContext context, String url, String title) open;
}

String _enc(String s) => Uri.encodeComponent(s);

Future<bool> _launch(String uri) async {
  try {
    return await launchUrl(Uri.parse(uri), mode: LaunchMode.externalApplication);
  } catch (_) {
    return false;
  }
}

Future<void> _openFirst(BuildContext context, List<String> uris) async {
  for (final u in uris) {
    if (await _launch(u)) return;
  }
  if (context.mounted) toast(context, 'No se pudo abrir la aplicación.', error: true);
}

List<_Net> get _nets => <_Net>[
  _Net('X', Colors.black, Text('𝕏', style: Tx.body(22, weight: FontWeight.w700, color: Colors.white)),
      (c, u, t) => _openFirst(c, ['twitter://post?message=${_enc(t.isEmpty ? u : '$t $u')}', 'https://x.com/intent/post?text=${_enc(t)}&url=${_enc(u)}'])),
  _Net('WhatsApp', const Color(0xFF25D366), const Icon(CupertinoIcons.chat_bubble_fill, color: Colors.white, size: 24),
      (c, u, t) => _openFirst(c, ['whatsapp://send?text=${_enc(t.isEmpty ? u : '$t $u')}', 'https://wa.me/?text=${_enc(t.isEmpty ? u : '$t $u')}'])),
  _Net('TikTok', const Color(0xFF010101), const Icon(CupertinoIcons.music_note, color: Colors.white, size: 24), (c, u, t) async {
    await Clipboard.setData(ClipboardData(text: u));
    if (c.mounted) toast(c, 'Enlace copiado: pégalo en un mensaje o en tu biografía de TikTok.');
    if (c.mounted) await _openFirst(c, ['snssdk1233://', 'tiktok://', 'https://www.tiktok.com/']);
  }),
  _Net('Facebook', const Color(0xFF1877F2), Text('f', style: Tx.body(26, weight: FontWeight.w800, color: Colors.white)),
      (c, u, t) => _openFirst(c, ['https://www.facebook.com/sharer/sharer.php?u=${_enc(u)}'])),
  _Net('Telegram', const Color(0xFF229ED9), const Icon(CupertinoIcons.paperplane_fill, color: Colors.white, size: 22),
      (c, u, t) => _openFirst(c, ['tg://msg_url?url=${_enc(u)}&text=${_enc(t)}', 'https://t.me/share/url?url=${_enc(u)}&text=${_enc(t)}'])),
  _Net('Mensaje', const Color(0xFF34C759), const Icon(CupertinoIcons.chat_bubble_text_fill, color: Colors.white, size: 22),
      (c, u, t) => _openFirst(c, ['sms:&body=${_enc(t.isEmpty ? u : '$t $u')}'])),
  _Net('Correo', Tx.surface4, Icon(CupertinoIcons.mail_solid, color: Tx.text, size: 22),
      (c, u, t) => _openFirst(c, ['mailto:?subject=${_enc(t.isEmpty ? 'Mira esto en TREVIX' : t)}&body=${_enc(t.isEmpty ? u : '$t\n\n$u')}'])),
  _Net('Copiar', Tx.surface4, Icon(CupertinoIcons.link, color: Tx.text, size: 22), (c, u, t) async {
    await Clipboard.setData(ClipboardData(text: u));
    if (c.mounted) toast(c, 'Enlace copiado.');
  }),
];

class _ShareSheet extends StatelessWidget {
  const _ShareSheet({required this.url, required this.title, required this.extra});

  final String url;
  final String title;
  final List<SheetAction> extra;

  @override
  Widget build(BuildContext context) {
    final root = Navigator.of(context, rootNavigator: true).context;
    return SheetFrame(
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
          child: Text('Compartir', style: Tx.display(19), textAlign: TextAlign.center),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 14),
          child: Text(title.isEmpty ? url : title,
              maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: Tx.body(13, color: Tx.muted)),
        ),
        for (final a in extra)
          InkWell(
            onTap: () {
              Navigator.pop(context);
              a.onTap();
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              child: Row(children: [
                Icon(a.icon, size: 22, color: Tx.text),
                const SizedBox(width: 14),
                Expanded(child: Text(a.label, style: Tx.body(16, weight: FontWeight.w500))),
              ]),
            ),
          ),
        if (extra.isNotEmpty) Divider(color: Tx.border, height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: GridView.count(
            crossAxisCount: 4,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 6,
            childAspectRatio: .9,
            children: [
              for (final n in _nets)
                _NetButton(
                  net: n,
                  onTap: () {
                    Navigator.pop(context);
                    n.open(root, url, title);
                  },
                ),
            ],
          ),
        ),
        CupertinoButton(
          onPressed: () {
            Navigator.pop(context);
            Share.share(title.isEmpty ? url : '$title\n$url');
          },
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(CupertinoIcons.share, size: 20, color: Tx.accent),
            const SizedBox(width: 8),
            Text('Más opciones', style: Tx.body(15, weight: FontWeight.w600, color: Tx.accent)),
          ]),
        ),
      ]),
    );
  }
}

class _NetButton extends StatelessWidget {
  const _NetButton({required this.net, required this.onTap});

  final _Net net;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Container(
          width: 54,
          height: 54,
          decoration: BoxDecoration(
            color: net.color,
            shape: BoxShape.circle,
            border: net.color == Colors.black ? Border.all(color: Tx.isDark ? Colors.white24 : Colors.transparent) : null,
          ),
          alignment: Alignment.center,
          child: net.glyph,
        ),
        const SizedBox(height: 6),
        Text(net.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: Tx.body(12, color: Tx.text)),
      ]),
    );
  }
}
