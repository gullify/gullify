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

/// Le verre clair : blanc lavé, presque rien (haut-gauche → bas-droite).
/// Idée #99 : la vitre a encore maigri — à ces alphas, ce qu'on voit d'une
/// surface est surtout ce qu'il y a DERRIÈRE elle, ravivé par le flou.
const _lightFill = [Color(0x54FFFFFF), Color(0x14FFFFFF)];

/// Le verre sombre : à peine blanchi — c'est le fond qui doit rester visible.
const _darkFill = [Color(0x24FFFFFF), Color(0x05FFFFFF)];

/// Le reflet qui glisse sur la moitié haute : une vitre penchée vers la
/// lumière n'est pas uniforme, elle a un éclat franc en haut et rien en bas.
const _lightGloss = [Color(0x59FFFFFF), Color(0x00FFFFFF)];
const _darkGloss = [Color(0x2EFFFFFF), Color(0x00FFFFFF)];

/// Ce qu'on glisse SOUS le verre quand le flou est coupé (sur certains GPU le
/// BackdropFilter se peint en plein écran) : sans flou, la lisibilité ne tient
/// plus qu'à un fond un peu plus dense.
const _lightScrim = Color(0x80FFFFFF);
const _darkScrim = Color(0x800B0B10);

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

    // La vitre : un dégradé qui s'efface vers le bas-droite, et par-dessus le
    // reflet de la lumière rasante (idée #99). Le reflet est DANS le verre,
    // donc sous le contenu — sinon il voilerait le texte.
    final fill = DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: light ? _lightFill : _darkFill,
        ),
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: const Alignment(0.35, 1),
            colors: light ? _lightGloss : _darkGloss,
            stops: const [0, 0.55],
          ),
        ),
        // L'éclat : la tache de lumière dans l'angle haut-gauche, celle qui
        // trahit une surface bombée. Le clip de la lentille la découpe.
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(-0.9, -1.1),
              radius: circle ? 0.9 : 0.8,
              colors: [
                Colors.white.withValues(alpha: light ? 0.45 : 0.22),
                Colors.white.withValues(alpha: 0),
              ],
            ),
          ),
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
            color: Color(light ? 0x260B1020 : 0x59000000),
            blurRadius: circle ? 22 : 52,
            offset: Offset(0, circle ? 8 : 22),
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

/// Le FOND D'ÉCRAN du thème (idée #99).
///
/// C'est la moitié qui manquait à l'idée #98. Une lentille ne se voit que sur
/// quelque chose : posée sur le gris perle de Gullify, la vitre la plus fine
/// ne rend qu'un gris — d'où « je ne vois même pas la différence ». Chez
/// Apple, le verre vit sur un fond d'écran ; ici le fond devient donc large,
/// coloré et franc, dérivé de l'accent choisi (l'accent reste le patron, il
/// n'est pas confisqué : les autres halos sont sa teinte tournée). Chaque
/// surface a enfin quelque chose à laisser passer, à flouter et à raviver.
class LiquidWallpaper extends StatelessWidget {
  const LiquidWallpaper({
    super.key,
    required this.accent,
    required this.dark,
  });

  final Color accent;
  final bool dark;

  /// Un halo : l'accent tourné de [turn] degrés, ramené à une clarté tenue
  /// (pastel en clair, profond en sombre) — assez franc pour se voir au
  /// travers du verre, assez sage pour que l'encre reste lisible dessus.
  Color _halo(double turn, double alpha) {
    final hsl = HSLColor.fromColor(accent);
    return hsl
        .withHue((hsl.hue + turn) % 360)
        .withSaturation((hsl.saturation * (dark ? 1.0 : 0.95)).clamp(0.35, 1))
        .withLightness(dark ? 0.45 : 0.63)
        .toColor()
        .withValues(alpha: alpha);
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final w = constraints.maxWidth, h = constraints.maxHeight;
      if (!w.isFinite || !h.isFinite) return const SizedBox.shrink();

      /// Un halo centré en ([fx], [fy]) — fractions de l'écran, débordements
      /// compris — d'un diamètre donné en largeurs d'écran.
      Widget halo(double fx, double fy, double size, double turn, double a) {
        final d = w * size;
        return Positioned(
          left: w * fx - d / 2,
          top: h * fy - d / 2,
          width: d,
          height: d,
          child: DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                // La couleur tient jusqu'à mi-rayon avant de s'éteindre :
                // un halo qui s'efface dès son centre ne teinte rien.
                colors: [_halo(turn, a), _halo(turn, a * 0.62), _halo(turn, 0)],
                stops: const [0, 0.5, 1],
              ),
            ),
          ),
        );
      }

      return Stack(
        children: [
          halo(0.02, 0.01, 1.5, 0, dark ? 0.62 : 0.50),
          halo(1.02, 0.24, 1.15, 52, dark ? 0.55 : 0.44),
          halo(-0.1, 0.62, 1.3, -62, dark ? 0.52 : 0.40),
          // Les teintes restent voisines de l'accent (au plus un quart de
          // roue) : un fond d'écran, pas un arc-en-ciel.
          halo(0.92, 1.0, 1.45, 92, dark ? 0.58 : 0.46),
        ],
      );
    },
  );
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
///
/// Idée #99 : l'arête a été franchement accentuée, parce que c'est elle qui
/// se voit de loin. Elle se peint maintenant en deux temps : la TRANCHE
/// (bande intérieure large et diffuse : l'épaisseur de la vitre, là où la
/// lumière se plie avant de ressortir) puis l'ARÊTE (le trait net, deux fois
/// plus épais qu'avant). L'éclat d'angle, lui, est peint DANS le verre (sous
/// le contenu) — une tache de lumière par-dessus le texte le voilerait.
class _SpecularRim extends CustomPainter {
  const _SpecularRim({
    required this.radius,
    required this.circle,
    required this.light,
  });

  final double radius;
  final bool circle;
  final bool light;

  /// Le contour de la lentille, rétréci de [inset] : disque ou superellipse.
  Path _outline(Rect rect, double inset) {
    final r = rect.deflate(inset);
    if (circle) return Path()..addOval(r);
    return RoundedSuperellipseBorder(
      borderRadius: BorderRadius.circular((radius - inset).clamp(0, radius)),
    ).getOuterPath(r);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final stroke = circle ? 1.6 : 2.4;
    final band = circle ? 3.5 : 7.0;

    Shader rake(List<double> alphas) => LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        for (final a in alphas) Colors.white.withValues(alpha: a),
      ],
      stops: const [0, 0.55, 1],
    ).createShader(rect);

    // 1. La tranche : large, tenue, juste à l'intérieur de l'arête.
    if (size.shortestSide > 2 * (stroke + band)) {
      canvas.drawPath(
        _outline(rect, stroke + band / 2),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = band
          ..shader = rake(
            light
                ? const [0.34, 0.06, 0.20]
                : const [0.20, 0.03, 0.12],
          ),
      );
    }

    // 2. L'arête elle-même : le trait net qui découpe la lentille du fond.
    canvas.drawPath(
      _outline(rect, stroke / 2),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..shader = rake(
          light ? const [1.0, 0.24, 0.70] : const [0.86, 0.12, 0.48],
        ),
    );

  }

  @override
  bool shouldRepaint(_SpecularRim old) =>
      old.radius != radius || old.circle != circle || old.light != light;
}
