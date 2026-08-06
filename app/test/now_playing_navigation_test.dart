// Depuis le lecteur plein écran, le nom de l'album et celui de l'artiste
// mènent à leur page (idée #64) : le lecteur se referme d'abord, et il ne
// réempile pas la page d'où l'on vient.
import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:gullify/screens/now_playing_screen.dart';
import 'package:gullify/state/favorites.dart';
import 'package:gullify/state/player.dart';

const _song = MediaItem(
  id: 'stream-1',
  title: 'Première chanson',
  artist: 'Artiste Test',
  album: 'Album Test',
  duration: Duration(seconds: 215),
  extras: {'songId': 1, 'albumId': 7, 'artistId': 3},
);

/// Un titre sans album ni artiste connus (pré-écoute, radio) : les noms
/// restent affichés, mais sans chevron ni destination.
const _unlinked = MediaItem(
  id: 'stream-2',
  title: 'Deuxième chanson',
  artist: 'Artiste Test',
  album: 'Album Test',
  extras: {'songId': 2},
);

class _FakePlayerActions extends Fake implements PlayerActions {}

/// Aucun favori, et surtout aucun appel réseau depuis le test.
class _NoFavorites extends FavoriteIds {
  @override
  Future<Set<int>> build() async => <int>{};
}

/// Écran bidon pour les destinations, repérable par son texte.
Widget _stub(String label) =>
    Scaffold(body: Center(child: Text('page:$label')));

Future<GoRouter> _pumpPlayer(WidgetTester tester, MediaItem item,
    {String from = '/'}) async {
  final router = GoRouter(
    initialLocation: from,
    routes: [
      GoRoute(path: '/', builder: (_, _) => _stub('accueil')),
      GoRoute(
        path: '/album/:id',
        builder: (_, s) => _stub('album-${s.pathParameters['id']}'),
      ),
      GoRoute(
        path: '/artist/:id',
        builder: (_, s) => _stub('artiste-${s.pathParameters['id']}'),
      ),
      GoRoute(path: '/now-playing', builder: (_, _) => const NowPlayingScreen()),
    ],
  );
  addTearDown(router.dispose);

  // Taille de téléphone : le lecteur plein écran ne tient pas dans les
  // 800×600 par défaut du test.
  tester.view.physicalSize = const Size(412, 892);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        playerActionsProvider.overrideWithValue(_FakePlayerActions()),
        currentMediaItemProvider
            .overrideWith((ref) => Stream<MediaItem?>.value(item)),
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
        child: MaterialApp.router(routerConfig: router),
      ),
    ),
  );
  await tester.pumpAndSettle();
  router.push('/now-playing');
  await tester.pumpAndSettle();
  return router;
}

void main() {
  testWidgets("le nom de l'album ouvre l'album et ferme le lecteur",
      (tester) async {
    final router = await _pumpPlayer(tester, _song);

    await tester.tap(find.text('Album Test'));
    await tester.pumpAndSettle();

    expect(find.text('page:album-7'), findsOneWidget);
    expect(find.byType(NowPlayingScreen), findsNothing);
    // Le lecteur n'est plus dans la pile : retour = la page de départ.
    router.pop();
    await tester.pumpAndSettle();
    expect(find.text('page:accueil'), findsOneWidget);
  });

  testWidgets("le nom de l'artiste ouvre l'artiste", (tester) async {
    await _pumpPlayer(tester, _song);

    await tester.tap(find.text('Artiste Test'));
    await tester.pumpAndSettle();

    expect(find.text('page:artiste-3'), findsOneWidget);
    expect(find.byType(NowPlayingScreen), findsNothing);
  });

  testWidgets('ouvert depuis la page visée, le lecteur se contente de fermer',
      (tester) async {
    final router = await _pumpPlayer(tester, _song, from: '/album/7');

    await tester.tap(find.text('Album Test'));
    await tester.pumpAndSettle();

    expect(find.text('page:album-7'), findsOneWidget);
    // Un seul album empilé : rien à dépiler au-dessus de la page de départ.
    expect(router.routerDelegate.currentConfiguration.matches.length, 1);
  });

  testWidgets('sans identifiant, les noms ne sont pas cliquables',
      (tester) async {
    await _pumpPlayer(tester, _unlinked);

    expect(find.text('Album Test'), findsOneWidget);
    expect(find.byIcon(Icons.chevron_right), findsNothing);

    await tester.tap(find.text('Artiste Test'));
    await tester.pumpAndSettle();
    expect(find.byType(NowPlayingScreen), findsOneWidget);
  });
}
