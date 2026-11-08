import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/nav.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';

/// Buscar texto dentro de una conversación. Al tocar un resultado devuelve el id del mensaje para saltar a él.
class ChatSearchScreen extends StatefulWidget {
  const ChatSearchScreen({super.key, required this.conversationId, required this.partnerName});

  final int conversationId;
  final String partnerName;

  @override
  State<ChatSearchScreen> createState() => _ChatSearchScreenState();
}

class _ChatSearchScreenState extends State<ChatSearchScreen> {
  final _search = TextEditingController();
  Timer? _debounce;
  List<Message>? _results;
  Object? _error;
  bool _loading = false;
  int _request = 0;

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _run(String q) async {
    final id = ++_request;
    if (q.length < 2) {
      setState(() {
        _results = null;
        _error = null;
        _loading = false;
      });
      return;
    }
    setState(() => _loading = true);
    try {
      final res = await api.get('conversations/${widget.conversationId}/search', {'q': q});
      if (id == _request && mounted) {
        setState(() {
          _results = res.list.map(Message.fromJson).toList();
          _error = null;
          _loading = false;
        });
      }
    } catch (e) {
      if (id == _request && mounted) {
        setState(() {
          _error = e;
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final results = _results;
    final term = _search.text.trim();
    return Scaffold(
      appBar: const GlassBar(title: 'Buscar en el chat'),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: TextField(
            controller: _search,
            autofocus: true,
            textInputAction: TextInputAction.search,
            onChanged: (v) {
              _debounce?.cancel();
              _debounce = Timer(const Duration(milliseconds: 350), () => _run(v.trim()));
            },
            onSubmitted: (v) => _run(v.trim()),
            style: Tx.body(15),
            decoration: fieldDecoration('Buscar mensajes', prefix: Icon(CupertinoIcons.search, color: Tx.subtle, size: 20)),
          ),
        ),
        Expanded(
          child: _error != null
              ? ErrorState(error: _error!, onRetry: () => _run(term))
              : _loading && results == null
                  ? const Loading()
                  : results == null
                      ? const EmptyState(icon: CupertinoIcons.search_circle, title: 'Busca en esta conversación', message: 'Escribe al menos 2 letras.')
                      : results.isEmpty
                          ? const EmptyState(icon: CupertinoIcons.search, title: 'Sin resultados', message: 'Ningún mensaje contiene ese texto.')
                          : ListView.separated(
                              itemCount: results.length,
                              separatorBuilder: (_, __) => Divider(height: 1, color: Tx.border, indent: 16),
                              itemBuilder: (_, i) {
                                final m = results[i];
                                return ListTile(
                                  onTap: () => Navigator.pop(context, m.id),
                                  title: Text(m.isMine ? 'Tú' : widget.partnerName, style: Tx.body(13, weight: FontWeight.w600, color: Tx.muted)),
                                  subtitle: _Highlighted(text: m.body ?? '', term: term),
                                  trailing: Text(timeAgo(m.createdAt), style: Tx.body(12, color: Tx.subtle)),
                                );
                              },
                            ),
        ),
      ]),
    );
  }
}

/// Texto con las coincidencias de la búsqueda resaltadas.
class _Highlighted extends StatelessWidget {
  const _Highlighted({required this.text, required this.term});

  final String text;
  final String term;

  @override
  Widget build(BuildContext context) {
    final base = Tx.body(15, color: Tx.text);
    if (term.isEmpty) return Text(text, maxLines: 3, overflow: TextOverflow.ellipsis, style: base);
    final lower = text.toLowerCase();
    final needle = term.toLowerCase();
    final spans = <TextSpan>[];
    var start = 0;
    while (true) {
      final i = lower.indexOf(needle, start);
      if (i < 0) {
        spans.add(TextSpan(text: text.substring(start)));
        break;
      }
      if (i > start) spans.add(TextSpan(text: text.substring(start, i)));
      spans.add(TextSpan(
        text: text.substring(i, i + needle.length),
        style: TextStyle(fontWeight: FontWeight.w700, color: Tx.accent, backgroundColor: Tx.alpha(Tx.accent, .15)),
      ));
      start = i + needle.length;
    }
    return Text.rich(TextSpan(style: base, children: spans), maxLines: 3, overflow: TextOverflow.ellipsis);
  }
}
