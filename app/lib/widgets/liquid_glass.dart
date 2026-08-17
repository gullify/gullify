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
/// Idée #107 — « la dernière version est terrible, je veux garder la
/// disposition, le problème c'est l'esthétique ». La disposition ne bouge donc
/// pas d'un pixel ici : c'est la MATIÈRE qu'on reprend, et elle se reprend
/// contre trois excès du #106, tous mesurables face aux valeurs iOS 26 que le
/// moteur publie lui-même (`GlassDefaults`, `GlassShadow`) :
///   1. le GIVRE. On floutait à 28 quand le moteur travaille entre 3 et 10.
///      Un fond réduit en purée n'a plus de matière à plier : la lentille
///      n'avait plus rien à réfracter et redevenait le panneau laiteux qu'on
///      lui reproche. C'est la réfraction qui fait le verre, pas le sigma —
///      la lisibilité, elle, passe maintenant par `whitenStrength`, le voile
///      de lisibilité d'iOS 26 (uniforme, et qui laisse l'encre nette).
///   2. l'OMBRE. 52 px de flou, 22 px de décalage, 15 % de noir sous CHAQUE
///      vitre — contre 6 %, 8 px et 2 px chez Apple. Chaque barre traînait un
///      halo gris ; on reprend l'ombre du moteur, découpée hors du verre.
///   3. la QUALITÉ. Le rendu « premium » échantillonne le fond dans une
///      texture (`toImageSync`) : le paquet le réserve explicitement aux
///      surfaces STATIQUES, parce que dans une liste qui défile la capture
///      montre un fond en retard. Il reste donc pour les barres, le lecteur
///      et les boutons flottants ; ce qui vit dans un défilement passe au
///      rendu « standard », calibré pour ça.
/// Et l'épaisseur, le prisme et l'éclat redescendent aux valeurs de la
/// matière (20 px, 0,2, 0,55) : poussés à fond, ils ne font pas « plus de
/// verre », ils font du plastique irisé.
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

/// Ce que le moteur a DÉJÀ posé sous la peinture — donc ce qu'il reste à
/// peindre (idée #107). Le #106 ne connaissait que deux cas ; il en manquait
/// un, et c'était le pire : sur un appareil sans shader, le moteur pose quand
/// même une vitre givrée, et on repeignait par-dessus la lentille COMPLÈTE.
/// Deux corps de verre l'un sur l'autre : le panneau blanc opaque.
enum _Pane {
  /// Le shader a plié le fond : la peinture n'a plus qu'à ne pas le cacher.
  lens,

  /// Pas de shader ici, mais le moteur a givré et cerclé la surface : la
  /// peinture ne fait que l'appuyer.
  frost,

  /// Rien dessous — le flou est coupé (petits boutons, écrans hors shell) :
  /// la lentille se dessine en entier, fond dense compris.
  painted,
}

/// La vitre peinte, du haut-gauche au bas-droite. Trois densités, une par
/// couche déjà présente dessous.
List<Color> _fillOf(_Pane pane, bool light) => switch ((pane, light)) {
  (_Pane.lens, true) => const [Color(0x1FFFFFFF), Color(0x0AFFFFFF)],
  (_Pane.lens, false) => const [Color(0x12FFFFFF), Color(0x03FFFFFF)],
  (_Pane.frost, true) => const [Color(0x2EFFFFFF), Color(0x0EFFFFFF)],
  (_Pane.frost, false) => const [Color(0x18FFFFFF), Color(0x04FFFFFF)],
  (_Pane.painted, true) => const [Color(0x54FFFFFF), Color(0x14FFFFFF)],
  (_Pane.painted, false) => const [Color(0x24FFFFFF), Color(0x05FFFFFF)],
};

/// Le reflet qui glisse sur la moitié haute : une vitre penchée vers la
/// lumière n'est pas uniforme, elle a un éclat franc en haut et rien en bas.
List<Color> _glossOf(_Pane pane, bool light) => switch ((pane, light)) {
  (_Pane.lens, true) => const [Color(0x1FFFFFFF), Color(0x00FFFFFF)],
  (_Pane.lens, false) => const [Color(0x12FFFFFF), Color(0x00FFFFFF)],
  (_Pane.frost, true) => const [Color(0x33FFFFFF), Color(0x00FFFFFF)],
  (_Pane.frost, false) => const [Color(0x1CFFFFFF), Color(0x00FFFFFF)],
  (_Pane.painted, true) => const [Color(0x4DFFFFFF), Color(0x00FFFFFF)],
  (_Pane.painted, false) => const [Color(0x2EFFFFFF), Color(0x00FFFFFF)],
};

/// L'éclat d'angle : la tache de lumière qui trahit une surface bombée. Là où
/// le moteur pose déjà la sienne, il n'en reste qu'un souffle — deux taches
/// l'une sur l'autre font un voile, pas du verre.
double _sheenOf(_Pane pane, bool light) => switch ((pane, light)) {
  (_Pane.lens, true) => 0.14,
  (_Pane.lens, false) => 0.08,
  (_Pane.frost, true) => 0.26,
  (_Pane.frost, false) => 0.14,
  (_Pane.painted, true) => 0.38,
  (_Pane.painted, false) => 0.20,
};

/// Ce qu'on glisse SOUS la vitre dessinée : sans flou, la lisibilité ne tient
/// plus qu'à un fond un peu plus dense.
const _lightScrim = Color(0x80FFFFFF);
const _darkScrim = Color(0x800B0B10);

/// La teinte du corps de verre. Le givre ayant beaucoup baissé (idée #107),
/// c'est elle — avec le voile de lisibilité — qui tient le texte au-dessus
/// d'un fond chargé. En sombre, le verre d'iOS 26 est sombre : un tint blanc
/// éclaircissait une matière qui doit assombrir.
const _lightTint = Color(0x1AF2F6FF);
const _darkTint = Color(0x1F0C0C14);

/// Le voile de lisibilité d'iOS 26 (`whitenStrength`), en clair seulement :
/// le verre fini est tiré vers le blanc d'un seul tenant, sans couture ni
/// halo, et le gate de luminance laisse l'encre nette. C'est ce qui remplace
/// le flou de 28 — Apple lit au travers, il ne masque pas.
const _whiten = 0.12;

/// L'épaisseur de la vitre, en pixels : c'est elle qui donne sa largeur à la
/// bande où le fond se plie. Un petit disque en a moins qu'un bandeau, sinon
/// la déformation lui mange tout l'intérieur.
///
/// Idée #107 : 30 px sur un bandeau de 62 tordaient la barre entière, bord à
/// bord — il ne restait plus un pixel de fond droit au milieu. 20 px (la
/// valeur de la matière) creusent le pourtour et laissent le centre tranquille.
const _panelThickness = 20.0;
const _circleThickness = 12.0;

/// La dispersion du prisme (0 à 4 dans le paquet, qui la donne lui-même pour
/// « encore un peu moche » au-delà) : de quoi iriser une arête sur un fond
/// contrasté. À 0,6, toutes les arêtes de l'app se bordaient de couleur.
const _dispersion = 0.2;

/// L'indice de réfraction, c'est-à-dire à quel point le fond se plie : la
/// valeur d'iOS 26 du paquet, pas le maximum de l'échelle.
const _refractiveIndex = 1.15;

/// La lumière du moteur. À 0,85 avec zéro ambiante, les arêtes viraient au
/// trait blanc dur ; l'ambiante et l'anneau de Fresnel rendent le pourtour
/// lumineux tout autour, comme la pilule d'iOS 26, sans ce contraste-là.
const _lightIntensity = 0.55;
const _ambient = 0.12;
const _ambientRim = 0.08;

/// L'ombre d'iOS 26, telle que le moteur la publie : 6 % de noir, 8 px de
/// flou, 2 px plus bas. Elle décolle la lentille du fond d'écran sans jamais
/// se voir — et le paquet la découpe hors de la vitre, pour que le verre ne
/// floute pas sa propre ombre. (Idée #107 : la nôtre faisait 52 px de flou et
/// 22 px de décalage sous chaque barre. C'étaient des taches grises.)
const _shadowElevation = 1.0;

/// La même, à peindre nous-mêmes là où le moteur n'intervient pas (flou
/// coupé). En sombre, iOS 26 ne pose pas d'ombre sur le verre ; un disque
/// posé sur une pochette, lui, a besoin d'un contact pour ne pas y coller.
const _paintedPanelShadow = [
  BoxShadow(color: Color(0x14000000), blurRadius: 10, offset: Offset(0, 3)),
];
const _paintedCircleShadow = [
  BoxShadow(color: Color(0x1F000000), blurRadius: 6, offset: Offset(0, 2)),
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
    final sigma = surfaces?.blurSigma ?? 10;
    final vibrancy = surfaces?.vibrancy ?? 1.5;
    // Qu'y a-t-il déjà sous la peinture ? Sans flou, rien du tout : le moteur
    // n'est même pas appelé, la lentille se dessine en entier. Avec, il pose
    // sa vitre — le fond plié quand le shader tourne, une vitre givrée sinon
    // — et la peinture n'a plus qu'à l'appuyer sans la cacher.
    final beneath = !blur
        ? _Pane.painted
        : (lensRefracts() ? _Pane.lens : _Pane.frost);

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
          colors: _fillOf(beneath, light),
        ),
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: const Alignment(0.35, 1),
            colors: _glossOf(beneath, light),
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
                Colors.white.withValues(alpha: _sheenOf(beneath, light)),
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
                pane: beneath,
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
        // Le rendu complet (deux passes Impeller : flou puis réfraction) ne
        // vaut que pour une surface qui NE BOUGE PAS — il échantillonne le
        // fond dans une texture, et dans un défilement cette capture montre
        // ce qui était là juste avant (idée #107). Les barres, le lecteur et
        // les boutons flottants y ont droit ; une carte de liste passe au
        // rendu standard, calibré pour ça. AdaptiveGlass redescend ensuite
        // tout seul jusqu'à la vitre givrée là où rien ne peut tourner.
        quality: Scrollable.maybeOf(context) == null
            ? lg.GlassQuality.premium
            : lg.GlassQuality.standard,
        settings: lg.LiquidGlassSettings(
          blur: sigma,
          thickness: circle ? _circleThickness : _panelThickness,
          glassColor: light ? _lightTint : _darkTint,
          // Vibrancy : ce qu'on voit au travers est ravivé, pas délavé —
          // c'est ce qui sépare le verre d'un voile.
          saturation: vibrancy,
          refractiveIndex: _refractiveIndex,
          chromaticAberration: _dispersion,
          // La lumière du verre : une ambiante douce et l'anneau de Fresnel
          // font le pourtour lumineux d'iOS 26 ; un éclat seul, poussé sans
          // ambiante, ne faisait qu'un trait blanc dur (idée #107).
          lightIntensity: _lightIntensity,
          ambientStrength: _ambient,
          ambientRim: _ambientRim,
          specularSharpness: lg.GlassSpecularSharpness.medium,
          // Le voile de lisibilité d'iOS 26, en clair : il remplace le givre
          // qu'on a rendu au fond d'écran.
          whitenStrength: light ? _whiten : 0,
          // Et l'ombre du moteur, celle d'Apple, à la place de la nôtre.
          shadowElevation: _shadowElevation,
        ),
        child: pane,
      );
    }

    return DecoratedBox(
      // Ici le moteur n'intervient pas : l'ombre d'iOS 26 se peint à la main,
      // douce et proche — juste de quoi décoller la lentille du fond.
      decoration: BoxDecoration(
        shape: circle ? BoxShape.circle : BoxShape.rectangle,
        boxShadow: circle ? _paintedCircleShadow : _paintedPanelShadow,
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
          halo(0.02, 0.01, 1.5, 0, dark ? 0.62 : 0.46),
          halo(1.02, 0.24, 1.15, 34, dark ? 0.55 : 0.40),
          halo(-0.1, 0.62, 1.3, -40, dark ? 0.52 : 0.36),
          // Idée #107 : les teintes se resserrent encore (un dixième de roue
          // au lieu d'un quart). Quatre couleurs franches et distinctes sous
          // du verre, ça n'est pas un fond d'écran d'Apple — c'est un
          // arc-en-ciel, et c'est lui qui salissait les vitres au-dessus.
          halo(0.92, 1.0, 1.45, 62, dark ? 0.58 : 0.42),
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
    this.pane = _Pane.painted,
  });

  final double radius;
  final bool circle;
  final bool light;

  /// Ce que le moteur a déjà posé dessous (idée #106). La TRANCHE peinte
  /// occupait pile la bande où le shader resserre le fond : elle la recouvrait
  /// d'un blanc laiteux. Dès que le moteur cercle la surface lui-même, on ne
  /// garde donc que l'ARÊTE — le trait qui découpe la lentille — et on lui
  /// laisse la tranche, qu'il creuse pour de vrai.
  final _Pane pane;

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
    if (pane == _Pane.painted && size.shortestSide > 2 * (stroke + band)) {
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
    // Elle reste dans tous les cas — c'est elle qui se voit de loin, et sans
    // elle une barre finirait par se confondre avec ce qu'il y a dessous.
    // Idée #107 : elle ne monte plus au blanc pur, même seule. Une arête à
    // fond, c'est un contour de plastique ; le verre, lui, s'éteint au milieu
    // et se reprend en bas — c'est le DÉGRADÉ qui fait la lentille.
    canvas.drawPath(
      _outline(rect, stroke / 2),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..shader = rake(
          switch ((light, pane)) {
            (true, _Pane.painted) => const [0.86, 0.20, 0.58],
            (true, _Pane.frost) => const [0.70, 0.14, 0.46],
            (true, _Pane.lens) => const [0.52, 0.10, 0.34],
            (false, _Pane.painted) => const [0.76, 0.10, 0.42],
            (false, _Pane.frost) => const [0.58, 0.07, 0.32],
            (false, _Pane.lens) => const [0.44, 0.05, 0.24],
          },
        ),
    );

  }

  @override
  bool shouldRepaint(_SpecularRim old) =>
      old.radius != radius ||
      old.circle != circle ||
      old.light != light ||
      old.pane != pane;
}
