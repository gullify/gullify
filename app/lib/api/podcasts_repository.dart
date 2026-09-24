import 'api_client.dart';

/// Une série de podcast (idée #112) : le flux et sa fiche.
///
/// Le flux (`feedUrl`) est l'identité d'une série d'un bout à l'autre — c'est
/// lui qu'on garde en s'abonnant, lui qui ouvre la liste des épisodes.
class PodcastShow {
  const PodcastShow({
    required this.feedUrl,
    required this.title,
    this.author = '',
    this.image = '',
    this.description = '',
    this.genre = '',
    this.itunesId = 0,
    this.episodeCount = 0,
    this.subscribed = false,
  });

  factory PodcastShow.fromJson(Map<String, dynamic> json) => PodcastShow(
        feedUrl: json['feedUrl'] as String? ?? '',
        title: json['title'] as String? ?? '',
        author: json['author'] as String? ?? '',
        image: json['image'] as String? ?? '',
        description: json['description'] as String? ?? '',
        genre: json['genre'] as String? ?? '',
        itunesId: (json['itunesId'] as num?)?.toInt() ?? 0,
        episodeCount: (json['episodeCount'] as num?)?.toInt() ?? 0,
        subscribed: json['subscribed'] == true,
      );

  final String feedUrl;
  final String title;
  final String author;
  final String image;
  final String description;
  final String genre;

  /// Identifiant dans l'annuaire d'Apple, 0 pour un flux ajouté à la main.
  final int itunesId;

  /// Ce qu'annonce l'annuaire — le flux, lui, n'en garde souvent qu'une partie.
  final int episodeCount;

  final bool subscribed;

  PodcastShow copyWith({bool? subscribed}) => PodcastShow(
        feedUrl: feedUrl,
        title: title,
        author: author,
        image: image,
        description: description,
        genre: genre,
        itunesId: itunesId,
        episodeCount: episodeCount,
        subscribed: subscribed ?? this.subscribed,
      );

  Map<String, dynamic> toJson() => {
        'feedUrl': feedUrl,
        'title': title,
        'author': author,
        'image': image,
        'description': description,
        'genre': genre,
        'itunesId': itunesId,
      };
}

/// Un épisode, tel que le flux le publie — et où l'on en est dedans.
class PodcastEpisode {
  const PodcastEpisode({
    required this.guid,
    required this.title,
    required this.audioUrl,
    this.description = '',
    this.duration = 0,
    this.publishedAt = 0,
    this.image = '',
    this.number = 0,
    this.season = 0,
    this.position = 0,
    this.completed = false,
  });

  factory PodcastEpisode.fromJson(Map<String, dynamic> json) => PodcastEpisode(
        guid: json['guid'] as String? ?? '',
        title: json['title'] as String? ?? '',
        audioUrl: json['audioUrl'] as String? ?? '',
        description: json['description'] as String? ?? '',
        duration: (json['duration'] as num?)?.toInt() ?? 0,
        publishedAt: (json['publishedAt'] as num?)?.toInt() ?? 0,
        image: json['image'] as String? ?? '',
        number: (json['episode'] as num?)?.toInt() ?? 0,
        season: (json['season'] as num?)?.toInt() ?? 0,
        position: (json['position'] as num?)?.toInt() ?? 0,
        completed: json['completed'] == true,
      );

  final String guid;
  final String title;
  final String audioUrl;
  final String description;

  /// Durée en secondes, 0 si le flux ne la donne pas (le lecteur la découvre).
  final int duration;

  /// Date de publication en secondes depuis l'époque, 0 si illisible.
  final int publishedAt;

  final String image;

  /// Numéro d'épisode et de saison quand le flux les donne (0 sinon).
  final int number;
  final int season;

  /// Où l'on en était, en secondes.
  final int position;
  final bool completed;

  DateTime? get published => publishedAt <= 0
      ? null
      : DateTime.fromMillisecondsSinceEpoch(publishedAt * 1000);

  /// Reprendre plus loin que le début n'a de sens que si l'on n'est ni au
  /// tout début ni à la toute fin (le reste d'un épisode fini, c'est le
  /// générique).
  bool get resumable =>
      !completed &&
      position > 30 &&
      (duration == 0 || position < duration - 30);

  Duration get startAt => resumable ? Duration(seconds: position) : Duration.zero;

  /// Part écoutée, entre 0 et 1, ou null quand on ne sait pas la calculer.
  double? get progress {
    if (completed) return 1;
    if (duration <= 0 || position <= 0) return null;
    return (position / duration).clamp(0.0, 1.0);
  }
}

/// Une série et ses épisodes, lus dans le flux.
class PodcastFeed {
  const PodcastFeed({required this.show, required this.episodes});

  final PodcastShow show;
  final List<PodcastEpisode> episodes;
}

/// Une catégorie du palmarès d'Apple.
class PodcastGenre {
  const PodcastGenre({required this.id, required this.name});

  factory PodcastGenre.fromJson(Map<String, dynamic> json) => PodcastGenre(
        id: (json['id'] as num?)?.toInt() ?? 0,
        name: json['name'] as String? ?? '',
      );

  final int id;
  final String name;
}

/// Les podcasts : annuaire public (recherche, palmarès), abonnements de
/// l'utilisateur et épisodes lus dans les flux. Tout passe par le serveur —
/// lui seul va chercher les flux, l'app ne parle qu'à Gullify (le son des
/// épisodes, lui, se lit en direct chez l'hébergeur du podcast).
class PodcastsRepository {
  PodcastsRepository(this._client);

  final ApiClient _client;

  static const _endpoint = 'podcasts.php';

  Future<List<PodcastGenre>> genres() async {
    final data = await _client.get(_endpoint, query: {'action': 'genres'});
    return _list(data, PodcastGenre.fromJson);
  }

  Future<List<PodcastShow>> search(String query, {int limit = 25}) async {
    final data = await _client.get(
      _endpoint,
      query: {'action': 'search', 'q': query, 'limit': limit},
    );
    return _list(data, PodcastShow.fromJson);
  }

  /// Le palmarès d'une catégorie — la liste « à découvrir ».
  Future<List<PodcastShow>> discover(int genreId, {int limit = 30}) async {
    final data = await _client.get(
      _endpoint,
      query: {'action': 'discover', 'genre': genreId, 'limit': limit},
    );
    return _list(data, PodcastShow.fromJson);
  }

  Future<List<PodcastShow>> subscriptions() async {
    final data = await _client.get(_endpoint, query: {'action': 'subscriptions'});
    return _list(data, PodcastShow.fromJson);
  }

  Future<void> subscribe(PodcastShow show) => _client.post(
        _endpoint,
        query: {'action': 'subscribe'},
        body: show.toJson(),
      );

  Future<void> unsubscribe(String feedUrl) => _client.post(
        _endpoint,
        query: {'action': 'unsubscribe'},
        body: {'feedUrl': feedUrl},
      );

  /// La série et ses épisodes. [refresh] force la relecture du flux (le
  /// serveur le garde une demi-heure).
  Future<PodcastFeed> episodes(
    String feedUrl, {
    int limit = 100,
    bool refresh = false,
  }) async {
    final data = await _client.get(
      _endpoint,
      query: {
        'action': 'episodes',
        'feed': feedUrl,
        'limit': limit,
        if (refresh) 'refresh': '1',
      },
    ) as Map<String, dynamic>;
    return PodcastFeed(
      show: PodcastShow.fromJson(
        (data['show'] as Map<String, dynamic>? ?? const {}),
      ),
      episodes: _list(data['episodes'], PodcastEpisode.fromJson),
    );
  }

  /// Retient où l'on en est dans un épisode (reprise à la seconde près).
  Future<void> saveProgress({
    required String feedUrl,
    required String guid,
    required int position,
    int duration = 0,
    bool completed = false,
  }) =>
      _client.post(
        _endpoint,
        query: {'action': 'progress'},
        body: {
          'feedUrl': feedUrl,
          'guid': guid,
          'position': position,
          'duration': duration,
          'completed': completed,
        },
      );

  static List<T> _list<T>(dynamic data, T Function(Map<String, dynamic>) from) {
    if (data is! List) return const [];
    return [
      for (final e in data)
        if (e is Map<String, dynamic>) from(e),
    ];
  }
}
