// Le bloc « Découvrir » de l'accueil (idée #118) : quatre portes sous une
// seule carte. Ce qui se vérifie ici, c'est ce qu'un golden ne dit pas — que
// les quatre entrées sont bien là, que l'artiste voisin n'apparaît que
// lorsqu'il y en a vraiment un, et que la porte « Nouveautés YouTube Music »
// ouvre l'onglet Recherche SANS requête (sinon elle montrerait les résultats
// de la visite d'avant, pas les nouveautés).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:gullify/api/notifications_repository.dart';
import 'package:gullify/api/stats_repository.dart';
import 'package:gullify/api/yt_downloads_repository.dart';
import 'package:gullify/screens/home_screen.dart';
import 'package:gullify/state/discover.dart';
import 'package:gullify/state/library.dart';
import 'package:gullify/state/notifications.dart';
import 'package:gullify/state/stats.dart';
import 'package:gullify/theme.dart';

const _discover = DiscoverArtist(
  artist: YtArtist(name: 'Voisine', browseId: 'UC1', thumbnail: ''),
  becauseOf: 'Artiste Test',
);

const _stats = ListeningStats(
  general: StatsGeneral(
    totalPlays: 0,
    totalListenTimeFormatted: '0 h',
    uniqueSongsPlayed: 0,
    completionRate: 0,
    totalSkips: 0,
    avgDurationFormatted: '0 min',
  ),
  topSongs: [],
  topArtists: [],
  topAlbums: [],
  dailyPlays: StatsChart(labels: [], data: []),
  hourly: StatsChart(labels: [], data: []),
  weekday: StatsChart(labels: [], data: []),
  genres: [],
  recentPlays: [],
);

/// L'accueil sans réseau : seuls les providers que la page regarde sont
/// remplacés. `discover` est le tirage de l'artiste voisin — une valeur, rien
/// du tout, ou une panne de YouTube Music.
ProviderContainer _container({
  DiscoverArtist? discover,
  bool failing = false,
}) {
  final container = ProviderContainer(
    // Riverpod 3 relance tout seul un provider qui a échoué : la minuterie
    // de cette reprise survit au test et le fait tomber sur « Timer still
    // pending ». Ici, une panne est une panne.
    retry: (_, _) => null,
    overrides: [
      recentAlbumsProvider.overrideWith((ref) async => []),
      popularSongsProvider.overrideWith((ref) async => []),
      statsProvider.overrideWith((ref) async => _stats),
      notificationsProvider.overrideWith(
        (ref) async => const NotificationsPage(items: [], unread: 0),
      ),
      discoverArtistProvider.overrideWith((ref) async {
        if (failing) throw Exception('YouTube Music injoignable');
        return discover;
      }),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

/// L'accueil dans un routeur minimal : les autres routes ne servent qu'à
/// noter où le bloc envoie.
Future<GoRouter> _pumpHome(
  WidgetTester tester,
  ProviderContainer container,
) async {
  tester.view.physicalSize = const Size(412, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final router = GoRouter(
    routes: [
      GoRoute(path: '/', builder: (_, _) => const HomeScreen()),
      for (final path in const ['/search', '/bandcamp', '/podcasts'])
        GoRoute(
          path: path,
          builder: (_, _) => Scaffold(body: Text('page $path')),
        ),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        theme: gullifyThemeFor(GullifyAccent.indigo, dark: false),
        routerConfig: router,
      ),
    ),
  );
  // Deux frames de plus : les FutureProvider factices se résolvent.
  await tester.pump();
  await tester.pump();
  return router;
}

void main() {
  testWidgets('les quatre portes tiennent dans un seul bloc', (tester) async {
    final container = _container(discover: _discover);
    await _pumpHome(tester, container);

    expect(find.text('Découvrir'), findsOneWidget);
    expect(find.text('Voisine'), findsOneWidget);
    expect(find.text('Nouveautés YouTube Music'), findsOneWidget);
    expect(find.text('Découvrir sur Bandcamp'), findsOneWidget);
    expect(find.text('Podcasts'), findsOneWidget);
  });

  testWidgets('sans artiste voisin, les trois autres portes restent', (
    tester,
  ) async {
    final container = _container();
    await _pumpHome(tester, container);

    expect(find.text('Voisine'), findsNothing);
    expect(find.text('Découvrir sur Bandcamp'), findsOneWidget);
    expect(find.text('Podcasts'), findsOneWidget);
  });

  testWidgets('YouTube Music injoignable : le bloc tient quand même', (
    tester,
  ) async {
    final container = _container(failing: true);
    await _pumpHome(tester, container);

    expect(find.text('Voisine'), findsNothing);
    expect(find.text('Nouveautés YouTube Music'), findsOneWidget);
  });

  testWidgets('« Nouveautés » ouvre la recherche sans requête', (tester) async {
    final container = _container();
    container.read(searchQueryProvider.notifier).set('vieille recherche');
    final router = await _pumpHome(tester, container);

    await tester.tap(find.text('Nouveautés YouTube Music'));
    await tester.pumpAndSettle();

    expect(container.read(searchQueryProvider), '');
    expect(router.routerDelegate.currentConfiguration.uri.path, '/search');
  });

  testWidgets('l\'artiste voisin ouvre la recherche sur son nom', (
    tester,
  ) async {
    final container = _container(discover: _discover);
    final router = await _pumpHome(tester, container);

    await tester.tap(find.text('Voisine'));
    await tester.pumpAndSettle();

    expect(container.read(searchQueryProvider), 'Voisine');
    expect(router.routerDelegate.currentConfiguration.uri.path, '/search');
  });

  testWidgets('Bandcamp et Podcasts mènent à leur page', (tester) async {
    final container = _container();
    final router = await _pumpHome(tester, container);

    await tester.tap(find.text('Découvrir sur Bandcamp'));
    await tester.pumpAndSettle();
    expect(find.text('page /bandcamp'), findsOneWidget);

    router.pop();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Podcasts'));
    await tester.pumpAndSettle();
    expect(find.text('page /podcasts'), findsOneWidget);
  });
}
