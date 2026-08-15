// Changer la jaquette d'un album (idée #93) : le menu de la fiche propose les
// jaquettes que YouTube Music et Deezer ont sous « artiste titre », un lien à
// coller, et la remise à zéro. Les propositions portent le titre ET l'artiste
// du SERVICE — c'est ce qui permet de voir qu'on tient une compilation ou un
// album homonyme, et de rechercher sous le bon libellé.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gullify/api/api_client.dart';
import 'package:gullify/api/library_repository.dart';
import 'package:gullify/models/album.dart';
import 'package:gullify/screens/album_screen.dart';
import 'package:gullify/state/library.dart';

class _FakeLibraryRepo extends Fake implements LibraryRepository {
  /// Ce que les services répondent, par texte cherché.
  Map<String, List<AlbumCoverCandidate>> byQuery = {
    'Artiste Test Album Test': const [
      AlbumCoverCandidate(
        title: 'Album Test',
        artist: 'Artiste Test',
        thumbnail: 'https://exemple/yt.jpg',
        source: 'ytmusic',
      ),
      // La compilation qui a avalé le titre : même requête, autre disque.
      AlbumCoverCandidate(
        title: 'Album Test (compilation)',
        artist: 'Artistes variés',
        thumbnail: 'https://exemple/dz.jpg',
        source: 'deezer',
      ),
    ],
  };

  /// Les textes cherchés, dans l'ordre.
  final List<String?> queries = [];
  String? setUrl;
  bool reset = false;
  Object? failWith;

  @override
  Future<List<AlbumCoverCandidate>> albumCoverCandidates(
    int albumId, {
    String? query,
  }) async {
    queries.add(query);
    return byQuery[query] ?? const [];
  }

  @override
  Future<void> setAlbumCoverFromUrl(int albumId, String url) async {
    if (failWith != null) throw failWith!;
    setUrl = url;
  }

  @override
  Future<void> resetAlbumCover(int albumId) async => reset = true;
}

const _album = Album(
  id: 7,
  name: 'Album Test',
  artistId: 1,
  artistName: 'Artiste Test',
);

Widget _wrap(_FakeLibraryRepo repo) => ProviderScope(
      overrides: [
        libraryRepositoryProvider.overrideWithValue(repo),
        albumDetailProvider(7).overrideWith(
          (ref) async => const AlbumDetail(album: _album, songs: []),
        ),
      ],
      child: const MaterialApp(home: AlbumScreen(albumId: 7)),
    );

/// Laisse tout se poser. Pas `pumpAndSettle` : l'égaliseur qui bat à côté du
/// titre n'a pas de fin.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  Future<void> openDialog(WidgetTester tester, _FakeLibraryRepo repo) async {
    tester.view.physicalSize = const Size(412, 892);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_wrap(repo));
    await settle(tester);
    await tester.tap(find.byIcon(Icons.more_vert).first);
    await settle(tester);
    await tester.tap(find.text('Changer la jaquette'));
    await settle(tester);
  }

  testWidgets('les propositions arrivent sous « artiste titre »',
      (tester) async {
    final repo = _FakeLibraryRepo();
    await openDialog(tester, repo);

    // La recherche part toute seule : le titre seul ramènerait les albums
    // homonymes de toute la planète.
    expect(repo.queries, ['Artiste Test Album Test']);
    expect(find.text('Album Test (compilation)'), findsOneWidget);
    // L'artiste du service distingue l'album de la compilation.
    expect(find.text('Artistes variés'), findsOneWidget);
    expect(find.text('YouTube Music'), findsOneWidget);
    expect(find.text('Deezer'), findsOneWidget);
  });

  testWidgets('taper une proposition la pose comme jaquette', (tester) async {
    final repo = _FakeLibraryRepo();
    await openDialog(tester, repo);

    await tester.tap(find.text('Album Test (compilation)'));
    await settle(tester);

    expect(repo.setUrl, 'https://exemple/dz.jpg');
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('Jaquette mise à jour'), findsOneWidget);
  });

  testWidgets('chercher sous un autre libellé rattrape le mauvais album',
      (tester) async {
    final repo = _FakeLibraryRepo()
      ..byQuery['Le Vrai Titre'] = const [
        AlbumCoverCandidate(
          // Un titre différent de ce qu'on a tapé : le champ de recherche
          // porte déjà le sien, la proposition doit se reconnaître à part.
          title: 'Le Vrai Titre (édition originale)',
          artist: 'Artiste Test',
          thumbnail: 'https://exemple/vrai.jpg',
          source: 'ytmusic',
        ),
      ];
    await openDialog(tester, repo);

    await tester.enterText(find.byType(TextField).first, 'Le Vrai Titre');
    await tester.tap(find.byIcon(Icons.search));
    await settle(tester);

    expect(repo.queries, ['Artiste Test Album Test', 'Le Vrai Titre']);
    expect(find.text('Le Vrai Titre (édition originale)'), findsOneWidget);
    expect(find.text('Album Test (compilation)'), findsNothing);

    await tester.tap(find.text('Le Vrai Titre (édition originale)'));
    await settle(tester);
    expect(repo.setUrl, 'https://exemple/vrai.jpg');
  });

  testWidgets('un lien collé sert de jaquette', (tester) async {
    final repo = _FakeLibraryRepo();
    await openDialog(tester, repo);

    await tester.enterText(
      find.widgetWithText(TextField, 'Coller un lien'),
      'https://ailleurs/pochette.jpg',
    );
    await tester.tap(find.byIcon(Icons.check));
    await settle(tester);

    expect(repo.setUrl, 'https://ailleurs/pochette.jpg');
  });

  testWidgets('« Jaquette automatique » défait le choix', (tester) async {
    final repo = _FakeLibraryRepo();
    await openDialog(tester, repo);

    await tester.tap(find.widgetWithText(TextButton, 'Jaquette automatique'));
    await settle(tester);

    expect(repo.reset, isTrue);
    expect(find.text('Jaquette automatique rétablie'), findsOneWidget);
  });

  testWidgets('un refus du serveur reste dans le dialogue', (tester) async {
    // La jaquette n'a pas changé : refermer obligerait à tout rouvrir pour
    // réessayer, et le message expliquant pourquoi serait perdu.
    final repo = _FakeLibraryRepo()
      ..failWith = ApiException('legacy_error', 'Rien à télécharger.');
    await openDialog(tester, repo);

    await tester.tap(find.text('Album Test (compilation)'));
    await settle(tester);

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('Rien à télécharger.'), findsOneWidget);
  });

  testWidgets('sans résultat, le dialogue le dit', (tester) async {
    final repo = _FakeLibraryRepo()..byQuery = {};
    await openDialog(tester, repo);

    expect(find.text('Aucune jaquette trouvée sous ce nom.'), findsOneWidget);
  });
}
