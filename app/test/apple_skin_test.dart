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
      // Plus transparente : c'est LA différence qu'on voit d'abord.
      double alpha(ThemeData theme) => surfaces(theme).barColor!.a;
      expect(alpha(apple()), lessThan(alpha(glass())));
      expect(alpha(apple(dark: true)), lessThan(alpha(glass(dark: true))));
      // Plus profond, et les couleurs du dessous ravivées (vibrancy).
      expect(
        surfaces(apple()).blurSigma,
        greaterThan(surfaces(glass()).blurSigma),
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
        expect(color.a, lessThan(0.55));
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
