import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/appearance.dart';
import '../../core/i18n.dart';
import '../../core/nav.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../core/vincode/vincode_codec.dart';
import '../../core/vincode/vincode_decoder.dart';
import '../../core/vincode/vincode_painter.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';
import 'auth_widgets.dart';

/// Cuenta autenticada: VINCRIPTAR (escanea / introduce código y autoriza).
class LinkHostScreen extends StatefulWidget {
  const LinkHostScreen({super.key});

  @override
  State<LinkHostScreen> createState() => _LinkHostScreenState();
}

class _LinkHostScreenState extends State<LinkHostScreen> with SingleTickerProviderStateMixin {
  final _manual = TextEditingController();
  CameraController? _cam;
  bool _busy = false;
  bool _scanning = false;
  int? _id;
  String? _guestName;
  String? _guestType;
  String _phase = 'scan'; // scan | confirm
  Object? _error;
  String? _lastCode;
  late final AnimationController _ring = AnimationController(vsync: this, duration: const Duration(seconds: 4))..repeat();

  @override
  void initState() {
    super.initState();
    _openCamera();
  }

  @override
  void dispose() {
    _manual.dispose();
    _ring.dispose();
    _stopCamera();
    super.dispose();
  }

  Future<void> _openCamera() async {
    try {
      final cams = await availableCameras();
      if (cams.isEmpty) return;
      final cam = cams.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cams.first,
      );
      final ctrl = CameraController(
        cam,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: Platform.isAndroid ? ImageFormatGroup.nv21 : ImageFormatGroup.bgra8888,
      );
      await ctrl.initialize();
      if (!mounted) {
        await ctrl.dispose();
        return;
      }
      setState(() => _cam = ctrl);
      _scanning = true;
      await ctrl.startImageStream(_onFrame);
    } catch (_) {
      /* sin cámara: solo manual */
    }
  }

  Future<void> _stopCamera() async {
    _scanning = false;
    final c = _cam;
    _cam = null;
    if (c == null) return;
    try {
      if (c.value.isStreamingImages) await c.stopImageStream();
    } catch (_) {}
    await c.dispose();
  }

  var _frameBusy = false;
  Future<void> _onFrame(CameraImage image) async {
    if (!_scanning || _busy || _frameBusy || _phase != 'scan') return;
    _frameBusy = true;
    try {
      final code = await decodeVincodeFromCameraImage(image);
      if (code != null && code != _lastCode && mounted) {
        _lastCode = code;
        await _scan(code);
      }
    } finally {
      _frameBusy = false;
    }
  }

  Future<void> _scan(String raw) async {
    final code = normalizeVincode(raw);
    if (code.length < 6 || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _stopCamera();
      final res = await api.post('auth/vincriptar/scan', {'code': code});
      if (!mounted) return;
      setState(() {
        _id = asInt(res.map['id']);
        _guestName = asStr(res.map['guest_device_name'], tr('Dispositivo'));
        _guestType = asStr(res.map['guest_device_type'], 'other');
        _phase = 'confirm';
        _busy = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e;
          _phase = 'scan';
        });
        toastError(context, e);
        await _openCamera();
      }
    }
  }

  Future<void> _approve() async {
    final id = _id;
    if (id == null || _busy) return;
    setState(() => _busy = true);
    try {
      await api.post('auth/vincriptar/approve', {'id': id});
      if (!mounted) return;
      toast(context, tr('Dispositivo vinculado.'));
      Navigator.maybePop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        toastError(context, e);
      }
    }
  }

  Future<void> _reject() async {
    final id = _id;
    if (id == null || _busy) return;
    setState(() => _busy = true);
    try {
      await api.post('auth/vincriptar/reject', {'id': id});
      if (!mounted) return;
      toast(context, tr('Rechazaste la vinculación.'));
      Navigator.maybePop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        toastError(context, e);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cam = _cam;
    final reduce = Appearance.motionReduced(context);
    return Scaffold(
      backgroundColor: Tx.bg,
      body: AuthBackground(
        child: SafeArea(
          child: Column(children: [
            _VinTopBar(onClose: () => Navigator.maybePop(context)),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(22, 4, 22, 36),
                children: [
                  _VinHero(
                    title: tr('VINCRIPTAR'),
                    subtitle: _phase == 'confirm'
                        ? tr('Confirma la vinculación')
                        : tr('Escanea el VINCODE del otro dispositivo o introduce el código.'),
                  ),
                  const SizedBox(height: 22),
                  if (_phase == 'scan') ...[
                    _ScanFrame(
                      ring: reduce ? null : _ring,
                      child: cam != null && cam.value.isInitialized
                          ? CameraPreview(cam)
                          : _CameraEmpty(),
                    ),
                    const SizedBox(height: 18),
                    TextField(
                      controller: _manual,
                      textCapitalization: TextCapitalization.characters,
                      textAlign: TextAlign.center,
                      style: Tx.display(22).copyWith(letterSpacing: 3),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9]')),
                        LengthLimitingTextInputFormatter(12),
                      ],
                      decoration: fieldDecoration(tr('Código')).copyWith(
                        filled: true,
                        fillColor: Tx.surface1,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                      ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 10),
                      Text(errorText(_error!), textAlign: TextAlign.center, style: Tx.body(13.5, color: Tx.danger)),
                    ],
                    const SizedBox(height: 16),
                    GradientButton(
                      label: tr('Continuar'),
                      loading: _busy,
                      onPressed: () => _scan(_manual.text),
                    ),
                  ] else ...[
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Tx.surface1,
                        borderRadius: BorderRadius.circular(Tx.radiusLg),
                        border: Border.all(color: Tx.border),
                        boxShadow: [
                          BoxShadow(color: Tx.alpha(Tx.cyan, .12), blurRadius: 28, offset: const Offset(0, 10)),
                        ],
                      ),
                      child: Column(children: [
                        Container(
                          width: 64,
                          height: 64,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(colors: [Tx.alpha(Tx.cyan, .35), Tx.alpha(const Color(0xFF8B5CF6), .35)]),
                          ),
                          child: Icon(CupertinoIcons.device_phone_portrait, size: 30, color: Tx.cyan),
                        ),
                        const SizedBox(height: 14),
                        Text(_guestName ?? tr('Dispositivo'), style: Tx.body(17, weight: FontWeight.w700)),
                        if (_guestType != null)
                          Text(tr(_deviceTypeLabel(_guestType!)), style: Tx.body(13, color: Tx.muted)),
                        const SizedBox(height: 10),
                        Text(
                          tr('«{device}» quiere entrar. ¿Lo apruebas?', {'device': _guestName ?? tr('Dispositivo')}),
                          textAlign: TextAlign.center,
                          style: Tx.body(14.5, color: Tx.muted, height: 1.35),
                        ),
                      ]),
                    ),
                    const SizedBox(height: 18),
                    GradientButton(label: tr('Autorizar'), loading: _busy, onPressed: _approve),
                    const SizedBox(height: 10),
                    SoftButton(label: tr('Rechazar'), expand: true, height: 46, onPressed: _busy ? null : _reject),
                  ],
                ],
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

String _deviceTypeLabel(String type) => switch (type) {
      'web' => 'Navegador web',
      'desktop' => 'Escritorio',
      'tablet' => 'Tableta',
      'phone' => 'Teléfono',
      _ => 'Dispositivo',
    };

/// Dispositivo nuevo: genera VINCODE y espera autorización.
class LinkGuestScreen extends StatefulWidget {
  const LinkGuestScreen({super.key});

  @override
  State<LinkGuestScreen> createState() => _LinkGuestScreenState();
}

class _LinkGuestScreenState extends State<LinkGuestScreen> {
  int? _id;
  String? _code;
  DateTime? _expiresAt;
  String _status = 'loading';
  Object? _error;
  Timer? _poll;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _poll?.cancel();
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _start() async {
    setState(() {
      _error = null;
      _status = 'loading';
    });
    try {
      final res = await api.post('auth/vincriptar/start', {
        'device_name': AppState.deviceName,
        'device_type': Platform.isIOS || Platform.isAndroid ? 'phone' : 'other',
      });
      if (!mounted) return;
      setState(() {
        _id = asInt(res.map['id']);
        _code = asStr(res.map['code']);
        _expiresAt = asDate(res.map['expires_at']);
        _status = asStr(res.map['status'], 'pending');
      });
      _poll?.cancel();
      _poll = Timer.periodic(const Duration(seconds: 2), (_) => _refresh());
      _tick?.cancel();
      _tick = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _refresh() async {
    final code = _code;
    if (code == null) return;
    try {
      final res = await api.get('auth/vincriptar/$code/status');
      final m = res.map;
      final status = asStr(m['status']);
      if (!mounted) return;
      setState(() {
        _status = status;
        _expiresAt = asDate(m['expires_at']) ?? _expiresAt;
      });
      if (status == 'approved' && m['token'] != null && m['user'] != null) {
        _poll?.cancel();
        final state = context.read<AppState>();
        await state.loginWithLink(m);
        return;
      }
      if (status == 'expired' || status == 'cancelled') {
        _poll?.cancel();
        if (!mounted) return;
        toast(context, tr('La vinculación se canceló o venció.'), error: true);
      }
    } catch (_) {}
  }

  Future<void> _cancel() async {
    final id = _id;
    final code = _code;
    if (id != null && code != null) {
      try {
        await api.post('auth/vincriptar/cancel', {'id': id, 'code': code});
      } catch (_) {}
    }
    if (mounted) Navigator.maybePop(context);
  }

  int get _left {
    final e = _expiresAt;
    if (e == null) return 0;
    return e.difference(DateTime.now()).inSeconds.clamp(0, 60);
  }

  @override
  Widget build(BuildContext context) {
    final code = _code;
    return Scaffold(
      backgroundColor: Tx.bg,
      body: AuthBackground(
        child: SafeArea(
          child: Column(children: [
            _VinTopBar(onClose: _cancel),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(22, 4, 22, 36),
                children: [
                  _VinHero(
                    title: tr('VINCRIPTAR'),
                    subtitle: tr('Muestra este VINCODE en el dispositivo donde ya iniciaste sesión (Ajustes → VINCRIPTAR).'),
                  ),
                  const SizedBox(height: 22),
                  if (_error != null)
                    ErrorState(error: _error!, onRetry: _start)
                  else if (code == null || _status == 'loading')
                    const Padding(padding: EdgeInsets.all(40), child: Loading())
                  else ...[
                    Center(
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Tx.alpha(Tx.surface1, .72),
                          border: Border.all(color: Tx.alpha(Tx.cyan, .22)),
                          boxShadow: [
                            BoxShadow(color: Tx.alpha(const Color(0xFF7C3AED), .18), blurRadius: 40),
                            BoxShadow(color: Tx.alpha(Tx.cyan, .12), blurRadius: 28, offset: const Offset(0, 12)),
                          ],
                        ),
                        child: VincodeView(code: code, size: MediaQuery.sizeOf(context).width * 0.72),
                      ),
                    ),
                    const SizedBox(height: 20),
                    GestureDetector(
                      onTap: () async {
                        await Clipboard.setData(ClipboardData(text: code));
                        if (!mounted) return;
                        toast(context, tr('Código copiado.'));
                      },
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                        decoration: BoxDecoration(
                          color: Tx.surface1,
                          borderRadius: BorderRadius.circular(Tx.radiusMd),
                          border: Border.all(color: Tx.border),
                        ),
                        child: Column(children: [
                          Text(code, textAlign: TextAlign.center, style: Tx.display(26).copyWith(letterSpacing: 6)),
                          const SizedBox(height: 6),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(CupertinoIcons.doc_on_doc, size: 14, color: Tx.subtle),
                              const SizedBox(width: 6),
                              Text(tr('Toca para copiar'), style: Tx.body(12.5, color: Tx.subtle)),
                            ],
                          ),
                        ]),
                      ),
                    ),
                    const SizedBox(height: 16),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(99),
                      child: LinearProgressIndicator(
                        value: _left / 60,
                        minHeight: 5,
                        backgroundColor: Tx.surface3,
                        color: _left <= 10 ? Tx.warning : Tx.cyan,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _left <= 0 ? tr('Caducado') : tr('Caduca en {n} s', {'n': _left}),
                      textAlign: TextAlign.center,
                      style: Tx.body(13, color: Tx.muted),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: Tx.alpha(Tx.cyan, .08),
                        borderRadius: BorderRadius.circular(Tx.radiusSm),
                        border: Border.all(color: Tx.alpha(Tx.cyan, .18)),
                      ),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 18,
                            height: 18,
                            child: _status == 'claimed'
                                ? CupertinoActivityIndicator(radius: 8, color: Tx.cyan)
                                : Icon(CupertinoIcons.link, size: 18, color: Tx.cyan),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _status == 'claimed'
                                  ? tr('Esperando confirmación…')
                                  : tr('Esperando a que escaneen tu VINCODE…'),
                              style: Tx.body(14, color: Tx.muted, height: 1.3),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_left <= 0 || _status == 'expired') ...[
                      const SizedBox(height: 18),
                      SoftButton(label: tr('Generar otro VINCODE'), expand: true, height: 46, onPressed: _start),
                    ],
                  ],
                ],
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

class _VinTopBar extends StatelessWidget {
  const _VinTopBar({required this.onClose});
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 2, 8, 0),
      child: Row(
        children: [
          CupertinoButton(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            onPressed: onClose,
            child: Text(tr('Cerrar'), style: Tx.body(16, weight: FontWeight.w600, color: Tx.accent)),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: Tx.alpha(Tx.cyan, .12),
              borderRadius: BorderRadius.circular(99),
              border: Border.all(color: Tx.alpha(Tx.cyan, .28)),
            ),
            child: Text('VINCODE', style: Tx.body(11.5, weight: FontWeight.w700, color: Tx.cyan)),
          ),
          const SizedBox(width: 10),
        ],
      ),
    );
  }
}

class _VinHero extends StatelessWidget {
  const _VinHero({required this.title, required this.subtitle});
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Text(title, textAlign: TextAlign.center, style: Tx.display(30)),
      const SizedBox(height: 10),
      Text(subtitle, textAlign: TextAlign.center, style: Tx.body(15.5, color: Tx.muted, height: 1.35)),
    ]);
  }
}

class _CameraEmpty extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Tx.surface2,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(CupertinoIcons.camera, size: 36, color: Tx.subtle),
            const SizedBox(height: 12),
            Text(tr('Introducir código'), textAlign: TextAlign.center, style: Tx.body(14.5, color: Tx.muted)),
            const SizedBox(height: 4),
            Text(
              tr('Sin cámara disponible. Usa el campo de abajo.'),
              textAlign: TextAlign.center,
              style: Tx.body(12.5, color: Tx.subtle),
            ),
          ]),
        ),
      ),
    );
  }
}

class _ScanFrame extends StatelessWidget {
  const _ScanFrame({required this.child, this.ring});
  final Widget child;
  final Animation<double>? ring;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context).width - 44;
    return ClipRRect(
      borderRadius: BorderRadius.circular(26),
      child: AspectRatio(
        aspectRatio: 1,
        child: Stack(fit: StackFit.expand, children: [
          child,
          IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  colors: [Colors.transparent, Tx.alpha(Colors.black, .45)],
                  stops: const [0.55, 1],
                ),
              ),
            ),
          ),
          IgnorePointer(
            child: Center(
              child: SizedBox(
                width: size * 0.58,
                height: size * 0.58,
                child: ring == null
                    ? CustomPaint(painter: _ScanRingPainter(progress: 0, staticRing: true))
                    : AnimatedBuilder(
                        animation: ring!,
                        builder: (_, __) => CustomPaint(painter: _ScanRingPainter(progress: ring!.value)),
                      ),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

class _ScanRingPainter extends CustomPainter {
  _ScanRingPainter({required this.progress, this.staticRing = false});
  final double progress;
  final bool staticRing;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.shortestSide / 2;
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..color = const Color(0x7369DCFF);
    canvas.drawCircle(c, r, base);
    if (staticRing) return;
    final sweep = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..shader = SweepGradient(
        startAngle: 0,
        endAngle: math.pi * 2,
        colors: const [Color(0x0037E6FF), Color(0xE637E6FF), Color(0x008B5CF6)],
        transform: GradientRotation(progress * math.pi * 2),
      ).createShader(Rect.fromCircle(center: c, radius: r));
    canvas.drawArc(Rect.fromCircle(center: c, radius: r), -math.pi / 2, math.pi * 1.35, false, sweep);
  }

  @override
  bool shouldRepaint(covariant _ScanRingPainter old) => old.progress != progress || old.staticRing != staticRing;
}
