import 'api_client.dart';

/// Album trouvé sur YouTube Music.
class YtAlbum {
  const YtAlbum({
    required this.title,
    required this.artist,
    required this.year,
    required this.thumbnail,
    required this.browseId,
  });

  factory YtAlbum.fromJson(Map<String, dynamic> json) => YtAlbum(
        title: json['title'] as String? ?? '',
        artist: json['artist'] as String? ?? '',
        year: '${json['year'] ?? ''}',
        thumbnail: json['thumbnail'] as String? ?? '',
        browseId: json['browseId'] as String? ?? '',
      );

  final String title;
  final String artist;
  final String year;
  final String thumbnail;
  final String browseId;
}

/// Album résolu en playlist téléchargeable.
class YtResolvedAlbum {
  const YtResolvedAlbum({
    required this.playlistUrl,
    required this.artist,
    required this.title,
    required this.year,
    required this.trackCount,
    required this.thumbnail,
  });

  factory YtResolvedAlbum.fromJson(Map<String, dynamic> json) =>
      YtResolvedAlbum(
        playlistUrl: json['playlistUrl'] as String? ?? '',
        artist: json['artist'] as String? ?? '',
        title: json['title'] as String? ?? '',
        year: '${json['year'] ?? ''}',
        trackCount: (json['track_count'] as num?)?.toInt() ?? 0,
        thumbnail: json['thumbnail'] as String? ?? '',
      );

  final String playlistUrl;
  final String artist;
  final String title;
  final String year;
  final int trackCount;
  final String thumbnail;
}

/// Téléchargement serveur (queue yt-dlp, fichiers dl_*.json).
class ServerDownload {
  const ServerDownload({
    required this.id,
    required this.status,
    required this.progress,
    required this.message,
    required this.artist,
    required this.album,
    required this.createdAt,
  });

  factory ServerDownload.fromJson(Map<String, dynamic> json) => ServerDownload(
        id: json['id'] as String? ?? '',
        status: json['status'] as String? ?? 'unknown',
        progress: (json['progress'] as num?)?.toInt() ?? 0,
        message: json['message'] as String? ?? '',
        artist: json['artist'] as String? ?? '',
        album: json['album'] as String? ?? '',
        createdAt: json['created_at'] as String? ?? '',
      );

  final String id;
  final String status;
  final int progress;
  final String message;
  final String artist;
  final String album;
  final String createdAt;

  bool get isActive =>
      status == 'queued' || status == 'downloading' || status == 'scanning';
  bool get isDone => status == 'completed';
  bool get isError => status == 'error';
  bool get isCancelled => status == 'cancelled';
}

/// Recherche YouTube Music et file de téléchargement serveur (yt-dlp).
/// Le proxy v2 force `user` à l'utilisateur authentifié.
class YtDownloadsRepository {
  YtDownloadsRepository(this._client);

  final ApiClient _client;

  Future<List<YtAlbum>> searchAlbums(String query) async {
    final data = await _client.get(
      'download.php',
      query: {'action': 'search_ytmusic', 'query': query},
    ) as Map<String, dynamic>;
    final albums = data['albums'] as List<dynamic>? ?? [];
    return albums
        .cast<Map<String, dynamic>>()
        .map(YtAlbum.fromJson)
        .where((a) => a.browseId.isNotEmpty)
        .toList();
  }

  Future<YtResolvedAlbum> resolveAlbum(String browseId) async {
    final data = await _client.get(
      'download.php',
      query: {'action': 'resolve_album', 'browse_id': browseId},
    ) as Map<String, dynamic>;
    return YtResolvedAlbum.fromJson(data);
  }

  /// Met l'album en file de téléchargement. `artist_id: new` laisse le
  /// worker créer l'artiste et déclencher le scan de la bibliothèque.
  Future<String> start({
    required String url,
    required String artistName,
    required String albumName,
  }) async {
    final data = await _client.post(
      'download.php',
      query: {'action': 'start'},
      form: {
        'url': url,
        'artist_name': artistName,
        'album_name': albumName,
        'artist_id': 'new',
      },
    ) as Map<String, dynamic>;
    return data['download_id'] as String? ?? '';
  }

  Future<List<ServerDownload>> list() async {
    // Legacy renvoie {success, data, count} → l'envelope v2 préserve les
    // clés sœurs : data = {data: [...], count: n}.
    final data = await _client.get(
      'download.php',
      query: {'action': 'list'},
    ) as Map<String, dynamic>;
    final items = data['data'] as List<dynamic>? ?? [];
    return items.cast<Map<String, dynamic>>().map(ServerDownload.fromJson).toList();
  }

  Future<void> cancel(String downloadId) => _post('cancel', downloadId);

  Future<void> retry(String downloadId) => _post('retry', downloadId);

  Future<void> delete(String downloadId) => _post('delete', downloadId);

  Future<void> _post(String action, String downloadId) => _client.post(
        'download.php',
        query: {'action': action},
        form: {'download_id': downloadId},
      );
}
