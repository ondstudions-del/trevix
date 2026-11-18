import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../core/app_icon.dart';
import '../../core/appearance.dart';
import '../../core/brand_theme.dart';
import '../../core/i18n.dart';
import '../../core/nav.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';
import '../../widgets/settings_tiles.dart';

/// Ajustes → Apariencia y accesibilidad. Todo se aplica al instante y se guarda en el teléfono.
class AppearanceScreen extends StatefulWidget {
  const AppearanceScreen({super.key});

  @override
  State<AppearanceScreen> createState() => _AppearanceScreenState();
}

class _AppearanceScreenState extends State<AppearanceScreen> {
  bool _iconBusy = false;
  bool? _iconsSupported;

  @override
  void initState() {
    super.initState();
    AppIcons.supported().then((ok) {
      if (mounted) setState(() => _iconsSupported = ok);
    });
  }

  Future<void> _setIcon(AppIconChoice icon) async {
    if (_iconBusy || Appearance.instance.appIcon == icon) return;
    if (_iconsSupported == false) {
      toast(context, tr('Este dispositivo no permite cambiar el icono de la app.'), error: true);
      return;
    }
    setState(() => _iconBusy = true);
    try {
      await Appearance.instance.setAppIcon(icon);
      if (mounted) toast(context, tr('Icono actualizado. En Android puede tardar un momento en verse.'));
    } catch (e) {
      if (mounted) toast(context, tr('No se pudo cambiar el icono en este dispositivo. Reinicia el teléfono si no se ve.'), error: true);
    } finally {
      if (mounted) setState(() => _iconBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = Appearance.instance;
    return ListenableBuilder(
      listenable: a,
      builder: (context, _) => Scaffold(
        appBar: GlassBar(title: tr('Apariencia y accesibilidad')),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 60),
          children: [
            SettingsGroup(
              title: tr('Tema'),
              footer: a.choice == ThemeChoice.system
                  ? tr('Cambia solo entre claro y oscuro según la configuración del teléfono.')
                  : null,
              children: [
                Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(children: [
                    for (final c in ThemeChoice.values) ...[
                      if (c != ThemeChoice.system) const SizedBox(width: 10),
                      Expanded(child: _ThemeCard(choice: c, selected: a.choice == c, onTap: () => a.setChoice(c))),
                    ],
                  ]),
                ),
              ],
            ),
            SettingsGroup(
              title: tr('Colores'),
              footer: tr('El color de botones, enlaces y detalles de TREVIX. El predeterminado es TREVIX.'),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
                  child: Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      for (final b in BrandTheme.values)
                        _BrandChip(theme: b, selected: a.brand == b, onTap: () => a.setBrand(b)),
                    ],
                  ),
                ),
              ],
            ),
            SettingsGroup(
              title: tr('Icono de la app'),
              footer: tr('Elige cómo se ve TREVIX en la pantalla de inicio. El original viene por defecto.'),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
                  child: Row(
                    children: [
                      for (final icon in AppIconChoice.values) ...[
                        if (icon != AppIconChoice.original) const SizedBox(width: 8),
                        Expanded(
                          child: _IconChoice(
                            choice: icon,
                            selected: a.appIcon == icon,
                            busy: _iconBusy,
                            onTap: () => _setIcon(icon),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            SettingsGroup(title: tr('Texto'), children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 6),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(tr('Tamaño del texto'), style: Tx.body(15.5, weight: FontWeight.w500)),
                  const SizedBox(height: 10),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    for (var i = 0; i < Appearance.textScales.length; i++)
                      PillChip(
                        label: tr(Appearance.textScaleLabels[i]),
                        selected: a.textScale == Appearance.textScales[i],
                        onTap: () => a.setTextScale(Appearance.textScales[i]),
                      ),
                  ]),
                  const SizedBox(height: 14),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(color: Tx.surface3, borderRadius: BorderRadius.circular(Tx.radiusMd)),
                    child: Text(
                      tr('Así se verán las publicaciones, los mensajes y los menús de TREVIX.'),
                      style: Tx.body(15, height: 1.4),
                    ),
                  ),
                  const SizedBox(height: 8),
                ]),
              ),
              SettingsRow(
                icon: CupertinoIcons.bold,
                color: Tx.blue400,
                label: tr('Texto en negrita'),
                trailing: TxSwitch(value: a.boldText, onChanged: a.setBoldText),
              ),
            ]),
            SettingsGroup(
              title: tr('Accesibilidad'),
              footer: tr('Si activaste estas opciones en los ajustes del teléfono, TREVIX también las respeta.'),
              children: [
                SettingsRow(
                  icon: CupertinoIcons.wand_stars,
                  color: Tx.accentSoft,
                  label: tr('Reducir movimiento'),
                  subtitle: tr('Fundidos en lugar de deslizamientos y sin animaciones de fondo.'),
                  trailing: TxSwitch(value: a.reduceMotion, onChanged: a.setReduceMotion),
                ),
                SettingsRow(
                  icon: CupertinoIcons.circle_lefthalf_fill,
                  color: Tx.warning,
                  label: tr('Aumentar contraste'),
                  subtitle: tr('Textos y bordes más marcados.'),
                  trailing: TxSwitch(value: a.highContrast, onChanged: a.setHighContrast),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _BrandChip extends StatelessWidget {
  const _BrandChip({required this.theme, required this.selected, required this.onTap});

  final BrandTheme theme;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = theme.colors;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.fromLTRB(10, 8, 12, 8),
        decoration: BoxDecoration(
          color: selected ? Tx.surface3 : Tx.surface2,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: selected ? c.mid : Tx.borderStrong, width: selected ? 2 : 1),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(colors: [c.mid, c.core, c.secondary]),
            ),
          ),
          const SizedBox(width: 8),
          Text(theme.label, style: Tx.body(13.5, weight: selected ? FontWeight.w700 : FontWeight.w500)),
          if (selected) ...[
            const SizedBox(width: 6),
            Icon(CupertinoIcons.checkmark_alt, size: 16, color: c.mid),
          ],
        ]),
      ),
    );
  }
}

class _IconChoice extends StatelessWidget {
  const _IconChoice({required this.choice, required this.selected, required this.busy, required this.onTap});

  final AppIconChoice choice;
  final bool selected;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: busy ? null : onTap,
      child: Column(children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.all(2.5),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: selected ? Tx.brand : null,
            border: selected ? null : Border.all(color: Tx.borderStrong),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(15.5),
            child: Image.asset(choice.previewAsset, width: 52, height: 52, fit: BoxFit.cover),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          choice.label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Tx.body(11, weight: selected ? FontWeight.w700 : FontWeight.w500, color: selected ? Tx.text : Tx.muted),
          textAlign: TextAlign.center,
        ),
      ]),
    );
  }
}

class _ThemeCard extends StatelessWidget {
  const _ThemeCard({required this.choice, required this.selected, required this.onTap});

  final ThemeChoice choice;
  final bool selected;
  final VoidCallback onTap;

  static const _labels = {ThemeChoice.system: 'Sistema', ThemeChoice.light: 'Claro', ThemeChoice.dark: 'Oscuro'};

  Widget _mock(TxPalette p) => Container(
        color: p.bg,
        padding: const EdgeInsets.all(7),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(width: 14, height: 14, decoration: BoxDecoration(shape: BoxShape.circle, gradient: Tx.brand)),
            const SizedBox(width: 5),
            Expanded(child: Container(height: 5, decoration: BoxDecoration(color: p.text.withAlpha(150), borderRadius: BorderRadius.circular(3)))),
          ]),
          const SizedBox(height: 7),
          Expanded(
            child: Container(
              decoration: BoxDecoration(color: p.surface2, borderRadius: BorderRadius.circular(6), border: Border.all(color: p.border)),
              padding: const EdgeInsets.all(5),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(height: 4, width: 38, decoration: BoxDecoration(color: p.text.withAlpha(170), borderRadius: BorderRadius.circular(2))),
                const SizedBox(height: 4),
                Container(height: 4, width: 26, decoration: BoxDecoration(color: p.muted.withAlpha(150), borderRadius: BorderRadius.circular(2))),
              ]),
            ),
          ),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final preview = switch (choice) {
      ThemeChoice.light => _mock(TxPalette.light),
      ThemeChoice.dark => _mock(TxPalette.dark),
      ThemeChoice.system => Row(children: [Expanded(child: _mock(TxPalette.light)), Expanded(child: _mock(TxPalette.dark))]),
    };
    return GestureDetector(
      onTap: onTap,
      child: Column(children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          height: 96,
          padding: const EdgeInsets.all(2.5),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: selected ? Tx.brand : null,
            border: selected ? null : Border.all(color: Tx.borderStrong),
          ),
          child: ClipRRect(borderRadius: BorderRadius.circular(13.5), child: preview),
        ),
        const SizedBox(height: 8),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(selected ? CupertinoIcons.checkmark_circle_fill : CupertinoIcons.circle, size: 17, color: selected ? Tx.accentSoft : Tx.subtle),
          const SizedBox(width: 5),
          Text(tr(_labels[choice]!), style: Tx.body(14, weight: selected ? FontWeight.w600 : FontWeight.w500)),
        ]),
      ]),
    );
  }
}
