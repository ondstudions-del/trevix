import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../core/appearance.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';
import '../../widgets/settings_tiles.dart';

/// Ajustes → Apariencia y accesibilidad. Todo se aplica al instante y se guarda en el teléfono.
class AppearanceScreen extends StatelessWidget {
  const AppearanceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final a = Appearance.instance;
    return ListenableBuilder(
      listenable: a,
      builder: (context, _) => Scaffold(
        appBar: const GlassBar(title: 'Apariencia y accesibilidad'),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 60),
          children: [
            SettingsGroup(
              title: 'Tema',
              footer: a.choice == ThemeChoice.system
                  ? 'Cambia solo entre claro y oscuro según la configuración del teléfono.'
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
            SettingsGroup(title: 'Texto', children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 6),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Tamaño del texto', style: Tx.body(15.5, weight: FontWeight.w500)),
                  const SizedBox(height: 10),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    for (var i = 0; i < Appearance.textScales.length; i++)
                      PillChip(
                        label: Appearance.textScaleLabels[i],
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
                      'Así se verán las publicaciones, los mensajes y los menús de TREVIX.',
                      style: Tx.body(15, height: 1.4),
                    ),
                  ),
                  const SizedBox(height: 8),
                ]),
              ),
              SettingsRow(
                icon: CupertinoIcons.bold,
                color: Tx.blue400,
                label: 'Texto en negrita',
                trailing: TxSwitch(value: a.boldText, onChanged: a.setBoldText),
              ),
            ]),
            SettingsGroup(
              title: 'Accesibilidad',
              footer: 'Si activaste estas opciones en los ajustes del teléfono, TREVIX también las respeta.',
              children: [
                SettingsRow(
                  icon: CupertinoIcons.wand_stars,
                  color: Tx.accentSoft,
                  label: 'Reducir movimiento',
                  subtitle: 'Fundidos en lugar de deslizamientos y sin animaciones de fondo.',
                  trailing: TxSwitch(value: a.reduceMotion, onChanged: a.setReduceMotion),
                ),
                SettingsRow(
                  icon: CupertinoIcons.circle_lefthalf_fill,
                  color: Tx.warning,
                  label: 'Aumentar contraste',
                  subtitle: 'Textos y bordes más marcados.',
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
            Container(width: 14, height: 14, decoration: const BoxDecoration(shape: BoxShape.circle, gradient: Tx.brand)),
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
          Text(_labels[choice]!, style: Tx.body(14, weight: selected ? FontWeight.w600 : FontWeight.w500)),
        ]),
      ]),
    );
  }
}
