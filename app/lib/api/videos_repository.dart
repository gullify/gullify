import 'api_client.dart';

/// Vidéo trouvée sur YouTube (clip, concert, live…).
class VideoResult {
  const VideoResult({
    required this.id,
    required this.title,
    required this.channel,
    required this.duration,
    required this.thumbnail,
    required this.live,
  });

  factory VideoResult.fromJson(Map<String, dynamic> json) => VideoResult(
    id: json['id'] as String? ?? '',
    title: json['title'] as String? ?? '',
    channel: json['channel'] as String? ?? '',
    duration: Duration(seconds: (json['duration'] as num?)?.toInt() ?? 0),
    thumbnail: json['thumbnail'] as String? ?? '',
    live: json['live'] as bool? ?? false,
  );

  final String id;
  final String title;
  final String channel;
  final Duration duration;
  final String thumbnail;
  final bool live;
}

/// État d'une vidéo de la vidéothèque du serveur.
enum VideoStatus { downloading, ready, error }

/// Vidéo téléchargée (ou en cours de téléchargement) sur le serveur.
class ServerVideo {
  const ServerVideo({
    required this.id,
    required this.title,
    required this.channel,
    required this.duration,
    required this.thumbnail,
    required this.status,
    required this.progress,
    required this.size,
  });

  factory ServerVideo.fromJson(Map<String, dynamic> json) => ServerVideo(
    id: json['id'] as String? ?? '',
    title: json['title'] as String? ?? '',
    channel: json['channel'] as String? ?? '',
    duration: Duration(seconds: (json['duration'] as num?)?.toInt() ?? 0),
    thumbnail: json['thumbnail'] as String? ?? '',
    status: switch (json['status'] as String? ?? '') {
      'ready' => VideoStatus.ready,
      'error' => VideoStatus.error,
      _ => VideoStatus.downloading,
    },
    progress: (json['progress'] as num?)?.toInt() ?? 0,
    size: (json['size'] as num?)?.toInt() ?? 0,
  );

  final String id;
  final String title;
  final String channel;
  final Duration duration;
  final String thumbnail;
  final VideoStatus status;

  /// Avancement du téléchargement, 0-100.
  final int progress;

  /// Taille du fichier sur le serveur, en octets.
  final int size;

  bool get isReady => status == VideoStatus.ready;
}

/// Recherche, lecture et téléchargement des vidéos (API v2 `videos.php`).
///
/// Le serveur relaie lui-même le flux : les URL YouTube sont liées à l'IP qui
/// les résout, donc injouables directement depuis le téléphone.
class VideosRepository {
  VideosRepository(this._client);

  final ApiClient _client;

  Future<List<VideoResult>> search(String query, {int limit = 20}) async {
    final data =
        await _client.get(
              'videos.php',
              query: {'action': 'search', 'q': query, 'limit': limit},
            )
            as List<dynamic>;
    return data
        .map((e) => VideoResult.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<ServerVideo>> library() async {
    final data =
        await _client.get('videos.php', query: {'action': 'library'})
            as List<dynamic>;
    return data
        .map((e) => ServerVideo.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> download(VideoResult video) => _client.post(
    'videos.php',
    query: {'action': 'download'},
    body: {
      'id': video.id,
      'title': video.title,
      'channel': video.channel,
      'duration': video.duration.inSeconds,
    },
  );

  Future<void> delete(String id) =>
      _client.post('videos.php', query: {'action': 'delete'}, body: {'id': id});

  /// URL de lecture (fichier téléchargé si disponible, sinon relais YouTube).
  String streamUrl(String id) =>
      _client.resourceUrl('api/v2/videos.php?action=stream&id=$id');
}
