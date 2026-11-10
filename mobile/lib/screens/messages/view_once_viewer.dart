import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/api.dart';
import '../../core/chat_media.dart';
import '../../core/theme.dart';
import '../../models/models.dart';

/// Foto de visualización única: se descarga una sola vez (solo en memoria) y se cierra al terminar el tiempo.
class ViewOnceViewer extends StatefulWidget {
  const ViewOnceViewer({super.key, required this.message});

  final Message message;

  @override
  State<ViewOnceViewer> createState() => _ViewOnceViewerState();
}

class _ViewOnceViewerState extends State<ViewOnceViewer> with SingleTickerProviderStateMixin {
  Uint8List? _bytes;
  String? _error;
  AnimationController? _timer;

  int get _seconds => widget.message.viewOnce?.seconds ?? 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _timer?.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final bytes = await ChatMedia.once(widget.message);
      if (!mounted) return;
      setState(() => _bytes = bytes);
      if (_seconds > 0) {
        _timer = AnimationController(vsync: this, duration: Duration(seconds: _seconds))
          ..addStatusListener((s) {
            if (s == AnimationStatus.completed && mounted) Navigator.of(context).pop(true);
          })
          ..forward();
        setState(() {});
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.status == 410 ? 'Ya abriste esta foto.' : e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'No se pudo abrir la foto.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final bytes = _bytes;
    final timer = _timer;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(children: [
          Positioned.fill(
            child: bytes != null
                ? InteractiveViewer(maxScale: 4, child: Center(child: Image.memory(bytes, fit: BoxFit.contain, gaplessPlayback: true)))
                : Center(
                    child: _error != null
                        ? Padding(
                            padding: const EdgeInsets.all(32),
                            child: Column(mainAxisSize: MainAxisSize.min, children: [
                              const Icon(CupertinoIcons.eye_slash, color: Colors.white70, size: 40),
                              const SizedBox(height: 12),
                              Text(_error!, textAlign: TextAlign.center, style: Tx.body(16, color: Colors.white)),
                            ]),
                          )
                        : const CupertinoActivityIndicator(color: Colors.white, radius: 14),
                  ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Row(children: [
                CupertinoButton(
                  padding: const EdgeInsets.all(6),
                  onPressed: () => Navigator.of(context).pop(_bytes != null),
                  child: const Icon(CupertinoIcons.xmark, color: Colors.white, size: 26),
                ),
                const Spacer(),
                if (bytes != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(16)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      if (timer != null)
                        AnimatedBuilder(
                          animation: timer,
                          builder: (_, __) => SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(value: 1 - timer.value, strokeWidth: 2.4, color: Colors.white, backgroundColor: Colors.white24),
                          ),
                        )
                      else
                        const Icon(CupertinoIcons.eye, color: Colors.white, size: 16),
                      const SizedBox(width: 8),
                      if (timer != null)
                        AnimatedBuilder(
                          animation: timer,
                          builder: (_, __) => Text('${(_seconds * (1 - timer.value)).ceil()} s', style: Tx.body(13.5, weight: FontWeight.w600, color: Colors.white)),
                        )
                      else
                        Text('Ver una vez', style: Tx.body(13.5, weight: FontWeight.w600, color: Colors.white)),
                    ]),
                  ),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}
