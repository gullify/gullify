// Le thème rétro Winamp (idée #82). Ce qui compte ici : qu'il soit VRAIMENT
// à part (le verre ne bouge pas d'un pixel quand il est éteint) et qu'il se
// reconnaisse à ce qui fait un Winamp — surfaces opaques biseautées, angles
// carrés, afficheur vert.
//
// Depuis l'idée #83 (« des carrés et du texte vert, ça ne ressemble pas
// vraiment »), on vérifie aussi le RELIEF : le biseau à deux traits et les
// chiffres dessinés segment par segment, qui sont ce qui manquait.
import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:gullify/screens/now_playing_screen.dart';
import 'package:gullify/state/player.dart';
import 'package:gullify/theme.dart';
import 'package:gullify/widgets/glass_box.dart';
import 'package:gullify/widgets/glass_kit.dart';
import 'package:gullify/widgets/retro_chrome.dart';
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

    testWidgets('rétro : plaque de chrome biseautée, sans flou', (tester) async {
      await tester.pumpWidget(box(retro()));
      final decorated = tester
          .widgetList<DecoratedBox>(find.byType(DecoratedBox))
          .map((d) => d.decoration)
          .whereType<BoxDecoration>()
          .where((d) => d.border != null)
          .toList();
      expect(decorated, isNotEmpty);
      final plate = decorated.first;
      // Le chrome est un dégradé opaque, pas un aplat gris (idée #85) : c'est
      // ce qui fait la tôle emboutie plutôt qu'un rectangle.
      final chrome = plate.gradient! as LinearGradient;
      expect(chrome.colors.first, isNot(chrome.colors.last));
      for (final color in chrome.colors) {
        expect(color.a, 1.0);
      }
      // Le haut est plus clair que le bas : la lumière vient d'en haut.
      expect(
        chrome.colors.first.computeLuminance(),
        greaterThan(chrome.colors.last.computeLuminance()),
      );
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
      // Idée #85 : VT323, le caractère tramé des terminaux à tube. Le
      // monospace générique gardait la chasse mais rendait des lettres de
      // 2024 — arrondies, antialiassées.
      expect(style.fontFamily, 'VT323');
      expect(style.fontFamilyFallback, contains('monospace'));
      expect(style.color, winampGreen);
    });
  });

  // Idée #85 : Maxime a DESSINÉ le skin (« chrome & LCD ») au lieu de le
  // décrire. Ce qui s'y joue tient en trois choses — deux lettrages bitmap,
  // un chrome en dégradé, et de l'ambre à côté du vert.
  group('le design « chrome & LCD »', () {
    test('deux lettrages, chacun à sa place', () {
      // Ce qui est GRAVÉ dans la tôle : Silkscreen, minuscule et espacé.
      final engraved = retroLabelStyle();
      expect(engraved.fontFamily, 'Silkscreen');
      expect(engraved.letterSpacing, greaterThan(0));
      // Ce qui s'AFFICHE derrière une vitre : VT323, en phosphore.
      expect(lcdTextStyle().fontFamily, 'VT323');
      expect(engraved.fontFamily, isNot(lcdTextStyle().fontFamily));
    });

    test('l\'ambre est la seconde voix du châssis', () {
      expect(retro().colorScheme.secondary, winampAmber);
      // …et il ne déteint pas sur le verre.
      expect(glass().colorScheme.secondary, isNot(winampAmber));
    });

    testWidgets('tout champ de saisie devient une vitre', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: retro(),
          home: const Scaffold(
            body: TextField(decoration: InputDecoration(hintText: 'Filtrer…')),
          ),
        ),
      );
      final decoration = Theme.of(
        tester.element(find.byType(TextField)),
      ).inputDecorationTheme;
      expect(decoration.filled, isTrue);
      expect(decoration.fillColor, winampLcd);
      // Le texte fantôme est en phosphore éteint, en VT323.
      expect(decoration.hintStyle!.fontFamily, 'VT323');
      expect(decoration.hintStyle!.color, winampGreenDim);
      // Angles vifs : un champ arrondi trahit le châssis.
      final border = decoration.border! as OutlineInputBorder;
      expect(border.borderRadius, BorderRadius.zero);
    });

    testWidgets('le titre de section est gravé en capitales', (tester) async {
      Future<Text> title(ThemeData theme) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            home: const Scaffold(body: SectionTitle('Derniers joués')),
          ),
        );
        await tester.pump(const Duration(milliseconds: 500));
        return tester.widget<Text>(find.byType(Text));
      }

      final engraved = await title(retro());
      expect(engraved.data, 'DERNIERS JOUÉS');
      expect(engraved.style!.fontFamily, 'Silkscreen');
      // Le verre, lui, ne bouge pas d'un pixel.
      final glassy = await title(glass());
      expect(glassy.data, 'Derniers joués');
      expect(glassy.style!.fontFamily, isNull);
    });
  });

  // Idée #83 : ce qui manquait au premier jet.
  group('le relief', () {
    testWidgets('un biseau se pose à deux traits, pas à un', (tester) async {
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: RetroBevel(
            fill: winampChassis,
            child: SizedBox(width: 60, height: 40),
          ),
        ),
      );
      final borders = tester
          .widgetList<DecoratedBox>(find.byType(DecoratedBox))
          .map((d) => d.decoration)
          .whereType<BoxDecoration>()
          .map((d) => d.border)
          .whereType<Border>()
          .toList();
      // Deux cadres emboîtés : c'est le second qui donne le relief.
      expect(borders.length, 2);
      for (final border in borders) {
        expect(border.top.color, border.left.color);
        expect(border.bottom.color, border.right.color);
        expect(border.top.color, isNot(border.bottom.color));
      }
      // Et le trait intérieur est plus clair en haut que le trait extérieur.
      expect(
        borders[1].top.color.computeLuminance(),
        greaterThan(borders[0].top.color.computeLuminance()),
      );
    });

    testWidgets('en creux, la lumière passe en bas', (tester) async {
      Future<Border> outer(bool sunken) async {
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: RetroBevel(
              sunken: sunken,
              fill: winampChassis,
              child: const SizedBox(width: 60, height: 40),
            ),
          ),
        );
        return tester
            .widgetList<DecoratedBox>(find.byType(DecoratedBox))
            .map((d) => d.decoration)
            .whereType<BoxDecoration>()
            .map((d) => d.border)
            .whereType<Border>()
            .first;
      }

      final raised = await outer(false);
      final sunken = await outer(true);
      expect(sunken.top.color, raised.bottom.color);
      expect(sunken.bottom.color, raised.top.color);
    });

    testWidgets('le temps est dessiné segment par segment', (tester) async {
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: Center(child: SevenSegment('03:12', height: 26)),
        ),
      );
      // Pas de texte : rien à lire dans l'arbre, tout est peint.
      expect(find.byType(Text), findsNothing);
      expect(find.byType(CustomPaint), findsWidgets);
      // Les deux points prennent moins de place qu'un chiffre.
      const digits = SevenSegment('00000', height: 26);
      const withColon = SevenSegment('00:00', height: 26);
      expect(withColon.width, lessThan(digits.width));
    });
  });

  group('l\'afficheur du lecteur', () {
    final item = MediaItem(
      id: 'stream-1',
      title: 'Première chanson',
      artist: 'Artiste Test',
      album: 'Album Test',
      duration: const Duration(seconds: 215),
      extras: const {'songId': 1, 'filePath': '/musique/premiere.flac'},
    );

    Widget lcd({required bool playing}) => ProviderScope(
      overrides: [
        positionProvider.overrideWith(
          (ref) => Stream.value(const Duration(seconds: 72)),
        ),
        playbackStateProvider.overrideWith(
          (ref) => Stream.value(PlaybackState(playing: playing)),
        ),
        queueProvider.overrideWith(
          (ref) => Stream.value([item, item.copyWith(id: 'stream-2')]),
        ),
      ],
      child: MaterialApp(
        theme: gullifyTheme(GullifySkin.winamp, GullifyAccent.indigo,
            dark: true),
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: RetroLcd(item: item),
            ),
          ),
        ),
      ),
    );

    testWidgets('rend le châssis du lecteur', (tester) async {
      tester.view.physicalSize = const Size(412, 200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(lcd(playing: true));
      // Durées fixes : l'analyseur et le titre défilant sont animés, le
      // golden doit tomber toujours au même instant.
      await tester.pump(const Duration(milliseconds: 300));
      await expectLater(
        find.byType(RetroLcd),
        matchesGoldenFile('goldens/retro_lcd.png'),
      );
    });

    testWidgets('annonce le format du fichier et le rang dans la file',
        (tester) async {
      await tester.pumpWidget(lcd(playing: true));
      await tester.pump();
      expect(find.text('FLAC'), findsOneWidget);
      expect(find.text('1/2'), findsOneWidget);
    });

    // Le golden du lecteur entier : c'est LUI qu'on regarde pour savoir si
    // « ça ressemble » — barre de titre hachurée, pochette encastrée,
    // afficheur, boutons gravés et glissière à bloc.
    testWidgets('le lecteur complet a la tête d\'un châssis', (tester) async {
      tester.view.physicalSize = const Size(412, 892);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            playerActionsProvider.overrideWithValue(_FakePlayerActions()),
            currentMediaItemProvider.overrideWith((ref) => Stream.value(item)),
            playbackStateProvider.overrideWith(
              (ref) => Stream.value(PlaybackState(playing: true)),
            ),
            positionProvider.overrideWith(
              (ref) => Stream.value(const Duration(seconds: 72)),
            ),
            queueProvider.overrideWith((ref) => Stream.value([item])),
          ],
          child: MaterialApp.router(
            theme: gullifyTheme(GullifySkin.winamp, GullifyAccent.indigo,
                dark: true),
            // Un routeur, même minimal : le lecteur se referme avec
            // `context.pop()` dès qu'il n'a plus rien à jouer.
            routerConfig: GoRouter(
              routes: [
                GoRoute(
                  path: '/',
                  builder: (context, state) => Builder(
                    builder: (context) => DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: Theme.of(context)
                            .extension<GullifySurfaces>()!
                            .background,
                      ),
                      // Comme main.dart : la tôle brossée derrière l'écran.
                      child: const RetroChassis(child: NowPlayingScreen()),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      // Durées fixes : afficheur et titre défilant sont animés.
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 50));
      await expectLater(
        find.byType(NowPlayingScreen),
        matchesGoldenFile('goldens/now_playing_winamp.png'),
      );
    });
  });
}

/// Le golden ne déclenche aucune lecture : un Fake suffit (le vrai
/// PlayerActions exigerait le handler audio et ses plugins).
class _FakePlayerActions extends Fake implements PlayerActions {}
