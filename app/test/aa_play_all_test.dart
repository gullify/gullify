// Android Auto : partout où il y a plusieurs choix, on doit pouvoir lancer la
// musique tout de suite — « Tout lire » et « Lecture aléatoire » en tête de
// liste (idée #71). Les genres n'en avaient pas du tout : il fallait choisir
// un artiste, puis un album, puis un titre, au volant.
import 'package:flutter_test/flutter_test.dart';
import 'package:gullify/api/api_client.dart';
import 'package:gullify/api/library_repository.dart';
import 'package:gullify/audio/audio_handler.dart';
import 'package:gullify/models/album.dart';
import 'package:gullify/models/artist.dart';
import 'package:gullify/models/game_source.dart';
import 'package:gullify/models/song.dart';

class _Repository extends LibraryRepository {
  _Repository() : super(ApiClient(serverUrl: 'https://exemple.test'));

  /// La dernière demande de titres aléatoires (vivier compris).
  GameSource? lastSource;
  int? lastLimit;

  @override
  Future<List<GenreCount>> genres() async =>
      [GenreCount('Rock', 3), GenreCount('Jazz', 1)];

  @override
  Future<List<Artist>> artistsByGenre(String genre) async =>
      const [Artist(id: 7, name: 'Un groupe')];

  @override
  Future<List<Album>> albums({
    int limit = 5000,
    int offset = 0,
    String? genre,
  }) async =>
      const [Album(id: 1, name: 'Un album', artistName: 'Quelqu\'un')];

  @override
  Future<List<Artist>> artists({int limit = 5000, int offset = 0}) async =>
      const [Artist(id: 7, name: 'Un groupe')];

  @override
  Future<List<Song>> randomSongs({
    int limit = 200,
    GameSource source = GameSource.all,
  }) async {
    lastLimit = limit;
    lastSource = source;
    // Renvoyés mélangés, comme le fait le serveur (ORDER BY RAND()).
    return const [
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
  }

  @override
  String streamUrl(Song song) => 'https://exemple.test/stream/${song.id}';
}

GullifyAudioHandler _handler() {
  final handler = GullifyAudioHandler()..repository = _Repository();
  addTearDown(handler.player.dispose);
  return handler;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('un genre s\'écoute en entier sans choisir d\'artiste', () async {
    final handler = _handler();

    final items = await handler.getChildren(BrowseIds.genre('Rock'));

    expect(items.map((i) => i.id).take(2),
        ['GENRE_Rock_PLAY', 'GENRE_Rock_SHUFFLE']);
    expect(items.map((i) => i.title).take(2), ['Tout lire', 'Lecture aléatoire']);
    // Les artistes du genre restent listés en dessous.
    expect(items.map((i) => i.id), contains(BrowseIds.artist(7)));
  });

  test('la liste des genres et celle des albums lancent aussi la musique',
      () async {
    final handler = _handler();

    for (final category in [BrowseIds.genres, BrowseIds.albums]) {
      final items = await handler.getChildren(category);
      expect(
        items.map((i) => i.id).take(2),
        ['ALL_PLAY', 'ALL_SHUFFLE'],
        reason: '$category doit pouvoir se jouer sans descendre d\'un cran',
      );
    }
  });

  test('« Tout lire » un genre : les titres du genre, remis en ordre',
      () async {
    final handler = _handler();
    final repo = handler.repository! as _Repository;

    final songs = await handler.genreSongs('GENRE_Hard Rock_PLAY', repo);

    // Le vivier demandé au serveur est bien le genre choisi (nom avec espace
    // compris : il ne se découpe pas au tiret bas).
    expect(repo.lastSource?.effectiveMode, GameSourceMode.genres);
    expect(repo.lastSource?.genres, ['Hard Rock']);
    expect(repo.lastLimit, 500);
    // Ordre artiste / album / piste, pas l'ordre aléatoire du serveur.
    expect(songs.map((s) => s.title), ['A', 'C', 'B']);
  });

  test('« Lecture aléatoire » d\'un genre garde le mélange du serveur',
      () async {
    final handler = _handler();
    final repo = handler.repository! as _Repository;

    final songs = await handler.genreSongs('GENRE_Rock_SHUFFLE', repo);

    expect(songs.map((s) => s.title), ['B', 'C', 'A']);
  });

  test('un genre non jouable ne lance rien', () async {
    final handler = _handler();
    final repo = handler.repository! as _Repository;

    expect(await handler.genreSongs(BrowseIds.genre('Rock'), repo), isEmpty);
    expect(repo.lastSource, isNull); // rien n'a même été demandé au serveur
  });
}
