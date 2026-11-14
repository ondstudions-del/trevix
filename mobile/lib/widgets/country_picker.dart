import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/i18n.dart';
import '../core/nav.dart';
import '../core/session.dart';
import '../core/theme.dart';

/// Bandera (emoji) de un código de país ISO de dos letras.
String countryFlag(String code) {
  final c = code.toUpperCase();
  if (c.length != 2 || !RegExp(r'^[A-Z]{2}$').hasMatch(c)) return '';
  return String.fromCharCodes([0x1F1E6 + c.codeUnitAt(0) - 65, 0x1F1E6 + c.codeUnitAt(1) - 65]);
}

/// Quita tildes y mayúsculas para buscar «peru» y encontrar «Perú».
String foldText(String s) {
  const from = 'áàäâãåéèëêíìïîóòöôõúùüûñçÁÀÄÂÃÅÉÈËÊÍÌÏÎÓÒÖÔÕÚÙÜÛÑÇ';
  const to = 'aaaaaaeeeeiiiiooooouuuuncaaaaaaeeeeiiiiooooouuuunc';
  final b = StringBuffer();
  for (final ch in s.split('')) {
    final i = from.indexOf(ch);
    b.write(i >= 0 ? to[i] : ch);
  }
  return b.toString().toLowerCase();
}

/// Elige un país con buscador y banderas. Devuelve el código, '' para «Sin especificar» o null si se cerró.
Future<String?> pickCountry(BuildContext context, {String? current}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _CountrySheet(current: current),
  );
}

class _CountrySheet extends StatefulWidget {
  const _CountrySheet({this.current});

  final String? current;

  @override
  State<_CountrySheet> createState() => _CountrySheetState();
}

class _CountrySheetState extends State<_CountrySheet> {
  final _query = TextEditingController();
  late final List<MapEntry<String, String>> _all;

  @override
  void initState() {
    super.initState();
    _all = context.read<AppState>().countries.entries.toList()
      ..sort((a, b) => foldText(a.value).compareTo(foldText(b.value)));
    _query.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final q = foldText(_query.text.trim());
    final items = q.isEmpty ? _all : _all.where((e) => foldText(e.value).contains(q) || e.key.toLowerCase() == q).toList();
    return SheetFrame(
      padding: EdgeInsets.zero,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * .8),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(padding: const EdgeInsets.fromLTRB(20, 0, 20, 10), child: Text(tr('País'), style: Tx.display(19))),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: CupertinoSearchTextField(controller: _query, placeholder: tr('Buscar país'), autofocus: true),
          ),
          if (q.isEmpty)
            ListTile(
              leading: Icon(CupertinoIcons.minus_circle, color: Tx.muted),
              title: Text(tr('Sin especificar'), style: Tx.body(15.5)),
              trailing: widget.current == null ? Icon(CupertinoIcons.checkmark_alt, color: Tx.accent) : null,
              onTap: () => Navigator.pop(context, ''),
            ),
          Flexible(
            child: items.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(28),
                    child: Text(tr('No encontramos ese país.'), textAlign: TextAlign.center, style: Tx.body(14.5, color: Tx.muted)),
                  )
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: items.length,
                    itemBuilder: (_, i) {
                      final e = items[i];
                      final selected = e.key == widget.current;
                      return ListTile(
                        leading: Text(countryFlag(e.key), style: const TextStyle(fontSize: 24)),
                        title: Text(e.value, style: Tx.body(15.5, weight: selected ? FontWeight.w700 : FontWeight.w500)),
                        trailing: selected ? Icon(CupertinoIcons.checkmark_alt, color: Tx.accent) : null,
                        onTap: () => Navigator.pop(context, e.key),
                      );
                    },
                  ),
          ),
        ]),
      ),
    );
  }
}
