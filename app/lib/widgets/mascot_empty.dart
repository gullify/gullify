import 'package:flutter/material.dart';

/// État vide signature : la mascotte Gullify en médaillon + un message.
/// Remplace les « Aucun résultat » nus.
///
/// La mouette n'est plus posée en couleurs sur le fond (le PNG détouré
/// laissait voir le fond à travers la poitrine, et le rendu criard volait la
/// vedette au message) : elle est gravée en **monochrome** — une seule teinte,
/// dérivée de l'accent du thème — au centre d'un disque de verre teinté.
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

/// La mouette gravée en monochrome sur un disque de verre teinté accent :
/// halo radial, liseré fin, ombre douce — le vocabulaire « Liquid Glass ».
class MascotMedallion extends StatelessWidget {
  const MascotMedallion({super.key, this.size = 132});

  final double size;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;

    // Deux tons d'une même teinte : le trait (casque, lunettes, bec) reste
    // lisible alors que tout est monochrome.
    final ink = Color.lerp(scheme.primary, Colors.black, dark ? 0.42 : 0.55)!;
    final paper =
        Color.lerp(scheme.primary, Colors.white, dark ? 0.66 : 0.34)!;
    final disc = size * 1.34;
    // Cadrage camée : la mouette descend jusqu'au bas du disque, où elle se
    // dissout en transparence (même geste que l'en-tête d'artiste) — le bas
    // plat du PNG détouré ne se lit plus comme une coupure.
    final art = disc * 1.05;

    return SizedBox(
      width: disc,
      height: disc,
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: scheme.primary.withValues(alpha: dark ? 0.22 : 0.14),
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
                      colors: [
                        scheme.primary.withValues(alpha: dark ? 0.26 : 0.18),
                        scheme.primary.withValues(alpha: 0.03),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  left: (disc - art) / 2,
                  // Le dessin s'arrête à 82,7 % de la hauteur du PNG : on
                  // remonte d'autant pour amener ce bas au bas du disque.
                  top: disc * 0.98 - art * 0.827,
                  width: art,
                  height: art,
                  child: ShaderMask(
                    shaderCallback: (rect) => const LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      stops: [0.0, 0.66, 0.86],
                      colors: [Colors.white, Colors.white, Colors.transparent],
                    ).createShader(rect),
                    blendMode: BlendMode.dstIn,
                    child: ColorFiltered(
                      colorFilter: duotoneFilter(ink, paper),
                      child: Image.asset('assets/icon/mascot.png'),
                    ),
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
