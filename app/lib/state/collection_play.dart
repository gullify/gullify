import '../api/library_repository.dart';
import '../models/game_source.dart';
import '../models/song.dart';

/// Ce qu'il faut pour lancer une collection sans la parcourir : ses titres,
/// en ordre ou mélangés. Un genre, une année, un artiste — la même liste au
/// volant et à l'écran, pour qu'« aléatoire » veuille dire la même chose aux
/// deux endroits.

/// L'ordre d'une bibliothèque : par artiste, par album, puis par numéro de
/// piste. C'est l'ordre dans lequel on veut entendre un genre ou une année
/// quand, justement, on ne veut pas de hasard.
List<Song> enOrdreDeBibliotheque(List<Song> songs) => songs.toList()
  ..sort((a, b) {
    final artist = (a.artistName ?? '').compareTo(b.artistName ?? '');
    if (artist != 0) return artist;
    final album = (a.albumName ?? '').compareTo(b.albumName ?? '');
    if (album != 0) return album;
    return (a.trackNumber ?? 0).compareTo(b.trackNumber ?? 0);
  });

/// Tous les titres d'un artiste, album par album, dans l'ordre des disques.
Future<List<Song>> titresDeLArtiste(LibraryRepository repo, int artistId) async {
  final detail = await repo.artistDetail(artistId);
  final albums = await Future.wait(
    [for (final a in detail.albums) repo.albumDetail(a.id)],
  );
  return [for (final a in albums) ...a.songs];
}

/// Les titres d'un genre. Le serveur tire dans son vivier (mélangé) ; s'il ne
/// rend rien, on rassemble le genre artiste par artiste plutôt que de laisser
/// le silence. [shuffle] garde la liste telle quelle ; sinon elle est remise
/// en ordre.
Future<List<Song>> titresDuGenre(
  LibraryRepository repo,
  String genre, {
  required bool shuffle,
  int limit = 500,
  void Function(String message)? journal,
}) async {
  var songs = await repo.randomSongs(
    limit: limit,
    source: GameSource(mode: GameSourceMode.genres, genres: [genre]),
  );
  if (songs.isEmpty) {
    songs = await _titresParArtiste(repo, genre, journal: journal);
    if (songs.isNotEmpty) songs = songs.toList()..shuffle();
  }
  journal?.call('genre « $genre » : ${songs.length} titres '
      '(${shuffle ? 'aléatoire' : 'tout lire'})');
  return shuffle ? songs : enOrdreDeBibliotheque(songs);
}

/// Repli du genre : ses artistes, puis leurs titres. Un genre peut compter
/// cinquante artistes et chacun coûte un détail par album — on s'arrête donc à
/// une poignée d'artistes tirés au hasard, de quoi remplir une file sans faire
/// attendre. Un artiste illisible est simplement sauté.
Future<List<Song>> _titresParArtiste(
  LibraryRepository repo,
  String genre, {
  void Function(String message)? journal,
}) async {
  const maxArtists = 8;
  final artists = await repo.artistsByGenre(genre);
  if (artists.isEmpty) return const [];
  final picked = artists.toList()..shuffle();
  final songs = <Song>[];
  for (final ar in picked.take(maxArtists)) {
    try {
      songs.addAll(await titresDeLArtiste(repo, ar.id));
    } catch (e) {
      journal?.call('genre « $genre » : artiste ${ar.name} illisible ($e)');
    }
  }
  journal?.call('genre « $genre » : repli par artiste, ${songs.length} titres');
  return songs;
}

/// Les titres d'une année : la radio « machine à remonter le temps » quand on
/// les mélange, l'année en ordre sinon.
Future<List<Song>> titresDeLAnnee(
  LibraryRepository repo,
  int year, {
  required bool shuffle,
}) async {
  final songs = await repo.yearSongs(year);
  return shuffle ? songs : enOrdreDeBibliotheque(songs);
}
