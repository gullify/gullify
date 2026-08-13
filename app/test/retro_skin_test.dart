// Le thème rétro Winamp (idée #82). Ce qui compte ici : qu'il soit VRAIMENT
// à part (le verre ne bouge pas d'un pixel quand il est éteint) et qu'il se
// reconnaisse à ce qui fait un Winamp — surfaces opaques biseautées, angles
// carrés, afficheur vert.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gullify/theme.dart';
import 'package:gullify/widgets/glass_box.dart';
import 'package:gullify/widgets/retro_lcd.dart';

void main() {
  ThemeData retro() =>
      gullifyTheme(GullifySkin.winamp, GullifyAccent.indigo, dark: true);
  ThemeData glass({bool dark = false}) =>
      gullifyTheme(GullifySkin.glass, GullifyAccent.indigo, dark: dark);

  group('le thème rétro', () {
    test('lève le drapeau rétro et éteint le verre', () {
      final surfaces = retro().extension<GullifySurfaces>()!;
      expect(surfaces.retro, isTrue);
      expect(surfaces.frosted, isFalse);
      // Pas de halo d'accent : un châssis de 1999 ne brille pas.
      expect(surfaces.accentBlob, isNull);
      expect(surfaces.bevelLight, isNotNull);
      expect(surfaces.bevelDark, isNotNull);
    });

    test('est vert, et sombre quoi qu\'on lui demande', () {
      expect(retro().colorScheme.primary, winampGreen);
      expect(retro().colorScheme.brightness, Brightness.dark);
      // Même en demandant le thème clair, Winamp reste Winamp.
      final light =
          gullifyTheme(GullifySkin.winamp, GullifyAccent.indigo, dark: false);
      expect(light.colorScheme.brightness, Brightness.dark);
      expect(light.colorScheme.primary, winampGreen);
    });

    test('ignore l\'accent choisi', () {
      for (final accent in GullifyAccent.values) {
        expect(
          gullifyTheme(GullifySkin.winamp, accent, dark: true).colorScheme.primary,
          winampGreen,
        );
      }
    });

    test('des angles presque carrés là où le verre fait des pilules', () {
      double corner(ThemeData theme) {
        final shape = theme.cardTheme.shape! as RoundedRectangleBorder;
        return (shape.borderRadius as BorderRadius).topLeft.x;
      }

      expect(corner(retro()), lessThan(6));
      expect(corner(glass()), greaterThan(12));
    });
  });

  group('le verre reste le verre', () {
    test('aucun drapeau rétro sous l\'habillage de toujours', () {
      for (final dark in [false, true]) {
        final surfaces = glass(dark: dark).extension<GullifySurfaces>()!;
        expect(surfaces.retro, isFalse);
        expect(surfaces.frosted, isTrue);
      }
    });

    test('le choix d\'habillage ne touche pas au thème d\'origine', () {
      // gullifyThemeFor est ce que le reste du code (et les goldens) utilise :
      // il doit rendre exactement ce qu'il rendait avant l'idée #82.
      expect(
        glass().colorScheme.primary,
        gullifyThemeFor(GullifyAccent.indigo, dark: false).colorScheme.primary,
      );
      expect(
        glass(dark: true).extension<GullifySurfaces>()!.barColor,
        gullifyThemeFor(GullifyAccent.indigo, dark: true)
            .extension<GullifySurfaces>()!
            .barColor,
      );
    });
  });

  group('les surfaces communes suivent l\'habillage', () {
    Widget box(ThemeData theme) => MaterialApp(
      theme: theme,
      home: const Scaffold(
        body: Center(
          child: GlassBox(radius: 20, blur: false, child: SizedBox(width: 100, height: 40)),
        ),
      ),
    );

    testWidgets('rétro : plaque opaque biseautée, sans flou', (tester) async {
      await tester.pumpWidget(box(retro()));
      final decorated = tester
          .widgetList<DecoratedBox>(find.byType(DecoratedBox))
          .map((d) => d.decoration)
          .whereType<BoxDecoration>()
          .where((d) => d.border != null)
          .toList();
      expect(decorated, isNotEmpty);
      final plate = decorated.first;
      // Opaque : le verre translucide n'a rien à faire ici.
      expect(plate.color!.a, 1.0);
      // Biseau : le bord haut et le bord bas n'ont pas la même couleur.
      final border = plate.border! as Border;
      expect(border.top.color, isNot(border.bottom.color));
      expect(plate.boxShadow, anyOf(isNull, isEmpty));
    });

    testWidgets('verre : bordure uniforme, comme avant', (tester) async {
      await tester.pumpWidget(box(glass(dark: true)));
      final plate = tester
          .widgetList<Container>(find.byType(Container))
          .map((c) => c.decoration)
          .whereType<BoxDecoration>()
          .firstWhere((d) => d.border != null);
      final border = plate.border! as Border;
      expect(border.top.color, border.bottom.color);
    });
  });

  group('l\'afficheur', () {
    testWidgets('ne se montre que sous le rétro', (tester) async {
      Widget app(ThemeData theme) => MaterialApp(
        theme: theme,
        home: Builder(builder: (context) => Text('${isRetroSkin(context)}')),
      );
      await tester.pumpWidget(app(retro()));
      expect(find.text('true'), findsOneWidget);
      // MaterialApp fond un thème dans l'autre (AnimatedTheme) : l'habillage
      // ne change vraiment qu'une fois ce fondu terminé.
      await tester.pumpWidget(app(glass()));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('false'), findsOneWidget);
    });

    test('écrit en chasse fixe, vert sur noir', () {
      final style = lcdTextStyle();
      expect(style.fontFamily, 'monospace');
      expect(style.color, winampGreen);
    });
  });
}
