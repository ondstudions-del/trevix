import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/catalog.dart';
import '../../core/format.dart';
import '../../core/nav.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';

/// Envío de una canción a revisión (POST me/music, multipart).
class ArtistUploadScreen extends StatefulWidget {
  const ArtistUploadScreen({super.key});

  @override
  State<ArtistUploadScreen> createState() => _ArtistUploadScreenState();
}

class _ArtistUploadScreenState extends State<ArtistUploadScreen> {
  final _title = TextEditingController();
  final _featuring = TextEditingController();
  String? _genre;
  bool _explicit = false;
  bool _rights = false;
  PlatformFile? _audio;
  XFile? _cover;
  bool _busy = false;
  Map<String, String> _errors = {};

  @override
  void dispose() {
    _title.dispose();
    _featuring.dispose();
    super.dispose();
  }

  List<String> get _extensions {
    final raw = context.read<AppState>().config['audio_extensions'];
    final list = (raw is List ? raw : const []).map((e) => '$e'.toLowerCase()).where((e) => e.isNotEmpty).toList();
    return list.isEmpty ? const ['mp3', 'm4a'] : list;
  }

  Future<void> _pickAudio() async {
    try {
      final result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: _extensions);
      final file = result?.files.single;
      if (file == null || file.path == null || !mounted) return;
      final max = context.read<AppState>().limit('audio_max_bytes', 15 * 1024 * 1024);
      if (file.size > max) {
        toast(context, 'El archivo pesa ${fileSize(file.size)}. El máximo es ${fileSize(max)}.', error: true);
        return;
      }
      setState(() {
        _audio = file;
        _errors.remove('audio');
        if (_title.text.trim().isEmpty) {
          final dot = file.name.lastIndexOf('.');
          _title.text = (dot > 0 ? file.name.substring(0, dot) : file.name).replaceAll(RegExp(r'[_\-]+'), ' ').trim();
        }
      });
    } catch (_) {
      if (mounted) toast(context, 'No se pudo abrir el selector de archivos.', error: true);
    }
  }

  Future<void> _pickCover() async {
    try {
      final file = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 92, maxWidth: 1400);
      if (file != null && mounted) setState(() => _cover = file);
    } catch (_) {
      if (mounted) toast(context, 'No se pudo abrir la galería. Revisa el permiso de Fotos.', error: true);
    }
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    final errors = <String, String>{};
    if (_title.text.trim().isEmpty) errors['title'] = 'Escribe el título de la canción.';
    if (_genre == null) errors['genre'] = 'Elige un género.';
    if (_audio == null) errors['audio'] = 'Adjunta el archivo de audio.';
    if (!_rights) errors['rights'] = 'Debes confirmar que tienes los derechos.';
    if (errors.isNotEmpty) {
      setState(() => _errors = errors);
      return;
    }
    setState(() {
      _busy = true;
      _errors = {};
    });
    try {
      final res = await api.upload('me/music', fields: {
        'title': _title.text.trim(),
        'featuring': _featuring.text.trim(),
        'genre': _genre!,
        'explicit': _explicit ? '1' : '0',
        'rights': '1',
      }, files: [
        Upload('audio', _audio!.path!, filename: _audio!.name),
        if (_cover != null) Upload('cover', _cover!.path, filename: _cover!.name),
      ]);
      if (!mounted) return;
      toast(context, '${res.map['message'] ?? 'Enviamos tu canción a revisión.'}');
      Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _errors = e.fields.isEmpty ? {'form': e.message} : e.fields;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _errors = {'form': errorText(e)};
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.read<AppState>();
    final minSec = state.limit('audio_min_seconds', 30);
    final maxSec = state.limit('audio_max_seconds', 600);
    final maxBytes = state.limit('audio_max_bytes', 15 * 1024 * 1024);
    return Scaffold(
      appBar: GlassBar(
        title: 'Subir canción',
        leading: CupertinoButton(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: Text('Cancelar', style: Tx.body(15.5, color: Tx.muted)),
        ),
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(18, 18, 18, 60), children: [
        if (_errors['form'] != null)
          Container(
            margin: const EdgeInsets.only(bottom: 14),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Tx.alpha(Tx.danger, .12), borderRadius: BorderRadius.circular(14), border: Border.all(color: Tx.alpha(Tx.danger, .4))),
            child: Text(_errors['form']!, style: Tx.body(14, color: Tx.danger)),
          ),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          GestureDetector(
            onTap: _busy ? null : _pickCover,
            child: Container(
              width: 110,
              height: 110,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22),
                gradient: _cover == null ? Tx.brandSoft : null,
                border: Border.all(color: _errors['cover'] != null ? Tx.danger : Tx.alpha(Tx.purple500, .4)),
              ),
              child: _cover != null
                  ? Image(image: ResizeImage(FileImage(_coverFile), width: 330), fit: BoxFit.cover)
                  : Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      const Icon(CupertinoIcons.photo_on_rectangle, color: Tx.purple300, size: 28),
                      const SizedBox(height: 6),
                      Text('Portada\n(opcional)', textAlign: TextAlign.center, style: Tx.body(12, color: Tx.muted)),
                    ]),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: GestureDetector(
              onTap: _busy ? null : _pickAudio,
              child: Container(
                height: 110,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Tx.surface2,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: _errors['audio'] != null ? Tx.danger : (_audio != null ? Tx.purple500 : Tx.border)),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(_audio != null ? CupertinoIcons.waveform : CupertinoIcons.cloud_upload, color: Tx.purple300, size: 26),
                  const SizedBox(height: 6),
                  Text(_audio?.name ?? 'Elegir archivo de audio', maxLines: 2, overflow: TextOverflow.ellipsis, style: Tx.body(14, weight: FontWeight.w600)),
                  Text(
                    _audio != null ? fileSize(_audio!.size) : '${_extensions.map((e) => e.toUpperCase()).join(', ')} · hasta ${fileSize(maxBytes)}',
                    style: Tx.body(12, color: Tx.subtle),
                  ),
                ]),
              ),
            ),
          ),
        ]),
        if (_errors['audio'] != null || _errors['cover'] != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(_errors['audio'] ?? _errors['cover']!, style: Tx.body(13, color: Tx.danger)),
          ),
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text('Duración entre ${clock(minSec)} y ${clock(maxSec)} minutos.', style: Tx.body(12, color: Tx.subtle)),
        ),
        const SizedBox(height: 18),
        TextField(
          controller: _title,
          maxLength: state.limit('song_title', 100),
          style: Tx.body(16),
          decoration: fieldDecoration('Nombre de la canción', label: 'Título', error: _errors['title']),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _featuring,
          maxLength: state.limit('song_featuring', 120),
          style: Tx.body(16),
          decoration: fieldDecoration('Artistas invitados (opcional)', label: 'Con la participación de', error: _errors['featuring']),
        ),
        const SizedBox(height: 10),
        Text('Género', style: Tx.body(13.5, weight: FontWeight.w600, color: Tx.muted)),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final g in songGenres.entries)
            PillChip(label: g.value, selected: _genre == g.key, onTap: () => setState(() {
                  _genre = g.key;
                  _errors.remove('genre');
                })),
        ]),
        if (_errors['genre'] != null)
          Padding(padding: const EdgeInsets.only(top: 6), child: Text(_errors['genre']!, style: Tx.body(13, color: Tx.danger))),
        const SizedBox(height: 18),
        Panel(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          child: Column(children: [
            Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Contenido explícito', style: Tx.body(15, weight: FontWeight.w600)),
                  Text('Letras con lenguaje fuerte o para adultos.', style: Tx.body(12.5, color: Tx.muted)),
                ]),
              ),
              TxSwitch(value: _explicit, onChanged: (v) => setState(() => _explicit = v)),
            ]),
            const Divider(color: Tx.border, height: 18),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() {
                _rights = !_rights;
                _errors.remove('rights');
              }),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(_rights ? CupertinoIcons.checkmark_square_fill : CupertinoIcons.square,
                      color: _errors['rights'] != null ? Tx.danger : (_rights ? Tx.purple400 : Tx.muted)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Confirmo que soy el autor o tengo los derechos para publicar esta canción y permitir que se use en TREVIX.',
                      style: Tx.body(13.5, color: Tx.text, height: 1.4),
                    ),
                  ),
                ]),
              ),
            ),
          ]),
        ),
        if (_errors['rights'] != null)
          Padding(padding: const EdgeInsets.only(top: 6), child: Text(_errors['rights']!, style: Tx.body(13, color: Tx.danger))),
        const SizedBox(height: 22),
        GradientButton(label: _busy ? 'Subiendo…' : 'Enviar a revisión', icon: CupertinoIcons.paperplane_fill, loading: _busy, onPressed: _submit),
        const SizedBox(height: 12),
        Text(
          'El equipo de TREVIX revisa cada canción antes de publicarla. Te avisaremos cuando esté lista.',
          textAlign: TextAlign.center,
          style: Tx.body(12.5, color: Tx.subtle, height: 1.4),
        ),
      ]),
    );
  }

  File get _coverFile => File(_cover!.path);
}
