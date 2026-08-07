import 'package:flutter/material.dart';

/// État vide signature : la mascotte Gullify en médaillon + un message.
/// Remplace les « Aucun résultat » nus.
///
/// La mouette n'est plus posée en couleurs sur le fond (le PNG détouré
/// laissait voir le fond à travers la poitrine, et le rendu criard volait la
/// vedette au message) : elle est gravée en **noir et blanc** — deux gris, sans
/// la moindre couleur d'accent — au centre d'un disque de verre neutre.
class MascotEmpty extends StatelessWidget {
  const MascotEmpty({
    super.key,
    required this.message,
    this.hint,
    this.action,
    this.size = 132,
  });

  final String message;
  final String? hint;
  final Widget? action;

  /// Diamètre de la mouette gravée ; le médaillon fait un tiers de plus.
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            MascotMedallion(size: size),
            const SizedBox(height: 18),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15.5,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.2,
                color: scheme.onSurface,
              ),
            ),
            if (hint != null) ...[
              const SizedBox(height: 4),
              Text(
                hint!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
            if (action != null) ...[
              const SizedBox(height: 18),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

/// La mouette gravée en noir et blanc sur un disque de verre neutre : halo
/// radial, liseré fin, ombre douce — le vocabulaire « Liquid Glass », sans
/// couleur. La couleur d'accent choisie dans les réglages ne teinte plus le
/// médaillon (idée #72) : l'état vide reste sobre, quelle que soit la teinte.
class MascotMedallion extends StatelessWidget {
  const MascotMedallion({super.key, this.size = 132});

  final double size;

  /// Le dessin n'occupe pas tout le PNG : son cadre utile va de 14,2 % à
  /// 82,7 % en hauteur et de 21,6 % à 78,4 % en largeur. Son centre est donc
  /// un peu au-dessus du centre du fichier — c'est de là que venait le
  /// médaillon « pas centré ».
  static const _artCenterY = 0.4846;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;

    // Deux gris purs : le trait (casque, lunettes, bec) reste lisible alors
    // que tout est monochrome.
    final ink = dark ? const Color(0xFF33373E) : const Color(0xFF202329);
    final paper = dark ? const Color(0xFFE9EBEF) : const Color(0xFFC8CCD3);
    final disc = size * 1.34;
    final art = disc * 1.02;

    return SizedBox(
      width: disc,
      height: disc,
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: dark ? 0.28 : 0.12),
              blurRadius: 28,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: DecoratedBox(
          position: DecorationPosition.foreground,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: dark ? const Color(0x26FFFFFF) : const Color(0xB3FFFFFF),
            ),
          ),
          child: ClipOval(
            child: Stack(
              fit: StackFit.expand,
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: dark
                          ? const [Color(0x1FFFFFFF), Color(0x08FFFFFF)]
                          : const [Color(0x14000000), Color(0x05000000)],
                    ),
                  ),
                ),
                // Le dessin est centré sur le disque : on compense le décalage
                // de son cadre utile dans le PNG.
                Positioned(
                  left: (disc - art) / 2,
                  top: disc / 2 - art * _artCenterY,
                  width: art,
                  height: art,
                  child: ColorFiltered(
                    colorFilter: duotoneFilter(ink, paper),
                    child: Image.asset('assets/icon/mascot.png'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Filtre bichrome : la luminance de l'image choisit la position entre [ink]
/// (noirs) et [paper] (blancs), l'alpha d'origine est conservé. Une image en
/// couleurs en ressort monochrome sans perdre son modelé.
ColorFilter duotoneFilter(Color ink, Color paper) {
  // Luminance perçue (Rec. 709).
  const lr = 0.2126, lg = 0.7152, lb = 0.0722;
  // Sortie = from + (to - from) × luminance. La matrice travaille en 0-255
  // (entrées comme décalage), les composantes de Color en 0-1 : la pente est
  // donc (to - from) tel quel, et le décalage from × 255.
  List<double> row(double from, double to) {
    final k = to - from;
    return [k * lr, k * lg, k * lb, 0, from * 255];
  }

  return ColorFilter.matrix([
    ...row(ink.r, paper.r),
    ...row(ink.g, paper.g),
    ...row(ink.b, paper.b),
    0, 0, 0, 1, 0,
  ]);
}
