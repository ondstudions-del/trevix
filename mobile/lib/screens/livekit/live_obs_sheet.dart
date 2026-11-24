import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../core/i18n.dart';
import '../../core/livekit_api.dart';
import '../../core/nav.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';
import 'obs_copy_field.dart';

Future<void> showLiveObsSheet(BuildContext context, LiveObsCredentials creds) {
  if (!creds.valid) {
    toast(context, tr('No hay datos RTMP para OBS.'), error: true);
    return Future.value();
  }
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: const Color(0xFF14141C),
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
    builder: (ctx) => Padding(
      padding: EdgeInsets.fromLTRB(20, 14, 20, MediaQuery.paddingOf(ctx).bottom + 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(4)))),
          const SizedBox(height: 16),
          Text(tr('Transmitir con OBS'), style: Tx.display(18, color: Colors.white)),
          const SizedBox(height: 8),
          Text(
            tr('En OBS: Ajustes → Emisión → Servicio «Personalizado…». Pega el servidor y la clave, luego «Iniciar transmisión».'),
            style: Tx.body(13, color: Colors.white60, height: 1.35),
          ),
          const SizedBox(height: 18),
          ObsCopyField(label: tr('Servidor'), value: creds.rtmpUrl),
          const SizedBox(height: 12),
          ObsCopyField(label: tr('Clave de retransmisión'), value: creds.streamKey, secret: true),
          if (creds.hasOverlayComments) ...[
            const SizedBox(height: 12),
            ObsCopyField(label: tr('URL comentarios (OBS)'), value: creds.overlayCommentsUrl!),
          ],
          if (creds.hasOverlayGifts) ...[
            const SizedBox(height: 12),
            ObsCopyField(label: tr('URL regalos (OBS)'), value: creds.overlayGiftsUrl!),
          ],
          const SizedBox(height: 8),
          Text(
            tr('Fuente «Navegador» en OBS: 1280×720, fondo transparente. El vídeo y el audio del live solo entran por RTMP desde OBS.'),
            style: Tx.body(11.5, color: Colors.white38, height: 1.35),
          ),
          const SizedBox(height: 14),
          Text(
            tr('Recomendado en OBS: lienzo 1280×720 (16:9), 30 fps. En la app el vídeo se ve en 16:9, no a pantalla completa vertical.'),
            style: Tx.body(12, color: Colors.white38, height: 1.35),
          ),
          const SizedBox(height: 16),
          SoftButton(label: tr('Listo'), onPressed: () => Navigator.pop(ctx)),
        ],
      ),
    ),
  );
}