// Idée #73 : voir les nouvelles sorties de YouTube Music depuis la recherche,
// et seulement les ALBUMS — les singles noieraient la liste. Le tri se fait
// côté serveur (python) ; ce qui se teste ici, c'est que l'app demande la
// bonne page, lise la réponse, et propose ces albums quand le champ est vide.
//
// Idée #74 : la page de YouTube ignore le pays, alors le serveur la reclasse
// (tes artistes d'abord) ; l'app se contente d'afficher l'ordre reçu et de
// signaler les sorties d'un artiste déjà écouté.
//
// Idée #116 : « Nouveautés » ne montre plus QUE la page de YouTube Music —
// les sorties des artistes qu'on écoute, qui y étaient mélangées, ont leur
// propre section dessous. Ce qui s'y trouvait ne ressemblait pas aux
// nouveautés de YouTube Music, et c'était juste.
//
// Idée #118 : le bloc « Découvrir » de l'accueil ouvre cet onglet sur les
// nouveautés — il vide donc la requête partagée. Le champ doit la suivre,
// sinon il garderait le texte de la visite d'avant et l'écran montrerait des
// résultats au lieu des nouveautés.
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
import 'package:gullify/widgets/download_confirm.dart';

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
          'known_artist': true,
        },
        // Sans browseId, l'album n'est pas téléchargeable : on l'écarte.
        {'title': 'Sans identifiant', 'artist': 'X', 'browseId': ''},
      ],
    };
  }
}

class _FakeRepo extends Fake implements YtDownloadsRepository {
  _FakeRepo(this.albums, {this.mine = const []});

  final List<YtAlbum> albums;

  /// Les sorties des artistes de la bibliothèque : l'autre liste, servie par
  /// une autre action du serveur.
  final List<YtAlbum> mine;

  final List<int> limits = [];
  final List<int> mineLimits = [];

  @override
  Future<List<YtAlbum>> newReleases({int limit = 30}) async {
    limits.add(limit);
    return albums.take(limit).toList();
  }

  @override
  Future<List<YtAlbum>> artistReleases({int limit = 30}) async {
    mineLimits.add(limit);
    return mine.take(limit).toList();
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

/// Sortie d'un artiste que l'utilisateur écoute déjà (le serveur l'a reconnu
/// et l'a remontée en tête).
const _connu = YtAlbum(
  title: 'Retour aux sources',
  artist: 'Les Cowboys Fringants',
  year: '',
  thumbnail: '',
  browseId: 'bconnu',
  knownArtist: true,
);

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
    expect(albums.single.knownArtist, isTrue);
  });

  testWidgets('le champ vide propose les nouveautés YouTube Music',
      (tester) async {
    final repo = _FakeRepo(_albums(3));
    await _pumpSearch(tester, repo);

    expect(find.text('Nouveautés'), findsOneWidget);
    expect(
      find.text('Les nouveaux albums de YouTube Music, tes artistes en premier'),
      findsOneWidget,
    );
    expect(find.text('Nouveauté 0'), findsOneWidget);
    expect(find.text('Artiste 2'), findsOneWidget);
    // Page incomplète : rien de plus à charger.
    expect(find.text('Charger plus'), findsNothing);
    expect(repo.limits, [12]);
  });

  testWidgets('une sortie d\'un artiste déjà écouté le dit sous son titre',
      (tester) async {
    await _pumpSearch(tester, _FakeRepo([_connu, ..._albums(2)]));

    // L'ordre vient du serveur : l'app ne retrie rien.
    expect(find.text('Retour aux sources'), findsOneWidget);
    expect(
      find.text('Les Cowboys Fringants · Tu écoutes déjà cet artiste'),
      findsOneWidget,
    );
    // Les autres gardent leur simple nom d'artiste.
    expect(find.text('Artiste 0'), findsOneWidget);
  });

  testWidgets('un album déjà rangé garde sa pastille, sans mention d\'artiste',
      (tester) async {
    await _pumpSearch(
      tester,
      _FakeRepo([
        YtAlbum(
          title: _connu.title,
          artist: _connu.artist,
          year: '',
          thumbnail: '',
          browseId: _connu.browseId,
          inLibrary: true,
          knownArtist: true,
        ),
      ]),
    );

    expect(find.text('Les Cowboys Fringants'), findsOneWidget);
    expect(find.byType(InLibraryBadge), findsOneWidget);
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
          ytArtistReleasesProvider
              .overrideWith((ref) async => throw 'hors ligne'),
          searchResultsProvider
              .overrideWith((ref) async => const SearchResults()),
          serverUsersProvider.overrideWith((ref) async => const <ServerUser>[]),
        ],
        child: const MaterialApp(home: SearchScreen()),
      ),
    );
    // Deux tours : les nouveautés tombent au premier, et la section des
    // artistes — jusque-là hors écran, donc pas encore construite — au second.
    await tester.pump();
    await tester.pump();

    expect(find.text('Nouveautés'), findsNothing);
    expect(find.text('Sorties de tes artistes'), findsNothing);
    // La recherche, elle, reste utilisable.
    expect(find.text('Recherche'), findsOneWidget);
  });

  // ─────────────────────────── idée #116 ───────────────────────────────────

  test('artistReleases demande sa propre action, pas celle des nouveautés',
      () async {
    final client = _FakeClient();
    final albums =
        await YtDownloadsRepository(client).artistReleases(limit: 12);

    expect(client.calls.single, {
      'path': 'download.php',
      'action': 'artist_releases',
      'limit': '12',
    });
    expect(albums.single.title, 'Legacy');
  });

  testWidgets('les deux listes cohabitent, chacune sous son intitulé',
      (tester) async {
    final repo = _FakeRepo(
      _albums(2),
      mine: const [
        YtAlbum(
          title: 'Pub Royal',
          artist: 'Les Cowboys Fringants',
          year: '2026',
          thumbnail: '',
          browseId: 'bmine',
          becauseOf: 'Les Cowboys Fringants',
        ),
      ],
    );
    await _pumpSearch(tester, repo);

    expect(find.text('Nouveautés'), findsOneWidget);
    expect(
      find.text('Les nouveaux albums de YouTube Music, tes artistes en '
          'premier'),
      findsOneWidget,
    );
    expect(find.text('Nouveauté 0'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('Sorties de tes artistes'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Pub Royal'), findsOneWidget);
    // L'artiste crédité est celui de la bibliothèque : pas de « parce que ».
    expect(find.text('Les Cowboys Fringants · 2026'), findsOneWidget);
    expect(repo.mineLimits, [12]);
  });

  testWidgets('un album à deux noms dit à cause de qui il est proposé',
      (tester) async {
    await _pumpSearch(
      tester,
      _FakeRepo(const [], mine: const [
        YtAlbum(
          title: 'Duo',
          artist: 'Klô Pelgag & Pierre Lapointe',
          year: '2026',
          thumbnail: '',
          browseId: 'bduo',
          becauseOf: 'Klô Pelgag',
        ),
      ]),
    );

    expect(
      find.text('Klô Pelgag & Pierre Lapointe · 2026 · parce que tu as '
          'Klô Pelgag'),
      findsOneWidget,
    );
  });

  testWidgets('rien à proposer chez tes artistes : pas de section vide',
      (tester) async {
    await _pumpSearch(tester, _FakeRepo(_albums(2)));

    expect(find.text('Nouveautés'), findsOneWidget);
    expect(find.text('Sorties de tes artistes'), findsNothing);
  });

  // ─────────────────────────── idée #118 ───────────────────────────────────

  testWidgets('la requête vidée d\'ailleurs vide aussi le champ',
      (tester) async {
    final container = ProviderContainer(
      overrides: [
        ytDownloadsRepositoryProvider.overrideWithValue(_FakeRepo(_albums(2))),
        searchResultsProvider.overrideWith((ref) async => const SearchResults()),
        serverUsersProvider.overrideWith((ref) async => const <ServerUser>[]),
      ],
    );
    addTearDown(container.dispose);

    tester.view.physicalSize = const Size(412, 892);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: SearchScreen()),
      ),
    );
    await tester.pump();

    await tester.enterText(find.byType(TextField), 'vieille recherche');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    expect(find.text('Nouveautés'), findsNothing);

    // Ce que fait le bloc « Découvrir » de l'accueil.
    container.read(searchQueryProvider.notifier).set('');
    await tester.pump();
    await tester.pump();

    expect(find.text('vieille recherche'), findsNothing);
    expect(find.text('Nouveautés'), findsOneWidget);
  });

  testWidgets('une requête posée d\'ailleurs s\'écrit dans le champ',
      (tester) async {
    final container = ProviderContainer(
      overrides: [
        ytDownloadsRepositoryProvider.overrideWithValue(_FakeRepo(_albums(2))),
        searchResultsProvider.overrideWith((ref) async => const SearchResults()),
        serverUsersProvider.overrideWith((ref) async => const <ServerUser>[]),
      ],
    );
    addTearDown(container.dispose);

    tester.view.physicalSize = const Size(412, 892);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: SearchScreen()),
      ),
    );
    await tester.pump();

    // L'artiste voisin de l'accueil : son nom part chercher dans l'onglet.
    container.read(searchQueryProvider.notifier).set('Voisine');
    await tester.pump();
    await tester.pump();

    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'Voisine',
    );
  });
}
