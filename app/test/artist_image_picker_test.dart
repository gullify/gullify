// Changer la photo d'un artiste (idée #78) : le menu de la fiche propose les
// photos que YouTube Music et Deezer ont sous ce nom, un lien à coller, et la
// remise à zéro. Les propositions portent le nom du SERVICE — c'est ce qui
// permet de voir qu'on tient un homonyme, et de rechercher sous le bon nom.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gullify/api/api_client.dart';
import 'package:gullify/api/library_repository.dart';
import 'package:gullify/models/album.dart';
import 'package:gullify/models/artist.dart';
import 'package:gullify/screens/artist_screen.dart';
import 'package:gullify/state/library.dart';
import 'package:gullify/state/yt_downloads.dart';

class _FakeLibraryRepo extends Fake implements LibraryRepository {
  /// Ce que les services répondent, par nom cherché.
  Map<String, List<ArtistImageCandidate>> byQuery = {
    'Artiste Test': const [
      ArtistImageCandidate(
        name: 'Artiste Test',
        thumbnail: 'https://exemple/yt.jpg',
        source: 'ytmusic',
      ),
      // L'homonyme : même requête, autre personne.
      ArtistImageCandidate(
        name: 'Artiste Test (comédien)',
        thumbnail: 'https://exemple/dz.jpg',
        source: 'deezer',
      ),
    ],
  };

  /// Les noms cherchés, dans l'ordre.
  final List<String?> queries = [];
  String? setUrl;
  bool reset = false;
  Object? failWith;

  @override
  Future<List<ArtistImageCandidate>> artistImageCandidates(
    int artistId, {
    String? query,
  }) async {
    queries.add(query);
    return byQuery[query] ?? const [];
  }

  @override
  Future<void> setArtistImageFromUrl(int artistId, String url) async {
    if (failWith != null) throw failWith!;
    setUrl = url;
  }

  @override
  Future<void> resetArtistImage(int artistId) async => reset = true;
}

Widget _wrap(_FakeLibraryRepo repo) => ProviderScope(
      overrides: [
        libraryRepositoryProvider.overrideWithValue(repo),
        artistsProvider.overrideWith((ref) async => const <Artist>[]),
        artistExtrasProvider('Artiste Test')
            .overrideWith((ref) async => const ArtistExtras()),
        // Sans ça, la fiche interroge YouTube — donc le réseau.
        ytArtistAlbumsProvider('Artiste Test').overrideWith((ref) async => []),
        relatedArtistsProvider('Artiste Test').overrideWith((ref) async => []),
        artistDetailProvider(1).overrideWith((ref) async => const ArtistDetail(
              artist: Artist(id: 1, name: 'Artiste Test', albumCount: 1),
              albums: [Album(id: 1, name: 'Album Test')],
              topTracks: [],
            )),
      ],
      child: const MaterialApp(home: ArtistScreen(artistId: 1)),
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
    await tester.tap(find.text("Changer l'image"));
    await settle(tester);
  }

  testWidgets('les propositions arrivent sous le nom de l\'artiste',
      (tester) async {
    final repo = _FakeLibraryRepo();
    await openDialog(tester, repo);

    // La recherche part toute seule, sous le nom de la bibliothèque.
    expect(repo.queries, ['Artiste Test']);
    expect(find.text('Artiste Test (comédien)'), findsOneWidget);
    expect(find.text('YouTube Music'), findsOneWidget);
    expect(find.text('Deezer'), findsOneWidget);
  });

  testWidgets('taper une proposition la pose comme photo', (tester) async {
    final repo = _FakeLibraryRepo();
    await openDialog(tester, repo);

    await tester.tap(find.text('Artiste Test (comédien)'));
    await settle(tester);

    expect(repo.setUrl, 'https://exemple/dz.jpg');
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('Image mise à jour'), findsOneWidget);
  });

  testWidgets('chercher sous un autre nom rattrape l\'homonyme',
      (tester) async {
    final repo = _FakeLibraryRepo()
      ..byQuery['Le Vrai Nom'] = const [
        ArtistImageCandidate(
          // Un nom différent de ce qu'on a tapé : le champ de recherche porte
          // déjà le sien, la proposition doit se reconnaître à part.
          name: 'Le Vrai Nom (officiel)',
          thumbnail: 'https://exemple/vrai.jpg',
          source: 'ytmusic',
        ),
      ];
    await openDialog(tester, repo);

    await tester.enterText(find.byType(TextField).first, 'Le Vrai Nom');
    await tester.tap(find.byIcon(Icons.search));
    await settle(tester);

    expect(repo.queries, ['Artiste Test', 'Le Vrai Nom']);
    expect(find.text('Le Vrai Nom (officiel)'), findsOneWidget);
    expect(find.text('Artiste Test (comédien)'), findsNothing);

    await tester.tap(find.text('Le Vrai Nom (officiel)'));
    await settle(tester);
    expect(repo.setUrl, 'https://exemple/vrai.jpg');
  });

  testWidgets('un lien collé sert de photo', (tester) async {
    final repo = _FakeLibraryRepo();
    await openDialog(tester, repo);

    await tester.enterText(
      find.widgetWithText(TextField, 'Coller un lien'),
      'https://ailleurs/photo.jpg',
    );
    await tester.tap(find.byIcon(Icons.check));
    await settle(tester);

    expect(repo.setUrl, 'https://ailleurs/photo.jpg');
  });

  testWidgets('« Image automatique » défait le choix', (tester) async {
    final repo = _FakeLibraryRepo();
    await openDialog(tester, repo);

    await tester.tap(find.widgetWithText(TextButton, 'Image automatique'));
    await settle(tester);

    expect(repo.reset, isTrue);
    expect(find.text('Image automatique rétablie'), findsOneWidget);
  });

  testWidgets('un refus du serveur reste dans le dialogue', (tester) async {
    // La photo n'a pas changé : refermer obligerait à tout rouvrir pour
    // réessayer, et le message expliquant pourquoi serait perdu.
    final repo = _FakeLibraryRepo()
      ..failWith = ApiException('legacy_error', 'Rien à télécharger.');
    await openDialog(tester, repo);

    await tester.tap(find.text('Artiste Test (comédien)'));
    await settle(tester);

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('Rien à télécharger.'), findsOneWidget);
  });

  testWidgets('sans résultat, le dialogue le dit', (tester) async {
    final repo = _FakeLibraryRepo()..byQuery = {};
    await openDialog(tester, repo);

    expect(find.text('Aucune photo trouvée sous ce nom.'), findsOneWidget);
  });
}
