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
      var logo = e['logo'] as String?;
      // Logos personnalisés stockés en chemin relatif → absolutise.
      if (logo != null && logo.startsWith('/')) {
        logo = '${_client.serverUrl()}$logo';
      }
      stations.add(RadioStation(
        id: e['id'] as String,
        name: e['name'] as String,
        streamUrl: (streams.first as Map<String, dynamic>)['url'] as String,
        country: e['country'] as String?,
        genres: (e['genres'] as List<dynamic>? ?? []).cast<String>(),
        logo: logo,
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

  /// Crée une station personnalisée. Renvoie son id (`custom:N`).
  Future<String> add({
    required String name,
    required String url,
    String? country,
    List<String> genres = const [],
    String? logo,
  }) async {
    final data = await _client.post(
      'web-radio.php',
      query: {'action': 'add'},
      body: {
        'name': name,
        'url': url,
        if (country != null && country.isNotEmpty) 'country': country,
        if (genres.isNotEmpty) 'genres': genres,
        if (logo != null && logo.isNotEmpty) 'logo': logo,
      },
    ) as Map<String, dynamic>;
    return data['id'] as String? ?? '';
  }

  /// Modifie une station personnalisée (station_id = `custom:N`).
  Future<void> update({
    required String stationId,
    required String name,
    required String url,
    String? country,
    List<String> genres = const [],
    String? logo,
  }) =>
      _client.post(
        'web-radio.php',
        query: {'action': 'update'},
        body: {
          'station_id': stationId,
          'name': name,
          'url': url,
          'country': country ?? '',
          'genres': genres,
          'logo': ?logo,
        },
      );

  Future<void> remove(String stationId) => _client.post(
        'web-radio.php',
        query: {'action': 'remove'},
        body: {'station_id': stationId},
      );

  Future<void> removeBulk(List<String> stationIds) => _client.post(
        'web-radio.php',
        query: {'action': 'remove_bulk'},
        body: {'station_ids': stationIds},
      );

  /// Reprend le catalogue Radio Browser dans la liste de l'utilisateur. Les
  /// stations qu'il a déjà ne sont pas dupliquées. Renvoie le nombre ajouté.
  Future<int> importCatalog() async {
    final data = await _client.post(
      'web-radio.php',
      query: {'action': 'import_catalog'},
    ) as Map<String, dynamic>;
    return (data['imported'] as num?)?.toInt() ?? 0;
  }

  /// Upload d'un logo (URL distante ou fichier local) → URL absolue servie.
  Future<String> uploadLogo({String? imageUrl, String? filePath}) =>
      _client.uploadRadioLogo(imageUrl: imageUrl, filePath: filePath);
}
