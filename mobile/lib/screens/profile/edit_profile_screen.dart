import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/catalog.dart';
import '../../core/device.dart';
import '../../core/i18n.dart';
import '../../core/nav.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';
import '../../widgets/settings_tiles.dart';
import '../music/music_picker.dart';
import 'personal_data_screen.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  late final Me _me = context.read<AppState>().me!;
  late final _name = TextEditingController(text: _me.user.displayName);
  late final _username = TextEditingController(text: _me.user.username);
  late final _bio = TextEditingController(text: _me.user.bio);
  late final _website = TextEditingController(text: _me.user.website ?? '');
  late String? _country = _me.user.country;
  late String _accountType = _me.user.accountType;
  late String? _category = _me.user.creatorCategory;
  bool _saving = false;
  bool _locating = false;
  String? _imageBusy;
  Map<String, String> _errors = {};
  ProfileDetails? _details;
  bool _songBusy = false;

  @override
  void initState() {
    super.initState();
    _loadDetails();
  }

  Future<void> _loadDetails() async {
    try {
      final res = await api.get('me/details');
      if (mounted) setState(() => _details = ProfileDetails.fromJson(asMap(res.map['details'])));
    } catch (_) {
      // Sin los datos personales la pantalla sigue sirviendo; la fila muestra «Añadir».
    }
  }

  Future<void> _pickProfileSong() async {
    final current = _details?.song;
    final picked = await pickSong(
      context,
      current: current != null && current.available ? PickedSong(current, current.clipStart ?? 0) : null,
    );
    if (picked == null || !mounted) return;
    setState(() => _songBusy = true);
    try {
      final res = await api.put('me/profile-song', {'song_id': picked.song.id, 'song_start': picked.start});
      if (!mounted) return;
      final song = res.map['song'] is Map ? Song.fromJson(asMap(res.map['song'])) : null;
      setState(() => _details?.song = song);
      toast(context, '${res.map['message'] ?? tr('Listo.')}');
    } catch (e) {
      if (mounted) toastError(context, e);
    }
    if (mounted) setState(() => _songBusy = false);
  }

  Future<void> _removeProfileSong() async {
    setState(() => _songBusy = true);
    try {
      final res = await api.delete('me/profile-song');
      if (!mounted) return;
      setState(() => _details?.song = null);
      toast(context, '${res.map['message'] ?? tr('Listo.')}');
    } catch (e) {
      if (mounted) toastError(context, e);
    }
    if (mounted) setState(() => _songBusy = false);
  }

  void _profileSongMenu() {
    final song = _details?.song;
    if (song == null) {
      _pickProfileSong();
      return;
    }
    actionSheet(context, [
      SheetAction(tr('Cambiar canción'), CupertinoIcons.music_note_2, _pickProfileSong),
      SheetAction(tr('Quitar del perfil'), CupertinoIcons.trash, _removeProfileSong, destructive: true),
    ], title: tr('Música del perfil'));
  }

  Future<void> _detectCountry() async {
    setState(() => _locating = true);
    try {
      final code = await DeviceAccess.detectCountry();
      if (!mounted) return;
      final state = context.read<AppState>();
      if (!state.countries.containsKey(code)) {
        toast(context, tr('Tu país ({code}) no está en la lista. Elígelo a mano.', {'code': code}), error: true);
      } else {
        setState(() => _country = code);
        toast(context, tr('País: {country}. Guarda para aplicarlo.', {'country': state.countryName(code)}));
      }
    } on DeviceException catch (e) {
      if (mounted) toast(context, e.message, error: true);
    }
    if (mounted) setState(() => _locating = false);
  }

  @override
  void dispose() {
    _name.dispose();
    _username.dispose();
    _bio.dispose();
    _website.dispose();
    super.dispose();
  }

  Future<void> _image(String kind) async {
    final user = context.read<AppState>().me!.user;
    final has = kind == 'avatar' ? user.avatarUrl != null : user.coverUrl != null;
    actionSheet(context, [
      SheetAction(tr('Elegir de la galería'), CupertinoIcons.photo, () => _upload(kind, ImageSource.gallery)),
      SheetAction(tr('Tomar foto'), CupertinoIcons.camera, () => _upload(kind, ImageSource.camera)),
      if (has) SheetAction(kind == 'avatar' ? tr('Quitar foto') : tr('Quitar portada'), CupertinoIcons.trash, () => _removeImage(kind), destructive: true),
    ], title: kind == 'avatar' ? tr('Foto de perfil') : tr('Portada'));
  }

  Future<void> _upload(String kind, ImageSource source) async {
    try {
      final file = await ImagePicker().pickImage(source: source, imageQuality: 92, maxWidth: kind == 'avatar' ? 1200 : 2400);
      if (file == null) return;
      setState(() => _imageBusy = kind);
      final res = await api.upload('me/$kind', files: [Upload(kind, file.path, filename: file.name)]);
      if (!mounted) return;
      context.read<AppState>().setMe(asMap(res.map['user']));
      toast(context, '${res.map['message'] ?? tr('Imagen actualizada.')}');
    } catch (e) {
      if (mounted) toastError(context, e);
    }
    if (mounted) setState(() => _imageBusy = null);
  }

  Future<void> _removeImage(String kind) async {
    setState(() => _imageBusy = kind);
    try {
      final res = await api.delete('me/$kind');
      if (mounted) {
        context.read<AppState>().setMe(asMap(res.map['user']));
        toast(context, '${res.map['message'] ?? tr('Imagen quitada.')}');
      }
    } catch (e) {
      if (mounted) toastError(context, e);
    }
    if (mounted) setState(() => _imageBusy = null);
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    if (_accountType == 'creator' && _category == null) {
      setState(() => _errors = {'creator_category': tr('Elige el tipo de creador.')});
      return;
    }
    setState(() {
      _saving = true;
      _errors = {};
    });
    try {
      final res = await api.patch('me', {
        'display_name': _name.text.trim(),
        'username': _username.text.trim().toLowerCase(),
        'bio': _bio.text.trim(),
        'website': _website.text.trim(),
        'country': _country ?? '',
        'account_type': _accountType,
        if (_accountType == 'creator') 'creator_category': _category,
      });
      if (!mounted) return;
      context.read<AppState>().setMe(asMap(res.map['user']));
      toast(context, '${res.map['message'] ?? tr('Perfil actualizado.')}');
      Navigator.pop(context);
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
    final me = context.watch<AppState>().me!;
    final countries = context.read<AppState>().countries.entries.toList()..sort((a, b) => a.value.compareTo(b.value));
    return Scaffold(
      appBar: GlassBar(
        title: tr('Editar perfil'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: GradientButton(label: tr('Guardar'), expand: false, height: 38, loading: _saving, onPressed: _save),
          ),
        ],
      ),
      body: ListView(padding: const EdgeInsets.only(bottom: 60), children: [
        SizedBox(
          height: 230,
          child: Stack(clipBehavior: Clip.none, children: [
            GestureDetector(
              onTap: () => _image('cover'),
              child: SizedBox(
                height: 170,
                width: double.infinity,
                child: Stack(fit: StackFit.expand, children: [
                  me.user.coverUrl != null
                      ? NetImage(me.user.coverUrl)
                      : Container(decoration: const BoxDecoration(gradient: LinearGradient(colors: [Tx.purple700, Tx.blue, Color(0xFF0E7490)]))),
                  Container(color: Colors.black.withAlpha(80)),
                  Center(
                    child: _imageBusy == 'cover'
                        ? const CupertinoActivityIndicator(color: Colors.white)
                        : Column(mainAxisSize: MainAxisSize.min, children: [
                            const Icon(CupertinoIcons.camera_fill, color: Colors.white),
                            const SizedBox(height: 4),
                            Text(tr('Cambiar portada'), style: Tx.body(13, weight: FontWeight.w600, color: Colors.white)),
                          ]),
                  ),
                ]),
              ),
            ),
            Positioned(
              left: 20,
              top: 120,
              child: GestureDetector(
                onTap: () => _image('avatar'),
                child: Stack(children: [
                  Container(
                    decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Tx.bg, width: 4)),
                    child: Avatar(user: me.user, size: 96),
                  ),
                  Positioned(
                    right: 2,
                    bottom: 2,
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(gradient: Tx.brand, shape: BoxShape.circle, border: Border.all(color: Tx.bg, width: 3)),
                      child: _imageBusy == 'avatar'
                          ? const Padding(padding: EdgeInsets.all(7), child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(CupertinoIcons.camera_fill, color: Colors.white, size: 14),
                    ),
                  ),
                ]),
              ),
            ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 0),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (_errors['form'] != null)
              Padding(padding: const EdgeInsets.only(bottom: 12), child: Text(_errors['form']!, style: Tx.body(14, color: Tx.danger))),
            _label(tr('Nombre')),
            TextField(controller: _name, maxLength: 60, style: Tx.body(16), decoration: fieldDecoration(tr('Tu nombre'), error: _errors['display_name'])),
            _label(tr('Nombre de usuario')),
            TextField(
              controller: _username,
              maxLength: 30,
              autocorrect: false,
              style: Tx.body(16),
              decoration: fieldDecoration(tr('usuario'), error: _errors['username'], prefix: Icon(CupertinoIcons.at, size: 18, color: Tx.subtle)),
            ),
            _label(tr('Biografía')),
            TextField(
              controller: _bio,
              maxLength: context.read<AppState>().limit('bio', 300),
              minLines: 3,
              maxLines: 6,
              style: Tx.body(16),
              decoration: fieldDecoration(tr('Cuéntale al mundo quién eres'), error: _errors['bio']),
            ),
            _label(tr('Sitio web')),
            TextField(
              controller: _website,
              keyboardType: TextInputType.url,
              autocorrect: false,
              style: Tx.body(16),
              decoration: fieldDecoration('https://…', error: _errors['website'], prefix: Icon(CupertinoIcons.link, size: 18, color: Tx.subtle)),
            ),
            SettingsGroup(title: tr('Más sobre ti'), children: [
              SettingsRow(
                icon: CupertinoIcons.music_note_2,
                color: Tx.purple400,
                label: tr('Música del perfil'),
                subtitle: tr('Suena cuando alguien la toca en tu perfil'),
                value: _details?.song?.available == true ? _details!.song!.title : tr('Añadir'),
                trailing: _songBusy ? const CupertinoActivityIndicator(radius: 9) : null,
                onTap: _songBusy ? null : _profileSongMenu,
              ),
              SettingsRow(
                icon: CupertinoIcons.person_crop_rectangle,
                color: const Color(0xFF0EA5E9),
                label: tr('Datos personales'),
                subtitle: tr('Ciudades, cumpleaños, situación sentimental, género, intereses, enlaces y contacto'),
                onTap: () async {
                  final saved = await push<bool>(context, const PersonalDataScreen());
                  if (saved == true) _loadDetails();
                },
              ),
            ]),
            const SizedBox(height: 16),
            _label(tr('País')),
            _SelectField(
              value: _country == null ? tr('Sin especificar') : context.read<AppState>().countryName(_country!),
              error: _errors['country'],
              onTap: () => actionSheet(context, [
                SheetAction(tr('Sin especificar'), CupertinoIcons.minus_circle, () => setState(() => _country = null)),
                for (final c in countries) SheetAction(c.value, CupertinoIcons.location, () => setState(() => _country = c.key)),
              ], title: tr('País')),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: CupertinoButton(
                padding: const EdgeInsets.only(top: 6, left: 4),
                onPressed: _locating ? null : _detectCountry,
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  _locating
                      ? const CupertinoActivityIndicator(radius: 8)
                      : Icon(CupertinoIcons.location_fill, size: 15, color: Tx.accent),
                  const SizedBox(width: 6),
                  Text(tr('Detectar mi país con la ubicación'), style: Tx.body(13.5, weight: FontWeight.w600, color: Tx.accent)),
                ]),
              ),
            ),
            const SizedBox(height: 22),
            _label(tr('Tipo de cuenta')),
            Row(children: [
              for (final e in accountTypes.entries)
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(right: e.key == 'personal' ? 8 : 0),
                    child: _ChoiceCard(
                      icon: e.key == 'personal' ? CupertinoIcons.person : CupertinoIcons.star,
                      label: tr(e.value),
                      selected: _accountType == e.key,
                      onTap: () => setState(() => _accountType = e.key),
                    ),
                  ),
                ),
            ]),
            if (_accountType == 'creator') ...[
              const SizedBox(height: 14),
              _label(tr('¿Qué tipo de creador eres?')),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final e in creatorCategories.entries)
                  PillChip(label: tr(e.value), selected: _category == e.key, onTap: () => setState(() => _category = e.key)),
              ]),
              if (_errors['creator_category'] != null)
                Padding(padding: const EdgeInsets.only(top: 8), child: Text(_errors['creator_category']!, style: Tx.body(13, color: Tx.danger))),
              if (_category == 'music_artist')
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Panel(
                    gradient: true,
                    padding: const EdgeInsets.all(14),
                    child: Row(children: [
                      Icon(CupertinoIcons.music_mic, color: Tx.accent),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(tr('Como artista musical podrás subir tus canciones al panel de artista. El equipo las revisa antes de publicarlas.'),
                            style: Tx.body(13.5, height: 1.4)),
                      ),
                    ]),
                  ),
                ),
            ],
          ]),
        ),
      ]),
    );
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8, top: 4),
        child: Text(text, style: Tx.body(13.5, weight: FontWeight.w600, color: Tx.muted)),
      );
}

class _SelectField extends StatelessWidget {
  const _SelectField({required this.value, required this.onTap, this.error});

  final String value;
  final VoidCallback onTap;
  final String? error;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: InputDecorator(
        decoration: fieldDecoration('', error: error, suffix: Icon(CupertinoIcons.chevron_down, size: 16, color: Tx.subtle)),
        child: Text(value, style: Tx.body(16)),
      ),
    );
  }
}

class _ChoiceCard extends StatelessWidget {
  const _ChoiceCard({required this.icon, required this.label, required this.selected, required this.onTap});

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: selected ? Tx.brandSoft : null,
          color: selected ? null : Tx.surface2,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: selected ? Tx.purple500 : Tx.border, width: selected ? 1.5 : 1),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, color: selected ? Tx.accent : Tx.muted),
          const SizedBox(height: 8),
          Text(label, style: Tx.body(14, weight: FontWeight.w600, color: selected ? Tx.text : Tx.muted)),
        ]),
      ),
    );
  }
}
