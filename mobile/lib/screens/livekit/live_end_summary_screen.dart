import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../core/i18n.dart';
import '../../core/livekit_api.dart';
import '../../core/theme.dart';
/// Resumen al finalizar un LIVE (estilo TikTok).
class LiveEndSummaryScreen extends StatelessWidget {
  const LiveEndSummaryScreen({super.key, required this.session});

  final LiveKitSession session;

  @override
  Widget build(BuildContext context) {
    final dur = session.durationSeconds ?? 0;
    final mins = dur ~/ 60;
    final secs = dur % 60;
    final durLabel = dur > 0 ? tr('Duración: {time}', {'time': '$mins:${secs.toString().padLeft(2, '0')}'}) : null;
    final viewers = session.uniqueViewers > 0 ? session.uniqueViewers : session.joinCount;
    final gifts = (session.giftsTotalCents / 100);
    final giftLabel = gifts > 0 ? gifts.toStringAsFixed(2) : '0';

    return Scaffold(
      backgroundColor: const Color(0xFF060608),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(CupertinoIcons.xmark, color: Colors.white),
              ),
            ),
            if (durLabel != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 0, 22, 6),
                child: Text(durLabel, style: Tx.body(13, color: Colors.white54)),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 8, 22, 6),
              child: Text(tr('¡Felicitaciones!'), style: Tx.display(28, color: Colors.white)),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22),
              child: Text(
                tr('Lo estás haciendo muy bien. ¡Sigue así!'),
                style: Tx.body(15, color: Colors.white70, height: 1.35),
              ),
            ),
            const SizedBox(height: 22),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: _StatsCard(
                children: [
                  _StatCell(value: '$viewers', label: tr('Espectadores')),
                  _StatCell(value: giftLabel, label: tr('Regalos')),
                  _StatCell(value: '${session.likes}', label: tr('Me gusta')),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 24),
                children: [
                  _InfoCard(
                    icon: CupertinoIcons.heart_fill,
                    iconColor: const Color(0xFFF43F5E),
                    title: tr('Tu audiencia'),
                    body: viewers > 0
                        ? tr('Tu LIVE llegó a {n} personas. Vuelve a transmitir pronto para crecer más.', {'n': '$viewers'})
                        : tr('La próxima vez invita a tus seguidores desde Stories o comparte el enlace al iniciar.'),
                  ),
                  if (session.title != null && session.title!.trim().isNotEmpty)
                    _InfoCard(
                      icon: CupertinoIcons.text_bubble,
                      iconColor: Tx.accent,
                      title: session.title!,
                      body: tr('Título de esta transmisión.'),
                    ),
                  _InfoCard(
                    icon: CupertinoIcons.gift_fill,
                    iconColor: const Color(0xFFFBBF24),
                    title: tr('Regalos en vivo'),
                    body: gifts > 0
                        ? tr('Recibiste regalos por un total de {amount}.', {'amount': giftLabel})
                        : tr('Activa los regalos en tu próximo LIVE para que tu comunidad te apoye.'),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 0, 22, 16),
              child: FilledButton(
                onPressed: () => Navigator.pop(context),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: Text(tr('Listo'), style: Tx.body(16, weight: FontWeight.w800)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatsCard extends StatelessWidget {
  const _StatsCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1C1C22),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withAlpha(20)),
      ),
      child: Row(children: [for (final c in children) Expanded(child: c)]),
    );
  }
}

class _StatCell extends StatelessWidget {
  const _StatCell({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value, style: Tx.display(22, color: Colors.white)),
        const SizedBox(height: 4),
        Text(label, textAlign: TextAlign.center, style: Tx.body(12, color: Colors.white54), maxLines: 2),
      ],
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.icon, required this.iconColor, required this.title, required this.body});

  final IconData icon;
  final Color iconColor;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF14141A),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: iconColor.withAlpha(40), borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, color: iconColor, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Tx.body(15, weight: FontWeight.w800, color: Colors.white)),
                const SizedBox(height: 6),
                Text(body, style: Tx.body(13.5, color: Colors.white60, height: 1.35)),
              ],
            ),
          ),
          const Icon(CupertinoIcons.chevron_forward, color: Colors.white24, size: 18),
        ],
      ),
    );
  }
}