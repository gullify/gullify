import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../theme.dart';

/// La MATIÈRE du thème « Apple Liquid Glass » (idée #98).
///
/// Gullify a toujours eu du verre ; celui d'Apple (iOS 26) n'est pas la même
/// vitre. Ce qui le distingue tient en quatre choses, et ce sont exactement
/// celles peintes ici :
///   1. il est BEAUCOUP plus fin — on lit au travers, la couleur du dessous
///      transparaît au lieu d'être masquée par un fond laiteux ;
///   2. il ravive ce qu'il laisse passer (vibrancy) : le flou sature les
///      couleurs du dessous au lieu de les délaver ;
///   3. ses ARÊTES accrochent la lumière — vive en haut à gauche, éteinte au
///      milieu, reprise en bas à droite : c'est ce liseré, et lui seul, qui
///      fait « une lentille » plutôt que « un rectangle translucide » ;
///   4. ses angles sont des superellipses (le squircle), pas des quarts de
///      cercle.
///
/// Comme retro_chrome.dart, ce fichier ne peint qu'une matière : il ne décide
/// de rien. C'est theme.dart qui vient y chercher sa palette.

/// Le thème Apple Liquid Glass est-il levé ? (idée #98)
bool isLiquidSkin(BuildContext context) =>
    Theme.of(context).extension<GullifySurfaces>()?.liquid ?? false;

/// Le verre clair : blanc lavé, très transparent (haut-gauche → bas-droite).
const _lightFill = [Color(0x73FFFFFF), Color(0x40FFFFFF)];

/// Le verre sombre : à peine blanchi — c'est le fond qui doit rester visible.
const _darkFill = [Color(0x2EFFFFFF), Color(0x0FFFFFFF)];

/// Ce qu'on glisse SOUS le verre quand le flou est coupé (sur certains GPU le
/// BackdropFilter se peint en plein écran) : sans flou, la lisibilité ne tient
/// plus qu'à un fond un peu plus dense.
const _lightScrim = Color(0x8CFFFFFF);
const _darkScrim = Color(0x8C0B0B10);

/// Panneau de verre façon Apple : flou profond et couleurs ravivées, dégradé
/// translucide, liseré spéculaire, angles en superellipse.
///
/// Même boîte, même place, même taille que `GlassBox` : seule la peinture
/// change — la mise en page ne bouge pas d'un pixel d'un thème à l'autre.
class LiquidGlass extends StatelessWidget {
  const LiquidGlass({
    super.key,
    required this.child,
    this.radius = 20,
    this.blur = true,
    this.circle = false,
  });

  final Widget child;

  /// Rayon des angles (ignoré si [circle]).
  final double radius;

  /// Flou en direct (BackdropFilter). Coupé hors du shell, comme ailleurs.
  final bool blur;

  /// Bouton rond : la lentille devient un disque.
  final bool circle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final surfaces = theme.extension<GullifySurfaces>();
    final light = theme.colorScheme.brightness == Brightness.light;
    final sigma = surfaces?.blurSigma ?? 30;
    final vibrancy = surfaces?.vibrancy ?? 1.0;

    Widget clip(Widget child) => circle
        ? ClipOval(child: child)
        : ClipRSuperellipse(
            borderRadius: BorderRadius.circular(radius),
            child: child,
          );

    final fill = DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: light ? _lightFill : _darkFill,
        ),
      ),
    );

    return DecoratedBox(
      // L'ombre d'Apple est large et basse : elle décolle la lentille du fond
      // sans jamais se voir comme un trait.
      decoration: BoxDecoration(
        shape: circle ? BoxShape.circle : BoxShape.rectangle,
        boxShadow: [
          BoxShadow(
            color: Color(light ? 0x1A0B1020 : 0x40000000),
            blurRadius: circle ? 18 : 40,
            offset: Offset(0, circle ? 6 : 16),
          ),
        ],
      ),
      child: Stack(
        // passthrough : le contenu reçoit les contraintes du parent telles
        // quelles, comme dans GlassBox. Sans ça, une barre à largeur imposée
        // se replierait sur son contenu — la mise en page doit rester au
        // pixel près celle des autres habillages.
        fit: StackFit.passthrough,
        children: [
          // La vitre elle-même, derrière le contenu.
          Positioned.fill(
            child: clip(
              blur
                  ? BackdropFilter(
                      // Vibrancy : ce qu'on voit au travers est ravivé, pas
                      // délavé — c'est ce qui sépare le verre d'un voile.
                      filter: ImageFilter.compose(
                        outer: ColorFilter.matrix(saturationMatrix(vibrancy)),
                        inner: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
                      ),
                      child: fill,
                    )
                  : DecoratedBox(
                      decoration: BoxDecoration(
                        color: light ? _lightScrim : _darkScrim,
                      ),
                      child: fill,
                    ),
            ),
          ),
          // Le contenu : c'est lui qui donne sa taille au Stack.
          clip(child),
          // Le liseré passe PAR-DESSUS : une arête de verre n'est pas cachée
          // par ce qu'elle contient.
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _SpecularRim(
                  radius: radius,
                  circle: circle,
                  light: light,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Matrice de saturation (identité à 1.0), coefficients de luminance Rec. 709
/// — c'est le `saturate()` de CSS, celui qui donne la vibrancy d'Apple.
List<double> saturationMatrix(double amount) {
  const lr = 0.2126, lg = 0.7152, lb = 0.0722;
  final s = amount;
  return <double>[
    lr + s * (1 - lr), lg * (1 - s), lb * (1 - s), 0, 0,
    lr * (1 - s), lg + s * (1 - lg), lb * (1 - s), 0, 0,
    lr * (1 - s), lg * (1 - s), lb + s * (1 - lb), 0, 0,
    0, 0, 0, 1, 0,
  ];
}

/// Le liseré qui fait la lentille : vif en haut à gauche (d'où vient la
/// lumière), presque éteint au milieu, repris en bas à droite — le verre
/// renvoie la lumière deux fois, une par arête.
class _SpecularRim extends CustomPainter {
  const _SpecularRim({
    required this.radius,
    required this.circle,
    required this.light,
  });

  final double radius;
  final bool circle;
  final bool light;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final stroke = circle ? 1.0 : 1.2;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Colors.white.withValues(alpha: light ? 0.95 : 0.72),
          Colors.white.withValues(alpha: light ? 0.22 : 0.10),
          Colors.white.withValues(alpha: light ? 0.60 : 0.38),
        ],
        stops: const [0, 0.55, 1],
      ).createShader(rect);

    final inner = rect.deflate(stroke / 2);
    if (circle) {
      canvas.drawOval(inner, paint);
    } else {
      canvas.drawPath(
        RoundedSuperellipseBorder(
          borderRadius: BorderRadius.circular(radius),
        ).getOuterPath(inner),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_SpecularRim old) =>
      old.radius != radius || old.circle != circle || old.light != light;
}
