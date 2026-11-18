import 'dart:async';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/api.dart';
import '../../core/i18n.dart';
import '../../core/nav.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';

/// Anfitrión: muestra QR + código para que otro dispositivo se vincule.
class LinkHostScreen extends StatefulWidget {
  const LinkHostScreen({super.key});

  @override
  State<LinkHostScreen> createState() => _LinkHostScreenState();
}

class _LinkHostScreenState extends State<LinkHostScreen> {
  int? _id;
  String? _code;
  String? _payload;
  DateTime? _expiresAt;
  String _status = 'loading';
  String? _guestName;
  Object? _error;
  bool _busy = false;
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
      _guestName = null;
    });
    try {
      final res = await api.post('auth/link/start');
      final m = res.map;
      if (!mounted) return;
      setState(() {
        _id = asInt(m['id']);
        _code = asStr(m['code']);
        _payload = asStr(m['payload']);
        _expiresAt = asDate(m['expires_at']);
        _status = asStr(m['status'], 'pending');
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
    if (code == null || _status == 'approved' || _status == 'cancelled') return;
    try {
      final res = await api.get('auth/link/$code/status');
      if (!mounted) return;
      final m = res.map;
      final next = asStr(m['status'], _status);
      setState(() {
        _status = next;
        _guestName = asStrOrNull(m['guest_device_name']);
        _expiresAt = asDate(m['expires_at']) ?? _expiresAt;
      });
      if (next == 'expired' || next == 'cancelled' || next == 'approved') {
        _poll?.cancel();
      }
    } catch (_) {}
  }

  Future<void> _approve() async {
    final id = _id;
    if (id == null || _busy) return;
    setState(() => _busy = true);
    try {
      final res = await api.post('auth/link/approve', {'id': id});
      if (!mounted) return;
      setState(() => _status = asStr(res.map['status'], 'approved'));
      _poll?.cancel();
      toast(context, '${res.map['message'] ?? tr('Dispositivo vinculado.')}');
    } catch (e) {
      if (mounted) toastError(context, e);
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _cancel() async {
    final id = _id;
    if (id != null) {
      try {
        await api.post('auth/link/cancel', {'id': id});
      } catch (_) {}
    }
    if (mounted) Navigator.pop(context);
  }

  int get _secondsLeft {
    final exp = _expiresAt;
    if (exp == null) return 0;
    return exp.difference(DateTime.now()).inSeconds.clamp(0, 999);
  }

  @override
  Widget build(BuildContext context) {
    final code = _code;
    final payload = _payload ?? '';
    final claimed = _status == 'claimed';
    final approved = _status == 'approved';
    final expired = _status == 'expired' || _secondsLeft <= 0 && _status == 'pending';

    return Scaffold(
      backgroundColor: Tx.bg,
      appBar: GlassBar(
        title: tr('Vincular dispositivo'),
        actions: [
          CupertinoButton(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            onPressed: _cancel,
            child: Text(tr('Cerrar'), style: Tx.body(15, weight: FontWeight.w600, color: Tx.accent)),
          ),
        ],
      ),
      body: _error != null
          ? ErrorState(error: _error!, onRetry: _start)
          : code == null
              ? const Loading()
              : SafeArea(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(24, 12, 24, 40),
                    children: [
                      Text(
                        approved
                            ? tr('Listo')
                            : claimed
                                ? tr('Confirma la vinculación')
                                : tr('Escanea este código'),
                        textAlign: TextAlign.center,
                        style: Tx.display(26),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        approved
                            ? tr('El otro dispositivo ya puede usar tu cuenta.')
                            : claimed
                                ? tr('«{device}» quiere entrar. ¿Lo apruebas?', {'device': _guestName ?? tr('Dispositivo')})
                                : tr('Abre TREVIX en el otro dispositivo → Vincular, o escribe el código.'),
                        textAlign: TextAlign.center,
                        style: Tx.body(15, color: Tx.muted),
                      ),
                      const SizedBox(height: 28),
                      if (!approved && !expired)
                        Center(
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 280),
                            padding: const EdgeInsets.all(18),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(24),
                              boxShadow: [
                                BoxShadow(color: Tx.alpha(Tx.purple500, claimed ? .35 : .18), blurRadius: claimed ? 28 : 18, offset: const Offset(0, 10)),
                              ],
                            ),
                            child: QrImageView(
                              data: payload,
                              size: 220,
                              backgroundColor: Colors.white,
                              eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: Color(0xFF1A1033)),
                              dataModuleStyle: const QrDataModuleStyle(dataModuleShape: QrDataModuleShape.square, color: Color(0xFF1A1033)),
                            ),
                          ),
                        ),
                      if (approved)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 28),
                          child: Icon(CupertinoIcons.checkmark_seal_fill, size: 88, color: Tx.success),
                        ),
                      const SizedBox(height: 22),
                      if (!approved) ...[
                        Center(
                          child: GestureDetector(
                            onTap: () async {
                              await Clipboard.setData(ClipboardData(text: code));
                              if (context.mounted) toast(context, tr('Código copiado.'));
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                              decoration: BoxDecoration(
                                color: Tx.surface1,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: Tx.border),
                              ),
                              child: Text(code, style: Tx.display(28).copyWith(letterSpacing: 4, fontWeight: FontWeight.w700)),
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          expired ? tr('El código venció.') : tr('Caduca en {n} s', {'n': '$_secondsLeft'}),
                          textAlign: TextAlign.center,
                          style: Tx.body(13.5, color: expired ? Tx.danger : Tx.muted),
                        ),
                      ],
                      const SizedBox(height: 28),
                      if (claimed && !approved)
                        GradientButton(label: tr('Vincular'), loading: _busy, onPressed: _approve),
                      if (expired || approved) ...[
                        SoftButton(label: tr('Generar otro código'), expand: true, height: 46, onPressed: _start),
                        const SizedBox(height: 10),
                      ],
                      if (claimed)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: SoftButton(label: tr('Rechazar'), color: Tx.danger, expand: true, height: 46, onPressed: _cancel),
                        ),
                    ],
                  ),
                ),
    );
  }
}

/// Guest: escanear QR o escribir código desde la pantalla de login.
class LinkGuestScreen extends StatefulWidget {
  const LinkGuestScreen({super.key});

  @override
  State<LinkGuestScreen> createState() => _LinkGuestScreenState();
}

class _LinkGuestScreenState extends State<LinkGuestScreen> {
  final _manual = TextEditingController();
  final _scanner = MobileScannerController(detectionSpeed: DetectionSpeed.normal);
  bool _busy = false;
  bool _scanning = true;
  String? _code;
  String _status = 'idle';
  Timer? _poll;
  Object? _error;

  @override
  void dispose() {
    _poll?.cancel();
    _manual.dispose();
    _scanner.dispose();
    super.dispose();
  }

  String? _parseCode(String raw) {
    final t = raw.trim().toUpperCase();
    final fromUrl = RegExp(r'trevix://link/([A-Z0-9]{6,12})', caseSensitive: false).firstMatch(t);
    if (fromUrl != null) return fromUrl.group(1)!.toUpperCase();
    final cleaned = t.replaceAll(RegExp(r'[^A-Z0-9]'), '');
    return cleaned.length >= 6 ? cleaned : null;
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_busy || _code != null) return;
    for (final b in capture.barcodes) {
      final code = _parseCode(b.rawValue ?? '');
      if (code != null) {
        await _claim(code);
        return;
      }
    }
  }

  Future<void> _submitManual() async {
    final code = _parseCode(_manual.text);
    if (code == null) {
      toast(context, tr('Escribe el código de 8 caracteres.'), error: true);
      return;
    }
    await _claim(code);
  }

  Future<void> _claim(String code) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _scanning = false;
    });
    try {
      await _scanner.stop();
      final res = await api.post('auth/link/claim', {
        'code': code,
        'device_name': AppState.deviceName,
        'device_type': Platform.isIOS || Platform.isAndroid ? 'phone' : 'other',
      });
      if (!mounted) return;
      setState(() {
        _code = asStr(res.map['code'], code);
        _status = 'claimed';
        _busy = false;
      });
      toast(context, '${res.map['message'] ?? tr('Confirma en el otro dispositivo.')}');
      _poll?.cancel();
      _poll = Timer.periodic(const Duration(seconds: 2), (_) => _waitApproved());
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _scanning = true;
          _error = e;
        });
        toastError(context, e);
        await _scanner.start();
      }
    }
  }

  Future<void> _waitApproved() async {
    final code = _code;
    if (code == null) return;
    try {
      final res = await api.get('auth/link/$code/status');
      final m = res.map;
      final status = asStr(m['status']);
      if (status == 'approved' && m['token'] != null && m['user'] != null) {
        _poll?.cancel();
        if (!mounted) return;
        setState(() => _status = 'approved');
        await context.read<AppState>().loginWithLink(m);
        return;
      }
      if (status == 'expired' || status == 'cancelled') {
        _poll?.cancel();
        if (mounted) {
          setState(() => _status = status);
          toast(context, tr('La vinculación se canceló o venció.'), error: true);
        }
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Tx.bg,
      appBar: GlassBar(title: tr('Vincular')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 36),
          children: [
            Text(tr('Vincula este dispositivo'), textAlign: TextAlign.center, style: Tx.display(26)),
            const SizedBox(height: 8),
            Text(
              tr('Escanea el QR que muestra tu otra sesión de TREVIX, o escribe el código.'),
              textAlign: TextAlign.center,
              style: Tx.body(15, color: Tx.muted),
            ),
            const SizedBox(height: 20),
            if (_status == 'idle' || _scanning) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(22),
                child: AspectRatio(
                  aspectRatio: 1,
                  child: MobileScanner(controller: _scanner, onDetect: _onDetect),
                ),
              ),
              const SizedBox(height: 18),
              TextField(
                controller: _manual,
                textCapitalization: TextCapitalization.characters,
                textAlign: TextAlign.center,
                style: Tx.display(22).copyWith(letterSpacing: 3),
                decoration: InputDecoration(
                  hintText: tr('Código'),
                  filled: true,
                  fillColor: Tx.surface1,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: Tx.border)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: Tx.border)),
                ),
                onSubmitted: (_) => _submitManual(),
              ),
              const SizedBox(height: 14),
              GradientButton(label: tr('Continuar'), loading: _busy, onPressed: _submitManual),
            ] else ...[
              const SizedBox(height: 40),
              Icon(
                _status == 'approved' ? CupertinoIcons.checkmark_seal_fill : CupertinoIcons.hourglass,
                size: 72,
                color: _status == 'approved' ? Tx.success : Tx.accent,
              ),
              const SizedBox(height: 16),
              Text(
                _status == 'approved' ? tr('Dispositivo vinculado.') : tr('Esperando confirmación…'),
                textAlign: TextAlign.center,
                style: Tx.body(17, weight: FontWeight.w600),
              ),
              if (_code != null) ...[
                const SizedBox(height: 8),
                Text(_code!, textAlign: TextAlign.center, style: Tx.body(15, color: Tx.muted).copyWith(letterSpacing: 2)),
              ],
              if (_busy) ...[
                const SizedBox(height: 20),
                const Center(child: CupertinoActivityIndicator()),
              ],
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(tr('No se pudo vincular. Inténtalo de nuevo.'), textAlign: TextAlign.center, style: Tx.body(13, color: Tx.danger)),
            ],
          ],
        ),
      ),
    );
  }
}
