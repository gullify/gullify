// Idée #73 : voir les nouvelles sorties de YouTube Music depuis la recherche,
// et seulement les ALBUMS — les singles noieraient la liste. Le tri se fait
// côté serveur (python) ; ce qui se teste ici, c'est que l'app demande la
// bonne page, lise la réponse, et propose ces albums quand le champ est vide.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gullify/api/api_client.dart';
import 'package:gullify/api/library_repository.dart';
import 'package:gullify/api/yt_downloads_repository.dart';
import 'package:gullify/models/server_user.dart';
import 'package:gullify/screens/search_screen.dart';
import 'package:gullify/state/library.dart';
import 'package:gullify/state/yt_downloads.dart';

class _FakeClient extends Fake implements ApiClient {
  final List<Map<String, dynamic>> calls = [];

  @override
  Future<dynamic> get(String path, {Map<String, dynamic>? query}) async {
    calls.add({'path': path, ...?query});
    return {
      'albums': [
        {
          'title': 'Legacy',
          'artist': 'Five Finger Death Punch',
          'year': '',
          'thumbnail': '',
          'browseId': 'MPREb_ZMJfKKUpEr7',
          'in_library': false,
        },
        // Sans browseId, l'album n'est pas téléchargeable : on l'écarte.
        {'title': 'Sans identifiant', 'artist': 'X', 'browseId': ''},
      ],
    };
  }
}

class _FakeRepo extends Fake implements YtDownloadsRepository {
  _FakeRepo(this.albums);

  final List<YtAlbum> albums;
  final List<int> limits = [];

  @override
  Future<List<YtAlbum>> newReleases({int limit = 30}) async {
    limits.add(limit);
    return albums.take(limit).toList();
  }
}

List<YtAlbum> _albums(int count) => [
      for (var i = 0; i < count; i++)
        YtAlbum(
          title: 'Nouveauté $i',
          artist: 'Artiste $i',
          year: '',
          thumbnail: '',
          browseId: 'b$i',
        ),
    ];

Future<void> _pumpSearch(WidgetTester tester, _FakeRepo repo) async {
  tester.view.physicalSize = const Size(412, 892);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ytDownloadsRepositoryProvider.overrideWithValue(repo),
        searchResultsProvider.overrideWith((ref) async => const SearchResults()),
        serverUsersProvider.overrideWith((ref) async => const <ServerUser>[]),
      ],
      child: const MaterialApp(home: SearchScreen()),
    ),
  );
  await tester.pump(); // résolution du FutureProvider
}

void main() {
  test('newReleases demande la page des nouveautés et ignore les sans-id',
      () async {
    final client = _FakeClient();
    final albums = await YtDownloadsRepository(client).newReleases(limit: 12);

    expect(client.calls.single, {
      'path': 'download.php',
      'action': 'new_releases',
      'limit': '12',
    });
    expect(albums, hasLength(1));
    expect(albums.single.title, 'Legacy');
    expect(albums.single.artist, 'Five Finger Death Punch');
  });

  testWidgets('le champ vide propose les nouveautés YouTube Music',
      (tester) async {
    final repo = _FakeRepo(_albums(3));
    await _pumpSearch(tester, repo);

    expect(find.text('Nouveautés'), findsOneWidget);
    expect(find.text('Nouveaux albums sur YouTube Music'), findsOneWidget);
    expect(find.text('Nouveauté 0'), findsOneWidget);
    expect(find.text('Artiste 2'), findsOneWidget);
    // Page incomplète : rien de plus à charger.
    expect(find.text('Charger plus'), findsNothing);
    expect(repo.limits, [12]);
  });

  testWidgets('« Charger plus » demande une tranche plus grande',
      (tester) async {
    final repo = _FakeRepo(_albums(30));
    await _pumpSearch(tester, repo);

    expect(repo.limits, [12]);
    await tester.scrollUntilVisible(
      find.text('Charger plus'),
      300,
      // Le champ de recherche a lui aussi un Scrollable : viser celui de la
      // liste (le premier dans l'arbre).
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(find.text('Charger plus'));
    await tester.pump();
    await tester.tap(find.widgetWithText(OutlinedButton, 'Charger plus'));
    await tester.pump();
    await tester.pump();

    expect(repo.limits, [12, 24]);
  });

  testWidgets('YouTube muet : la section disparaît sans encombrer l\'écran',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ytNewReleasesProvider.overrideWith((ref) async => throw 'hors ligne'),
          searchResultsProvider
              .overrideWith((ref) async => const SearchResults()),
          serverUsersProvider.overrideWith((ref) async => const <ServerUser>[]),
        ],
        child: const MaterialApp(home: SearchScreen()),
      ),
    );
    await tester.pump();

    expect(find.text('Nouveautés'), findsNothing);
    // La recherche, elle, reste utilisable.
    expect(find.text('Recherche'), findsOneWidget);
  });
}
