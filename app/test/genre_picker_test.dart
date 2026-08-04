// Le choix du genre d'un artiste propose la liste fermée du serveur : on
// range en tapant sur un genre, plutôt qu'en retapant son nom à chaque fois
// (« Punk Rock », « punk rock », « Punk-Rock »… finissaient en autant de
// genres différents).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gullify/api/library_repository.dart';
import 'package:gullify/models/album.dart';
import 'package:gullify/models/artist.dart';
import 'package:gullify/screens/artist_screen.dart';
import 'package:gullify/state/library.dart';
import 'package:gullify/state/yt_downloads.dart';

const _taxonomy = [
  'Chanson québécoise/francophone',
  'Traditionnel québécois',
  'Punk',
  'Métal',
];

class _FakeLibraryRepo extends Fake implements LibraryRepository {
  _FakeLibraryRepo({this.pending});

  /// Quand il est fourni, l'enregistrement ne se termine que lorsque le test
  /// le décide : c'est le cas réel, où le serveur répond bien après que le
  /// dialogue s'est refermé.
  final Completer<void>? pending;

  String? savedGenre;
  int? savedArtistId;

  @override
  Future<void> setArtistGenre(int artistId, String genre) async {
    savedArtistId = artistId;
    savedGenre = genre;
    if (pending != null) await pending!.future;
  }
}

Widget _wrap(
  _FakeLibraryRepo repo, {
  String? genre,
  GenreSuggestion suggestion = const GenreSuggestion(),
}) {
  return ProviderScope(
    overrides: [
      libraryRepositoryProvider.overrideWithValue(repo),
      genreTaxonomyProvider.overrideWith((ref) async => _taxonomy),
      genresProvider.overrideWith((ref) async => const [
            GenreCount('Punk', 4, albumCount: 9),
            // Un genre déjà en base qui ne fait pas partie de la liste : il
            // reste proposé, sans quoi on ne pourrait plus le remettre.
            GenreCount('Ska-punk maison', 1, albumCount: 1),
          ]),
      artistsProvider.overrideWith((ref) async => const <Artist>[]),
      // La suggestion part sur le réseau (MusicBrainz, côté serveur) : par
      // défaut le test n'en donne aucune, le dialogue doit marcher sans.
      genreSuggestionProvider(1).overrideWith((ref) async => suggestion),
      artistExtrasProvider('Artiste Test')
          .overrideWith((ref) async => const ArtistExtras()),
      // Sans ça, la fiche interroge YouTube — donc le client HTTP, donc la
      // session, qui arme un minuteur que le test ne verra jamais expirer.
      ytArtistAlbumsProvider('Artiste Test').overrideWith((ref) async => []),
      relatedArtistsProvider('Artiste Test').overrideWith((ref) async => []),
      artistDetailProvider(1).overrideWith((ref) async => ArtistDetail(
            artist: Artist(id: 1, name: 'Artiste Test', albumCount: 1, genre: genre),
            albums: const [Album(id: 1, name: 'Album Test', year: 2024)],
            topTracks: const [],
          )),
    ],
    child: const MaterialApp(home: ArtistScreen(artistId: 1)),
  );
}

void main() {
  Future<void> openDialog(WidgetTester tester) async {
    await tester.tap(find.text('Définir le genre'));
    await tester.pumpAndSettle();
  }

  Future<void> pump(
    WidgetTester tester,
    _FakeLibraryRepo repo, {
    String? genre,
    GenreSuggestion suggestion = const GenreSuggestion(),
  }) async {
    tester.view.physicalSize = const Size(412, 892);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_wrap(repo, genre: genre, suggestion: suggestion));
    await tester.pumpAndSettle();
    // Le dialogue s'ouvre depuis le menu de l'artiste.
    await tester.tap(find.byIcon(Icons.more_vert).first);
    await tester.pumpAndSettle();
    await openDialog(tester);
  }

  testWidgets('les genres principaux sont proposés, plus ceux déjà en base',
      (tester) async {
    await pump(tester, _FakeLibraryRepo());

    for (final g in _taxonomy) {
      expect(find.widgetWithText(ChoiceChip, g), findsOneWidget, reason: g);
    }
    expect(find.widgetWithText(ChoiceChip, 'Ska-punk maison'), findsOneWidget);
  });

  testWidgets('taper un genre puis enregistrer l\'envoie tel quel',
      (tester) async {
    final repo = _FakeLibraryRepo();
    await pump(tester, repo);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Punk'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Enregistrer'));
    await tester.pumpAndSettle();

    expect(repo.savedArtistId, 1);
    expect(repo.savedGenre, 'Punk');
  });

  testWidgets('le champ libre prend le pas sur la sélection', (tester) async {
    final repo = _FakeLibraryRepo();
    await pump(tester, repo);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Punk'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Turlututu');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Enregistrer'));
    await tester.pumpAndSettle();

    expect(repo.savedGenre, 'Turlututu');
  });

  testWidgets('« Retirer » vide le genre, et n\'apparaît que s\'il y en a un',
      (tester) async {
    final repo = _FakeLibraryRepo();
    await pump(tester, repo, genre: 'Punk');

    expect(find.widgetWithText(TextButton, 'Retirer'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Retirer'));
    await tester.pumpAndSettle();
    expect(repo.savedGenre, '');
  });

  testWidgets('sans genre défini, pas de bouton « Retirer »', (tester) async {
    await pump(tester, _FakeLibraryRepo());
    expect(find.widgetWithText(TextButton, 'Retirer'), findsNothing);
  });

  testWidgets('le serveur peut répondre après la fermeture du dialogue',
      (tester) async {
    // Repro du bug : le dialogue se referme avant la réponse du serveur, donc
    // la suite de l'enregistrement s'exécute alors que le widget est démonté.
    final pending = Completer<void>();
    final repo = _FakeLibraryRepo(pending: pending);
    await pump(tester, repo);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Punk'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Enregistrer'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);

    pending.complete();
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(repo.savedGenre, 'Punk');
    expect(find.text('Genre mis à jour'), findsOneWidget);
  });

  // ── La suggestion (MusicBrainz) ─────────────────────────────────────────
  testWidgets('la suggestion se montre, avec les étiquettes qui l\'ont dictée',
      (tester) async {
    await pump(
      tester,
      _FakeLibraryRepo(),
      suggestion: const GenreSuggestion(
        genre: 'Métal',
        tags: ['heavy metal', 'québécois'],
      ),
    );

    expect(find.text('Suggestion'), findsOneWidget);
    expect(find.text('d\'après MusicBrainz : heavy metal, québécois'),
        findsOneWidget);
    // Le genre suggéré fait partie de la liste : il apparaît deux fois, en
    // suggestion et dans les choix.
    expect(find.widgetWithText(ChoiceChip, 'Métal'), findsNWidgets(2));
  });

  testWidgets('taper la suggestion la choisit, sans rien enregistrer seule',
      (tester) async {
    final repo = _FakeLibraryRepo();
    await pump(
      tester,
      repo,
      suggestion: const GenreSuggestion(genre: 'Métal', tags: ['heavy metal']),
    );

    // Rien n'est parti tant qu'on n'a pas enregistré : la suggestion propose.
    expect(repo.savedGenre, isNull);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Métal').first);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Enregistrer'));
    await tester.pumpAndSettle();

    expect(repo.savedGenre, 'Métal');
  });

  testWidgets('sans rien de sûr, la suggestion se tait poliment',
      (tester) async {
    await pump(tester, _FakeLibraryRepo());

    expect(find.text('MusicBrainz ne dit rien de cet artiste'), findsOneWidget);
    expect(find.text('Suggestion'), findsNothing);
    // Le reste du dialogue marche comme avant.
    expect(find.widgetWithText(ChoiceChip, 'Punk'), findsOneWidget);
  });

  testWidgets('des étiquettes sans genre net le disent, sans rien imposer',
      (tester) async {
    await pump(
      tester,
      _FakeLibraryRepo(),
      suggestion: const GenreSuggestion(tags: ['seen live', 'canadian']),
    );

    expect(find.text('Rien de net chez MusicBrainz (seen live, canadian)'),
        findsOneWidget);
  });

  // ── Le medley ───────────────────────────────────────────────────────────
  testWidgets('le medley se propose, sans jouer tant qu\'on ne le demande pas',
      (tester) async {
    await pump(tester, _FakeLibraryRepo());

    expect(find.text('Écouter un medley'), findsOneWidget);
    expect(find.text('Arrêter le medley'), findsNothing);
  });
}
