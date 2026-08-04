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
import 'package:gullify/models/song.dart';
import 'package:gullify/screens/artist_screen.dart';
import 'package:gullify/state/genre_medley.dart';
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

  /// Ce qu'il reste à ranger, tel que le serveur le dirait après
  /// l'enregistrement.
  UntaggedArtists untagged = const UntaggedArtists();

  /// Ce que contiennent les albums : le medley part tout seul à l'ouverture du
  /// dialogue, et sans titre lisible il se contente de le dire.
  List<Song> albumSongs = const [];

  /// Tous les genres enregistrés, dans l'ordre — une série en range plusieurs.
  final List<(int, String)> saves = [];

  @override
  Future<void> setArtistGenre(int artistId, String genre) async {
    savedArtistId = artistId;
    savedGenre = genre;
    saves.add((artistId, genre));
    if (pending != null) await pending!.future;
  }

  @override
  Future<UntaggedArtists> artistsWithoutGenre({int limit = 50}) async =>
      untagged;

  @override
  Future<AlbumDetail> albumDetail(int id) async => AlbumDetail(
        album: Album(id: id, name: 'Album Test'),
        songs: albumSongs,
      );

  @override
  String streamUrl(Song song) => 'https://exemple/stream${song.id}';
}

/// Un lecteur de medley qui ne sort aucun son, mais qui note ce qu'on lui a
/// demandé de jouer.
class _FakeMedleyAudio implements MedleyAudio {
  _FakeMedleyAudio(this.urls);

  final List<String> urls;
  bool playing = false;
  Completer<void>? _playing;

  @override
  Future<void> setVolume(double volume) async {}

  @override
  Future<void> setUrl(String url, {Duration? initialPosition}) async =>
      urls.add(url);

  /// Comme just_audio : ne rend la main qu'à l'arrêt du son.
  @override
  Future<void> play() {
    playing = true;
    return (_playing = Completer<void>()).future;
  }

  @override
  Future<void> stop() async {
    playing = false;
    _playing?.complete();
    _playing = null;
  }

  @override
  Future<void> dispose() async => stop();
}

Widget _wrap(
  _FakeLibraryRepo repo, {
  String? genre,
  GenreSuggestion suggestion = const GenreSuggestion(),
  List<String> taxonomy = _taxonomy,
  List<String>? medleyUrls,
}) {
  return ProviderScope(
    overrides: [
      libraryRepositoryProvider.overrideWithValue(repo),
      if (medleyUrls != null)
        medleyAudioProvider
            .overrideWithValue(() => _FakeMedleyAudio(medleyUrls)),
      genreTaxonomyProvider.overrideWith(
        // Un genre ajouté à la main vient à la suite de la liste principale.
        (ref) async => GenreTaxonomy(
          genres: [...taxonomy, 'Musique de fanfare'],
          custom: const ['Musique de fanfare'],
        ),
      ),
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
      // L'artiste sur lequel on enchaîne (voir « artiste suivant ») : sa
      // suggestion part sur le réseau elle aussi.
      genreSuggestionProvider(2)
          .overrideWith((ref) async => const GenreSuggestion()),
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
      // L'artiste sur lequel on enchaîne : son medley part tout seul lui aussi.
      artistDetailProvider(2).overrideWith((ref) async => const ArtistDetail(
            artist: Artist(id: 2, name: 'Sans Genre', albumCount: 1),
            albums: [Album(id: 2, name: 'Album Suivant')],
            topTracks: [],
          )),
    ],
    child: const MaterialApp(home: ArtistScreen(artistId: 1)),
  );
}

/// Laisse tout se poser. Pas `pumpAndSettle` : le medley part tout seul à
/// l'ouverture du dialogue (idée #56), et l'égaliseur qui bat à côté du titre
/// n'a pas de fin — on n'en reviendrait jamais.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  Future<void> openDialog(WidgetTester tester) async {
    await tester.tap(find.text('Définir le genre'));
    await settle(tester);
  }

  /// « Enregistrer » : range l'artiste et referme, sans lancer de série.
  Future<void> save(WidgetTester tester) async {
    await tester.tap(find.widgetWithText(TextButton, 'Enregistrer'));
    await settle(tester);
  }

  /// « Enregistrer et suivant » : range, puis rouvre le choix sur l'artiste
  /// suivant qui n'a pas de genre.
  Future<void> saveAndNext(WidgetTester tester) async {
    await tester.tap(find.widgetWithText(FilledButton, 'Enregistrer et suivant'));
    await settle(tester);
  }

  Future<void> pump(
    WidgetTester tester,
    _FakeLibraryRepo repo, {
    String? genre,
    GenreSuggestion suggestion = const GenreSuggestion(),
    List<String> taxonomy = _taxonomy,
    List<String>? medleyUrls,
  }) async {
    tester.view.physicalSize = const Size(412, 892);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_wrap(
      repo,
      genre: genre,
      suggestion: suggestion,
      taxonomy: taxonomy,
      medleyUrls: medleyUrls,
    ));
    await settle(tester);
    // Le dialogue s'ouvre depuis le menu de l'artiste.
    await tester.tap(find.byIcon(Icons.more_vert).first);
    await settle(tester);
    await openDialog(tester);
  }

  testWidgets('les genres principaux sont proposés, plus ceux déjà en base',
      (tester) async {
    await pump(tester, _FakeLibraryRepo());

    for (final g in _taxonomy) {
      expect(find.widgetWithText(ChoiceChip, g), findsOneWidget, reason: g);
    }
    expect(find.widgetWithText(ChoiceChip, 'Ska-punk maison'), findsOneWidget);
    // Et ceux qu'on a ajoutés soi-même, même sans artiste qui les porte.
    expect(find.widgetWithText(ChoiceChip, 'Musique de fanfare'), findsOneWidget);
  });

  testWidgets('taper un genre puis enregistrer l\'envoie tel quel',
      (tester) async {
    final repo = _FakeLibraryRepo();
    await pump(tester, repo);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Punk'));
    await settle(tester);
    await save(tester);

    expect(repo.savedArtistId, 1);
    expect(repo.savedGenre, 'Punk');
  });

  testWidgets('le champ libre prend le pas sur la sélection', (tester) async {
    final repo = _FakeLibraryRepo();
    await pump(tester, repo);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Punk'));
    await settle(tester);
    await tester.enterText(find.byType(TextField), 'Turlututu');
    await settle(tester);
    await save(tester);

    expect(repo.savedGenre, 'Turlututu');
  });

  testWidgets('« Retirer » vide le genre, et n\'apparaît que s\'il y en a un',
      (tester) async {
    final repo = _FakeLibraryRepo();
    await pump(tester, repo, genre: 'Punk');

    expect(find.widgetWithText(TextButton, 'Retirer'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Retirer'));
    await settle(tester);
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
    await settle(tester);
    await save(tester);
    expect(find.byType(AlertDialog), findsNothing);

    pending.complete();
    await settle(tester);

    expect(tester.takeException(), isNull);
    expect(repo.savedGenre, 'Punk');
    expect(find.text('Genre mis à jour'), findsOneWidget);
  });

  // ── L'enchaînement (ranger par séries, idée #56) ────────────────────────
  testWidgets('« Enregistrer » range et s\'arrête là', (tester) async {
    final repo = _FakeLibraryRepo()
      ..untagged = const UntaggedArtists(
        artists: [Artist(id: 2, name: 'Sans Genre')],
        total: 1,
      );
    await pump(tester, repo);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Punk'));
    await settle(tester);
    await save(tester);

    expect(repo.savedGenre, 'Punk');
    expect(find.text('Genre mis à jour'), findsOneWidget);
    // Il reste pourtant un artiste à ranger : c'est l'autre bouton qui
    // enchaîne, celui-ci referme.
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('« Enregistrer et suivant » rouvre le choix sur le suivant',
      (tester) async {
    final repo = _FakeLibraryRepo()
      ..untagged = const UntaggedArtists(
        artists: [
          // Celui qu'on vient de ranger peut encore figurer dans la liste :
          // il ne doit jamais être reproposé.
          Artist(id: 1, name: 'Artiste Test'),
          Artist(id: 2, name: 'Sans Genre'),
        ],
        total: 2,
      );
    await pump(tester, repo);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Punk'));
    await settle(tester);
    await saveAndNext(tester);

    // Le dialogue dit qui l'on range : c'est tout ce qui le signale, la fiche
    // en dessous étant restée celle de l'artiste précédent.
    expect(find.text('Genre de « Sans Genre »'), findsOneWidget);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Métal'));
    await settle(tester);
    await save(tester);

    expect(repo.saves, [(1, 'Punk'), (2, 'Métal')]);
  });

  testWidgets('la série s\'arrête quand tout est rangé', (tester) async {
    final repo = _FakeLibraryRepo();
    await pump(tester, repo);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Punk'));
    await settle(tester);
    await saveAndNext(tester);

    expect(repo.savedGenre, 'Punk');
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('Genre mis à jour · plus aucun artiste sans genre'),
        findsOneWidget);
  });

  testWidgets('retirer le genre ne lance pas de série', (tester) async {
    final repo = _FakeLibraryRepo()
      ..untagged = const UntaggedArtists(
        artists: [Artist(id: 2, name: 'Sans Genre')],
        total: 1,
      );
    await pump(tester, repo, genre: 'Punk');

    await tester.tap(find.widgetWithText(TextButton, 'Retirer'));
    await settle(tester);

    expect(repo.savedGenre, '');
    expect(find.text('Genre retiré'), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
  });

  // ── La suggestion (les catalogues) ──────────────────────────────────────
  testWidgets('la suggestion se montre, avec les étiquettes qui l\'ont dictée',
      (tester) async {
    await pump(
      tester,
      _FakeLibraryRepo(),
      suggestion: const GenreSuggestion(
        genre: 'Métal',
        tags: ['heavy metal', 'québécois'],
        source: 'musicbrainz',
      ),
    );

    expect(find.text('Suggestion'), findsOneWidget);
    expect(find.text('d\'après MusicBrainz : heavy metal, québécois'),
        findsOneWidget);
    // Le genre suggéré fait partie de la liste : il apparaît deux fois, en
    // suggestion et dans les choix.
    expect(find.widgetWithText(ChoiceChip, 'Métal'), findsNWidgets(2));
  });

  testWidgets('la suggestion dit de quel catalogue elle vient', (tester) async {
    // MusicBrainz ne connaît pas tout le monde : Deezer et Apple Music
    // prennent le relais, et le dialogue dit lequel a répondu (idée #54).
    await pump(
      tester,
      _FakeLibraryRepo(),
      suggestion: const GenreSuggestion(
        genre: 'Punk',
        tags: ['Alternative', 'Rock'],
        source: 'deezer',
      ),
    );

    expect(find.text('d\'après Deezer : Alternative, Rock'), findsOneWidget);
  });

  testWidgets('un catalogue sans étiquette se nomme quand même',
      (tester) async {
    await pump(
      tester,
      _FakeLibraryRepo(),
      suggestion: const GenreSuggestion(genre: 'Punk', source: 'itunes'),
    );

    expect(find.text('d\'après Apple Music'), findsOneWidget);
  });

  testWidgets('taper la suggestion la choisit, sans rien enregistrer seule',
      (tester) async {
    final repo = _FakeLibraryRepo();
    await pump(
      tester,
      repo,
      suggestion: const GenreSuggestion(
        genre: 'Métal',
        tags: ['heavy metal'],
        source: 'musicbrainz',
      ),
    );

    // Rien n'est parti tant qu'on n'a pas enregistré : la suggestion propose.
    expect(repo.savedGenre, isNull);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Métal').first);
    await settle(tester);
    await save(tester);

    expect(repo.savedGenre, 'Métal');
  });

  testWidgets('sans rien de sûr, la suggestion se tait poliment',
      (tester) async {
    await pump(tester, _FakeLibraryRepo());

    expect(find.text('Aucun catalogue ne dit rien de cet artiste'),
        findsOneWidget);
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

    expect(find.text('Rien de net dans les catalogues (seen live, canadian)'),
        findsOneWidget);
  });

  // ── Le medley (idée #56) ────────────────────────────────────────────────
  testWidgets('le medley part tout seul à l\'ouverture', (tester) async {
    final urls = <String>[];
    final repo = _FakeLibraryRepo()
      ..albumSongs = const [
        Song(id: 7, title: 'Titre 7', filePath: '/musique/7.mp3', duration: 240),
      ];
    await pump(tester, repo, medleyUrls: urls);

    // Sans rien demander : ça joue, et le bouton ne sert plus qu'à couper.
    expect(urls, ['https://exemple/stream7']);
    expect(find.text('Arrêter le medley'), findsOneWidget);
    expect(find.text('Écouter un medley'), findsNothing);

    // Et ça s'arrête à la fermeture du dialogue.
    await tester.tap(find.widgetWithText(TextButton, 'Annuler'));
    await settle(tester);
    // Le pas de fondu en cours expire, et se tait en voyant que le medley
    // n'est plus de son temps.
    await tester.pump(const Duration(milliseconds: 100));
    expect(urls, ['https://exemple/stream7']);
  });

  testWidgets('en enchaînant, le medley passe à l\'artiste suivant',
      (tester) async {
    // Repro : le dialogue précédent se défait *après* que le suivant a lancé
    // son medley — sa fermeture coupait le son qui venait de partir.
    final urls = <String>[];
    final repo = _FakeLibraryRepo()
      ..albumSongs = const [
        Song(id: 7, title: 'Titre 7', filePath: '/musique/7.mp3', duration: 240),
      ]
      ..untagged = const UntaggedArtists(
        artists: [Artist(id: 2, name: 'Sans Genre')],
        total: 1,
      );
    await pump(tester, repo, medleyUrls: urls);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Punk'));
    await settle(tester);
    await saveAndNext(tester);
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Genre de « Sans Genre »'), findsOneWidget);
    // L'album du suivant, et le medley toujours en train de jouer.
    expect(urls.length, 2);
    expect(find.text('Arrêter le medley'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'Annuler'));
    await settle(tester);
    await tester.pump(const Duration(milliseconds: 100));
  });

  testWidgets('sans rien à faire entendre, le medley le dit', (tester) async {
    // Le dialogue marche sans medley : un artiste dont aucun titre n'est
    // lisible ne doit rien casser.
    await pump(tester, _FakeLibraryRepo(), medleyUrls: []);

    expect(find.text('Rien à faire écouter'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'Punk'), findsOneWidget);
  });

  // ── Le dialogue tient dans l'écran (idée #54) ───────────────────────────
  testWidgets('une longue liste de genres ne repousse rien hors de l\'écran',
      (tester) async {
    // Repro : avec les 21 genres principaux et ceux ajoutés à la main, les
    // tuiles poussaient le champ libre, le medley et les boutons vers le bas.
    // Seules les tuiles défilent désormais ; le reste reste sous la main.
    final repo = _FakeLibraryRepo();
    await pump(
      tester,
      repo,
      taxonomy: [for (var i = 0; i < 30; i++) 'Genre numéro $i'],
    );

    expect(find.text('Écouter un medley').hitTestable(), findsOneWidget);
    expect(find.byType(TextField).hitTestable(), findsOneWidget);
    // Les deux boutons d'enregistrement restent sous la main, quitte à ce que
    // l'OverflowBar les range en colonne.
    expect(find.widgetWithText(TextButton, 'Enregistrer').hitTestable(),
        findsOneWidget);
    expect(
      find.widgetWithText(FilledButton, 'Enregistrer et suivant').hitTestable(),
      findsOneWidget,
    );

    // Et tout marche sans avoir à faire défiler quoi que ce soit.
    await tester.enterText(find.byType(TextField), 'Turlututu');
    await settle(tester);
    await save(tester);

    expect(repo.savedGenre, 'Turlututu');
  });

  testWidgets('les tuiles défilent pour atteindre les derniers genres',
      (tester) async {
    final repo = _FakeLibraryRepo();
    await pump(
      tester,
      repo,
      taxonomy: [for (var i = 0; i < 30; i++) 'Genre numéro $i'],
    );

    await tester.scrollUntilVisible(
      find.widgetWithText(ChoiceChip, 'Genre numéro 29'),
      120,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.widgetWithText(ChoiceChip, 'Genre numéro 29'));
    await settle(tester);
    await save(tester);

    expect(repo.savedGenre, 'Genre numéro 29');
  });
}
