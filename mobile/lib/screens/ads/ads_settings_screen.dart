import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../core/i18n.dart';
import '../../core/nav.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';
import '../../widgets/settings_tiles.dart';
import 'ads_screen.dart';

/// OND-ADS en ajustes: dónde aparecen los anuncios (fijos) y acceso a crear campañas con botón de acción.
class AdsSettingsScreen extends StatefulWidget {
  const AdsSettingsScreen({super.key});

  @override
  State<AdsSettingsScreen> createState() => _AdsSettingsScreenState();
}

class _AdsSettingsScreenState extends State<AdsSettingsScreen> {
  static const _zones = [
    ('feed', 'Feed e inicio'),
    ('profile', 'Perfiles'),
    ('stories', 'Historias'),
    ('reels', 'Reels'),
    ('community', 'Comunidades'),
  ];

  static const _actions = [
    ('visit', 'Visitar sitio web o app', 'URL del destino (https://…).'),
    ('shop', 'Comprar un producto', 'Enlace de pago o tienda + precio o etiqueta.'),
    ('contact', 'Contactar', 'Enlace web, correo (mailto:) o teléfono (tel:).'),
    ('subscribe', 'Suscribirse a una cuenta', 'Usuario @ de la cuenta en TREVIX.'),
    ('sign_up', 'Registrarse', 'URL del formulario o landing.'),
    ('learn_more', 'Más información', 'URL con los detalles.'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: GlassBar(title: tr('OND-ADS')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
        children: [
          Panel(
            gradient: true,
            padding: const EdgeInsets.all(18),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tr('Anuncios en TREVIX'), style: Tx.body(17, weight: FontWeight.w800)),
              const SizedBox(height: 8),
              Text(
                tr('Los anuncios aprobados se muestran de forma nativa en el feed, perfiles, historias, reels y comunidades. No hace falta activar esas zonas: ya vienen habilitadas para todas las personas.'),
                style: Tx.body(13.5, color: Tx.muted, height: 1.45),
              ),
            ]),
          ),
          const SizedBox(height: 16),
          SectionTitle(tr('Dónde se muestran'), padding: const EdgeInsets.fromLTRB(4, 0, 4, 10)),
          SettingsGroup(
            children: [
              for (final z in _zones)
                SettingsRow(
                  icon: CupertinoIcons.checkmark_seal_fill,
                  color: Tx.success,
                  label: tr(z.$2),
                  subtitle: tr('Siempre activo'),
                  trailing: Icon(CupertinoIcons.lock_fill, size: 16, color: Tx.subtle),
                ),
            ],
          ),
          const SizedBox(height: 16),
          SectionTitle(tr('Configuración del anuncio'), padding: const EdgeInsets.fromLTRB(4, 0, 4, 10)),
          Text(
            tr('Al crear un anuncio libre eliges el tipo de contenido y el botón de acción. Ejemplos:'),
            style: Tx.body(13, color: Tx.muted, height: 1.4),
          ),
          const SizedBox(height: 10),
          SettingsGroup(
            children: [
              for (final a in _actions)
                SettingsRow(
                  icon: CupertinoIcons.hand_point_right_fill,
                  color: Tx.accent,
                  label: tr(a.$2),
                  subtitle: tr(a.$3),
                ),
            ],
          ),
          const SizedBox(height: 16),
          SettingsGroup(children: [
            SettingsRow(
              icon: CupertinoIcons.speaker_2_fill,
              color: Tx.warning,
              label: tr('Crear o gestionar anuncios'),
              subtitle: tr('Promociona publicaciones o diseña un anuncio con botón, enlace y precio.'),
              onTap: () => push(context, const AdsScreen()),
            ),
          ]),
        ],
      ),
    );
  }
}