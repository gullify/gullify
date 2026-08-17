import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart' as lg;

import '../theme.dart';

/// La MATIÈRE du thème « Apple Liquid Glass » (idées #98, #99, #105 et #106).
///
/// Gullify a toujours eu du verre ; celui d'Apple (iOS 26) n'est pas la même
/// vitre. Ce qui le distingue tient en cinq choses :
///   1. il est BEAUCOUP plus fin — on lit au travers, la couleur du dessous
///      transparaît au lieu d'être masquée par un fond laiteux ;
///   2. il ravive ce qu'il laisse passer (vibrancy) : le flou sature les
///      couleurs du dessous au lieu de les délaver ;
///   3. ses ARÊTES accrochent la lumière — vive en haut à gauche, éteinte au
///      milieu, reprise en bas à droite : c'est ce liseré qui fait « une
///      lentille » plutôt que « un rectangle translucide » ;
///   4. ses angles sont des superellipses (le squircle), pas des quarts de
///      cercle ;
///   5. et surtout — c'est ce qui manquait (idée #105) — il RÉFRACTE : une
///      lentille ne floute pas ce qu'il y a derrière, elle le PLIE. Le fond
///      s'écrase et se décale sur le pourtour, les couleurs s'y séparent
///      comme dans un prisme. Sans ça, ce n'est qu'un rectangle flouté de
///      plus, aussi soigné soit son liseré.
///
/// Les quatre premières se peignent ici à la main. La cinquième demande un
/// shader qui échantillonne le fond pixel par pixel : c'est le paquet
/// `liquid_glass_widgets` (MIT, celui pointé par l'idée #105) qui la rend,
/// via `AdaptiveGlass` — il connaît les pièges de chaque moteur de rendu
/// (Impeller Vulkan/Metal, GLES à l'axe Y inversé, Skia, « transparence
/// réduite ») et retombe tout seul sur une vitre givrée là où le shader ne
/// peut pas tourner.
///
/// Idée #106 — « je ne vois aucune différence avec la dernière version » : la
/// réfraction du #105 tournait bel et bien, mais on la repeignait aussitôt.
/// Vitre + reflet rasant + éclat d'angle + tranche du liseré s'empilaient à
/// près de trois quarts d'opacité blanche DANS L'ANGLE HAUT-GAUCHE — c'est-à-
/// dire pile là où le shader resserre le fond et en sépare les couleurs. On
/// travaillait contre soi. Désormais, quand le shader tourne pour de vrai, la
/// peinture s'efface (elle ne garde que l'arête, celle qui découpe la surface
/// du fond) et le laisse se voir ; là où il ne peut pas tourner, la vitre
/// dessinée se peint en entier, comme avant.
///
/// Comme retro_chrome.dart, ce fichier ne peint qu'une matière : il ne décide
/// de rien. C'est theme.dart qui vient y chercher sa palette.

/// Le thème Apple Liquid Glass est-il levé ? (idée #98)
bool isLiquidSkin(BuildContext context) =>
    Theme.of(context).extension<GullifySurfaces>()?.liquid ?? false;

/// Le shader de réfraction peut-il tourner ici ? C'est le test qu'utilise
/// `AdaptiveGlass` lui-même pour choisir entre le rendu complet et sa vitre
/// givrée de secours. On le refait ici pour une raison précise (idée #106) :
/// quand le fond se plie VRAIMENT sous la surface, la peinture à la main doit
/// s'effacer pour le laisser voir — sinon on repeint par-dessus la seule
/// chose qui distingue une lentille d'un rectangle flouté.
bool lensRefracts() =>
    debugLensRefracts ?? ui.ImageFilter.isShaderFilterSupported;

/// Le banc d'essai tourne sous Skia : le shader n'y tourne JAMAIS, et sans
/// cette prise la moitié « réfractée » de la matière ne serait vérifiée par
/// aucun test — c'est pourtant celle qui se voit sur un téléphone.
@visibleForTesting
bool? debugLensRefracts;

/// Les couleurs de la vitre peinte à la main, celle des surfaces où le flou
/// est coupé (petits boutons, écrans hors shell) : sans fond flouté à plier,
/// le shader n'a rien à réfracter, alors la lentille se dessine.
///
/// Le verre clair : blanc lavé, presque rien (haut-gauche → bas-droite).
const _lightFill = [Color(0x54FFFFFF), Color(0x14FFFFFF)];

/// Le verre sombre : à peine blanchi — c'est le fond qui doit rester visible.
const _darkFill = [Color(0x24FFFFFF), Color(0x05FFFFFF)];

/// Le reflet qui glisse sur la moitié haute : une vitre penchée vers la
/// lumière n'est pas uniforme, elle a un éclat franc en haut et rien en bas.
const _lightGloss = [Color(0x59FFFFFF), Color(0x00FFFFFF)];
const _darkGloss = [Color(0x2EFFFFFF), Color(0x00FFFFFF)];

/// Les MÊMES couches, mais posées sur un fond que le shader a déjà plié
/// (idée #106). Là, la peinture n'a plus à faire le verre — elle a juste à ne
/// pas le cacher. Le blanc du haut-gauche montait à trois quarts d'opacité en
/// cumulant vitre + reflet + éclat : c'était exactement l'angle où le fond se
/// resserre et se sépare en couleurs. On le divise donc par trois, et ce qui
/// reste ne sert plus qu'à tenir la surface quand le fond derrière elle est
/// uni (une pochette noire, un aplat).
const _lightLensFill = [Color(0x1FFFFFFF), Color(0x0AFFFFFF)];
const _darkLensFill = [Color(0x12FFFFFF), Color(0x03FFFFFF)];
const _lightLensGloss = [Color(0x24FFFFFF), Color(0x00FFFFFF)];
const _darkLensGloss = [Color(0x14FFFFFF), Color(0x00FFFFFF)];

/// Ce qu'on glisse SOUS cette vitre-là : sans flou, la lisibilité ne tient
/// plus qu'à un fond un peu plus dense.
const _lightScrim = Color(0x80FFFFFF);
const _darkScrim = Color(0x800B0B10);

/// La teinte que le shader pose sur le fond réfracté : presque rien, parce
/// que la vitre peinte vient juste après y ajouter la sienne. Deux corps de
/// verre l'un sur l'autre feraient un panneau laiteux — l'inverse de l'idée.
const _lightTint = Color(0x0FE8EEFA);
const _darkTint = Color(0x0AFFFFFF);

/// L'épaisseur de la vitre, en pixels : c'est elle qui donne sa largeur à la
/// bande où le fond se plie. Un petit disque en a moins qu'un bandeau, sinon
/// la déformation lui mange tout l'intérieur.
///
/// Idée #106 : 22 px sur un bandeau de 62 ne pliaient qu'un tiers de sa
/// hauteur, et la peinture couvrait ce tiers. Une vitre plus épaisse creuse
/// une bande qu'on voit sans la chercher.
const _panelThickness = 30.0;
const _circleThickness = 14.0;

/// La dispersion du prisme (0 à 4 dans le paquet) : assez pour qu'une arête
/// irise sur un fond contrasté, pas au point de border l'écran de rouge.
const _dispersion = 0.6;

/// L'indice de réfraction, c'est-à-dire à quel point le fond se plie. 1.2 est
/// le maximum de l'échelle du paquet — Apple ne fait pas dans la demi-mesure.
const _refractiveIndex = 1.2;

/// L'ombre d'Apple : large et basse, elle décolle la lentille du fond d'écran
/// sans jamais se voir comme un trait. Le paquet la découpe à l'extérieur de
/// la vitre, pour que le verre ne floute pas sa propre ombre.
const _panelShadow = [
  BoxShadow(color: Color(0x260B1020), blurRadius: 52, offset: Offset(0, 22)),
];
const _circleShadow = [
  BoxShadow(color: Color(0x260B1020), blurRadius: 22, offset: Offset(0, 8)),
];

/// Panneau de verre façon Apple : fond réfracté et ravivé, teinte à peine
/// posée, liseré spéculaire, angles en superellipse.
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
    // Le fond va-t-il vraiment se plier sous cette surface-là ? Il y faut les
    // deux : un fond flouté en direct (donc le shell) ET un moteur capable de
    // faire tourner le shader. C'est ce booléen qui décide de tout ce qui
    // suit — peinture allégée et arête discrète d'un côté, vitre dessinée en
    // entier de l'autre.
    final refracting = blur && lensRefracts();

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
          colors: refracting
              ? (light ? _lightLensFill : _darkLensFill)
              : (light ? _lightFill : _darkFill),
        ),
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: const Alignment(0.35, 1),
            colors: refracting
                ? (light ? _lightLensGloss : _darkLensGloss)
                : (light ? _lightGloss : _darkGloss),
            stops: const [0, 0.55],
          ),
        ),
        // L'éclat : la tache de lumière dans l'angle haut-gauche, celle qui
        // trahit une surface bombée. Le clip de la lentille la découpe. Sur un
        // fond réfracté il ne reste qu'un souffle : le shader pose déjà le
        // sien, et deux taches de lumière l'une sur l'autre font un voile.
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(-0.9, -1.1),
              radius: circle ? 0.9 : 0.8,
              colors: [
                Colors.white.withValues(
                  alpha: refracting
                      ? (light ? 0.16 : 0.09)
                      : (light ? 0.45 : 0.22),
                ),
                Colors.white.withValues(alpha: 0),
              ],
            ),
          ),
        ),
      ),
    );

    // La vitre peinte : son dégradé, son reflet, son éclat d'angle et son
    // liseré. C'est elle qui donne sa matière à la surface, avec ou sans
    // shader — une barre qui ne tiendrait qu'au shader disparaîtrait sur le
    // moindre appareil où il ne tourne pas.
    final pane = Stack(
      // passthrough : le contenu reçoit les contraintes du parent telles
      // quelles, comme dans GlassBox. Sans ça, une barre à largeur imposée
      // se replierait sur son contenu — la mise en page doit rester au
      // pixel près celle des autres habillages.
      fit: StackFit.passthrough,
      children: [
        // La vitre elle-même, derrière le contenu. Sans flou, il n'y a rien
        // sous elle : la lisibilité ne tient plus alors qu'à un fond un peu
        // plus dense.
        Positioned.fill(
          child: clip(
            blur
                ? fill
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
                refracting: refracting,
              ),
            ),
          ),
        ),
      ],
    );

    // Ce qui manquait (idée #105) : la RÉFRACTION. Le shader lit le fond,
    // le plie sur le pourtour, en sépare les couleurs, puis la vitre peinte
    // se pose par-dessus. Il lui faut un fond à plier — donc le flou en
    // direct, donc le shell ; là où le flou est coupé (petits boutons,
    // écrans hors shell), il n'y a rien à réfracter et la vitre peinte tient
    // le rôle seule.
    if (blur) {
      return lg.AdaptiveGlass(
        shape: circle
            ? const lg.LiquidOval()
            : lg.LiquidRoundedSuperellipse(borderRadius: radius),
        // Le rendu complet : deux passes Impeller (flou puis réfraction).
        // AdaptiveGlass redescend tout seul sur le shader léger (Skia, web)
        // puis sur une simple vitre givrée (« transparence réduite »).
        quality: lg.GlassQuality.premium,
        settings: lg.LiquidGlassSettings(
          blur: sigma,
          thickness: circle ? _circleThickness : _panelThickness,
          glassColor: light ? _lightTint : _darkTint,
          // Vibrancy : ce qu'on voit au travers est ravivé, pas délavé —
          // c'est ce qui sépare le verre d'un voile.
          saturation: vibrancy,
          refractiveIndex: _refractiveIndex,
          chromaticAberration: _dispersion,
          // L'éclat du shader n'est plus bridé (idée #106) : c'est lui qui
          // sait où la lumière se prend dans une surface bombée — la peinture,
          // elle, ne peut que la supposer. Elle s'est donc effacée juste
          // au-dessus, et il reprend sa place.
          lightIntensity: 0.85,
          specularSharpness: lg.GlassSpecularSharpness.medium,
          shadow: circle ? _circleShadow : _panelShadow,
        ),
        child: pane,
      );
    }

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
      child: pane,
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
    this.refracting = false,
  });

  final double radius;
  final bool circle;
  final bool light;

  /// Le fond se plie-t-il sous cette surface ? (idée #106) La TRANCHE peinte
  /// occupait pile la bande où le shader resserre le fond : elle la recouvrait
  /// d'un blanc laiteux. Là où il tourne, on ne garde donc que l'ARÊTE — le
  /// trait qui découpe la lentille — et on laisse la tranche au shader, qui la
  /// creuse pour de vrai.
  final bool refracting;

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
    if (!refracting && size.shortestSide > 2 * (stroke + band)) {
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
    // Elle reste dans les deux cas — c'est elle qui se voit de loin, et sans
    // elle une barre finirait par se confondre avec ce qu'il y a dessous.
    canvas.drawPath(
      _outline(rect, stroke / 2),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..shader = rake(
          switch ((light, refracting)) {
            (true, false) => const [1.0, 0.24, 0.70],
            (true, true) => const [0.78, 0.14, 0.50],
            (false, false) => const [0.86, 0.12, 0.48],
            (false, true) => const [0.62, 0.07, 0.34],
          },
        ),
    );

  }

  @override
  bool shouldRepaint(_SpecularRim old) =>
      old.radius != radius ||
      old.circle != circle ||
      old.light != light ||
      old.refracting != refracting;
}
