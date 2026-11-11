import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/nav.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';

/// Datos de un evento antes de publicarlo; el servidor vuelve a validarlo todo.
class EventDraft {
  EventDraft({required this.title, required this.place, required this.description, required this.startsAt, this.endsAt, this.cover});

  final String title;
  final String place;
  final String description;
  final DateTime startsAt;
  final DateTime? endsAt;
  final XFile? cover;

  /// Campos `event[...]` en UTC (ISO 8601): el servidor los pasa a su zona horaria.
  Map<String, String> fields() => {
        'title': title,
        'place': place,
        'description': description,
        'starts_at': startsAt.toUtc().toIso8601String(),
        if (endsAt != null) 'ends_at': endsAt!.toUtc().toIso8601String(),
      };
}

/// Formulario de evento: portada, nombre, inicio y fin, lugar y descripción.
class EventFormScreen extends StatefulWidget {
  const EventFormScreen({super.key, this.initial});

  final EventDraft? initial;

  @override
  State<EventFormScreen> createState() => _EventFormScreenState();
}

class _EventFormScreenState extends State<EventFormScreen> {
  late final _title = TextEditingController(text: widget.initial?.title ?? '');
  late final _place = TextEditingController(text: widget.initial?.place ?? '');
  late final _description = TextEditingController(text: widget.initial?.description ?? '');
  late DateTime? _starts = widget.initial?.startsAt;
  late DateTime? _ends = widget.initial?.endsAt;
  late XFile? _cover = widget.initial?.cover;
  Map<String, String> _errors = {};

  @override
  void dispose() {
    _title.dispose();
    _place.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _pickCover() async {
    try {
      final file = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 90, maxWidth: 2400);
      if (file != null && mounted) setState(() => _cover = file);
    } catch (e) {
      if (mounted) toastError(context, e);
    }
  }

  Future<void> _pickDate({required bool end}) async {
    final now = DateTime.now();
    final base = end ? (_ends ?? (_starts ?? now).add(const Duration(hours: 2))) : (_starts ?? now.add(const Duration(hours: 1)));
    final min = end ? (_starts ?? now) : now.subtract(const Duration(minutes: 5));
    var picked = base.isBefore(min) ? min.add(const Duration(minutes: 5)) : base;
    picked = DateTime(picked.year, picked.month, picked.day, picked.hour, (picked.minute ~/ 5) * 5);
    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => Container(
        height: 330,
        decoration: BoxDecoration(color: Tx.surface2, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        child: SafeArea(
          top: false,
          child: Column(children: [
            Row(children: [
              const SizedBox(width: 20),
              Text(end ? tr('Termina') : tr('Empieza'), style: Tx.display(17)),
              const Spacer(),
              if (end && _ends != null)
                CupertinoButton(
                  onPressed: () {
                    setState(() => _ends = null);
                    Navigator.pop(ctx);
                  },
                  child: Text(tr('Quitar'), style: Tx.body(16, color: Tx.danger)),
                ),
              CupertinoButton(
                onPressed: () {
                  setState(() {
                    if (end) {
                      _ends = picked;
                    } else {
                      _starts = picked;
                      if (_ends != null && !_ends!.isAfter(picked)) _ends = null;
                    }
                  });
                  Navigator.pop(ctx);
                },
                child: Text(tr('Listo'), style: Tx.body(16, weight: FontWeight.w700, color: Tx.accent)),
              ),
            ]),
            Expanded(
              child: CupertinoTheme(
                data: CupertinoThemeData(brightness: Tx.palette.brightness),
                child: CupertinoDatePicker(
                  mode: CupertinoDatePickerMode.dateAndTime,
                  use24hFormat: true,
                  minuteInterval: 5,
                  initialDateTime: picked,
                  minimumDate: DateTime(min.year, min.month, min.day),
                  maximumDate: now.add(const Duration(days: 365 * 3)),
                  onDateTimeChanged: (d) => picked = d,
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  void _save() {
    FocusScope.of(context).unfocus();
    final e = <String, String>{};
    final title = _title.text.trim(), place = _place.text.trim();
    if (title.length < 3) e['title'] = tr('El nombre debe tener al menos 3 caracteres.');
    if (place.length < 2) e['place'] = tr('Indica el lugar.');
    if (_starts == null) {
      e['starts'] = tr('Indica cuándo empieza.');
    } else if (_starts!.isBefore(DateTime.now().subtract(const Duration(minutes: 30)))) {
      e['starts'] = tr('La fecha de inicio ya pasó.');
    }
    if (_ends != null && _starts != null && !_ends!.isAfter(_starts!)) e['ends'] = tr('Debe terminar después de empezar.');
    setState(() => _errors = e);
    if (e.isNotEmpty) return;
    Navigator.pop(
      context,
      EventDraft(title: title, place: place, description: _description.text.trim(), startsAt: _starts!, endsAt: _ends, cover: _cover),
    );
  }

  Widget _dateTile(String label, DateTime? value, String? error, {required bool end}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GestureDetector(
        onTap: () => _pickDate(end: end),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: Tx.surface2,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: error != null ? Tx.danger : Tx.border),
          ),
          child: Row(children: [
            Icon(end ? CupertinoIcons.clock : CupertinoIcons.calendar, color: Tx.accent, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(label, style: Tx.body(12.5, color: Tx.muted)),
                const SizedBox(height: 2),
                Text(value == null ? (end ? tr('Opcional') : tr('Elegir fecha y hora')) : eventWhen(value, null), style: Tx.body(15.5, weight: FontWeight.w600)),
                if (error != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text(error, style: Tx.body(12.5, color: Tx.danger))),
              ]),
            ),
            Icon(CupertinoIcons.chevron_right, size: 16, color: Tx.muted),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: GlassBar(
        title: widget.initial == null ? tr('Crear evento') : tr('Editar evento'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: GradientButton(label: tr('Listo'), expand: false, height: 38, onPressed: _save),
          ),
        ],
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(18, 16, 18, 60), children: [
        GestureDetector(
          onTap: _pickCover,
          child: Container(
            height: 150,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(20), border: Border.all(color: Tx.border)),
            child: Stack(fit: StackFit.expand, children: [
              _cover != null
                  ? Image.file(File(_cover!.path), fit: BoxFit.cover)
                  : Container(decoration: const BoxDecoration(gradient: LinearGradient(colors: [Tx.purple700, Tx.blue]))),
              Container(color: Colors.black.withAlpha(70)),
              Center(
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(CupertinoIcons.photo, color: Colors.white, size: 20),
                  const SizedBox(width: 8),
                  Text(_cover == null ? tr('Añadir portada (opcional)') : tr('Cambiar portada'), style: Tx.body(14, weight: FontWeight.w600, color: Colors.white)),
                ]),
              ),
              if (_cover != null)
                Positioned(
                  top: 8,
                  right: 8,
                  child: GestureDetector(
                    onTap: () => setState(() => _cover = null),
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                      child: const Icon(CupertinoIcons.xmark, color: Colors.white, size: 14),
                    ),
                  ),
                ),
            ]),
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _title,
          maxLength: 120,
          style: Tx.body(16),
          textCapitalization: TextCapitalization.sentences,
          decoration: fieldDecoration(tr('Ej.: Concierto en el parque'), error: _errors['title'], label: tr('Nombre del evento')),
        ),
        const SizedBox(height: 8),
        _dateTile(tr('Empieza'), _starts, _errors['starts'], end: false),
        _dateTile(tr('Termina'), _ends, _errors['ends'], end: true),
        const SizedBox(height: 6),
        TextField(
          controller: _place,
          maxLength: 160,
          style: Tx.body(16),
          textCapitalization: TextCapitalization.sentences,
          decoration: fieldDecoration(tr('Dirección o nombre del lugar'), error: _errors['place'], label: tr('Lugar'), prefix: const Icon(CupertinoIcons.location_solid, size: 18)),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _description,
          maxLength: 2000,
          minLines: 3,
          maxLines: 8,
          style: Tx.body(16),
          textCapitalization: TextCapitalization.sentences,
          decoration: fieldDecoration(tr('Cuenta de qué trata (opcional)'), label: tr('Descripción')),
        ),
      ]),
    );
  }
}
