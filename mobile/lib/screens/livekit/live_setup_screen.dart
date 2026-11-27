import 'dart:ui' show ImageFilter;

import 'package:camera/camera.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart' show ImageSource;

import '../../core/profile_image_picker.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/i18n.dart';
import '../../core/livekit_api.dart';
import '../../core/nav.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';
import '../profile/edit_profile_screen.dart';
import 'live_obs_sheet.dart';
import 'obs_copy_field.dart';
import 'livekit_room_screen.dart';

const _liveCategories = ['Gaming', 'Música', 'Charla', 'Belleza', 'Deportes', 'Otro'];

/// Pantalla previa al live (estilo TikTok: vista cámara/voz + panel inferior).
class LiveSetupScreen extends StatefulWidget {
  const LiveSetupScreen({super.key});

  @override
  State<LiveSetupScreen> createState() => _LiveSetupScreenState();
}

class _LiveSetupScreenState extends State<LiveSetupScreen> {
  final _title = TextEditingController();
  final _description = TextEditingController();
  final _hashtags = TextEditingController();
  String _category = _liveCategories.first;
  String _liveMode = 'camera';
  String? _coverUrl;
  bool _starting = false;
  CameraController? _camera;
  bool _cameraReady = false;
  bool _backCamera = false;
  bool _isAdultLive = false;
  LiveObsCredentials? _obsCreds;
  bool _obsLoading = false;
  String? _obsLoadError;

  @override
  void initState() {
    super.initState();
    final me = context.read<AppState>().me?.user;
    _coverUrl = me?.coverUrl ?? me?.avatarUrl;
    if (_title.text.isEmpty && me != null) {
      _title.text = me.displayName;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncCamera());
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _hashtags.dispose();
    _camera?.dispose();
    super.dispose();
  }

  /// Libera la cámara del plugin `camera` antes de que LiveKit use WebRTC.
  Future<void> _releaseCamera() async {
    final prev = _camera;
    _camera = null;
    if (mounted) setState(() => _cameraReady = false);
    if (prev != null) {
      try {
        await prev.dispose();
      } catch (_) {}
    }
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }

  Future<void> _ensureObsCredentials() async {
    if (_obsLoading || (_obsCreds?.valid ?? false)) return;
    setState(() {
      _obsLoading = true;
      _obsLoadError = null;
    });
    try {
      final creds = await liveKitPrepareObs();
      if (!mounted) return;
      setState(() {
        _obsCreds = creds;
        _obsLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _obsLoading = false;
        _obsLoadError = errorText(e);
      });
    }
  }

  Future<void> _syncCamera() async {
    if (_liveMode == 'obs') {
      await _releaseCamera();
      await _ensureObsCredentials();
      return;
    }
    if (_liveMode != 'camera') {
      await _releaseCamera();
      return;
    }
    try {
      final cams = await availableCameras();
      if (cams.isEmpty || !mounted) return;
      final pick = _backCamera
          ? cams.firstWhere((c) => c.lensDirection == CameraLensDirection.back, orElse: () => cams.first)
          : cams.firstWhere((c) => c.lensDirection == CameraLensDirection.front, orElse: () => cams.first);
      final ctrl = CameraController(pick, ResolutionPreset.high, enableAudio: false);
      await ctrl.initialize();
      await _camera?.dispose();
      _camera = ctrl;
      if (mounted) setState(() => _cameraReady = true);
    } catch (_) {
      if (mounted) setState(() => _cameraReady = false);
    }
  }

  void _flipCamera() {
    setState(() => _backCamera = !_backCamera);
    _syncCamera();
  }

  Future<void> _pickCover() async {
    try {
      final file = await pickProfileImage(ImageSource.gallery, maxWidthCamera: 2400.0);
      if (file == null) return;
      final res = await api.upload('me/cover', files: [Upload('cover', file.path, filename: file.name)]);
      if (!mounted) return;
      final user = asMap(res.map['user']);
      final url = asStrOrNull(user['cover_url']) ?? asStrOrNull(user['avatar_url']);
      context.read<AppState>().setMe(user);
      setState(() => _coverUrl = url);
    } catch (e) {
      if (mounted) toastError(context, e);
    }
  }

  Future<void> _openDetails() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF14141C),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(20, 12, 20, MediaQuery.paddingOf(ctx).bottom + 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(4)),
              ),
            ),
            const SizedBox(height: 16),
            Text(tr('Ajustes del LIVE'), style: Tx.display(18, color: Colors.white)),
            const SizedBox(height: 16),
            _sheetField(_description, tr('Descripción'), hint: tr('Cuénta a tu audiencia de qué va'), maxLines: 3),
            const SizedBox(height: 12),
            _sheetField(_hashtags, tr('Hashtags'), hint: tr('gaming charla música'), prefix: '#'),
            const SizedBox(height: 14),
            Text(tr('Categoría'), style: Tx.body(13, color: Colors.white60)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final c in _liveCategories)
                  PillChip(label: tr(c), selected: _category == c, onTap: () => setState(() => _category = c)),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(tr('Este live muestra contenido para adultos?'), style: Tx.body(14.5, weight: FontWeight.w600, color: Colors.white)),
                      const SizedBox(height: 4),
                      Text(
                        tr('Antes de entrar se mostrará una advertencia +18. No se muestra a menores.'),
                        style: Tx.body(12, color: Colors.white54, height: 1.3),
                      ),
                    ],
                  ),
                ),
                CupertinoSwitch(
                  value: _isAdultLive,
                  activeTrackColor: Tx.purple500,
                  onChanged: (v) => setState(() => _isAdultLive = v),
                ),
              ],
            ),
            const SizedBox(height: 18),
            SoftButton(label: tr('Listo'), onPressed: () => Navigator.pop(ctx)),
          ],
        ),
      ),
    );
  }

  Future<void> _start() async {
    final me = context.read<AppState>().me;
    if (me == null || !me.user.isStreamer) return;
    setState(() => _starting = true);
    try {
      if (_liveMode == 'camera') {
        await _releaseCamera();
      }
      final join = await liveKitStartLiveJoin(
        title: _title.text,
        description: _description.text,
        hashtags: _hashtags.text.replaceAll('#', '').trim(),
        category: _category,
        coverUrl: _coverUrl,
        liveMode: _liveMode,
        isAdult: _isAdultLive,
      );
      if (!mounted) return;
      if (_liveMode == 'obs' && join.hasObs) {
        await showLiveObsSheet(
          context,
          LiveObsCredentials(
            rtmpUrl: join.obsRtmpUrl!,
            streamKey: join.obsStreamKey!,
            overlayCommentsUrl: join.obsOverlayCommentsUrl,
            overlayGiftsUrl: join.obsOverlayGiftsUrl,
          ),
        );
      }
      if (!mounted) return;
      await push(
        context,
        LiveKitRoomScreen(
          join: join,
          title: join.session.title ?? (_title.text.trim().isNotEmpty ? _title.text.trim() : tr('En vivo')),
          video: _liveMode == 'camera',
          mode: LiveKitRoomMode.live,
        ),
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) toastError(context, e);
    }
    if (mounted) setState(() => _starting = false);
  }

  Widget _streamerGate() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(CupertinoIcons.dot_radiowaves_left_right, size: 48, color: Tx.muted),
          const SizedBox(height: 16),
          Text(tr('Transmisión en vivo'), style: Tx.display(20), textAlign: TextAlign.center),
          const SizedBox(height: 10),
          Text(
            tr('Para iniciar un LIVE, activa la categoría de creador «Stream» en tu perfil.'),
            style: Tx.body(14.5, color: Tx.muted),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 22),
          SoftButton(label: tr('Editar perfil'), onPressed: () => push(context, const EditProfileScreen())),
        ]),
      ),
    );
  }

  Widget _previewBackground(User? user) {
    if (_liveMode == 'camera' && _cameraReady && _camera != null) {
      return FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(width: _camera!.value.previewSize?.height ?? 1, height: _camera!.value.previewSize?.width ?? 1, child: CameraPreview(_camera!)),
      );
    }
    if (_coverUrl != null) {
      return NetImage(_coverUrl, fit: BoxFit.cover);
    }
    return const ColoredBox(color: Color(0xFF0A0A0F));
  }

  Widget _obsPreview(User? user) {
    return ColoredBox(
      color: const Color(0xFF0B0B10),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 48, 20, 180),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(tr('Transmite desde OBS Studio'), textAlign: TextAlign.center, style: Tx.display(18, color: Colors.white)),
            const SizedBox(height: 8),
            Text(
              tr('Copia el servidor y la clave en OBS. Usa «Mostrar» y el icono de copiar en la clave. Las URLs de overlay salen al iniciar el LIVE.'),
              textAlign: TextAlign.center,
              style: Tx.body(13, color: Colors.white54, height: 1.35),
            ),
            const SizedBox(height: 18),
            if (_obsLoading)
              const Center(child: Padding(padding: EdgeInsets.all(12), child: CupertinoActivityIndicator(color: Colors.white)))
            else if (_obsLoadError != null)
              Text(_obsLoadError!, textAlign: TextAlign.center, style: Tx.body(13, color: Tx.accent))
            else if (_obsCreds?.valid ?? false) ...[
              ObsCopyField(label: tr('Servidor'), value: _obsCreds!.rtmpUrl),
              const SizedBox(height: 10),
              ObsCopyField(label: tr('Clave de retransmisión'), value: _obsCreds!.streamKey, secret: true),
              const SizedBox(height: 10),
              Text(
                tr('Las URLs para OBS (comentarios y regalos por separado) aparecen al pulsar «Iniciar LIVE».'),
                style: Tx.body(12, color: Colors.white38, height: 1.3),
              ),
            ] else
              SoftButton(label: tr('Obtener servidor RTMP'), onPressed: _ensureObsCredentials),
          ],
        ),
      ),
    );
  }

  Widget _voiceChatPreview(User? user) {
    return ColoredBox(
      color: const Color(0xFF0B0B10),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 160),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (user != null)
                DecoratedBox(
                  decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Tx.accent, width: 2)),
                  child: Padding(
                    padding: const EdgeInsets.all(3),
                    child: Avatar(user: user, size: 52),
                  ),
                )
              else
                Icon(CupertinoIcons.mic_fill, size: 48, color: Colors.white.withAlpha(40)),
              const SizedBox(height: 12),
              Text(
                tr('Los participantes aparecerán aquí, centrados.'),
                textAlign: TextAlign.center,
                style: Tx.body(12.5, color: Colors.white54),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final me = context.read<AppState>().me;
    final user = me?.user;
    final isStreamer = user?.isStreamer ?? false;

    return Scaffold(
      backgroundColor: Colors.black,
      body: isStreamer
          ? Stack(
              fit: StackFit.expand,
              children: [
                if (_liveMode == 'voice_chat')
                  _voiceChatPreview(user)
                else if (_liveMode == 'obs')
                  _obsPreview(user)
                else
                  _previewBackground(user),
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.black.withAlpha(120), Colors.transparent, Colors.black.withAlpha(200)],
                      stops: const [0, 0.35, 1],
                    ),
                  ),
                ),
                SafeArea(
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Row(
                          children: [
                            IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(CupertinoIcons.xmark, color: Colors.white)),
                            const Spacer(),
                            if (_liveMode == 'camera')
                              IconButton(
                                onPressed: _flipCamera,
                                icon: const Icon(CupertinoIcons.camera_rotate, color: Colors.white, size: 26),
                              ),
                          ],
                        ),
                      ),
                      const Spacer(),
                      _bottomPanel(user),
                    ],
                  ),
                ),
              ],
            )
          : SafeArea(child: _streamerGate()),
    );
  }

  Widget _bottomPanel(User? user) {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A22).withAlpha(220),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            border: Border(top: BorderSide(color: Colors.white.withAlpha(30))),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(CupertinoIcons.chevron_compact_down, color: Colors.white.withAlpha(80), size: 22),
              const SizedBox(height: 10),
              _toolRow(),
              const SizedBox(height: 14),
              _titleRow(user),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton(
                  onPressed: _starting ? null : _start,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFFF2D55),
                    disabledBackgroundColor: const Color(0xFFFF2D55).withAlpha(120),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: _starting
                      ? const CupertinoActivityIndicator(color: Colors.white)
                      : Text(tr('Iniciar LIVE'), style: Tx.body(17, weight: FontWeight.w800, color: Colors.white)),
                ),
              ),
              const SizedBox(height: 12),
              _modeSelector(),
              SizedBox(height: MediaQuery.paddingOf(context).bottom),
            ],
          ),
        ),
      ),
    );
  }

  Widget _toolRow() {
    final tools = [
      (CupertinoIcons.settings, tr('Ajustes'), _openDetails),
      (CupertinoIcons.photo, tr('Portada'), _pickCover),
      (CupertinoIcons.square_arrow_up, tr('Compartir'), () => toast(context, tr('Activa el LIVE para compartir.'))),
    ];
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        for (final t in tools)
          _ToolIcon(icon: t.$1, label: t.$2, onTap: t.$3),
      ],
    );
  }

  Widget _titleRow(User? user) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: Colors.black.withAlpha(80), borderRadius: BorderRadius.circular(14)),
      child: Row(
        children: [
          if (user != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: NetImage(user.avatarUrl, width: 40, height: 40, fit: BoxFit.cover),
            )
          else
            const SizedBox(width: 40, height: 40),
          const SizedBox(width: 10),
          Container(width: 1, height: 28, color: Colors.white24),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: _title,
              style: Tx.body(15, weight: FontWeight.w700, color: Colors.white),
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                hintText: tr('Título del LIVE'),
                hintStyle: Tx.body(14, color: Colors.white38),
              ),
              maxLines: 1,
            ),
          ),
        ],
      ),
    );
  }

  Widget _modeSelector() {
    final modes = [
      ('voice_chat', CupertinoIcons.mic_fill, tr('Chat de voz')),
      ('camera', CupertinoIcons.videocam_fill, tr('Cámara del dispositivo')),
      ('obs', CupertinoIcons.tv, tr('OBS Studio')),
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (final m in modes) ...[
            GestureDetector(
              onTap: () {
                if (_liveMode == m.$1) return;
                setState(() => _liveMode = m.$1);
                _syncCamera();
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(m.$2, size: 16, color: _liveMode == m.$1 ? Colors.white : Colors.white54),
                    const SizedBox(width: 6),
                    Text(
                      m.$3,
                      style: Tx.body(13, weight: _liveMode == m.$1 ? FontWeight.w800 : FontWeight.w500, color: _liveMode == m.$1 ? Colors.white : Colors.white54),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _sheetField(TextEditingController ctrl, String label, {String? hint, int maxLines = 1, String? prefix}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Tx.body(13, color: Colors.white60)),
        const SizedBox(height: 6),
        TextField(
          controller: ctrl,
          maxLines: maxLines,
          style: Tx.body(15, color: Colors.white),
          decoration: InputDecoration(
            filled: true,
            fillColor: Colors.white.withAlpha(14),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            hintText: hint,
            hintStyle: Tx.body(14, color: Colors.white38),
            prefixText: prefix,
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          ),
        ),
      ],
    );
  }
}

class _ToolIcon extends StatelessWidget {
  const _ToolIcon({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 72,
        child: Column(
          children: [
            Icon(icon, color: Colors.white, size: 26),
            const SizedBox(height: 6),
            Text(label, textAlign: TextAlign.center, maxLines: 2, style: Tx.body(11, color: Colors.white70)),
          ],
        ),
      ),
    );
  }
}