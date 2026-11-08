import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/nav.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';
import '../../widgets/profile_about.dart';
import '../../widgets/settings_tiles.dart';

/// Datos personales del perfil: ciudades, cumpleaños, situación sentimental, género, intereses, enlaces,
/// contactos y quién puede verlos (PUT me/details).
class PersonalDataScreen extends StatefulWidget {
  const PersonalDataScreen({super.key});

  @override
  State<PersonalDataScreen> createState() => _PersonalDataScreenState();
}

class _LinkRow {
  _LinkRow([String title = '', String url = ''])
      : title = TextEditingController(text: title),
        url = TextEditingController(text: url);

  final TextEditingController title;
  final TextEditingController url;

  void dispose() {
    title.dispose();
    url.dispose();
  }
}

class _ContactRow {
  _ContactRow(this.type, [String value = '']) : value = TextEditingController(text: value);

  String type;
  final TextEditingController value;
}

class _PersonalDataScreenState extends State<PersonalDataScreen> {
  final _city = TextEditingController();
  final _hometown = TextEditingController();
  final _interest = TextEditingController();
  final List<_LinkRow> _links = [];
  final List<_ContactRow> _contacts = [];
  List<String> _interests = [];
  String? _relationship;
  String? _gender;
  String _audience = 'everyone';
  bool _showYear = false;
  DateTime? _birth;

  List<Choice> _relationships = const [];
  List<Choice> _genders = const [];
  List<Choice> _audiences = const [];
  List<Choice> _contactTypes = const [];
  int _maxInterests = 15, _maxLinks = 5, _maxContacts = 10;

  bool _loading = true;
  bool _saving = false;
  Object? _error;
  Map<String, String> _errors = {};

  @override
  void initState() {
    super.initState();
    final birth = context.read<AppState>().me?.birthDate;
    _birth = birth == null ? null : DateTime.tryParse(birth);
    _load();
  }

  @override
  void dispose() {
    _city.dispose();
    _hometown.dispose();
    _interest.dispose();
    for (final l in _links) {
      l.dispose();
    }
    for (final c in _contacts) {
      c.value.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await api.get('me/details');
      if (!mounted) return;
      final d = ProfileDetails.fromJson(asMap(res.map['details']));
      final o = asMap(res.map['options']);
      final limits = asMap(o['limits']);
      setState(() {
        _city.text = d.city ?? '';
        _hometown.text = d.hometown ?? '';
        _relationship = d.relationshipStatus;
        _gender = d.gender;
        _audience = d.audience ?? 'everyone';
        _showYear = d.showBirthYear;
        _interests = [...d.interests];
        _links
          ..clear()
          ..addAll(d.links.map((l) => _LinkRow(l.title, l.url)));
        _contacts
          ..clear()
          ..addAll(d.contacts.map((c) => _ContactRow(c.type, c.value)));
        _relationships = asList(o['relationship_status'], Choice.fromJson);
        _genders = asList(o['gender'], Choice.fromJson);
        _audiences = asList(o['details_audience'], Choice.fromJson);
        _contactTypes = asList(o['contact_types'], Choice.fromJson);
        _maxInterests = asInt(limits['interests'], 15);
        _maxLinks = asInt(limits['links'], 5);
        _maxContacts = asInt(limits['contacts'], 10);
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e;
          _loading = false;
        });
      }
    }
  }

  String _label(List<Choice> list, String? key, String fallback) =>
      key == null ? fallback : list.firstWhere((c) => c.key == key, orElse: () => Choice(key, key)).label;

  String get _birthText =>
      _birth == null ? '' : '${_birth!.year}-${_birth!.month.toString().padLeft(2, '0')}-${_birth!.day.toString().padLeft(2, '0')}';

  Future<void> _pickBirth() async {
    FocusScope.of(context).unfocus();
    final now = DateTime.now();
    var picked = _birth ?? DateTime(now.year - 18, now.month, now.day);
    await showCupertinoModalPopup<void>(
      context: context,
      builder: (ctx) => Container(
        height: 320,
        decoration: BoxDecoration(color: Tx.surface2, borderRadius: const BorderRadius.vertical(top: Radius.circular(24))),
        child: SafeArea(
          top: false,
          child: Column(children: [
            Row(children: [
              const SizedBox(width: 20),
              Text('Fecha de nacimiento', style: Tx.display(17)),
              const Spacer(),
              CupertinoButton(
                onPressed: () {
                  setState(() => _birth = picked);
                  Navigator.pop(ctx);
                },
                child: Text('Listo', style: Tx.body(16, weight: FontWeight.w700, color: Tx.accent)),
              ),
            ]),
            Expanded(
              child: CupertinoTheme(
                data: CupertinoThemeData(brightness: Tx.palette.brightness),
                child: CupertinoDatePicker(
                  mode: CupertinoDatePickerMode.date,
                  initialDateTime: picked,
                  minimumDate: DateTime(now.year - 120),
                  maximumDate: now,
                  onDateTimeChanged: (d) => picked = d,
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  void _choose(String title, List<Choice> options, String? current, ValueChanged<String?> onPick) {
    FocusScope.of(context).unfocus();
    actionSheet(context, [
      SheetAction('Sin especificar', CupertinoIcons.minus_circle, () => setState(() => onPick(null))),
      for (final c in options)
        SheetAction(c.label, c.key == current ? CupertinoIcons.checkmark_alt : CupertinoIcons.circle, () => setState(() => onPick(c.key))),
    ], title: title);
  }

  void _addInterest() {
    final text = _interest.text.trim().replaceFirst(RegExp(r'^#+'), '');
    if (text.isEmpty) return;
    if (_interests.length >= _maxInterests) {
      toast(context, 'Puedes añadir hasta $_maxInterests intereses.', error: true);
      return;
    }
    if (_interests.any((i) => i.toLowerCase() == text.toLowerCase())) {
      _interest.clear();
      return;
    }
    setState(() {
      _interests.add(text);
      _interest.clear();
    });
  }

  void _addContact() {
    FocusScope.of(context).unfocus();
    actionSheet(context, [
      for (final c in _contactTypes)
        SheetAction(c.label, contactIcon(c.key), () => setState(() => _contacts.add(_ContactRow(c.key)))),
    ], title: 'Añadir contacto');
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    _addInterest();
    setState(() {
      _saving = true;
      _errors = {};
    });
    try {
      final res = await api.put('me/details', {
        'city': _city.text.trim(),
        'hometown': _hometown.text.trim(),
        'relationship_status': _relationship ?? '',
        'gender': _gender ?? '',
        'details_audience': _audience,
        'show_birth_year': _showYear,
        if (_birth != null) 'birth_date': _birthText,
        'interests': _interests,
        'links': [
          for (final l in _links)
            if (l.url.text.trim().isNotEmpty) {'title': l.title.text.trim(), 'url': l.url.text.trim()},
        ],
        'contacts': [
          for (final c in _contacts)
            if (c.value.text.trim().isNotEmpty) {'type': c.type, 'value': c.value.text.trim()},
        ],
      });
      if (!mounted) return;
      await context.read<AppState>().refreshMe();
      if (!mounted) return;
      toast(context, '${res.map['message'] ?? 'Guardado.'}');
      Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _errors = e.fields.isEmpty ? {'form': e.message} : e.fields;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: GlassBar(
        title: 'Datos personales',
        actions: [
          if (!_loading && _error == null)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: GradientButton(label: 'Guardar', expand: false, height: 38, loading: _saving, onPressed: _save),
            ),
        ],
      ),
      body: _loading
          ? const Loading()
          : _error != null
              ? ErrorState(error: _error!, onRetry: _load)
              : _form(),
    );
  }

  Widget _form() {
    final hasYear = _birth != null;
    return ListView(padding: const EdgeInsets.fromLTRB(0, 8, 0, 60), children: [
      if (_errors['form'] != null)
        Padding(padding: const EdgeInsets.fromLTRB(20, 4, 20, 8), child: Text(_errors['form']!, style: Tx.body(14, color: Tx.danger))),
      _section('Lugares', [
        TextField(
          controller: _city,
          maxLength: 80,
          textCapitalization: TextCapitalization.words,
          style: Tx.body(16),
          decoration: fieldDecoration('¿Dónde vives?', label: 'Ciudad o localidad actual', error: _errors['city'], prefix: Icon(CupertinoIcons.house, size: 18, color: Tx.subtle)),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _hometown,
          maxLength: 80,
          textCapitalization: TextCapitalization.words,
          style: Tx.body(16),
          decoration: fieldDecoration('¿De dónde eres?', label: 'Ciudad natal o de origen', error: _errors['hometown'], prefix: Icon(CupertinoIcons.location, size: 18, color: Tx.subtle)),
        ),
        Text('Usamos tu ciudad para sugerirte personas cercanas.', style: Tx.body(12.5, color: Tx.subtle)),
      ]),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18),
        child: SettingsGroup(title: 'Sobre ti', children: [
        SettingsRow(
          icon: CupertinoIcons.gift,
          color: const Color(0xFFEC4899),
          label: 'Fecha de nacimiento',
          value: hasYear ? birthday(_birth!.day, _birth!.month, _birth!.year) : 'Elegir',
          onTap: _pickBirth,
        ),
        SettingsRow(
          icon: CupertinoIcons.calendar,
          color: const Color(0xFF8B5CF6),
          label: 'Mostrar el año de nacimiento',
          trailing: TxSwitch(value: _showYear, onChanged: (v) => setState(() => _showYear = v)),
        ),
        SettingsRow(
          icon: CupertinoIcons.heart,
          color: const Color(0xFFEF4444),
          label: 'Situación sentimental',
          value: _label(_relationships, _relationship, 'Sin especificar'),
          onTap: () => _choose('Situación sentimental', _relationships, _relationship, (v) => _relationship = v),
        ),
        SettingsRow(
          icon: CupertinoIcons.person,
          color: const Color(0xFF0EA5E9),
          label: 'Género',
          value: _label(_genders, _gender, 'Sin especificar'),
          onTap: () => _choose('Género', _genders, _gender, (v) => _gender = v),
        ),
        ]),
      ),
      if (_errors['birth_date'] != null || _errors['relationship_status'] != null || _errors['gender'] != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: Text(_errors['birth_date'] ?? _errors['relationship_status'] ?? _errors['gender']!, style: Tx.body(13, color: Tx.danger)),
        ),
      _section('Intereses', [
        if (_interests.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Wrap(spacing: 8, runSpacing: 8, children: [
              for (final i in _interests) InterestTag(i, onRemove: () => setState(() => _interests.remove(i))),
            ]),
          ),
        TextField(
          controller: _interest,
          maxLength: 30,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _addInterest(),
          style: Tx.body(16),
          decoration: fieldDecoration(
            'Música, fútbol, fotografía…',
            error: _errors['interests'],
            suffix: IconButton(icon: Icon(CupertinoIcons.add_circled_solid, color: Tx.accent), onPressed: _addInterest),
          ),
        ),
        Text('${_interests.length} de $_maxInterests. Ayudan a encontrar personas con tus mismos gustos.', style: Tx.body(12.5, color: Tx.subtle)),
      ]),
      _section('Enlaces', [
        for (final l in _links) ...[
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Column(children: [
                TextField(controller: l.title, maxLength: 40, style: Tx.body(15), decoration: fieldDecoration('Título (opcional)')),
                TextField(
                  controller: l.url,
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  style: Tx.body(15),
                  decoration: fieldDecoration('https://…', prefix: Icon(CupertinoIcons.link, size: 18, color: Tx.subtle)),
                ),
              ]),
            ),
            IconButton(
              tooltip: 'Quitar enlace',
              icon: Icon(CupertinoIcons.minus_circle_fill, color: Tx.danger),
              onPressed: () => setState(() {
                _links.remove(l);
                l.dispose();
              }),
            ),
          ]),
          const SizedBox(height: 12),
        ],
        if (_errors['links'] != null) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(_errors['links']!, style: Tx.body(13, color: Tx.danger))),
        if (_links.length < _maxLinks)
          Align(
            alignment: Alignment.centerLeft,
            child: SoftButton(label: 'Añadir enlace', icon: CupertinoIcons.add, onPressed: () => setState(() => _links.add(_LinkRow()))),
          ),
      ]),
      _section('Información de contacto', [
        for (final c in _contacts) ...[
          Row(children: [
            Expanded(
              child: TextField(
                controller: c.value,
                autocorrect: false,
                keyboardType: switch (c.type) {
                  'email' => TextInputType.emailAddress,
                  'phone' || 'whatsapp' => TextInputType.phone,
                  _ => TextInputType.text,
                },
                style: Tx.body(15),
                decoration: fieldDecoration(
                  switch (c.type) {
                    'email' => 'correo@ejemplo.com',
                    'phone' || 'whatsapp' => '+57 300 000 0000',
                    _ => 'usuario',
                  },
                  label: _label(_contactTypes, c.type, c.type),
                  prefix: Icon(contactIcon(c.type), size: 18, color: Tx.subtle),
                ),
              ),
            ),
            IconButton(
              tooltip: 'Quitar contacto',
              icon: Icon(CupertinoIcons.minus_circle_fill, color: Tx.danger),
              onPressed: () => setState(() {
                _contacts.remove(c);
                c.value.dispose();
              }),
            ),
          ]),
          const SizedBox(height: 10),
        ],
        if (_errors['contacts'] != null) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(_errors['contacts']!, style: Tx.body(13, color: Tx.danger))),
        if (_contacts.length < _maxContacts)
          Align(alignment: Alignment.centerLeft, child: SoftButton(label: 'Añadir contacto', icon: CupertinoIcons.add, onPressed: _addContact)),
      ]),
      _section('¿Quién puede ver tus datos personales?', [
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final a in _audiences) PillChip(label: a.label, selected: _audience == a.key, onTap: () => setState(() => _audience = a.key)),
        ]),
        const SizedBox(height: 10),
        Text(
          'Se aplica a tus ciudades, cumpleaños, situación sentimental, género y contactos. «Amigos» son las personas que '
          'se siguen contigo mutuamente. Tus intereses, enlaces y canción del perfil son públicos.',
          style: Tx.body(12.5, color: Tx.subtle, height: 1.4),
        ),
      ]),
    ]);
  }

  Widget _section(String title, List<Widget> children) => Padding(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 6),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.only(left: 6, bottom: 10),
            child: Text(title.toUpperCase(), style: Tx.body(12, weight: FontWeight.w700, color: Tx.subtle).copyWith(letterSpacing: .8)),
          ),
          ...children,
        ]),
      );
}
