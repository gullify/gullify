// Machine à remonter le temps (idée #80) : la bibliothèque se parcourt aussi
// par année, et chaque millésime a sa radio — ses titres, mélangés.
//
// Ce qui compte ici : l'app lit bien les millésimes que rend le serveur, les
// range par décennie du plus récent au plus ancien, et le bouton d'une année
// lance vraiment ses titres.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gullify/api/api_client.dart';
import 'package:gullify/api/library_repository.dart';
import 'package:gullify/models/album.dart';
import 'package:gullify/models/song.dart';
import 'package:gullify/screens/library_screen.dart';
import 'package:gullify/screens/year_screen.dart';
import 'package:gullify/state/library.dart';
import 'package:gullify/state/player.dart';
import 'package:gullify/theme.dart';

class _FakeClient extends Fake implements ApiClient {
  final List<Map<String, dynamic>> calls = [];

  @override
  Future<dynamic> get(String path, {Map<String, dynamic>? query}) async {
    calls.add({'path': path, ...?query});
    if (query?['action'] == 'get_years') {
      return {
        'years': [
          {
            'year': 2024,
            'albumCount': 3,
            'songCount': 41,
            'artworkUrls': ['serve_image.php?album_id=1'],
          },
          {'year': 1994, 'albumCount': 1, 'songCount': 12},
          {'year': 1991, 'albumCount': 2, 'songCount': 24},
        ],
      };
    }
    return [
      {'id': 7, 'title': 'Un titre de 1994', 'filePath': 'a.mp3', 'duration': 200},
    ];
  }

  @override
  String resourceUrl(String relative) => 'https://exemple.test/$relative';
}

class _FakeRepo extends Fake implements LibraryRepository {
  _FakeRepo({this.songs = const []});

  final List<Song> songs;
  final List<int> asked = [];

  @override
  Future<List<Song>> yearSongs(int year, {int limit = 200}) async {
    asked.add(year);
    return songs;
  }
}

class _FakeActions extends Fake implements PlayerActions {
  final List<List<Song>> played = [];

  @override
  Future<void> playSongs(List<Song> songs, {int startIndex = 0}) async =>
      played.add(songs);
}

// (Le type des overrides n'est pas exporté par Riverpod : chaque test
// construit son ProviderScope lui-même, comme ailleurs dans ces tests.)
Widget _app(Widget child) => MaterialApp(
      theme: gullifyThemeFor(GullifyAccent.indigo, dark: false),
      home: child,
    );

void main() {
  test('les millésimes se lisent depuis la réponse du serveur', () async {
    final client = _FakeClient();
    final years = await LibraryRepository(client).years();

    expect(client.calls.single['action'], 'get_years');
    expect(years.map((y) => y.year), [2024, 1994, 1991]);
    expect(years.first.albumCount, 3);
    expect(years.first.songCount, 41);
    // Les pochettes deviennent des adresses absolues, comme ailleurs.
    expect(years.first.artworkUrls.single, startsWith('https://exemple.test/'));
    // Sans pochette, la carte n'en affiche simplement aucune.
    expect(years[1].artworkUrls, isEmpty);
  });

  test('une année sait de quelle décennie elle est', () {
    expect(const YearCount(1994).decade, 1990);
    expect(const YearCount(1990).decade, 1990);
    expect(const YearCount(2000).decade, 2000);
    expect(const YearCount(2024).decade, 2020);
  });

  test('le flux d\'une année est demandé au serveur, mélangé', () async {
    final client = _FakeClient();
    final songs = await LibraryRepository(client).yearSongs(1994);

    expect(client.calls.single['action'], 'year_songs');
    expect(client.calls.single['year'], 1994);
    expect(songs.single.title, 'Un titre de 1994');
  });

  testWidgets('la bibliothèque range les années par décennie', (tester) async {
    tester.view.physicalSize = const Size(412, 892);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(ProviderScope(
      overrides: [
        // La vue « Artistes » s'affiche en premier : sans ces deux-là, elle
        // irait chercher un vrai serveur (et sa restauration de session).
        artistsProvider.overrideWith((ref) async => const []),
        genresProvider.overrideWith((ref) async => const []),
        yearsProvider.overrideWith((ref) async => const [
              YearCount(2024, albumCount: 3, songCount: 41),
              YearCount(1994, albumCount: 1, songCount: 12),
              YearCount(1991, albumCount: 2, songCount: 24),
            ]),
      ],
      child: _app(const LibraryScreen()),
    ));
    await tester.pump();

    await tester.tap(find.text('Années'));
    await tester.pumpAndSettle();

    expect(find.text('Années 20'), findsOneWidget);
    expect(find.text('Années 90'), findsOneWidget);
    expect(find.text('2024'), findsOneWidget);
    expect(find.text('1994'), findsOneWidget);
    expect(find.text('1 album · 12 titres'), findsOneWidget);
  });

  testWidgets('la radio d\'une année joue ses titres', (tester) async {
    final repo = _FakeRepo(songs: const [
      Song(id: 7, title: 'Un titre de 1994', filePath: 'a.mp3', duration: 200),
    ]);
    final actions = _FakeActions();

    await tester.pumpWidget(ProviderScope(
      overrides: [
        libraryRepositoryProvider.overrideWithValue(repo),
        playerActionsProvider.overrideWithValue(actions),
      ],
      child: _app(
        const Scaffold(body: Center(child: YearRadioButton(year: 1994))),
      ),
    ));

    expect(find.text('Radio 1994'), findsOneWidget);
    await tester.tap(find.text('Radio 1994'));
    await tester.pumpAndSettle();

    expect(repo.asked, [1994]);
    expect(actions.played.single.single.title, 'Un titre de 1994');
  });

  testWidgets('une année vide le dit plutôt que de lancer le vide',
      (tester) async {
    final repo = _FakeRepo();
    final actions = _FakeActions();

    await tester.pumpWidget(ProviderScope(
      overrides: [
        libraryRepositoryProvider.overrideWithValue(repo),
        playerActionsProvider.overrideWithValue(actions),
      ],
      child: _app(
        const Scaffold(body: Center(child: YearRadioButton(year: 1994))),
      ),
    ));

    await tester.tap(find.text('Radio 1994'));
    await tester.pumpAndSettle();

    expect(actions.played, isEmpty);
    expect(find.text('Aucun titre de 1994'), findsOneWidget);
  });

  testWidgets('la page d\'une année montre ses albums', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        albumsByYearProvider(1994).overrideWith((ref) async => const [
              Album(id: 1, name: 'Un album de 1994', year: 1994),
            ]),
      ],
      child: _app(const YearScreen(year: 1994)),
    ));
    await tester.pumpAndSettle();

    // Le millésime en barre du haut (l'année s'affiche aussi sur la carte de
    // l'album, d'où la recherche ciblée).
    expect(find.widgetWithText(AppBar, '1994'), findsOneWidget);
    expect(find.text('Albums · 1'), findsOneWidget);
    expect(find.text('Un album de 1994'), findsOneWidget);
  });
}
