// Le thème « Apple Liquid Glass » (idée #98). Ce qui compte ici, comme pour
// le rétro : qu'il soit VRAIMENT à part (le verre de Gullify ne bouge pas
// d'un pixel quand il est éteint) et qu'il se reconnaisse à ce qui fait un
// Liquid Glass d'Apple — une vitre bien plus fine, un flou plus profond qui
// ravive les couleurs, des arêtes qui accrochent la lumière et des angles en
// superellipse.
//
// À la différence de Winamp, il garde l'accent choisi et le clair/sombre :
// chez Apple, le verre est une matière, pas une palette.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart' as lg;
import 'package:gullify/theme.dart';
import 'package:gullify/widgets/glass_box.dart';
import 'package:gullify/widgets/glass_kit.dart';
import 'package:gullify/widgets/liquid_glass.dart';

void main() {
  ThemeData apple({bool dark = false}) =>
      gullifyTheme(GullifySkin.apple, GullifyAccent.indigo, dark: dark);
  ThemeData glass({bool dark = false}) =>
      gullifyTheme(GullifySkin.glass, GullifyAccent.indigo, dark: dark);
  ThemeData retro() =>
      gullifyTheme(GullifySkin.winamp, GullifyAccent.indigo, dark: true);

  GullifySurfaces surfaces(ThemeData theme) =>
      theme.extension<GullifySurfaces>()!;

  group('le thème Apple Liquid Glass', () {
    test('lève son drapeau, et lui seul', () {
      expect(surfaces(apple()).liquid, isTrue);
      expect(surfaces(apple()).retro, isFalse);
      // Le verre reste du verre : le flou est bien réel.
      expect(surfaces(apple()).frosted, isTrue);
      // …et rien de tout cela ne déteint sur les autres habillages.
      expect(surfaces(glass()).liquid, isFalse);
      expect(surfaces(retro()).liquid, isFalse);
    });

    test('une vitre plus fine, un givre qui laisse lire dessous', () {
      // Plus transparente : c'est LA différence qu'on voit d'abord. Idée #99 :
      // « je ne vois même pas la différence » — donc pas « un peu plus fine »,
      // deux fois moins dense au minimum.
      double alpha(ThemeData theme) => surfaces(theme).barColor!.a;
      expect(alpha(apple()), lessThan(alpha(glass()) / 2));
      expect(alpha(apple(dark: true)), lessThan(alpha(glass(dark: true)) / 2));
      // Idée #105 puis #107 : c'est la réfraction qui fait la matière, pas le
      // sigma — et un fond effacé n'a plus rien à plier. Le givre descend donc
      // SOUS le nôtre, dans la fourchette où le moteur travaille (3 à 10) ;
      // au-dessus, la lentille n'a plus qu'un aplat à réfracter et redevient
      // le panneau laiteux qu'on lui reproche depuis le début.
      expect(
        surfaces(apple()).blurSigma,
        lessThan(surfaces(glass()).blurSigma),
      );
      expect(surfaces(apple()).blurSigma, lessThanOrEqualTo(10));
      // Les couleurs du dessous restent ravivées — mais au 1,5 de la matière :
      // à 1,8 le moindre halo virait au fluo sous la vitre.
      expect(surfaces(apple()).vibrancy, greaterThan(1.0));
      expect(surfaces(apple()).vibrancy, lessThanOrEqualTo(1.5));
      expect(surfaces(glass()).vibrancy, 1.0);
    });

    test('garde l\'accent choisi et le clair/sombre', () {
      for (final accent in GullifyAccent.values) {
        expect(
          gullifyTheme(GullifySkin.apple, accent, dark: false)
              .colorScheme
              .primary,
          accent.color,
        );
      }
      expect(apple().colorScheme.brightness, Brightness.light);
      expect(apple(dark: true).colorScheme.brightness, Brightness.dark);
    });

    test('des angles en superellipse, plus généreux que les nôtres', () {
      final card = apple().cardTheme.shape!;
      expect(card, isA<RoundedSuperellipseBorder>());
      double corner(ShapeBorder shape) => switch (shape) {
        RoundedSuperellipseBorder(:final borderRadius) =>
          (borderRadius as BorderRadius).topLeft.x,
        RoundedRectangleBorder(:final borderRadius) =>
          (borderRadius as BorderRadius).topLeft.x,
        _ => 0,
      };
      expect(corner(card), greaterThan(corner(glass().cardTheme.shape!)));
      // Les boutons pleins sont des gélules, comme sur iOS.
      final button = apple().filledButtonTheme.style!.shape!.resolve({});
      expect(button, isA<StadiumBorder>());
    });

  });

  // Idée #105 : « ton liquid glass est pas vrmt ça encore ». Ce qui manquait
  // n'était ni le liseré ni la superellipse — c'était la RÉFRACTION. Une
  // lentille ne floute pas ce qu'il y a derrière, elle le plie et en sépare
  // les couleurs. Là où il y a un fond à plier (flou en direct), la matière
  // passe donc par le shader de liquid_glass_widgets.
  group('la lentille réfracte vraiment (idée #105)', () {
    Widget box(ThemeData theme) => MaterialApp(
      theme: theme,
      home: const Scaffold(
        body: Center(
          child: GlassBox(
            radius: 20,
            child: SizedBox(width: 160, height: 80),
          ),
        ),
      ),
    );

    testWidgets('le fond passe par le shader, pas par un simple flou',
        (tester) async {
      await tester.pumpWidget(box(apple()));
      await tester.pump(const Duration(milliseconds: 500));

      final lens = tester.widget<lg.AdaptiveGlass>(find.byType(lg.AdaptiveGlass));
      // Le rendu complet : c'est lui, et lui seul, qui échantillonne le fond.
      expect(lens.quality, lg.GlassQuality.premium);
      // Le fond se plie, et les couleurs s'y séparent comme dans un prisme.
      expect(lens.settings.refractiveIndex, greaterThan(1.0));
      expect(lens.settings.chromaticAberration, greaterThan(0.0));
      // Une vitre a une épaisseur : c'est elle qui donne sa largeur à la
      // bande où le fond se plie.
      expect(lens.settings.thickness, greaterThan(0.0));
      // Le thème reste le patron : le givre et la vibrancy viennent de lui.
      expect(lens.settings.blur, surfaces(apple()).blurSigma);
      expect(lens.settings.saturation, surfaces(apple()).vibrancy);
      // Et l'angle reste une superellipse.
      expect(lens.shape, isA<lg.LiquidRoundedSuperellipse>());
      expect(
        (lens.shape as lg.LiquidRoundedSuperellipse).borderRadius,
        20,
      );
    });

    testWidgets('le bouton rond réfracte en disque', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: apple(),
          home: const Scaffold(
            body: Center(
              child: LiquidGlass(
                circle: true,
                child: SizedBox(width: 44, height: 44),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));
      expect(
        tester.widget<lg.AdaptiveGlass>(find.byType(lg.AdaptiveGlass)).shape,
        isA<lg.LiquidOval>(),
      );
    });

    testWidgets('sans flou, la vitre reste peinte à la main', (tester) async {
      // Petits boutons, écrans hors shell : pas de BackdropFilter, donc aucun
      // fond à réfracter. Inutile d'allumer un shader pour ne plier que du
      // vide — c'est la lentille dessinée qui tient le rôle.
      await tester.pumpWidget(
        MaterialApp(
          theme: apple(),
          home: const Scaffold(
            body: Center(
              child: GlassBox(
                radius: 20,
                blur: false,
                child: SizedBox(width: 160, height: 80),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(lg.AdaptiveGlass), findsNothing);
      expect(find.byType(LiquidGlass), findsOneWidget);
    });

    testWidgets('le verre de Gullify n\'y touche pas', (tester) async {
      await tester.pumpWidget(box(glass()));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(lg.AdaptiveGlass), findsNothing);
    });
  });

  group('les surfaces communes suivent l\'habillage', () {
    Widget box(ThemeData theme) => MaterialApp(
      theme: theme,
      home: const Scaffold(
        body: Center(
          child: GlassBox(
            radius: 20,
            blur: false,
            child: SizedBox(width: 120, height: 60),
          ),
        ),
      ),
    );

    testWidgets('Apple : une lentille en superellipse, cerclée de lumière',
        (tester) async {
      await tester.pumpWidget(box(apple()));
      expect(find.byType(LiquidGlass), findsOneWidget);
      // L'angle n'est pas un quart de cercle mais un squircle.
      expect(
        find.descendant(
          of: find.byType(LiquidGlass),
          matching: find.byType(ClipRSuperellipse),
        ),
        findsWidgets,
      );
      // Le liseré spéculaire est peint par-dessus le contenu.
      expect(
        find.descendant(
          of: find.byType(LiquidGlass),
          matching: find.byType(CustomPaint),
        ),
        findsWidgets,
      );
      // La vitre est un dégradé (haut-gauche plus dense que bas-droite) et
      // reste très transparente : on doit lire au travers.
      final fill = tester
          .widgetList<DecoratedBox>(
            find.descendant(
              of: find.byType(LiquidGlass),
              matching: find.byType(DecoratedBox),
            ),
          )
          .map((d) => d.decoration)
          .whereType<BoxDecoration>()
          .map((d) => d.gradient)
          .whereType<LinearGradient>()
          .first;
      expect(fill.colors.first.a, greaterThan(fill.colors.last.a));
      for (final color in fill.colors) {
        // Idée #99 : la vitre a encore maigri — à ce point, ce qu'on voit
        // d'une surface est surtout ce qu'il y a derrière elle.
        expect(color.a, lessThan(0.35));
      }
    });

    testWidgets('la lentille a un reflet et un éclat, pas qu\'une arête',
        (tester) async {
      await tester.pumpWidget(box(apple()));
      final layers = tester
          .widgetList<DecoratedBox>(
            find.descendant(
              of: find.byType(LiquidGlass),
              matching: find.byType(DecoratedBox),
            ),
          )
          .map((d) => d.decoration)
          .whereType<BoxDecoration>()
          .map((d) => d.gradient)
          .nonNulls
          .toList();
      // La vitre, le reflet rasant, l'éclat d'angle (idée #99) : trois
      // couches, sinon la « transparence très accentuée » n'est qu'un aplat
      // plus clair.
      expect(layers.whereType<LinearGradient>().length, greaterThanOrEqualTo(2));
      expect(layers.whereType<RadialGradient>(), isNotEmpty);
      // Le reflet vient d'en haut à gauche et s'éteint : jamais un voile.
      for (final layer in layers) {
        expect(layer.colors.last.a, lessThan(layer.colors.first.a));
      }
    });

    testWidgets('le verre de Gullify ne bouge pas d\'un pixel', (tester) async {
      await tester.pumpWidget(box(glass()));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(LiquidGlass), findsNothing);
      expect(find.byType(ClipRSuperellipse), findsNothing);
      // La bordure de toujours : uniforme, pas un liseré qui varie.
      final plate = tester
          .widgetList<Container>(find.byType(Container))
          .map((c) => c.decoration)
          .whereType<BoxDecoration>()
          .firstWhere((d) => d.border != null);
      final border = plate.border! as Border;
      expect(border.top.color, border.bottom.color);
    });

    testWidgets('le bouton rond devient un disque de verre', (tester) async {
      Future<void> pump(ThemeData theme) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            home: Scaffold(
              body: Center(
                child: GlassIconButton(
                  icon: Icons.arrow_back,
                  onPressed: () {},
                ),
              ),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 500));
      }

      await pump(apple());
      expect(find.byType(LiquidGlass), findsOneWidget);
      expect(tester.widget<LiquidGlass>(find.byType(LiquidGlass)).circle,
          isTrue);
      // Le bouton garde son diamètre : la matière change, pas la taille.
      expect(tester.getSize(find.byType(LiquidGlass)), const Size(44, 44));
      await pump(glass());
      expect(find.byType(LiquidGlass), findsNothing);
    });
  });

  // Idée #99 : le thème ne se voyait pas. Deux raisons, deux réponses — le
  // verre n'avait rien sous lui (voici le fond d'écran), et il ne couvrait
  // que le dock et le mini-lecteur (le voici sur toutes les surfaces).
  group('le fond d\'écran qui rend le verre visible (idée #99)', () {
    testWidgets('quatre halos larges, tous parents de l\'accent',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: LiquidWallpaper(accent: glassAccent, dark: false),
          ),
        ),
      );

      final halos = tester
          .widgetList<DecoratedBox>(
            find.descendant(
              of: find.byType(LiquidWallpaper),
              matching: find.byType(DecoratedBox),
            ),
          )
          .map((d) => (d.decoration as BoxDecoration).gradient)
          .whereType<RadialGradient>()
          .toList();
      expect(halos.length, 4);

      final accentHue = HSLColor.fromColor(glassAccent).hue;
      for (final halo in halos) {
        // Franc au centre, éteint au bord : un halo transparent ne teinte
        // rien, et c'est précisément ce qu'on reprochait au précédent.
        expect(halo.colors.first.a, greaterThan(0.3));
        expect(halo.colors.last.a, 0);
        // La teinte reste voisine de l'accent : un fond d'écran, pas un
        // arc-en-ciel — l'accent choisi reste le patron.
        final turn = (HSLColor.fromColor(halo.colors.first).hue - accentHue)
            .abs();
        expect(turn > 180 ? 360 - turn : turn, lessThanOrEqualTo(95));
      }

      // Larges : chacun déborde de l'écran, sinon on verrait des ronds.
      final screen = tester.getSize(find.byType(LiquidWallpaper));
      for (var i = 0; i < halos.length; i++) {
        expect(
          tester
              .getSize(
                find.descendant(
                  of: find.byType(LiquidWallpaper),
                  matching: find.byType(DecoratedBox),
                ).at(i),
              )
              .width,
          greaterThan(screen.width),
        );
      }
    });

    test('le verre déborde des barres : gélules, champs, feuilles', () {
      final theme = apple();
      // Les filtres, la recherche : la même vitre que les barres.
      expect(theme.chipTheme.backgroundColor!.a, lessThan(0.35));
      expect(theme.chipTheme.shape, isA<StadiumBorder>());
      expect(theme.inputDecorationTheme.fillColor!.a, lessThan(0.35));
      // Les feuilles et les alertes : du verre aussi, mais assez dense pour
      // qu'on lise — elles n'ont rien derrière elles.
      expect(theme.dialogTheme.backgroundColor!.a, lessThan(1.0));
      expect(theme.dialogTheme.shape, isA<RoundedSuperellipseBorder>());
      expect(theme.bottomSheetTheme.shape, isA<RoundedSuperellipseBorder>());
      // Et le verre de toujours ne change pas de tête pour autant.
      expect(glass().chipTheme.backgroundColor, isNull);
      expect(glass().dialogTheme.shape, isNull);
    });
  });

  // Idée #106 : « je ne vois aucune différence avec la dernière version ». La
  // réfraction du #105 tournait — on la repeignait aussitôt. Vitre, reflet,
  // éclat d'angle et tranche du liseré s'empilaient dans l'angle haut-gauche,
  // c'est-à-dire pile là où le shader resserre le fond. Là où il tourne, la
  // peinture doit donc s'effacer.
  group('la peinture s\'efface là où le fond se plie (idée #106)', () {
    tearDown(() => debugLensRefracts = null);

    /// Les dégradés de la vitre peinte : ceux qui vont du haut-gauche au
    /// bas-droite, en blanc — la couche de fond de la lentille.
    List<LinearGradient> paint(WidgetTester tester) => tester
        .widgetList<DecoratedBox>(
          find.descendant(
            of: find.byType(LiquidGlass),
            matching: find.byType(DecoratedBox),
          ),
        )
        .map((d) => d.decoration)
        .whereType<BoxDecoration>()
        .map((d) => d.gradient)
        .whereType<LinearGradient>()
        .where((g) =>
            g.begin == Alignment.topLeft && g.end == Alignment.bottomRight)
        .toList();

    Future<double> pump(
      WidgetTester tester, {
      required bool refracting,
      required bool blur,
    }) async {
      debugLensRefracts = refracting;
      await tester.pumpWidget(
        MaterialApp(
          key: ValueKey('$refracting-$blur'),
          theme: apple(),
          home: Scaffold(
            body: Center(
              child: GlassBox(
                radius: 20,
                blur: blur,
                child: const SizedBox(width: 160, height: 80),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));
      final fills = paint(tester);
      expect(fills, isNotEmpty);
      return fills.first.colors.first.a;
    }

    testWidgets('sur un fond réfracté, la vitre peinte devient un souffle',
        (tester) async {
      // La vitre dessinée en entier, c'est celle des surfaces sans flou : là,
      // rien ne se plie sous elle, elle fait tout le travail.
      final painted = await pump(tester, refracting: false, blur: false);
      final over = await pump(tester, refracting: true, blur: true);
      // Pas « un peu plus légère » : c'est le blanc cumulé de l'angle
      // haut-gauche qui effaçait la lentille, donc il faut qu'il tombe.
      expect(over, lessThan(painted / 2));
    });

    // Idée #107 : il manquait un cas, et c'était le pire. Sur un appareil où
    // le shader ne tourne pas, le moteur pose quand même sa vitre givrée — et
    // on repeignait la lentille COMPLÈTE par-dessus. Deux corps de verre l'un
    // sur l'autre : le panneau blanc opaque, exactement ce qu'on reproche.
    testWidgets('sans shader, on n\'empile plus deux vitres', (tester) async {
      final lens = await pump(tester, refracting: true, blur: true);
      final frost = await pump(tester, refracting: false, blur: true);
      final painted = await pump(tester, refracting: false, blur: false);
      // Trois densités, une par couche déjà présente dessous — et la givrée
      // est bien entre les deux, jamais la pleine peinture.
      expect(lens, lessThan(frost));
      expect(frost, lessThan(painted));
    });

    testWidgets('sans shader, la vitre se peint en entier — rien ne disparaît',
        (tester) async {
      // La sécurité du #105 : une barre qui ne tiendrait qu'au shader
      // s'évanouirait sur le premier appareil qui ne peut pas le faire
      // tourner. Sans flou (petits boutons, écrans hors shell) il n'y a de
      // toute façon rien à plier : la peinture reste pleine.
      final off = await pump(tester, refracting: false, blur: false);
      final on = await pump(tester, refracting: true, blur: false);
      expect(on, off);
      expect(on, greaterThan(0.3));
    });

  });

  // Idée #107 : « la dernière version est terrible, je veux garder la
  // disposition, le problème c'est l'esthétique ». Le #106 avait poussé tous
  // les curseurs à fond pour répondre au « je ne vois aucune différence » —
  // et un verre poussé à fond ne fait pas plus de verre, il fait du plastique
  // irisé sur fond de taches grises. La matière reprend les valeurs qu'iOS 26
  // se donne, celles que le moteur publie lui-même.
  group('la matière reprend les valeurs d\'iOS 26 (idée #107)', () {
    tearDown(() => debugLensRefracts = null);

    Future<lg.AdaptiveGlass> pump(
      WidgetTester tester, {
      Widget Function(Widget glass)? around,
    }) async {
      debugLensRefracts = true;
      const glass = GlassBox(
        radius: 20,
        child: SizedBox(width: 160, height: 80),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: apple(),
          home: Scaffold(
            body: around?.call(glass) ?? const Center(child: glass),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));
      return tester.widget<lg.AdaptiveGlass>(find.byType(lg.AdaptiveGlass));
    }

    testWidgets('l\'épaisseur, le prisme et la lumière redescendent',
        (tester) async {
      final lens = await pump(tester);
      // 30 px d'épaisseur tordaient un bandeau de 62 px bord à bord : il n'y
      // restait pas un pixel de fond droit. La bande se creuse au pourtour et
      // laisse le centre tranquille.
      expect(lens.settings.thickness, lessThanOrEqualTo(20));
      expect(lens.settings.thickness, greaterThan(0));
      // Le prisme redescend sous le réglage d'usine du moteur : de quoi iriser
      // une arête, pas border toute l'app de couleur.
      expect(lens.settings.chromaticAberration, lessThan(0.5));
      expect(lens.settings.chromaticAberration, greaterThan(0));
      // Un éclat poussé SANS ambiante ne fait pas une lentille, il fait un
      // trait blanc dur. La lumière baisse, l'ambiante et l'anneau de Fresnel
      // prennent le relais tout autour.
      expect(lens.settings.lightIntensity, lessThan(0.8));
      expect(lens.settings.ambientStrength, greaterThan(0));
      expect(lens.settings.ambientRim, greaterThan(0));
    });

    testWidgets('l\'ombre redevient celle d\'Apple', (tester) async {
      final lens = await pump(tester);
      // La nôtre faisait 52 px de flou et 22 px de décalage sous CHAQUE vitre
      // — des taches grises, là où iOS 26 pose 6 % de noir sur 8 px. On rend
      // donc l'ombre au moteur, qui la découpe hors du verre (sans quoi la
      // vitre floute sa propre ombre et se borde de sale).
      expect(lens.settings.shadow, isNull);
      expect(lens.settings.shadowElevation, lessThanOrEqualTo(1.0));
      for (final shadow in lens.settings.effectiveShadow) {
        expect(shadow.blurRadius, lessThanOrEqualTo(8));
        expect(shadow.color.a, lessThan(0.1));
      }
    });

    testWidgets('le voile de lisibilité remplace le givre', (tester) async {
      // Le flou ayant rendu le fond au fond d'écran, c'est lui qui tient le
      // texte au-dessus : un blanc d'un seul tenant, sans couture, et dont le
      // gate de luminance laisse l'encre nette.
      final lens = await pump(tester);
      expect(lens.settings.whitenStrength, greaterThan(0));
      expect(lens.settings.whitenGated, isTrue);
    });

    testWidgets('le rendu complet reste aux surfaces qui ne défilent pas',
        (tester) async {
      // Le premium échantillonne le fond dans une texture : le paquet le
      // réserve aux surfaces statiques, parce que dans un défilement cette
      // capture montre ce qui était là juste avant. Les barres, le lecteur et
      // les boutons flottants y ont droit…
      expect((await pump(tester)).quality, lg.GlassQuality.premium);
      // …une carte qui vit dans une liste, non : elle passe au rendu standard,
      // calibré pour ça.
      final scrolled = await pump(
        tester,
        around: (glass) => ListView(children: [glass]),
      );
      expect(scrolled.quality, lg.GlassQuality.standard);
    });
  });

  group('l\'habillage se reconnaît depuis n\'importe quel widget', () {
    testWidgets('isLiquidSkin ne dit oui que sous Apple', (tester) async {
      Future<void> pump(ThemeData theme) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            home: Builder(
              builder: (context) => Text('${isLiquidSkin(context)}'),
            ),
          ),
        );
        // MaterialApp fond un thème dans l'autre (AnimatedTheme).
        await tester.pump(const Duration(milliseconds: 500));
      }

      await pump(apple());
      expect(find.text('true'), findsOneWidget);
      await pump(glass());
      expect(find.text('false'), findsOneWidget);
      await pump(retro());
      expect(find.text('false'), findsOneWidget);
    });
  });
}
