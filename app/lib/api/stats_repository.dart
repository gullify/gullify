import 'api_client.dart';

class StatsGeneral {
  const StatsGeneral({
    required this.totalPlays,
    required this.totalListenTimeFormatted,
    required this.uniqueSongsPlayed,
    required this.completionRate,
    required this.totalSkips,
    required this.avgDurationFormatted,
  });

  factory StatsGeneral.fromJson(Map<String, dynamic> json) => StatsGeneral(
        totalPlays: (json['totalPlays'] as num?)?.toInt() ?? 0,
        totalListenTimeFormatted:
            json['totalListenTimeFormatted'] as String? ?? '0 min',
        uniqueSongsPlayed: (json['uniqueSongsPlayed'] as num?)?.toInt() ?? 0,
        completionRate: (json['completionRate'] as num?)?.toInt() ?? 0,
        totalSkips: (json['totalSkips'] as num?)?.toInt() ?? 0,
        avgDurationFormatted: json['avgDurationFormatted'] as String? ?? '—',
      );

  final int totalPlays;
  final String totalListenTimeFormatted;
  final int uniqueSongsPlayed;
  final int completionRate;
  final int totalSkips;
  final String avgDurationFormatted;
}

class StatsTopSong {
  const StatsTopSong({
    required this.title,
    required this.artistName,
    required this.albumId,
    required this.playCount,
    required this.artworkUrl,
  });

  final String title;
  final String artistName;
  final int albumId;
  final int playCount;
  final String artworkUrl;
}

class StatsTopArtist {
  const StatsTopArtist({
    required this.id,
    required this.name,
    required this.playCount,
    required this.imageUrl,
  });

  final int id;
  final String name;
  final int playCount;
  final String imageUrl;
}

class StatsTopAlbum {
  const StatsTopAlbum({
    required this.id,
    required this.name,
    required this.artistName,
    required this.playCount,
    required this.artworkUrl,
  });

  final int id;
  final String name;
  final String artistName;
  final int playCount;
  final String artworkUrl;
}

/// Série {labels, data} des graphiques du serveur.
class StatsChart {
  const StatsChart({required this.labels, required this.data});

  factory StatsChart.fromJson(Map<String, dynamic>? json) => StatsChart(
        labels: (json?['labels'] as List<dynamic>? ?? [])
            .map((e) => '$e')
            .toList(),
        data: (json?['data'] as List<dynamic>? ?? [])
            .map((e) => (e as num).toInt())
            .toList(),
      );

  final List<String> labels;
  final List<int> data;

  bool get isEmpty => data.isEmpty || data.every((v) => v == 0);
}

class StatsGenre {
  const StatsGenre({
    required this.label,
    required this.count,
    required this.color,
  });

  final String label;
  final int count;

  /// Couleur hex '#rrggbb' fournie par le serveur (palette web).
  final String color;
}

class ListeningStats {
  const ListeningStats({
    required this.general,
    required this.topSongs,
    required this.topArtists,
    required this.topAlbums,
    required this.dailyPlays,
    required this.hourly,
    required this.weekday,
    required this.genres,
  });

  final StatsGeneral general;
  final List<StatsTopSong> topSongs;
  final List<StatsTopArtist> topArtists;
  final List<StatsTopAlbum> topAlbums;
  final StatsChart dailyPlays;
  final StatsChart hourly;
  final StatsChart weekday;
  final List<StatsGenre> genres;

  bool get hasPlays => general.totalPlays > 0;
}

class StatsRepository {
  StatsRepository(this._client);

  final ApiClient _client;

  String _abs(String relative) =>
      relative.isEmpty ? '' : _client.resourceUrl(relative);

  Future<ListeningStats> stats() async {
    final data = await _client.get('stats.php') as Map<String, dynamic>;

    final genreChart = data['genreChart'] as Map<String, dynamic>? ?? {};
    final genreLabels =
        (genreChart['labels'] as List<dynamic>? ?? []).map((e) => '$e').toList();
    final genreData = (genreChart['data'] as List<dynamic>? ?? [])
        .map((e) => (e as num).toInt())
        .toList();
    final genreColors =
        (genreChart['colors'] as List<dynamic>? ?? []).map((e) => '$e').toList();

    return ListeningStats(
      general: StatsGeneral.fromJson(
        data['general'] as Map<String, dynamic>? ?? {},
      ),
      topSongs: (data['topSongs'] as List<dynamic>? ?? [])
          .cast<Map<String, dynamic>>()
          .map(
            (j) => StatsTopSong(
              title: j['title'] as String? ?? '',
              artistName: j['artist_name'] as String? ?? '',
              albumId: (j['album_id'] as num?)?.toInt() ?? 0,
              playCount: (j['play_count'] as num?)?.toInt() ?? 0,
              artworkUrl: _abs(j['artworkUrl'] as String? ?? ''),
            ),
          )
          .toList(),
      topArtists: (data['topArtists'] as List<dynamic>? ?? [])
          .cast<Map<String, dynamic>>()
          .map(
            (j) => StatsTopArtist(
              id: (j['id'] as num?)?.toInt() ?? 0,
              name: j['name'] as String? ?? '',
              playCount: (j['play_count'] as num?)?.toInt() ?? 0,
              imageUrl: _abs(j['imageUrl'] as String? ?? ''),
            ),
          )
          .toList(),
      topAlbums: (data['topAlbums'] as List<dynamic>? ?? [])
          .cast<Map<String, dynamic>>()
          .map(
            (j) => StatsTopAlbum(
              id: (j['id'] as num?)?.toInt() ?? 0,
              name: j['name'] as String? ?? '',
              artistName: j['artist_name'] as String? ?? '',
              playCount: (j['play_count'] as num?)?.toInt() ?? 0,
              artworkUrl: _abs(j['artworkUrl'] as String? ?? ''),
            ),
          )
          .toList(),
      dailyPlays:
          StatsChart.fromJson(data['dailyPlaysChart'] as Map<String, dynamic>?),
      hourly: StatsChart.fromJson(data['hourlyChart'] as Map<String, dynamic>?),
      weekday:
          StatsChart.fromJson(data['weekdayChart'] as Map<String, dynamic>?),
      genres: [
        for (var i = 0; i < genreLabels.length && i < genreData.length; i++)
          StatsGenre(
            label: genreLabels[i],
            count: genreData[i],
            color: i < genreColors.length ? genreColors[i] : '',
          ),
      ],
    );
  }
}
