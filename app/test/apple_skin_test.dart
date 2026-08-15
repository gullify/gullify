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

    test('une vitre plus fine et un flou plus profond que le nôtre', () {
      // Plus transparente : c'est LA différence qu'on voit d'abord. Idée #99 :
      // « je ne vois même pas la différence » — donc pas « un peu plus fine »,
      // deux fois moins dense au minimum.
      double alpha(ThemeData theme) => surfaces(theme).barColor!.a;
      expect(alpha(apple()), lessThan(alpha(glass()) / 2));
      expect(alpha(apple(dark: true)), lessThan(alpha(glass(dark: true)) / 2));
      // Plus profond, et les couleurs du dessous ravivées (vibrancy).
      expect(
        surfaces(apple()).blurSigma,
        greaterThan(surfaces(glass()).blurSigma * 1.5),
      );
      expect(surfaces(apple()).vibrancy, greaterThan(1.0));
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

    test('la matrice de saturation ne touche à rien à 1.0', () {
      expect(
        saturationMatrix(1.0),
        // Identité : R, V, B inchangés, alpha inchangé.
        const [
          1.0, 0.0, 0.0, 0, 0, //
          0.0, 1.0, 0.0, 0, 0, //
          0.0, 0.0, 1.0, 0, 0, //
          0, 0, 0, 1, 0, //
        ],
      );
      // Au-delà de 1, la composante d'une couleur tire sur elle-même.
      expect(saturationMatrix(1.7)[0], greaterThan(1.0));
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
