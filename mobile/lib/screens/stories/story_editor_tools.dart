import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/i18n.dart';
import '../../core/nav.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';
import '../../widgets/story_layers.dart';

typedef StoryText = ({String text, String color, String style});

const _textStyles = ['plain', 'box', 'neon'];
const _textStyleNames = {'plain': 'Normal', 'box': 'Fondo', 'neon': 'Neón'};

/// Escribir o editar un texto de la historia sobre la propia historia (fondo oscurecido). Devuelve null si se cancela
/// y un texto vacío si se borró todo.
Future<StoryText?> editStoryText(BuildContext context, {String text = '', String color = '#FFFFFF', String style = 'plain'}) {
  return Navigator.of(context).push<StoryText>(PageRouteBuilder<StoryText>(
    opaque: false,
    barrierColor: Colors.black.withAlpha(150),
    transitionDuration: const Duration(milliseconds: 180),
    pageBuilder: (_, __, ___) => _TextEditor(text: text, color: color, style: style),
    transitionsBuilder: (_, a, __, child) => FadeTransition(opacity: a, child: child),
  ));
}

class _TextEditor extends StatefulWidget {
  const _TextEditor({required this.text, required this.color, required this.style});

  final String text;
  final String color;
  final String style;

  @override
  State<_TextEditor> createState() => _TextEditorState();
}

class _TextEditorState extends State<_TextEditor> {
  late final _controller = TextEditingController(text: widget.text);
  late String _color = widget.color;
  late String _style = widget.style;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _done() => Navigator.pop<StoryText>(context, (text: _controller.text.trim(), color: _color, style: _style));

  @override
  Widget build(BuildContext context) {
    final color = hexColor(_color);
    final isBox = _style == 'box';
    final textColor = isBox ? (color.computeLuminance() > .5 ? Colors.black : Colors.white) : color;
    final field = TextField(
      controller: _controller,
      autofocus: true,
      maxLength: 150,
      maxLines: null,
      textAlign: TextAlign.center,
      textCapitalization: TextCapitalization.sentences,
      cursorColor: textColor,
      style: TxDark.display(28, color: textColor, height: 1.2).copyWith(
        shadows: _style == 'neon' ? [Shadow(color: color, blurRadius: 8), Shadow(color: color, blurRadius: 22)] : null,
      ),
      decoration: InputDecoration(
        border: InputBorder.none,
        isDense: true,
        counterText: '',
        hintText: tr('Escribe…'),
        hintStyle: TxDark.display(28, color: textColor.withAlpha(120)),
      ),
    );
    return Scaffold(
      backgroundColor: Colors.transparent,
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
            child: Row(children: [
              CupertinoButton(
                onPressed: () => Navigator.pop(context),
                child: Text(tr('Cancelar'), style: TxDark.body(16, weight: FontWeight.w600, color: Colors.white)),
              ),
              const Spacer(),
              GestureDetector(
                onTap: () => setState(() => _style = _textStyles[(_textStyles.indexOf(_style) + 1) % _textStyles.length]),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(border: Border.all(color: Colors.white, width: 1.5), borderRadius: BorderRadius.circular(18)),
                  child: Text('Aa · ${tr(_textStyleNames[_style] ?? '')}', style: TxDark.body(14, weight: FontWeight.w700, color: Colors.white)),
                ),
              ),
              const Spacer(),
              CupertinoButton(
                onPressed: _done,
                child: Text(tr('Listo'), style: TxDark.body(16, weight: FontWeight.w700, color: Colors.white)),
              ),
            ]),
          ),
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _done,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 28),
                  child: isBox
                      ? Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(10)),
                          child: field,
                        )
                      : field,
                ),
              ),
            ),
          ),
          SizedBox(
            height: 52,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              children: [
                for (final hex in storyTextColors)
                  GestureDetector(
                    onTap: () => setState(() => _color = hex),
                    child: Container(
                      width: 34,
                      height: 34,
                      margin: const EdgeInsets.symmetric(horizontal: 5),
                      decoration: BoxDecoration(
                        color: hexColor(hex),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: _color == hex ? 3.5 : 1.5),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ]),
      ),
    );
  }
}

/// Encuesta de 2 respuestas.
Future<({String question, List<String> options})?> editStoryPoll(BuildContext context, {String question = '', List<String> options = const []}) {
  final q = TextEditingController(text: question);
  final a = TextEditingController(text: options.isNotEmpty ? options[0] : tr('Sí'));
  final b = TextEditingController(text: options.length > 1 ? options[1] : tr('No'));
  return showModalBottomSheet<({String question, List<String> options})>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => SheetFrame(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      child: StatefulBuilder(builder: (ctx, setSheet) {
        final first = a.text.trim(), second = b.text.trim();
        final valid = q.text.trim().isNotEmpty && first.isNotEmpty && second.isNotEmpty && first.toLowerCase() != second.toLowerCase();
        return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(tr('Encuesta'), style: Tx.display(18)),
          const SizedBox(height: 4),
          Text(tr('Quien vea tu historia podrá elegir una de las dos respuestas.'), style: Tx.body(13.5, color: Tx.muted)),
          const SizedBox(height: 14),
          TextField(
            controller: q,
            autofocus: true,
            maxLength: 80,
            onChanged: (_) => setSheet(() {}),
            textCapitalization: TextCapitalization.sentences,
            style: Tx.body(16),
            decoration: fieldDecoration(tr('Haz una pregunta')),
          ),
          Row(children: [
            Expanded(
              child: TextField(
                controller: a,
                maxLength: 25,
                onChanged: (_) => setSheet(() {}),
                style: Tx.body(15),
                decoration: fieldDecoration(tr('Respuesta 1')),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: b,
                maxLength: 25,
                onChanged: (_) => setSheet(() {}),
                style: Tx.body(15),
                decoration: fieldDecoration(tr('Respuesta 2')),
              ),
            ),
          ]),
          if (first.isNotEmpty && first.toLowerCase() == second.toLowerCase())
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(tr('Las dos respuestas deben ser distintas.'), style: Tx.body(13, color: Tx.danger)),
            ),
          SizedBox(
            height: 50,
            child: FilledButton(
              onPressed: valid ? () => Navigator.pop(ctx, (question: q.text.trim(), options: [first, second])) : null,
              style: FilledButton.styleFrom(backgroundColor: Tx.purple, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
              child: Text(tr('Añadir'), style: Tx.body(16, weight: FontWeight.w600)),
            ),
          ),
        ]);
      }),
    ),
  ).whenComplete(() => Future.delayed(const Duration(milliseconds: 400), () {
        q.dispose();
        a.dispose();
        b.dispose();
      }));
}

/// Enlace con texto opcional para el botón.
Future<({String url, String label})?> editStoryLink(BuildContext context, {String url = '', String label = ''}) {
  final u = TextEditingController(text: url);
  final l = TextEditingController(text: label);
  String? normalized() {
    var value = u.text.trim();
    if (value.isEmpty) return null;
    if (!RegExp(r'^https?://', caseSensitive: false).hasMatch(value)) value = 'https://$value';
    final uri = Uri.tryParse(value);
    if (uri == null || !uri.host.contains('.') || uri.userInfo.isNotEmpty || value.length > 300) return null;
    return value;
  }

  return showModalBottomSheet<({String url, String label})>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => SheetFrame(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      child: StatefulBuilder(builder: (ctx, setSheet) {
        final link = normalized();
        return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(tr('Enlace'), style: Tx.display(18)),
          const SizedBox(height: 4),
          Text(tr('Quien toque el enlace en tu historia irá a esta página.'), style: Tx.body(13.5, color: Tx.muted)),
          const SizedBox(height: 14),
          TextField(
            controller: u,
            autofocus: true,
            keyboardType: TextInputType.url,
            autocorrect: false,
            maxLength: 300,
            onChanged: (_) => setSheet(() {}),
            style: Tx.body(16),
            decoration: fieldDecoration('https://…', prefix: Icon(CupertinoIcons.link, color: Tx.subtle, size: 20)),
          ),
          TextField(
            controller: l,
            maxLength: 30,
            style: Tx.body(15),
            decoration: fieldDecoration(tr('Texto del botón (opcional)')),
          ),
          SizedBox(
            height: 50,
            child: FilledButton(
              onPressed: link == null ? null : () => Navigator.pop(ctx, (url: link, label: l.text.trim())),
              style: FilledButton.styleFrom(backgroundColor: Tx.purple, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
              child: Text(tr('Añadir'), style: Tx.body(16, weight: FontWeight.w600)),
            ),
          ),
        ]);
      }),
    ),
  ).whenComplete(() => Future.delayed(const Duration(milliseconds: 400), () {
        u.dispose();
        l.dispose();
      }));
}

/// Buscar a la persona que se quiere mencionar. Devuelve su nombre de usuario.
Future<String?> pickMention(BuildContext context) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _MentionPicker(),
  );
}

class _MentionPicker extends StatefulWidget {
  const _MentionPicker();

  @override
  State<_MentionPicker> createState() => _MentionPickerState();
}

class _MentionPickerState extends State<_MentionPicker> {
  final _search = TextEditingController();
  Timer? _debounce;
  List<User> _users = const [];
  bool _loading = false;
  Object? _error;
  int _request = 0;

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    final q = value.trim().replaceFirst('@', '');
    if (q.isEmpty) {
      setState(() {
        _users = const [];
        _loading = false;
        _error = null;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 300), () => _load(q));
  }

  Future<void> _load(String q) async {
    final id = ++_request;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await api.get('search', {'q': q, 'type': 'people', 'limit': '15'});
      if (!mounted || id != _request) return;
      setState(() {
        _users = res.list.map(User.fromJson).toList();
        _loading = false;
      });
    } catch (e) {
      if (!mounted || id != _request) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    return SheetFrame(
      padding: EdgeInsets.zero,
      child: SizedBox(
        height: (mq.size.height - mq.viewInsets.bottom - mq.padding.top - 60).clamp(220.0, mq.size.height * .7),
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: Text(tr('Mencionar a alguien'), style: Tx.display(18)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _search,
              autofocus: true,
              autocorrect: false,
              onChanged: _onChanged,
              style: Tx.body(15),
              decoration: fieldDecoration(tr('Buscar personas'), prefix: Icon(CupertinoIcons.search, color: Tx.subtle, size: 20)),
            ),
          ),
          const SizedBox(height: 6),
          Expanded(
            child: _error != null
                ? ErrorState(error: _error!, onRetry: () => _load(_search.text.trim().replaceFirst('@', '')))
                : _loading && _users.isEmpty
                    ? const Loading()
                    : _users.isEmpty
                        ? SingleChildScrollView(
                            child: EmptyState(
                              icon: CupertinoIcons.at,
                              title: _search.text.trim().isEmpty ? tr('Escribe un nombre') : tr('Sin resultados'),
                              message: _search.text.trim().isEmpty ? tr('Busca a la persona que quieres mencionar.') : tr('Prueba con otro nombre.'),
                            ),
                          )
                        : ListView.builder(
                            itemCount: _users.length,
                            itemBuilder: (_, i) {
                              final u = _users[i];
                              return ListTile(
                                leading: Avatar(user: u, size: 40),
                                title: NameLine(user: u, size: 15),
                                subtitle: Text('@${u.username}', style: Tx.body(13, color: Tx.muted)),
                                onTap: () => Navigator.pop(context, u.username),
                              );
                            },
                          ),
          ),
        ]),
      ),
    );
  }
}
