import 'dart:ui' show ImageFilter;

import 'package:camera/camera.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
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

  Future<void> _syncCamera() async {
    if (_liveMode != 'camera') {
      await _camera?.dispose();
      _camera = null;
      if (mounted) setState(() => _cameraReady = false);
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
      final file = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 88, maxWidth: 2400);
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
      final join = await liveKitStartLiveJoin(
        title: _title.text,
        description: _description.text,
        hashtags: _hashtags.text.replaceAll('#', '').trim(),
        category: _category,
        coverUrl: _coverUrl,
        liveMode: _liveMode,
      );
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

  Widget _voiceChatPreview(User? user) {
    return ColoredBox(
      color: const Color(0xFF0A0A0F),
      child: GridView.builder(
        padding: const EdgeInsets.fromLTRB(28, 80, 28, 220),
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, mainAxisSpacing: 14, crossAxisSpacing: 14),
        itemCount: 9,
        itemBuilder: (_, i) {
          if (i == 0 && user != null) {
            return Container(
              decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Tx.accent, width: 2)),
              child: ClipOval(child: NetImage(user.avatarUrl, fit: BoxFit.cover)),
            );
          }
          return Container(
            decoration: BoxDecoration(color: Colors.white.withAlpha(18), shape: BoxShape.circle),
            child: Icon(CupertinoIcons.person_fill, color: Colors.white.withAlpha(50)),
          );
        },
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