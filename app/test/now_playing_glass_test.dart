// Idée #106 : « il y a plein d'endroits où il ne s'affiche même pas, comme le
// player ». C'était exact — le lecteur plein écran n'avait PAS UNE surface de
// verre : des commandes nues posées sur un voile presque opaque, alors que le
// dock, le mini-lecteur, l'accueil, la bibliothèque en ont tous. Sous l'Apple
// Liquid Glass, elles se rangent maintenant sur deux vitres (la fiche du
// titre, le pupitre) — et ailleurs, rien ne bouge.
import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:gullify/screens/now_playing_screen.dart';
import 'package:gullify/state/favorites.dart';
import 'package:gullify/state/player.dart';
import 'package:gullify/theme.dart';
import 'package:gullify/widgets/glass_box.dart';
import 'package:gullify/widgets/glass_kit.dart';
import 'package:gullify/widgets/liquid_glass.dart';

const _song = MediaItem(
  id: 'stream-1',
  title: 'Première chanson',
  artist: 'Artiste Test',
  album: 'Album Test',
  duration: Duration(seconds: 215),
  extras: {'songId': 1, 'albumId': 7, 'artistId': 3},
);

class _FakePlayerActions extends Fake implements PlayerActions {}

class _NoFavorites extends FavoriteIds {
  @override
  Future<Set<int>> build() async => <int>{};
}

Future<void> _pumpPlayer(
  WidgetTester tester,
  GullifySkin skin, {
  bool dark = false,
  Size size = const Size(412, 892),
  // Le rétro anime son analyseur de spectre en boucle : rien ne s'y « pose »
  // jamais, il faut donc y avancer d'un nombre de frames choisi.
  bool settles = true,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(path: '/', builder: (_, _) => const Scaffold()),
      GoRoute(path: '/now-playing', builder: (_, _) => const NowPlayingScreen()),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        playerActionsProvider.overrideWithValue(_FakePlayerActions()),
        currentMediaItemProvider
            .overrideWith((ref) => Stream<MediaItem?>.value(_song)),
        playbackStateProvider
            .overrideWith((ref) => Stream.value(PlaybackState())),
        positionProvider.overrideWith((ref) => Stream.value(Duration.zero)),
        favoriteIdsProvider.overrideWith(_NoFavorites.new),
      ],
      // Le flux du titre en cours est écouté dès le départ, comme dans l'app
      // (le mini-lecteur le tient) : sinon le lecteur se construit une frame
      // sans titre et se referme aussitôt.
      child: Consumer(
        builder: (context, ref, child) {
          ref.watch(currentMediaItemProvider);
          return child!;
        },
        child: MaterialApp.router(
          theme: gullifyTheme(skin, GullifyAccent.indigo, dark: dark),
          routerConfig: router,
          // Comme main.dart : le dégradé du thème derrière tout le
          // navigateur, et sous l'Apple Liquid Glass le fond d'écran coloré
          // par-dessus. Sans lui, les vitres du lecteur n'auraient rien à
          // laisser passer — et c'est justement ce qu'on vérifie.
          builder: (context, child) {
            final surfaces = Theme.of(context).extension<GullifySurfaces>()!;
            return KeyedSubtree(
              key: const Key('golden-root'),
              child: DecoratedBox(
                decoration: BoxDecoration(gradient: surfaces.background),
                child: Stack(
                  children: [
                    if (surfaces.liquid)
                      Positioned.fill(
                        child: LiquidWallpaper(
                          accent: surfaces.accentBlob!,
                          dark: dark,
                        ),
                      ),
                    child!,
                  ],
                ),
              ),
            );
          },
        ),
      ),
    ),
  );
  Future<void> advance() async {
    if (settles) {
      await tester.pumpAndSettle();
      return;
    }
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  await advance();
  router.push('/now-playing');
  await advance();
}

void main() {
  testWidgets('sous Apple, le lecteur pose ses commandes sur du verre',
      (tester) async {
    await _pumpPlayer(tester, GullifySkin.apple);

    // La fiche du titre et le pupitre : deux vitres, pas une.
    expect(find.byType(GlassBox), findsNWidgets(2));
    // …et ce sont bien des lentilles d'Apple, la même matière que le dock.
    expect(find.byType(LiquidGlass), findsWidgets);
    // La flèche de fermeture devient un disque de verre.
    expect(find.byType(GlassIconButton), findsOneWidget);

    // Les commandes restent là, et au même endroit : c'est la matière qui
    // change, pas le lecteur.
    expect(find.text('Première chanson'), findsOneWidget);
    expect(find.byIcon(Icons.play_circle_fill), findsOneWidget);
    expect(find.byIcon(Icons.skip_next), findsOneWidget);
    expect(find.byIcon(Icons.queue_music), findsOneWidget);
    expect(find.byIcon(Icons.keyboard_arrow_down), findsOneWidget);
  });

  testWidgets('le voile s\'allège : il reste quelque chose à laisser passer',
      (tester) async {
    Future<double> scrim(GullifySkin skin) async {
      await _pumpPlayer(tester, skin);
      return tester
          .widgetList<DecoratedBox>(find.byType(DecoratedBox))
          .map((d) => d.decoration)
          .whereType<BoxDecoration>()
          .where((d) => d.color != null && d.gradient == null)
          .map((d) => d.color!.a)
          .reduce((a, b) => a > b ? a : b);
    }

    final apple = await scrim(GullifySkin.apple);
    final gullify = await scrim(GullifySkin.glass);
    // Un voile à 85 % ne laissait rien à réfracter sous les vitres : c'est ce
    // qui donnait « le verre ne s'affiche même pas ».
    expect(apple, lessThan(gullify));
  });

  testWidgets('le verre de Gullify ne change pas de tête', (tester) async {
    await _pumpPlayer(tester, GullifySkin.glass);
    expect(find.byType(GlassBox), findsNothing);
    expect(find.byType(LiquidGlass), findsNothing);
    expect(find.byType(GlassIconButton), findsNothing);
    expect(find.text('Première chanson'), findsOneWidget);
  });

  testWidgets('le châssis de 1999 non plus', (tester) async {
    await _pumpPlayer(tester, GullifySkin.winamp, dark: true, settles: false);
    expect(find.byType(GlassBox), findsNothing);
    expect(find.byType(LiquidGlass), findsNothing);
    expect(find.text('Première chanson'), findsOneWidget);
  });

  // Un rendu de contrôle : l'idée #106 commence par « je ne vois aucune
  // différence ». Le golden garde donc trace de ce que le lecteur doit
  // donner sous l'Apple Liquid Glass — vitres comprises, fond d'écran
  // dessous, et de quoi comparer à la prochaine fois.
  testWidgets('rendu de contrôle du lecteur sous Apple', (tester) async {
    await _pumpPlayer(tester, GullifySkin.apple);
    await expectLater(
      find.byKey(const Key('golden-root')),
      matchesGoldenFile('goldens/now_playing_apple.png'),
    );
  });

  // Les vitres ajoutent leur marge : sur un écran court, le lecteur ne doit
  // pas déborder pour autant (un débordement fait échouer le test).
  testWidgets('même sur un écran court, rien ne déborde', (tester) async {
    await _pumpPlayer(
      tester,
      GullifySkin.apple,
      size: const Size(360, 640),
    );
    expect(find.byType(GlassBox), findsNWidgets(2));
  });
}
