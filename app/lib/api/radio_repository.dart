import 'api_client.dart';

class RadioStation {
  const RadioStation({
    required this.id,
    required this.name,
    required this.streamUrl,
    this.country,
    this.genres = const [],
    this.logo,
    this.favorite = false,
  });

  final String id;
  final String name;
  final String streamUrl;
  final String? country;
  final List<String> genres;
  final String? logo;
  final bool favorite;
}

class RadioRepository {
  RadioRepository(this._client);

  final ApiClient _client;

  Future<List<RadioStation>> stations() async {
    final data = await _client.get('web-radio.php', query: {'action': 'list'})
        as Map<String, dynamic>;
    final stations = <RadioStation>[];
    for (final e in (data['stations'] as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>>()) {
      final streams = e['streams'] as List<dynamic>? ?? [];
      if (streams.isEmpty) continue;
      stations.add(RadioStation(
        id: e['id'] as String,
        name: e['name'] as String,
        streamUrl: (streams.first as Map<String, dynamic>)['url'] as String,
        country: e['country'] as String?,
        genres: (e['genres'] as List<dynamic>? ?? []).cast<String>(),
        logo: e['logo'] as String?,
        favorite: e['favorite'] == true,
      ));
    }
    return stations;
  }

  Future<void> toggleFavorite(String stationId) => _client.post(
        'web-radio.php',
        query: {'action': 'toggle_favorite'},
        body: {'station_id': stationId},
      );
}
