import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/api.dart';
import '../core/format.dart';
import '../core/i18n.dart';
import '../core/nav.dart';
import '../core/theme.dart';
import '../models/models.dart';
import 'common.dart';

/// Evento dentro de una publicación: portada, fecha, lugar y «Asistiré» / «Me interesa».
class EventCard extends StatefulWidget {
  const EventCard({super.key, required this.event});

  final EventInfo event;

  @override
  State<EventCard> createState() => _EventCardState();
}

class _EventCardState extends State<EventCard> {
  bool _busy = false;

  EventInfo get e => widget.event;

  Future<void> _respond(String choice) async {
    if (_busy) return;
    final next = e.response == choice ? 'none' : choice;
    HapticFeedback.selectionClick();
    setState(() => _busy = true);
    try {
      final res = await api.post('events/${e.id}/respond', {'choice': next});
      e.going = asInt(res.map['going_count'], e.going);
      e.interested = asInt(res.map['interested_count'], e.interested);
      e.response = asStrOrNull(res.map['viewer_response']);
      if (mounted && next == 'going') toast(context, tr('Le avisamos al organizador que asistirás.'));
    } catch (err) {
      if (mounted) toastError(context, err);
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final starts = e.startsAt;
    return Container(
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(color: Tx.surface2, borderRadius: BorderRadius.circular(18), border: Border.all(color: Tx.border)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (e.coverUrl != null) AspectRatio(aspectRatio: 1200 / 630, child: NetImage(e.coverUrl)),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (starts != null)
              Container(
                width: 54,
                height: 58,
                decoration: BoxDecoration(color: Tx.surface3, borderRadius: BorderRadius.circular(12)),
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Text(shortMonth(starts).toUpperCase(), style: Tx.body(11.5, weight: FontWeight.w700, color: const Color(0xFFF87171))),
                  Text('${starts.day}', style: Tx.display(22)),
                ]),
              ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Flexible(
                    child: Text(eventWhen(starts, e.endsAt),
                        style: Tx.body(12.5, weight: FontWeight.w600, color: const Color(0xFFF87171)), maxLines: 2),
                  ),
                  if (e.isPast) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(color: Tx.surface3, borderRadius: BorderRadius.circular(8)),
                      child: Text(tr('Finalizado'), style: Tx.body(11, color: Tx.muted)),
                    ),
                  ],
                ]),
                const SizedBox(height: 3),
                Text(e.title, style: Tx.display(17)),
                const SizedBox(height: 3),
                Row(children: [
                  Icon(CupertinoIcons.location_solid, size: 13, color: Tx.muted),
                  const SizedBox(width: 4),
                  Expanded(child: Text(e.place, style: Tx.body(13, color: Tx.muted), maxLines: 2, overflow: TextOverflow.ellipsis)),
                ]),
                const SizedBox(height: 4),
                Text('${plural(e.going, 'asistirá', 'asistirán')} · ${plural(e.interested, 'interesado', 'interesados')}',
                    style: Tx.body(12, color: Tx.subtle)),
              ]),
            ),
          ]),
        ),
        if (e.description.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
            child: Text(e.description, style: Tx.body(14, height: 1.45), maxLines: 6, overflow: TextOverflow.ellipsis),
          ),
        if (!e.isPast)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
            child: Row(children: [
              Expanded(child: _choice('going', tr('Asistiré'), CupertinoIcons.checkmark_circle_fill)),
              const SizedBox(width: 8),
              Expanded(child: _choice('interested', tr('Me interesa'), CupertinoIcons.star_fill)),
            ]),
          )
        else
          const SizedBox(height: 14),
      ]),
    );
  }

  Widget _choice(String key, String label, IconData icon) {
    final active = e.response == key;
    return Material(
      color: active ? Tx.purple500 : Tx.surface3,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: _busy ? null : () => _respond(key),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, size: 16, color: active ? Colors.white : Tx.muted),
            const SizedBox(width: 6),
            Text(label, style: Tx.body(13.5, weight: FontWeight.w600, color: active ? Colors.white : Tx.text)),
          ]),
        ),
      ),
    );
  }
}

/// Icono de cada acontecimiento importante (las claves vienen del servidor).
IconData lifeEventIcon(String key) => switch (key) {
      'job' => CupertinoIcons.briefcase_fill,
      'graduation' => CupertinoIcons.book_fill,
      'move' => CupertinoIcons.house_fill,
      'relationship' => CupertinoIcons.heart_fill,
      'family' => CupertinoIcons.person_3_fill,
      'travel' => CupertinoIcons.airplane,
      'achievement' => CupertinoIcons.rosette,
      'project' => CupertinoIcons.lightbulb_fill,
      'birthday' => CupertinoIcons.gift_fill,
      _ => CupertinoIcons.star_fill,
    };
