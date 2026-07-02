import '../models/album.dart';
import '../models/artist.dart';
import '../models/song.dart';
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

  Artist _artist(Map<String, dynamic> j) =>
      Artist.fromJson(j).copyWith(imageUrl: _abs(j['imageUrl'] as String?));

  Album _album(Map<String, dynamic> j) =>
      Album.fromJson(j).copyWith(artworkUrl: _abs(j['artworkUrl'] as String?));

  Song _song(Map<String, dynamic> j) =>
      Song.fromJson(j).copyWith(artworkUrl: _abs(j['artworkUrl'] as String?));

  List<T> _list<T>(dynamic v, T Function(Map<String, dynamic>) map) =>
      (v as List<dynamic>? ?? [])
          .map((e) => map(e as Map<String, dynamic>))
          .toList();

  /// URL used by the audio player to stream a song.
  String streamUrl(Song song) => _client.resourceUrl(
        'stream.php?path=${Uri.encodeQueryComponent(song.filePath)}',
      );

  Future<List<Artist>> artists({int limit = 5000, int offset = 0}) async {
    final data = await _client.get('library.php', query: {
      'action': 'library',
      'limit': limit,
      'offset': offset,
    }) as Map<String, dynamic>;
    return _list(data['artists'], _artist);
  }

  Future<List<Album>> albums({int limit = 5000, int offset = 0}) async {
    final data = await _client.get('library.php', query: {
      'action': 'get_all_albums',
      'limit': limit,
      'offset': offset,
    }) as Map<String, dynamic>;
    return _list(data['albums'], _album);
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
    final l = data['lyrics'] as String?;
    return (l == null || l.trim().isEmpty) ? null : l;
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
    final data = await _client.get('library.php', query: {
      'action': 'search',
      'query': query,
    }) as Map<String, dynamic>;
    return SearchResults(
      artists: _list(data['artists'], _artist),
      albums: _list(data['albums'], _album),
      songs: _list(data['songs'], _song),
    );
  }
}
