import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';
import '../../widgets/user_tile.dart';

/// Estado de un mensaje propio para una persona: «read» (lo leyó), «delivered» (le llegó) o «sent» (aún no le llega).
class _Recipient {
  _Recipient(Json j)
      : user = User.fromJson(asMap(j['user'])),
        status = asStr(j['status'], 'sent'),
        opened = j['opened'] is bool ? j['opened'] as bool : null,
        readHidden = asBool(j['read_hidden']);

  final User user;
  final String status;

  /// Solo en visualización única: null si no se puede saber (confirmación de lectura desactivada).
  final bool? opened;
  final bool readHidden;
}

/// «Info» del mensaje: quién lo leyó, a quién le llegó y a quién no, y quién abrió la foto o el video de una vez.
class MessageInfoScreen extends StatefulWidget {
  const MessageInfoScreen({super.key, required this.message, this.isGroup = false});

  final Message message;
  final bool isGroup;

  @override
  State<MessageInfoScreen> createState() => _MessageInfoScreenState();
}

class _MessageInfoScreenState extends State<MessageInfoScreen> {
  late Future<Json> _future = _load();

  Future<Json> _load() async => (await api.get('messages/${widget.message.id}/info')).map;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: GlassBar(title: tr('Info del mensaje')),
      body: FutureBuilder<Json>(
        future: _future,
        builder: (context, snap) {
          if (snap.hasError) return ErrorState(error: snap.error!, onRetry: () => setState(() => _future = _load()));
          final data = snap.data;
          if (data == null) return const Loading();
          return RefreshIndicator(
            onRefresh: () async {
              final next = _load();
              setState(() => _future = next);
              await next;
            },
            child: _body(data),
          );
        },
      ),
    );
  }

  Widget _body(Json data) {
    final people = asList(data['people'], (e) => _Recipient(asMap(e)));
    final receipts = data['read_receipts'] != false;
    final viewOnce = asBool(data['view_once']);
    final total = asInt(data['recipients']);
    final read = people.where((p) => p.status == 'read').toList();
    final delivered = people.where((p) => p.status == 'delivered').toList();
    final pending = people.where((p) => p.status == 'sent').toList();
    final opened = people.where((p) => p.opened == true).toList();
    final notOpened = people.where((p) => p.opened == false).toList();
    final m = widget.message;
    final what = m.fileIsVideo ? tr('video') : tr('foto');
    return ListView(padding: const EdgeInsets.only(bottom: 40), children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: Tx.surface2, borderRadius: BorderRadius.circular(16), border: Border.all(color: Tx.border)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(m.summary, maxLines: 3, overflow: TextOverflow.ellipsis, style: Tx.body(15)),
            if (m.createdAt != null) ...[
              const SizedBox(height: 6),
              Text(tr('Enviado {time}', {'time': timeAgo(m.createdAt!)}), style: Tx.body(12.5, color: Tx.subtle)),
            ],
          ]),
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: Wrap(spacing: 8, runSpacing: 8, children: [
          if (receipts) _Stat(icon: CupertinoIcons.eye_fill, label: tr('Leído'), value: tr('{n} de {total}', {'n': read.length, 'total': total}), color: Tx.accent),
          _Stat(icon: CupertinoIcons.checkmark_alt_circle_fill, label: tr('Entregado'), value: tr('{n} de {total}', {'n': read.length + delivered.length, 'total': total}), color: Tx.success),
          _Stat(icon: CupertinoIcons.clock_fill, label: tr('Sin entregar'), value: '${pending.length}', color: Tx.muted),
          if (viewOnce && receipts) _Stat(icon: CupertinoIcons.eye_slash_fill, label: tr('Abrieron'), value: tr('{n} de {total}', {'n': opened.length, 'total': total}), color: Tx.purple500),
        ]),
      ),
      if (!receipts)
        _Notice(
          viewOnce
              ? tr('Desactivaste la confirmación de lectura: no puedes ver quién leyó tus mensajes ni quién abrió esta {what}. Puedes activarla en Ajustes › Chats.', {'what': what})
              : tr('Desactivaste la confirmación de lectura: no puedes ver quién leyó tus mensajes. Puedes activarla en Ajustes › Chats.'),
        ),
      if (receipts && people.any((p) => p.readHidden))
        _Notice(tr('Algunas personas desactivaron la confirmación de lectura: de ellas solo sabes si les llegó el mensaje.')),
      if (viewOnce && receipts) ...[
        _Section(title: tr('Abrieron la {what}', {'what': what}), count: opened.length),
        for (final p in opened) UserTile(user: p.user, subtitle: '@${p.user.username}', showFollow: false),
        if (opened.isEmpty) _Empty(tr('Nadie la ha abierto todavía.')),
        _Section(title: tr('Aún no la abren'), count: notOpened.length),
        for (final p in notOpened) UserTile(user: p.user, subtitle: _statusText(p), showFollow: false),
        if (notOpened.isEmpty && opened.isNotEmpty) _Empty(tr('Todos la abrieron.')),
      ] else ...[
        if (receipts) ...[
          _Section(title: widget.isGroup ? tr('Leído por') : tr('Leído'), count: read.length),
          for (final p in read) UserTile(user: p.user, subtitle: '@${p.user.username}', showFollow: false),
          if (read.isEmpty) _Empty(tr('Todavía nadie lo ha leído.')),
        ],
        _Section(title: tr('Entregado a'), count: delivered.length),
        for (final p in delivered) UserTile(user: p.user, subtitle: _statusText(p), showFollow: false),
        if (delivered.isEmpty) _Empty(receipts ? tr('Sin entregas pendientes de leer.') : tr('Todavía no le llega a nadie.')),
      ],
      _Section(title: tr('Sin entregar'), count: pending.length),
      for (final p in pending) UserTile(user: p.user, subtitle: tr('Aún no abre TREVIX desde que lo enviaste'), showFollow: false),
      if (pending.isEmpty) _Empty(tr('Le llegó a todos.')),
    ]);
  }

  String _statusText(_Recipient p) {
    if (p.status == 'sent') return tr('Sin entregar');
    if (p.readHidden) return tr('Entregado · no comparte la confirmación de lectura');
    return p.status == 'read' ? tr('Leído') : tr('Entregado');
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.icon, required this.label, required this.value, required this.color});

  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(color: Tx.surface2, borderRadius: BorderRadius.circular(14), border: Border.all(color: Tx.border)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 8),
        Text(label, style: Tx.body(13, color: Tx.muted)),
        const SizedBox(width: 6),
        Text(value, style: Tx.body(13.5, weight: FontWeight.w700)),
      ]),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.count});

  final String title;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 22, 16, 6),
      child: Text('${title.toUpperCase()} · $count', style: Tx.body(12, weight: FontWeight.w700, color: Tx.subtle).copyWith(letterSpacing: .8)),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(CupertinoIcons.info_circle, size: 16, color: Tx.subtle),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: Tx.body(13, color: Tx.muted, height: 1.35))),
      ]),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Text(text, style: Tx.body(13.5, color: Tx.subtle)),
    );
  }
}
