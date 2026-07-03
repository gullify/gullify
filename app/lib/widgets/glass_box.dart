import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../theme.dart';

/// Carte « liquid glass » : flou + saturation du contenu dessous, fond
/// translucide, liseré lumineux, ombre douce. Recette commune du
/// mini-lecteur et de la barre d'onglets (style Liquid Glass Player).
class GlassBox extends StatelessWidget {
  const GlassBox({
    super.key,
    required this.child,
    this.radius = 20,
  });

  final Widget child;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final surfaces = Theme.of(context).extension<GullifySurfaces>();
    final light = scheme.brightness == Brightness.light;

    final background = light
        ? const Color(0x8CFFFFFF)
        : surfaces?.barColor ?? scheme.surfaceContainerHighest.withValues(alpha: 0.72);
    final borderColor =
        light ? const Color(0xB3FFFFFF) : const Color(0x26FFFFFF);

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: const [
          BoxShadow(
            color: Color(0x261A1E37),
            blurRadius: 34,
            offset: Offset(0, 14),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: Container(
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(radius),
              border: Border.all(color: borderColor),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}
