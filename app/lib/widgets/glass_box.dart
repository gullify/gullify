import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../theme.dart';
import 'liquid_glass.dart';
import 'retro_chrome.dart';

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
    // biseautée. Le biseau se pose à deux traits (idée #83) — un seul ne
    // dessinait qu'un cadre, et un cadre n'est qu'un carré. Même boîte, même
    // place, même taille : seule la peinture change.
    if (surfaces?.retro ?? false) {
      // Idée #85 : le chrome est un dégradé, pas un aplat — c'est lui qui
      // fait la tôle emboutie plutôt qu'un rectangle gris.
      return RetroBevel(
        gradient: winampChrome,
        child: ClipRect(child: child),
      );
    }

    // Apple Liquid Glass (idée #98) : la même boîte, mais une autre vitre —
    // plus fine, ravivée, cerclée de lumière et en superellipse. Elle se
    // peint dans liquid_glass.dart ; ici on ne fait que l'aiguiller.
    if (surfaces?.liquid ?? false) {
      return LiquidGlass(radius: radius, blur: blur, child: child);
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
