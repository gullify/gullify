import '../models/album.dart';
import '../models/artist.dart';
import '../models/game_source.dart';
import '../models/game_track.dart';
import '../models/server_user.dart';
import '../models/song.dart';
import '../models/song_chords.dart';
import '../models/track_edges.dart';
import 'api_client.dart';

/// Detail payload for an artist page.
class ArtistDetail {
  const ArtistDetail({
    required this.artist,
    required this.albums,
    required this.topTracks,
  });

  final Artist artist;
  final List<Album> albums;
  final List<Song> topTracks;
}

/// Detail payload for an album page.
class AlbumDetail {
  const AlbumDetail({required this.album, required this.songs});

  final Album album;
  final List<Song> songs;
}

class NewsArticle {
  const NewsArticle({
    required this.title,
    required this.url,
    required this.source,
    required this.date,
  });

  final String title;
  final String url;
  final String source;
  final String date;
}

/// Une photo que YouTube Music ou Deezer propose pour un nom d'artiste
/// (idée #78). Le [name] est celui du service, pas celui de la bibliothèque :
/// c'est à lui qu'on voit qu'on tient l'homonyme plutôt que le bon artiste.
class ArtistImageCandidate {
  const ArtistImageCandidate({
    required this.name,
    required this.thumbnail,
    required this.source,
  });

  final String name;
  final String thumbnail;

  /// `ytmusic` ou `deezer`.
  final String source;
}

/// Ce qu'a donné la correction de l'artiste ou du titre d'un album
/// (idée #94) : l'album à afficher ensuite — ce n'est plus le même quand il a
/// fusionné avec un homonyme — et de quoi dire à l'écran ce qui s'est passé.
class AlbumEdit {
  const AlbumEdit({
    required this.albumId,
    required this.artistId,
    required this.artist,
    required this.album,
    required this.changed,
    required this.moved,
    required this.renamed,
    required this.merged,
    required this.removedArtist,
    required this.songs,
    required this.tagsWritten,
    required this.tagsFailed,
  });

  factory AlbumEdit.fromJson(Map<String, dynamic> json) => AlbumEdit(
        albumId: (json['album_id'] as num?)?.toInt() ?? 0,
        artistId: (json['artist_id'] as num?)?.toInt() ?? 0,
        artist: json['artist'] as String? ?? '',
        album: json['album'] as String? ?? '',
        changed: json['changed'] as bool? ?? false,
        moved: json['moved'] as bool? ?? false,
        renamed: json['renamed'] as bool? ?? false,
        merged: json['merged'] as bool? ?? false,
        removedArtist: json['removed_artist'] as String?,
        songs: (json['songs'] as num?)?.toInt() ?? 0,
        tagsWritten: (json['tags_written'] as num?)?.toInt() ?? 0,
        tagsFailed: (json['tags_failed'] as num?)?.toInt() ?? 0,
      );

  /// L'album après coup : l'album d'accueil si les deux ont fusionné.
  final int albumId;
  final int artistId;
  final String artist;
  final String album;

  /// Faux quand les noms envoyés étaient déjà ceux de l'album.
  final bool changed;

  /// L'album a changé d'artiste.
  final bool moved;

  /// Le titre de l'album a changé.
  final bool renamed;

  /// L'album a rejoint un album du même titre déjà chez cet artiste.
  final bool merged;

  /// L'artiste laissé sans album, effacé au passage (null sinon).
  final String? removedArtist;

  final int songs;

  /// Fichiers dont les tags ont été récrits, et ceux qui ont résisté
  /// (format que le serveur ne sait pas écrire, fichier en lecture seule).
  final int tagsWritten;
  final int tagsFailed;

  /// Ce qu'on annonce à l'écran une fois la correction faite.
  String get summary {
    if (!changed) return 'Rien à corriger';
    final what = merged
        ? 'Album réuni avec « $album »'
        : moved
            ? 'Album transféré à $artist'
            : 'Album renommé « $album »';
    if (tagsFailed > 0) {
      return '$what — tags de $tagsFailed fichier'
          '${tagsFailed > 1 ? 's' : ''} inchangés';
    }
    return what;
  }
}

/// Une jaquette que YouTube Music ou Deezer propose pour un album (idée #93).
/// Le [title] et l'[artist] sont ceux du service : deux albums du même nom ne
/// se distinguent qu'à ça, et une compilation qui a avalé le titre cherché se
/// repère de la même façon.
class AlbumCoverCandidate {
  const AlbumCoverCandidate({
    required this.title,
    required this.artist,
    required this.thumbnail,
    required this.source,
  });

  final String title;
  final String artist;
  final String thumbnail;

  /// `ytmusic` ou `deezer`.
  final String source;
}

/// Bio et actualités d'un artiste (sources externes, meilleur effort).
class ArtistExtras {
  const ArtistExtras({
    this.bio,
    this.listeners = 0,
    this.articles = const [],
  });

  final String? bio;
  final int listeners;
  final List<NewsArticle> articles;

  bool get isEmpty => bio == null && articles.isEmpty;
}

/// Suggestions du serveur, centrées sur un genre.
class Suggestions {
  const Suggestions({
    this.genre,
    this.artists = const [],
    this.albums = const [],
    this.songs = const [],
  });

  final String? genre;
  final List<Artist> artists;
  final List<Album> albums;
  final List<Song> songs;

  bool get isEmpty => artists.isEmpty && albums.isEmpty && songs.isEmpty;
}

/// Matière première des jeux : titres datés (frise chronologique, duel) et
/// albums pochettés (pochette mystère). Servi en un appel.
class GamePool {
  const GamePool({this.tracks = const [], this.albums = const []});

  final List<GameTrack> tracks;
  final List<Album> albums;
}

/// Un titre jamais écouté, servi au jeu « Défricheur » : trente secondes à
/// juger, puis on le garde ou on le passe.
class DiscoveryTrack {
  const DiscoveryTrack({required this.song, this.year});

  final Song song;

  /// L'année de l'album, affichée sur la carte quand on la connaît.
  final int? year;
}

class SearchResults {
  const SearchResults({
    this.artists = const [],
    this.albums = const [],
    this.songs = const [],
  });

  final List<Artist> artists;
  final List<Album> albums;
  final List<Song> songs;

  bool get isEmpty => artists.isEmpty && albums.isEmpty && songs.isEmpty;
}

/// Où en est la version karaoké d'un titre côté serveur (idée #63).
enum KaraokeState { ready, rendering, unavailable }

class KaraokeStatus {
  const KaraokeStatus({required this.state, this.reason});

  final KaraokeState state;

  /// Pourquoi c'est indisponible : `mono` (mixage trop centré, rien à
  /// annuler), `source` (fichier hors du serveur), `ffmpeg`, `probe`, `cache`.
  final String? reason;
}

class LibraryRepository {
  LibraryRepository(this._client);

  final ApiClient _client;

  /// Legacy endpoints return artwork as server-root-relative URLs
  /// (e.g. "serve_image.php?album_id=1") — make them absolute.
  String? _abs(String? url) {
    if (url == null || url.isEmpty) return null;
    if (url.startsWith('http://') || url.startsWith('https://')) return url;
    return _client.resourceUrl(url);
  }

  /// Les artistes dont la photo a changé depuis le lancement (idée #78), et
  /// quand. La date entre dans l'URL : sans elle, le cache d'images de l'app
  /// (comme celui d'Android) continuerait de servir l'ancienne photo, et
  /// changer d'image n'aurait l'air de rien.
  final Map<int, int> _imageVersion = {};

  /// Le suffixe d'URL qui distingue la photo courante de la précédente.
  String _imageV(int artistId) {
    final v = _imageVersion[artistId];
    return v == null ? '' : '&v=$v';
  }

  Artist _artist(Map<String, dynamic> j) {
    // Le serveur omet imageUrl quand l'image n'est pas en DB, mais
    // serve_image.php sait aussi la trouver dans le dossier de l'artiste.
    // fallback=404 : pas d'image nulle part → l'app garde son icône.
    final id = (j['id'] as num?)?.toInt() ?? 0;
    final url = j['imageUrl'] as String? ??
        'serve_image.php?artist_id=$id&fallback=404';
    return Artist.fromJson(j).copyWith(imageUrl: _abs('$url${_imageV(id)}'));
  }

  /// L'image de l'en-tête d'un artiste (idée #67). `fetch=1` autorise le
  /// serveur à aller la chercher sur le web (YouTube Music, puis Deezer) s'il
  /// ne l'a nulle part — un artiste qui vient d'arriver dans la bibliothèque
  /// n'a rien, et restait sur le logo Gullify. Réservé à la page d'un artiste :
  /// une liste en déclencherait des centaines.
  String artistImageUrl(int id) => _client.resourceUrl(
        'serve_image.php?artist_id=$id&fetch=1&fallback=404${_imageV(id)}',
      );

  /// Les albums dont la jaquette a changé depuis le lancement (idée #93), et
  /// quand. Même raison que pour les artistes : le serveur date bien ses URL,
  /// mais une liste déjà chargée garderait l'ancienne adresse — et donc
  /// l'ancienne pochette, tirée du cache d'images.
  final Map<int, int> _coverVersion = {};

  /// L'URL d'une jaquette, datée du dernier changement fait depuis l'app.
  /// La date que le serveur avait posée est remplacée par la nôtre, qui est
  /// la plus récente des deux.
  String? _cover(String? url, int? albumId) {
    final v = albumId == null ? null : _coverVersion[albumId];
    if (url == null || url.isEmpty || v == null) return _abs(url);
    final bare = url.replaceAll(RegExp(r'[&?]v=\d+'), '');
    return _abs('$bare${bare.contains('?') ? '&' : '?'}v=$v');
  }

  Album _album(Map<String, dynamic> j) => Album.fromJson(j).copyWith(
        artworkUrl:
            _cover(j['artworkUrl'] as String?, (j['id'] as num?)?.toInt()),
      );

  Song _song(Map<String, dynamic> j) => Song.fromJson(j).copyWith(
        artworkUrl:
            _cover(j['artworkUrl'] as String?, (j['albumId'] as num?)?.toInt()),
      );

  List<T> _list<T>(dynamic v, T Function(Map<String, dynamic>) map) =>
      (v as List<dynamic>? ?? [])
          .map((e) => map(e as Map<String, dynamic>))
          .toList();

  /// URL used by the audio player to stream a song.
  String streamUrl(Song song) => streamUrlForPath(song.filePath);

  /// Idem à partir du seul chemin du fichier (le lecteur n'a que ça sous la
  /// main dans les extras de sa file). En mode [karaoke], le serveur sert la
  /// version voix atténuée s'il l'a déjà rendue, et l'original sinon.
  String streamUrlForPath(String filePath, {bool karaoke = false}) =>
      _client.resourceUrl(
        'stream.php?path=${Uri.encodeQueryComponent(filePath)}'
        '${karaoke ? '&karaoke=1' : ''}',
      );

  /// Demande (et lance si besoin) le rendu de la version karaoké d'un titre.
  /// Voir src/Karaoke.php : le rendu se fait en tâche de fond, on redemande
  /// jusqu'à `ready` — ou `unavailable`, qui est définitif.
  Future<KaraokeStatus> prepareKaraoke(String filePath) async {
    final data =
        await _client.get('karaoke.php', query: {'path': filePath}) as Map;
    return KaraokeStatus(
      state: switch (data['status']) {
        'ready' => KaraokeState.ready,
        'rendering' => KaraokeState.rendering,
        _ => KaraokeState.unavailable,
      },
      reason: data['reason'] as String?,
    );
  }

  Future<List<Artist>> artists({int limit = 5000, int offset = 0}) async {
    final data = await _client.get('library.php', query: {
      'action': 'library',
      'limit': limit,
      'offset': offset,
    }) as Map<String, dynamic>;
    return _list(data['artists'], _artist);
  }

  /// Les albums de la bibliothèque, éventuellement restreints à un [genre]
  /// (porté par l'album ou, à défaut, par son artiste).
  Future<List<Album>> albums({
    int limit = 5000,
    int offset = 0,
    String? genre,
    int? year,
  }) async {
    final data = await _client.get('library.php', query: {
      'action': 'get_all_albums',
      'limit': limit,
      'offset': offset,
      'genre': ?genre,
      'year': ?year,
    }) as Map<String, dynamic>;
    return _list(data['albums'], _album);
  }

  /// Bio (Last.fm) et actualités (Google News) d'un artiste.
  Future<ArtistExtras> artistExtras(String artistName) async {
    final data = await _client.get('artist-news.php', query: {
      'artist': artistName,
    }) as Map<String, dynamic>;
    final bio = data['bio'] as Map<String, dynamic>?;
    final news = data['news'] as Map<String, dynamic>?;
    return ArtistExtras(
      bio: bio?['available'] == true ? bio!['bio_summary'] as String? : null,
      listeners: (bio?['listeners'] as num?)?.toInt() ?? 0,
      articles: [
        for (final a in (news?['articles'] as List<dynamic>? ?? []))
          NewsArticle(
            title: (a as Map<String, dynamic>)['title'] as String? ?? '',
            url: a['url'] as String? ?? '',
            source: a['source'] as String? ?? '',
            date: a['date'] as String? ?? '',
          ),
      ],
    );
  }

  /// Échantillon aléatoire de la bibliothèque (mélangé côté serveur).
  /// [source] restreint le vivier (genres, playlists, favoris) pour les jeux.
  Future<List<Song>> randomSongs({
    int limit = 200,
    GameSource source = GameSource.all,
  }) async {
    final data =
        await _client.get('library.php', query: {
      'action': 'random_songs',
      'limit': limit,
      ...source.query,
    });
    return _list(data, _song);
  }

  /// Matière première des jeux : un titre par album daté et pochetté, plus
  /// des albums pochettés, le tout mélangé côté serveur.
  Future<GamePool> gamePool({
    int limit = 150,
    GameSource source = GameSource.all,
  }) async {
    final data = await _client.get('library.php', query: {
      'action': 'game_pool',
      'limit': limit,
      ...source.query,
    }) as Map<String, dynamic>;
    return GamePool(
      tracks: [
        for (final e in data['tracks'] as List<dynamic>? ?? [])
          if (((e as Map<String, dynamic>)['year'] as num?) != null)
            GameTrack(song: _song(e), year: (e['year'] as num).toInt()),
      ],
      albums: _list(data['albums'], _album),
    );
  }

  /// Ce que le serveur a mesuré aux bords des titres demandés (idée #79) :
  /// silence de fin, descente naturelle, entrée en matière, niveau de
  /// référence et niveaux des deux bords (idée #102), de quoi tailler le fondu
  /// enchaîné sur le morceau. Les titres que le serveur ne sait pas
  /// analyser (stockage distant, fichier illisible) sont simplement absents du
  /// résultat — le lecteur retombe alors sur le croisement réglé à la main.
  Future<Map<int, TrackEdges>> songTransitions(List<int> songIds) async {
    if (songIds.isEmpty) return const {};
    final data = await _client.get('library.php', query: {
      'action': 'song_transitions',
      'ids': songIds.join(','),
    }) as Map<String, dynamic>;
    final edges = <int, TrackEdges>{};
    for (final e in data['transitions'] as List<dynamic>? ?? []) {
      final row = e as Map<String, dynamic>;
      final id = (row['songId'] as num?)?.toInt();
      if (id == null) continue;
      Duration ms(String key) =>
          Duration(milliseconds: (row[key] as num?)?.round() ?? 0);
      // Un niveau RMS est toujours négatif : zéro veut dire « jamais mesuré »
      // (profil mis en cache avant que le serveur ne le rende), et se comparer
      // à zéro retiendrait le titre suivant pour rien.
      double? db(String key) {
        final value = (row[key] as num?)?.toDouble();
        return value != null && value < 0 ? value : null;
      }

      edges[id] = TrackEdges(
        tail: ms('tailMs'),
        decay: ms('decayMs'),
        lead: ms('leadMs'),
        level: db('levelDb'),
      );
    }
    return edges;
  }

  /// Titres récemment écoutés (distincts), du plus récent au plus ancien.
  Future<List<Song>> recentSongs({int limit = 50}) async {
    final data = await _client.get('library.php', query: {
      'action': 'recent_songs',
      'limit': limit,
    });
    return _list(data, _song);
  }

  /// Titres jamais joués, assez longs pour qu'il y ait quelque chose à
  /// entendre (jeu « Défricheur »). Mélangés côté serveur.
  Future<List<DiscoveryTrack>> discoveryTracks({
    int limit = 60,
    GameSource source = GameSource.all,
  }) async {
    final data = await _client.get('library.php', query: {
      'action': 'discovery_tracks',
      'limit': limit,
      ...source.query,
    }) as Map<String, dynamic>;
    return [
      for (final e in data['songs'] as List<dynamic>? ?? [])
        DiscoveryTrack(
          song: _song(e as Map<String, dynamic>),
          year: (e['year'] as num?)?.toInt(),
        ),
    ];
  }

  /// Titres jamais joués (mode « Découverte »), mélangés.
  Future<List<Song>> discoverySongs({int limit = 200}) async {
    final data = await _client.get('library.php', query: {
      'action': 'discovery_songs',
      'limit': limit,
    });
    return _list(data, _song);
  }

  /// Titres les plus écoutés (song_stats).
  Future<List<Song>> popularSongs({int limit = 20}) async {
    final data = await _client.get('popular.php', query: {'limit': limit});
    return _list(data, _song);
  }

  /// Suggestions basées sur un genre écouté récemment.
  Future<Suggestions> suggestions() async {
    final data = await _client.get('suggestions.php') as Map<String, dynamic>;
    return Suggestions(
      genre: data['genre'] as String?,
      artists: _list(data['artists'], _artist),
      albums: _list(data['albums'], _album),
      songs: _list(data['songs'], _song),
    );
  }

  Future<List<Album>> recentAlbums({int limit = 20}) async {
    final data = await _client.get('library.php', query: {
      'action': 'recent_albums',
      'limit': limit,
    });
    return _list(data, _album);
  }

  Future<ArtistDetail> artistDetail(int id) async {
    final data = await _client.get('library.php', query: {
      'action': 'artist',
      'id': id,
    }) as Map<String, dynamic>;
    final artist = _artist(data['artist'] as Map<String, dynamic>);
    return ArtistDetail(
      artist: artist.copyWith(imageUrl: artistImageUrl(id)),
      albums: _list(data['albums'], _album),
      topTracks: _list(data['topTracks'], _song),
    );
  }

  Future<AlbumDetail> albumDetail(int id) async {
    final data = await _client.get('library.php', query: {
      'action': 'album_songs',
      'id': id,
    }) as Map<String, dynamic>;
    final artist = data['artist'] as Map<String, dynamic>?;
    return AlbumDetail(
      album: Album(
        id: (data['id'] as num).toInt(),
        name: data['name'] as String? ?? '',
        year: (data['year'] as num?)?.toInt(),
        artworkUrl: _abs(data['artworkUrl'] as String?),
        artistId: (artist?['id'] as num?)?.toInt(),
        artistName: artist?['name'] as String?,
      ),
      songs: _list(data['songs'], _song),
    );
  }

  Future<Set<int>> favoriteIds() async {
    final data = await _client.get('library.php', query: {
      'action': 'get_favorites',
    }) as List<dynamic>;
    return {
      for (final e in data) ((e as Map<String, dynamic>)['id'] as num).toInt(),
    };
  }

  Future<List<Song>> allFavorites() async {
    final data = await _client.get('library.php', query: {
      'action': 'get_all_favorites',
    }) as Map<String, dynamic>;
    // get_all_favorites uses `artist`/`album` keys instead of the usual names.
    return [
      for (final e in data['songs'] as List<dynamic>? ?? [])
        _song({
          ...e as Map<String, dynamic>,
          'artistName': e['artist'],
          'albumName': e['album'],
        }),
    ];
  }

  /// Returns true if the song is now a favorite.
  Future<bool> toggleFavorite(int songId) async {
    final data = await _client.post(
      'library.php',
      query: {'action': 'toggle_favorite'},
      form: {'song_id': songId},
    ) as Map<String, dynamic>;
    return data['status'] == 'added';
  }

  Future<String?> lyrics(String filePath) async {
    final data = await _client.get('lyrics.php', query: {
      'path': filePath,
    }) as Map<String, dynamic>;
    // syncedLyrics = LRC horodaté (défilement synchronisé); sinon texte brut.
    final synced = data['syncedLyrics'] as String?;
    if (synced != null && synced.trim().isNotEmpty) return synced;
    final l = data['lyrics'] as String?;
    return (l == null || l.trim().isEmpty) ? null : l;
  }

  /// Grille d'accords guitare du titre (bouton « Accords » du lecteur).
  Future<ChordsResult> chords(String filePath) async {
    final data = await _client.get('chords.php', query: {
      'path': filePath,
    }) as Map<String, dynamic>;
    final raw = data['chords'];
    return ChordsResult(
      chords: raw is Map<String, dynamic> ? SongChords.fromJson(raw) : null,
      searchUrl: data['searchUrl'] as String?,
    );
  }

  /// Report a play to the server (play_history + song_stats).
  Future<void> trackPlay({
    required int songId,
    required int seconds,
    required bool completed,
  }) async {
    await _client.post(
      'radio.php',
      query: {'action': 'track_play'},
      form: {
        'song_id': songId,
        'duration_played': seconds,
        'completed': completed ? 1 : 0,
      },
    );
  }

  Future<SearchResults> search(String query) async {
    if (query.trim().isEmpty) return const SearchResults();
    // Le serveur lit `q` (le nom `query` était ignoré → il renvoyait tout).
    final data = await _client.get('library.php', query: {
      'action': 'search',
      'q': query,
    }) as Map<String, dynamic>;
    return SearchResults(
      artists: _list(data['artists'], _artist),
      albums: _list(data['albums'], _album),
      songs: _list(data['songs'], _song),
    );
  }

  // ─────────────── Suppression définitive (fichiers + base) ───────────────

  Future<void> deleteSongs(List<int> songIds) => _client.post(
        'library.php',
        query: {'action': 'delete_songs'},
        body: {'song_ids': songIds},
      );

  Future<void> deleteAlbum(int albumId) => _client.post(
        'library.php',
        query: {'action': 'delete_album'},
        form: {'album_id': albumId},
      );

  Future<void> deleteArtist(int artistId) => _client.post(
        'library.php',
        query: {'action': 'delete_artist'},
        form: {'artist_id': artistId},
      );

  // ─────────────── Photo d'un artiste (idée #78) ───────────────

  /// Les photos que YouTube Music et Deezer proposent pour cet artiste — sous
  /// son nom, ou sous [query] quand c'est un homonyme qui a été trouvé.
  Future<List<ArtistImageCandidate>> artistImageCandidates(
    int artistId, {
    String? query,
  }) async {
    final data = await _client.get('library.php', query: {
      'action': 'artist_image_candidates',
      'artist_id': artistId,
      'q': ?query,
    }) as Map<String, dynamic>;
    return [
      for (final c in data['candidates'] as List<dynamic>? ?? [])
        if (c is Map<String, dynamic>)
          ArtistImageCandidate(
            name: c['name'] as String? ?? '',
            thumbnail: c['thumbnail'] as String? ?? '',
            source: c['source'] as String? ?? '',
          ),
    ];
  }

  /// Donne à l'artiste la photo qui se trouve à cette adresse (lien collé, ou
  /// proposition choisie dans la liste).
  Future<void> setArtistImageFromUrl(int artistId, String url) async {
    final data = await _client.post(
      'library.php',
      query: {'action': 'set_artist_image'},
      form: {'artist_id': artistId, 'url': url},
    );
    _noteImageChange(artistId, data);
  }

  /// Envoie une image du téléphone comme photo de l'artiste.
  Future<void> uploadArtistImage(int artistId, String filePath) async {
    _noteImageChange(
      artistId,
      await _client.uploadArtistImage(artistId, filePath),
    );
  }

  /// Défait le choix manuel : l'image du dossier de l'artiste, ou celle du
  /// web, reprend la main.
  Future<void> resetArtistImage(int artistId) async {
    final data = await _client.post(
      'library.php',
      query: {'action': 'reset_artist_image'},
      form: {'artist_id': artistId},
    );
    _noteImageChange(artistId, data);
  }

  /// Retient que la photo a changé, pour que les URL construites ensuite ne
  /// ressemblent pas à celles d'avant. La date vient du serveur quand il la
  /// donne (elle vaut 0 après une remise à zéro) ; sinon celle du téléphone,
  /// qui suffit à distinguer l'avant de l'après.
  void _noteImageChange(int artistId, dynamic data) {
    final v = data is Map ? (data['version'] as num?)?.toInt() ?? 0 : 0;
    _imageVersion[artistId] =
        v > 0 ? v : DateTime.now().millisecondsSinceEpoch ~/ 1000;
  }

  // ─────────────── Artiste et titre d'un album (idée #94) ───────────────

  /// Corrige l'artiste et/ou le titre de l'album, ce qui le TRANSFÈRE :
  /// il rejoint l'artiste ainsi nommé (celui qui existe déjà, s'il existe) et
  /// se réunit avec l'album du même titre s'il y en a un chez lui. Le serveur
  /// récrit aussi les tags des fichiers, sans quoi le prochain scan ramènerait
  /// l'erreur.
  Future<AlbumEdit> editAlbum(
    int albumId, {
    required String artist,
    required String album,
  }) async {
    final data = await _client.post(
      'library.php',
      query: {'action': 'edit_album'},
      form: {'album_id': albumId, 'artist': artist, 'album': album},
    );
    return AlbumEdit.fromJson(data as Map<String, dynamic>);
  }

  // ─────────────── Jaquette d'un album (idée #93) ───────────────

  /// Les jaquettes que YouTube Music et Deezer proposent pour cet album —
  /// sous « artiste titre », ou sous [query] quand ce n'est pas ce libellé-là
  /// qu'il faut chercher (album mal taggé, titre original, réédition).
  Future<List<AlbumCoverCandidate>> albumCoverCandidates(
    int albumId, {
    String? query,
  }) async {
    final data = await _client.get('library.php', query: {
      'action': 'album_cover_candidates',
      'album_id': albumId,
      'q': ?query,
    }) as Map<String, dynamic>;
    return [
      for (final c in data['candidates'] as List<dynamic>? ?? [])
        if (c is Map<String, dynamic>)
          AlbumCoverCandidate(
            title: c['title'] as String? ?? '',
            artist: c['artist'] as String? ?? '',
            thumbnail: c['thumbnail'] as String? ?? '',
            source: c['source'] as String? ?? '',
          ),
    ];
  }

  /// Donne à l'album la jaquette qui se trouve à cette adresse (lien collé,
  /// ou proposition choisie dans la liste).
  Future<void> setAlbumCoverFromUrl(int albumId, String url) async {
    final data = await _client.post(
      'library.php',
      query: {'action': 'set_album_cover'},
      form: {'album_id': albumId, 'url': url},
    );
    _noteCoverChange(albumId, data);
  }

  /// Envoie une image du téléphone comme jaquette de l'album.
  Future<void> uploadAlbumCover(int albumId, String filePath) async {
    _noteCoverChange(
      albumId,
      await _client.uploadAlbumCover(albumId, filePath),
    );
  }

  /// Défait le choix manuel : la pochette du dossier, ou celle des tags,
  /// reprend la main.
  Future<void> resetAlbumCover(int albumId) async {
    final data = await _client.post(
      'library.php',
      query: {'action': 'reset_album_cover'},
      form: {'album_id': albumId},
    );
    _noteCoverChange(albumId, data);
  }

  /// Retient que la jaquette a changé, pour que les URL construites ensuite
  /// ne ressemblent pas à celles d'avant (voir [_noteImageChange]).
  void _noteCoverChange(int albumId, dynamic data) {
    final v = data is Map ? (data['version'] as num?)?.toInt() ?? 0 : 0;
    _coverVersion[albumId] =
        v > 0 ? v : DateTime.now().millisecondsSinceEpoch ~/ 1000;
  }

  // ─────────────── Genres ───────────────

  /// Définit le genre d'un artiste (propagé à ses albums côté serveur).
  Future<void> setArtistGenre(int artistId, String genre) => _client.post(
        'library.php',
        query: {'action': 'set_artist_genre'},
        form: {'artist_id': artistId, 'genre': genre},
      );

  /// Liste des genres présents dans la bibliothèque (nom + nb d'artistes).
  Future<List<GenreCount>> genres() async {
    final data = await _client.get('library.php', query: {
      'action': 'get_genres',
    }) as Map<String, dynamic>;
    return _list(
      data['genres'],
      (j) => GenreCount(
        j['name'] as String? ?? '',
        (j['artistCount'] as num?)?.toInt() ?? 0,
        albumCount: (j['albumCount'] as num?)?.toInt() ?? 0,
        artworkUrls: [
          for (final u in j['artworkUrls'] as List<dynamic>? ?? [])
            ?_abs(u as String?),
        ],
      ),
    );
  }

  /// Les millésimes présents dans la bibliothèque (idée #80), du plus récent
  /// au plus ancien. L'année vient de l'album : c'est la seule date que porte
  /// la bibliothèque.
  Future<List<YearCount>> years() async {
    final data = await _client.get('library.php', query: {
      'action': 'get_years',
    }) as Map<String, dynamic>;
    return _list(
      data['years'],
      (j) => YearCount(
        (j['year'] as num?)?.toInt() ?? 0,
        albumCount: (j['albumCount'] as num?)?.toInt() ?? 0,
        songCount: (j['songCount'] as num?)?.toInt() ?? 0,
        artworkUrls: [
          for (final u in j['artworkUrls'] as List<dynamic>? ?? [])
            ?_abs(u as String?),
        ],
      ),
    );
  }

  /// Le flux d'une année (idée #80) : ses titres, mélangés côté serveur.
  Future<List<Song>> yearSongs(int year, {int limit = 200}) async {
    final data = await _client.get('library.php', query: {
      'action': 'year_songs',
      'year': year,
      'limit': limit,
    });
    return _list(data, _song);
  }

  /// Les genres que le serveur propose (ils ne dépendent pas de ce que
  /// contient la bibliothèque) : la liste principale, puis ceux ajoutés à la
  /// main.
  Future<GenreTaxonomy> genreTaxonomy() async {
    final data = await _client.get('library.php', query: {
      'action': 'get_genre_taxonomy',
    }) as Map<String, dynamic>;
    List<String> names(Object? raw) => [
          for (final g in raw as List<dynamic>? ?? [])
            if (g is String && g.isNotEmpty) g,
        ];
    return GenreTaxonomy(
      genres: names(data['genres']),
      custom: names(data['custom']),
    );
  }

  /// Ajoute un genre à la liste proposée. Le serveur refuse un nom vide ou un
  /// genre déjà là (à la casse et aux accents près) : le message qu'il rend
  /// est fait pour être montré tel quel.
  Future<void> addGenre(String name) => _client.post(
        'library.php',
        query: {'action': 'add_genre'},
        form: {'name': name},
      );

  /// Le genre que les catalogues suggèrent pour un artiste (MusicBrainz, puis
  /// Deezer, puis Apple Music), ramené à la liste fermée. `genre` est nul
  /// quand rien de fiable n'en sort — mieux vaut aucune suggestion qu'une
  /// fausse.
  Future<GenreSuggestion> suggestArtistGenre(int artistId) async {
    final data = await _client.get('library.php', query: {
      'action': 'suggest_artist_genre',
      'artist_id': artistId,
    }) as Map<String, dynamic>;
    return GenreSuggestion(
      genre: (data['genre'] as String?)?.trim().isEmpty ?? true
          ? null
          : data['genre'] as String,
      tags: [
        for (final t in data['tags'] as List<dynamic>? ?? [])
          if (t is String && t.isNotEmpty) t,
      ],
      source: (data['source'] as String?)?.trim().isEmpty ?? true
          ? null
          : data['source'] as String,
    );
  }

  Future<void> renameGenre(String from, String to) => _client.post(
        'library.php',
        query: {'action': 'rename_genre'},
        form: {'from': from, 'to': to},
      );

  Future<void> deleteGenre(String genre) => _client.post(
        'library.php',
        query: {'action': 'delete_genre'},
        form: {'genre': genre},
      );

  /// Les artistes qui n'ont pas encore de genre, par ordre alphabétique. La
  /// liste est plafonnée ([limit]) mais le total dit combien il en reste : de
  /// quoi enchaîner le rangement d'un artiste au suivant.
  Future<UntaggedArtists> artistsWithoutGenre({int limit = 50}) async {
    final data = await _client.get('library.php', query: {
      'action': 'get_artists_without_genre',
      'limit': limit,
    }) as Map<String, dynamic>;
    return UntaggedArtists(
      artists: _list(data['artists'], _artist),
      total: (data['total'] as num?)?.toInt() ?? 0,
    );
  }

  Future<List<Artist>> artistsByGenre(String genre) async {
    final data = await _client.get('library.php', query: {
      'action': 'get_artists_by_genre',
      'genre': genre,
    }) as Map<String, dynamic>;
    return _list(data['artists'], _artist);
  }

  // ─────────────── Scan de la bibliothèque ───────────────

  /// Lance un scan complet du dossier musique (nouveaux artistes / albums /
  /// titres, pochettes régénérées). Le scan tourne côté serveur en arrière-
  /// plan ; suivre l'avancement via [scanStatus].
  Future<void> forceScan() =>
      _client.get('scan.php', query: {'action': 'force_scan'});

  /// Scan rapide : structure seulement, sans (re)extraire les pochettes.
  Future<void> fastScan() =>
      _client.get('scan.php', query: {'action': 'fast_scan'});

  /// État du scan de la bibliothèque (en cours ? dernière mise à jour ?).
  Future<ScanStatus> scanStatus() async {
    final data = await _client.get('scan.php', query: {
      'action': 'scan_status',
    }) as Map<String, dynamic>;
    return ScanStatus(
      scanning: data['scanning'] == true,
      lastUpdate: (data['last_update'] as num?)?.toInt(),
    );
  }

  /// Détecte automatiquement le genre des artistes qui n'en ont pas (via
  /// MusicBrainz). Tourne côté serveur ; suivre via [genreScanStatus].
  Future<void> genreScan() =>
      _client.get('scan.php', query: {'action': 'genre_scan'});

  /// État de la détection automatique de genres.
  Future<GenreScanStatus> genreScanStatus() async {
    final data = await _client.get('scan.php', query: {
      'action': 'genre_scan_status',
    }) as Map<String, dynamic>;
    final p = data['progress'] as Map<String, dynamic>? ?? const {};
    return GenreScanStatus(
      scanning: data['scanning'] == true,
      status: p['status'] as String? ?? 'idle',
      processed: (p['processed'] as num?)?.toInt() ?? 0,
      total: (p['total'] as num?)?.toInt() ?? 0,
      percent: (p['percent'] as num?)?.toInt() ?? 0,
      currentArtist: p['current_artist'] as String? ?? '',
    );
  }

  // ─────────────── Découverte des autres utilisateurs ───────────────

  /// Les autres utilisateurs du serveur, du plus grand catalogue au plus
  /// petit (pour explorer leurs bibliothèques).
  Future<List<ServerUser>> serverUsers() async {
    final data = await _client.get('users.php', query: {
      'action': 'list',
    }) as Map<String, dynamic>;
    return [
      for (final e in data['users'] as List<dynamic>? ?? [])
        _serverUser(e as Map<String, dynamic>),
    ];
  }

  ServerUser _serverUser(Map<String, dynamic> j) => ServerUser(
        id: (j['id'] as num).toInt(),
        username: j['username'] as String? ?? '',
        fullName: j['fullName'] as String?,
        artistCount: (j['artistCount'] as num?)?.toInt() ?? 0,
        albumCount: (j['albumCount'] as num?)?.toInt() ?? 0,
        songCount: (j['songCount'] as num?)?.toInt() ?? 0,
        avatarUrl: _abs(j['avatarUrl'] as String?),
      );

  /// La liste des artistes de la bibliothèque d'un autre utilisateur.
  /// Les détails (artiste/album) et la lecture passent ensuite par les
  /// endpoints habituels, indexés par id global.
  Future<List<Artist>> userLibrary(String username) async {
    final data = await _client.get('users.php', query: {
      'action': 'library',
      'user': username,
    }) as Map<String, dynamic>;
    return _list(data['artists'], _artist);
  }
}

/// Ce que les catalogues disent d'un artiste : un genre de la liste fermée
/// (nul si rien de fiable n'en sort), les étiquettes qui y ont mené — elles se
/// montrent, pour que le choix reste éclairé plutôt qu'imposé — et [source],
/// celui des catalogues qui a répondu.
class GenreSuggestion {
  const GenreSuggestion({this.genre, this.tags = const [], this.source});

  final String? genre;
  final List<String> tags;

  /// « musicbrainz », « deezer », « itunes », ou nul quand personne n'a rien
  /// dit. Voir [sourceLabel] pour le nom à afficher.
  final String? source;

  bool get isEmpty => genre == null && tags.isEmpty;

  /// Le nom du catalogue tel qu'on le montre. Une source inconnue se donne
  /// telle quelle plutôt que de se taire : c'est le serveur qui la nomme.
  String? get sourceLabel => switch (source) {
        'musicbrainz' => 'MusicBrainz',
        'deezer' => 'Deezer',
        'itunes' => 'Apple Music',
        null || '' => null,
        final other => other,
      };
}

/// Les genres proposés au moment de ranger un artiste : [genres] les donne
/// tous, dans l'ordre d'affichage voulu ; [custom] rappelle lesquels ont été
/// ajoutés à la main (ils figurent aussi dans [genres], à la fin).
class GenreTaxonomy {
  const GenreTaxonomy({this.genres = const [], this.custom = const []});

  final List<String> genres;
  final List<String> custom;
}

/// Les artistes qu'il reste à ranger : un début de liste (plafonnée) et le
/// nombre exact qui reste sans genre.
class UntaggedArtists {
  const UntaggedArtists({this.artists = const [], this.total = 0});

  final List<Artist> artists;
  final int total;

  /// Le premier de la liste qui n'est pas [exceptId] — l'artiste qu'on vient
  /// de ranger peut encore y figurer si le serveur a répondu de son cache.
  Artist? next({int? exceptId}) {
    for (final a in artists) {
      if (a.id != exceptId) return a;
    }
    return null;
  }
}

/// Un genre, ce qu'il pèse dans la bibliothèque et un aperçu de ses
/// pochettes (mosaïque de la vue « Genres »).
class GenreCount {
  const GenreCount(
    this.name,
    this.artistCount, {
    this.albumCount = 0,
    this.artworkUrls = const [],
  });

  final String name;
  final int artistCount;
  final int albumCount;

  /// Jusqu'à 4 pochettes d'albums du genre (les plus récentes).
  final List<String> artworkUrls;
}

/// Un millésime de la bibliothèque, ce qu'il pèse et un aperçu de ses
/// pochettes (mosaïque de la vue « Années », idée #80).
class YearCount {
  const YearCount(
    this.year, {
    this.albumCount = 0,
    this.songCount = 0,
    this.artworkUrls = const [],
  });

  final int year;
  final int albumCount;
  final int songCount;

  /// Jusqu'à 4 pochettes d'albums de l'année.
  final List<String> artworkUrls;

  /// La décennie à laquelle l'année appartient (1994 → 1990).
  int get decade => year - year % 10;
}

/// État d'un scan de la bibliothèque.
class ScanStatus {
  const ScanStatus({required this.scanning, this.lastUpdate});

  final bool scanning;

  /// Horodatage Unix (secondes) de la dernière mise à jour, ou null.
  final int? lastUpdate;

  DateTime? get lastUpdateAt => lastUpdate == null
      ? null
      : DateTime.fromMillisecondsSinceEpoch(lastUpdate! * 1000);
}

/// État de la détection automatique de genres (MusicBrainz).
class GenreScanStatus {
  const GenreScanStatus({
    required this.scanning,
    required this.status,
    required this.processed,
    required this.total,
    required this.percent,
    required this.currentArtist,
  });

  final bool scanning;
  final String status; // idle | starting | scanning | completed | error
  final int processed;
  final int total;
  final int percent;
  final String currentArtist;
}
