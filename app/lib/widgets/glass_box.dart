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
    this.blur = true,
  });

  final Widget child;
  final double radius;

  /// Flou en direct (BackdropFilter). À désactiver hors du shell : sur
  /// certains GPU le filtre se peint en plein écran (bug pilote).
  final bool blur;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final surfaces = Theme.of(context).extension<GullifySurfaces>();
    final light = scheme.brightness == Brightness.light;

    // Rétro Winamp (idée #82) : le verre laisse la place à une plaque opaque
    // biseautée — lumière en haut à gauche, ombre en bas à droite, angles à
    // peine cassés. Même boîte, même place, même taille : seule la peinture
    // change.
    if (surfaces?.retro ?? false) {
      final bevelLight = surfaces!.bevelLight ?? Colors.white24;
      final bevelDark = surfaces.bevelDark ?? Colors.black54;
      return DecoratedBox(
        // Angles vifs, pas de rayon : un biseau a deux couleurs (lumière en
        // haut à gauche, ombre en bas à droite), et Flutter refuse d'arrondir
        // une bordure qui n'est pas d'une seule teinte. Ça tombe bien — un
        // châssis de 1999 est parfaitement carré.
        decoration: BoxDecoration(
          color: surfaces.barColor ?? scheme.surfaceContainerHighest,
          border: Border(
            top: BorderSide(color: bevelLight, width: 1.5),
            left: BorderSide(color: bevelLight, width: 1.5),
            right: BorderSide(color: bevelDark, width: 1.5),
            bottom: BorderSide(color: bevelDark, width: 1.5),
          ),
        ),
        child: ClipRect(child: child),
      );
    }

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
        child: blur
            ? BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                child: Container(
                  decoration: BoxDecoration(
                    color: background,
                    borderRadius: BorderRadius.circular(radius),
                    border: Border.all(color: borderColor),
                  ),
                  child: child,
                ),
              )
            : Container(
                decoration: BoxDecoration(
                  // Sans flou : fond plus opaque pour rester lisible.
                  color: Color.alphaBlend(
                    background,
                    light
                        ? const Color(0x59FFFFFF)
                        : const Color(0x59000000),
                  ),
                  borderRadius: BorderRadius.circular(radius),
                  border: Border.all(color: borderColor),
                ),
                child: child,
              ),
      ),
    );
  }
}
