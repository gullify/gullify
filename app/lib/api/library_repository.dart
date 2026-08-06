import '../models/album.dart';
import '../models/artist.dart';
import '../models/game_source.dart';
import '../models/game_track.dart';
import '../models/server_user.dart';
import '../models/song.dart';
import '../models/song_chords.dart';
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

  Artist _artist(Map<String, dynamic> j) {
    // Le serveur omet imageUrl quand l'image n'est pas en DB, mais
    // serve_image.php sait aussi la trouver dans le dossier de l'artiste.
    // fallback=404 : pas d'image nulle part → l'app garde son icône.
    final url = j['imageUrl'] as String? ??
        'serve_image.php?artist_id=${j['id']}&fallback=404';
    return Artist.fromJson(j).copyWith(imageUrl: _abs(url));
  }

  Album _album(Map<String, dynamic> j) =>
      Album.fromJson(j).copyWith(artworkUrl: _abs(j['artworkUrl'] as String?));

  Song _song(Map<String, dynamic> j) =>
      Song.fromJson(j).copyWith(artworkUrl: _abs(j['artworkUrl'] as String?));

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
  }) async {
    final data = await _client.get('library.php', query: {
      'action': 'get_all_albums',
      'limit': limit,
      'offset': offset,
      'genre': ?genre,
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
    return ArtistDetail(
      artist: _artist(data['artist'] as Map<String, dynamic>),
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
