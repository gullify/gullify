// « Tout lire » et l'aléatoire, partout où il y a une collection : sans eux il
// faut descendre jusqu'à un titre pour lancer la musique. Un genre, une année,
// les téléchargements — les trois endroits qui n'avaient pas les deux gestes.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gullify/api/library_repository.dart';
import 'package:gullify/models/album.dart';
import 'package:gullify/models/artist.dart';
import 'package:gullify/models/game_source.dart';
import 'package:gullify/models/song.dart';
import 'package:gullify/screens/genre_screen.dart';
import 'package:gullify/state/collection_play.dart';
import 'package:gullify/state/library.dart';
import 'package:gullify/state/player.dart';
import 'package:gullify/theme.dart';
import 'package:gullify/widgets/play_pair.dart';

/// Le serveur rend son vivier mélangé (ORDER BY RAND()) : c'est à l'app de
/// remettre en ordre quand on demande « tout lire ».
const _melange = [
  Song(
    id: 2,
    title: 'B',
    filePath: '/b.mp3',
    artistName: 'Zoé',
    albumName: 'Un album',
    trackNumber: 1,
  ),
  Song(
    id: 3,
    title: 'C',
    filePath: '/c.mp3',
    artistName: 'Alice',
    albumName: 'Autre album',
    trackNumber: 2,
  ),
  Song(
    id: 1,
    title: 'A',
    filePath: '/a.mp3',
    artistName: 'Alice',
    albumName: 'Autre album',
    trackNumber: 1,
  ),
];

class _FakeRepo extends Fake implements LibraryRepository {
  _FakeRepo({this.pool = _melange, this.artistsOfGenre = const []});

  final List<Song> pool;
  final List<Artist> artistsOfGenre;
  GameSource? lastSource;

  @override
  Future<List<Song>> randomSongs({
    int limit = 200,
    GameSource source = GameSource.all,
  }) async {
    lastSource = source;
    return pool;
  }

  @override
  Future<List<Artist>> artistsByGenre(String genre) async => artistsOfGenre;

  @override
  Future<ArtistDetail> artistDetail(int id) async => const ArtistDetail(
        artist: Artist(id: 7, name: 'Un groupe'),
        albums: [Album(id: 1, name: 'Un album', artistName: 'Un groupe')],
        topTracks: [],
      );

  @override
  Future<AlbumDetail> albumDetail(int id) async => const AlbumDetail(
        album: Album(id: 1, name: 'Un album', artistName: 'Un groupe'),
        songs: [
          Song(id: 9, title: 'Repli', filePath: '/repli.mp3', trackNumber: 1),
        ],
      );
}

class _FakeActions extends Fake implements PlayerActions {
  final List<List<Song>> played = [];

  @override
  Future<void> playSongs(List<Song> songs, {int startIndex = 0}) async =>
      played.add(songs);
}

Widget _app(Widget child, {required _FakeRepo repo, required _FakeActions a}) =>
    ProviderScope(
      overrides: [
        libraryRepositoryProvider.overrideWithValue(repo),
        playerActionsProvider.overrideWithValue(a),
      ],
      child: MaterialApp(
        theme: gullifyThemeFor(GullifyAccent.indigo, dark: false),
        home: Scaffold(body: Center(child: child)),
      ),
    );

void main() {
  testWidgets('un genre se lance en entier, en ordre ou mélangé',
      (tester) async {
    final repo = _FakeRepo();
    final actions = _FakeActions();

    await tester.pumpWidget(
      _app(const GenrePlayButtons(genre: 'Hard Rock'), repo: repo, a: actions),
    );

    // Les deux gestes sont là sans ouvrir un artiste ni un album.
    expect(find.text('Tout lire'), findsOneWidget);
    expect(find.byIcon(Icons.shuffle), findsOneWidget);

    await tester.tap(find.text('Tout lire'));
    await tester.pumpAndSettle();

    // Le vivier demandé est bien le genre choisi — nom avec espace compris.
    expect(repo.lastSource?.effectiveMode, GameSourceMode.genres);
    expect(repo.lastSource?.genres, ['Hard Rock']);
    // Remis en ordre artiste / album / piste, pas l'ordre du serveur.
    expect(actions.played.single.map((s) => s.title), ['A', 'C', 'B']);

    await tester.tap(find.byIcon(Icons.shuffle));
    await tester.pumpAndSettle();

    // L'aléatoire garde le mélange du serveur.
    expect(actions.played.last.map((s) => s.title), ['B', 'C', 'A']);
  });

  testWidgets('un genre que le serveur ne sait pas tirer passe par ses artistes',
      (tester) async {
    final repo = _FakeRepo(
      pool: const [],
      artistsOfGenre: const [Artist(id: 7, name: 'Un groupe')],
    );
    final actions = _FakeActions();

    await tester.pumpWidget(
      _app(const GenrePlayButtons(genre: 'Rock'), repo: repo, a: actions),
    );
    await tester.tap(find.text('Tout lire'));
    await tester.pumpAndSettle();

    // Le silence n'est pas une réponse : le genre se rassemble artiste par
    // artiste, comme au volant.
    expect(actions.played.single.map((s) => s.title), ['Repli']);
  });

  testWidgets('un genre vide le dit plutôt que de lancer le vide',
      (tester) async {
    final repo = _FakeRepo(pool: const []);
    final actions = _FakeActions();

    await tester.pumpWidget(
      _app(const GenrePlayButtons(genre: 'Rock'), repo: repo, a: actions),
    );
    await tester.tap(find.text('Tout lire'));
    await tester.pumpAndSettle();

    expect(actions.played, isEmpty);
    expect(find.text('Aucun titre dans ce genre'), findsOneWidget);
  });

  testWidgets('une liste déjà en main se mélange sur place', (tester) async {
    // Le cas des téléchargements : rien à charger, donc rien à attendre.
    final actions = _FakeActions();
    final songs = _melange.toList();

    await tester.pumpWidget(_app(
      PaireDeLecture(
        titres: ({required bool shuffle}) async =>
            shuffle ? (songs.toList()..shuffle()) : songs,
      ),
      repo: _FakeRepo(),
      a: actions,
    ));

    await tester.tap(find.text('Tout lire'));
    await tester.pumpAndSettle();
    expect(actions.played.single.map((s) => s.title), ['B', 'C', 'A']);

    await tester.tap(find.byIcon(Icons.shuffle));
    await tester.pumpAndSettle();
    expect(actions.played.last.map((s) => s.title),
        containsAll(['A', 'B', 'C']));
  });

  test('l\'ordre de bibliothèque : artiste, puis album, puis piste', () {
    expect(
      enOrdreDeBibliotheque(_melange).map((s) => s.title),
      ['A', 'C', 'B'],
    );
  });
}
