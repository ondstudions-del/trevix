import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/theme.dart';
import '../models/models.dart';
import 'tx_icon.dart';

export 'tx_icon.dart';

/// Imagen de red con caché, marcador animado y error discreto.
class NetImage extends StatelessWidget {
  const NetImage(this.url, {super.key, this.fit = BoxFit.cover, this.width, this.height, this.radius = 0});

  final String? url;
  final BoxFit fit;
  final double? width;
  final double? height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final u = url;
    Widget child;
    if (u == null || u.isEmpty) {
      child = Container(width: width, height: height, color: Tx.surface3);
    } else {
      child = CachedNetworkImage(
        imageUrl: u,
        fit: fit,
        width: width,
        height: height,
        fadeInDuration: const Duration(milliseconds: 220),
        placeholder: (_, __) => Container(width: width, height: height, color: Tx.surface3),
        errorWidget: (_, __, ___) => Container(
          width: width,
          height: height,
          color: Tx.surface3,
          alignment: Alignment.center,
          child: Icon(CupertinoIcons.photo, color: Tx.subtle),
        ),
      );
    }
    return radius > 0 ? ClipRRect(borderRadius: BorderRadius.circular(radius), child: child) : child;
  }
}

/// Foto de perfil con iniciales de respaldo y, opcionalmente, el anillo de historias.
class Avatar extends StatelessWidget {
  const Avatar({super.key, required this.user, this.size = 44, this.ring = false, this.ringSeen = false, this.online = false, this.onTap});

  final User user;
  final double size;
  final bool ring;
  final bool ringSeen;
  final bool online;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final initials = user.displayName.trim().isEmpty ? '?' : user.displayName.trim().characters.first.toUpperCase();
    final inner = ClipOval(
      child: SizedBox(
        width: size,
        height: size,
        child: user.avatarUrl != null
            ? NetImage(user.avatarUrl, width: size, height: size)
            : DecoratedBox(
                decoration: const BoxDecoration(gradient: Tx.brand),
                child: Center(child: Text(initials, style: Tx.display(size * .4, color: Colors.white))),
              ),
      ),
    );
    Widget result = inner;
    if (ring) {
      final gap = size > 60 ? 3.5 : 2.5;
      result = Container(
        padding: EdgeInsets.all(gap),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: ringSeen ? null : Tx.ring,
          color: ringSeen ? Tx.surface4 : null,
        ),
        child: Container(
          padding: EdgeInsets.all(gap * .8),
          decoration: BoxDecoration(shape: BoxShape.circle, color: Tx.bg),
          child: inner,
        ),
      );
    }
    if (online) {
      final dot = (size * .26).clamp(9.0, 16.0);
      result = Stack(clipBehavior: Clip.none, children: [
        result,
        Positioned(
          right: ring ? 4 : 0,
          bottom: ring ? 4 : 0,
          child: Container(
            width: dot,
            height: dot,
            decoration: BoxDecoration(color: Tx.success, shape: BoxShape.circle, border: Border.all(color: Tx.bg, width: 2)),
          ),
        ),
      ]);
    }
    if (onTap != null) {
      result = GestureDetector(onTap: onTap, behavior: HitTestBehavior.opaque, child: result);
    }
    return result;
  }
}

/// Nombre con la insignia de verificación.
class NameLine extends StatelessWidget {
  const NameLine({super.key, required this.user, this.size = 15, this.weight = FontWeight.w600, this.showUsername = false, this.maxWidth});

  final User user;
  final double size;
  final FontWeight weight;
  final bool showUsername;
  final double? maxWidth;

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Flexible(child: Text(user.displayName, maxLines: 1, overflow: TextOverflow.ellipsis, style: Tx.body(size, weight: weight))),
      if (user.isVerified) ...[
        const SizedBox(width: 4),
        VerifiedBadge(size: size * .95),
      ],
      if (showUsername) ...[
        const SizedBox(width: 6),
        Flexible(
          child: Text('@${user.username}', maxLines: 1, overflow: TextOverflow.ellipsis, style: Tx.body(size - 1, color: Tx.subtle)),
        ),
      ],
    ]);
  }
}

class VerifiedBadge extends StatelessWidget {
  const VerifiedBadge({super.key, this.size = 15});

  final double size;

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: (b) => Tx.brand.createShader(Offset.zero & b.size),
      child: Icon(CupertinoIcons.checkmark_seal_fill, size: size),
    );
  }
}

/// Botón principal con el degradado de la marca.
class GradientButton extends StatelessWidget {
  const GradientButton({super.key, required this.label, this.onPressed, this.loading = false, this.icon, this.height = 52, this.expand = true});

  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final IconData? icon;
  final double height;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !loading;
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 180),
      opacity: enabled ? 1 : .55,
      child: Container(
        height: height,
        width: expand ? double.infinity : null,
        decoration: BoxDecoration(
          gradient: Tx.brand,
          borderRadius: BorderRadius.circular(height / 2.6),
          boxShadow: enabled ? [BoxShadow(color: Tx.alpha(Tx.purple, .38), blurRadius: 22, offset: const Offset(0, 8))] : null,
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(height / 2.6),
            onTap: enabled ? onPressed : null,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: expand ? 0 : 22),
              child: Center(
                child: loading
                    ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                    : Row(mainAxisSize: MainAxisSize.min, children: [
                        if (icon != null) ...[Icon(icon, size: 19, color: Colors.white), const SizedBox(width: 8)],
                        Text(label, style: Tx.body(16, weight: FontWeight.w600, color: Colors.white)),
                      ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Botón secundario (superficie con borde).
class SoftButton extends StatelessWidget {
  const SoftButton({super.key, required this.label, this.onPressed, this.icon, this.height = 40, this.color, this.loading = false, this.expand = false});

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final double height;
  final Color? color;
  final bool loading;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final fg = color ?? Tx.text;
    return SizedBox(
      height: height,
      width: expand ? double.infinity : null,
      child: Material(
        color: Tx.surface3,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(height / 2.6), side: BorderSide(color: Tx.borderStrong)),
        child: InkWell(
          borderRadius: BorderRadius.circular(height / 2.6),
          onTap: loading ? null : onPressed,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [
              if (loading)
                SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: fg))
              else if (icon != null)
                Icon(icon, size: 17, color: fg),
              if (loading || icon != null) const SizedBox(width: 7),
              Text(label, style: Tx.body(14, weight: FontWeight.w600, color: fg)),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Botón redondo de icono con contador opcional.
class IconBadgeButton extends StatelessWidget {
  const IconBadgeButton({super.key, this.icon, this.glyph, this.count = 0, this.onTap, this.size = 24})
      : assert(icon != null || glyph != null);

  final IconData? icon;
  final TxGlyph? glyph;
  final int count;
  final VoidCallback? onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 40,
        height: 40,
        margin: const EdgeInsets.symmetric(horizontal: 3),
        decoration: BoxDecoration(color: Tx.alpha(Tx.text, .06), shape: BoxShape.circle, border: Border.all(color: Tx.border)),
        child: Stack(clipBehavior: Clip.none, alignment: Alignment.center, children: [
          if (glyph != null) TxIcon(glyph!, size: size * .88, stroke: 2) else Icon(icon, size: size * .9, color: Tx.text),
          if (count > 0) Positioned(right: -5, top: -5, child: CountBadge(count)),
        ]),
      ),
    );
  }
}

class CountBadge extends StatelessWidget {
  const CountBadge(this.count, {super.key});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 18),
      height: 18,
      padding: const EdgeInsets.symmetric(horizontal: 5),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Tx.danger, Color(0xFFEC4899)]),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: Tx.bg, width: 1.5),
      ),
      alignment: Alignment.center,
      child: Text(count > 99 ? '99+' : '$count', style: Tx.body(10, weight: FontWeight.w700, color: Colors.white, height: 1)),
    );
  }
}

/// Chip seleccionable (pestañas, filtros, géneros).
class PillChip extends StatelessWidget {
  const PillChip({super.key, required this.label, required this.selected, required this.onTap, this.icon});

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
        decoration: BoxDecoration(
          gradient: selected ? Tx.brand : null,
          color: selected ? null : Tx.surface3,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? Colors.transparent : Tx.border),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[Icon(icon, size: 15, color: selected ? Colors.white : Tx.muted), const SizedBox(width: 6)],
          Text(label, style: Tx.body(13.5, weight: FontWeight.w600, color: selected ? Colors.white : Tx.muted)),
        ]),
      ),
    );
  }
}

/// Tarjeta de superficie redondeada.
class Panel extends StatelessWidget {
  const Panel({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.margin, this.onTap, this.gradient = false});

  final Widget child;
  final EdgeInsets padding;
  final EdgeInsets? margin;
  final VoidCallback? onTap;
  final bool gradient;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin,
      decoration: BoxDecoration(
        color: gradient ? null : Tx.surface2,
        gradient: gradient ? Tx.brandSoft : null,
        borderRadius: BorderRadius.circular(Tx.radiusLg),
        border: Border.all(color: gradient ? Tx.alpha(Tx.purple500, .3) : Tx.border),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(Tx.radiusLg),
          onTap: onTap,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

/// Barra superior de vidrio para las pantallas internas.
class GlassBar extends StatelessWidget implements PreferredSizeWidget {
  const GlassBar({super.key, this.title, this.titleWidget, this.actions = const [], this.leading, this.bottom, this.showBack = true});

  final String? title;
  final Widget? titleWidget;
  final List<Widget> actions;
  final Widget? leading;
  final PreferredSizeWidget? bottom;
  final bool showBack;

  @override
  Size get preferredSize => Size.fromHeight(52 + (bottom?.preferredSize.height ?? 0));

  @override
  Widget build(BuildContext context) {
    final canPop = showBack && Navigator.of(context).canPop();
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          decoration: BoxDecoration(color: Tx.alpha(Tx.bg, .78), border: Border(bottom: BorderSide(color: Tx.border))),
          child: SafeArea(
            bottom: false,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              SizedBox(
                height: 52,
                child: Row(children: [
                  if (leading != null)
                    leading!
                  else if (canPop)
                    CupertinoButton(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      onPressed: () => Navigator.of(context).maybePop(),
                      child: const TxIcon(TxGlyph.back, size: 26, stroke: 2.2),
                    )
                  else
                    const SizedBox(width: 16),
                  Expanded(
                    child: titleWidget ??
                        Text(title ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: Tx.display(18, weight: FontWeight.w600)),
                  ),
                  ...actions,
                  const SizedBox(width: 6),
                ]),
              ),
              if (bottom != null) bottom!,
            ]),
          ),
        ),
      ),
    );
  }
}

class Loading extends StatelessWidget {
  const Loading({super.key, this.padding = 40});

  final double padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.all(padding),
      child: Center(child: CupertinoActivityIndicator(radius: 13, color: Tx.accentSoft)),
    );
  }
}

/// Estado vacío con icono en degradado.
class EmptyState extends StatelessWidget {
  const EmptyState({super.key, this.icon, this.glyph, required this.title, this.message, this.action})
      : assert(icon != null || glyph != null);

  final IconData? icon;
  final TxGlyph? glyph;
  final String title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 84,
          height: 84,
          decoration: BoxDecoration(
            gradient: Tx.brandSoft,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: Tx.alpha(Tx.purple500, .35)),
            boxShadow: [BoxShadow(color: Tx.alpha(Tx.purple, .25), blurRadius: 30, offset: const Offset(0, 10))],
          ),
          alignment: Alignment.center,
          child: glyph != null
              ? TxIcon(glyph!, size: 36, gradient: Tx.brandText, stroke: 1.7)
              : ShaderMask(
                  blendMode: BlendMode.srcIn,
                  shaderCallback: (b) => Tx.brandText.createShader(Offset.zero & b.size),
                  child: Icon(icon, size: 34),
                ),
        ),
        const SizedBox(height: 18),
        Text(title, textAlign: TextAlign.center, style: Tx.display(19)),
        if (message != null) ...[
          const SizedBox(height: 8),
          Text(message!, textAlign: TextAlign.center, style: Tx.body(14.5, color: Tx.muted, height: 1.45)),
        ],
        if (action != null) ...[const SizedBox(height: 20), action!],
      ]),
    );
  }
}

class ErrorState extends StatelessWidget {
  const ErrorState({super.key, required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return EmptyState(
      icon: CupertinoIcons.wifi_exclamationmark,
      title: 'No se pudo cargar',
      message: errorText(error),
      action: SoftButton(label: 'Reintentar', icon: CupertinoIcons.refresh, onPressed: onRetry),
    );
  }
}

/// Interruptor con los colores de la marca.
class TxSwitch extends StatelessWidget {
  const TxSwitch({super.key, required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final enabled = onChanged != null;
    return GestureDetector(
      onTap: enabled ? () => onChanged!(!value) : null,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 180),
        opacity: enabled ? 1 : .5,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          width: 52,
          height: 32,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            gradient: value ? Tx.brand : null,
            color: value ? null : Tx.surface4,
            borderRadius: BorderRadius.circular(16),
          ),
          child: AnimatedAlign(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            alignment: value ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: Colors.black.withAlpha(60), blurRadius: 4, offset: const Offset(0, 1))],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Encabezado de sección.
class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.trailing, this.padding = const EdgeInsets.fromLTRB(16, 22, 16, 10)});

  final String text;
  final Widget? trailing;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Row(children: [
        Expanded(child: Text(text, style: Tx.display(19))),
        if (trailing != null) trailing!,
      ]),
    );
  }
}
