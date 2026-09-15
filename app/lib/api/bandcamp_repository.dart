import 'api_client.dart';

/// Sortie trouvée sur Bandcamp : un album, ou un titre publié seul.
///
/// Une sortie ne porte pas toujours son lien : la discographie d'un artiste
/// ne donne que des identifiants, et c'est [BandcampRepository.resolve] qui va
/// chercher l'URL (et le nombre de pistes) au moment du tap.
class BcRelease {
  const BcRelease({
    required this.title,
    required this.artist,
    required this.year,
    required this.thumbnail,
    required this.url,
    required this.itemId,
    required this.bandId,
    required this.itemType,
    this.inLibrary = false,
  });

  factory BcRelease.fromJson(Map<String, dynamic> json) => BcRelease(
        title: json['title'] as String? ?? '',
        artist: json['artist'] as String? ?? '',
        year: '${json['year'] ?? ''}',
        thumbnail: json['thumbnail'] as String? ?? '',
        url: json['url'] as String? ?? '',
        itemId: (json['itemId'] as num?)?.toInt() ?? 0,
        bandId: (json['bandId'] as num?)?.toInt() ?? 0,
        itemType: json['itemType'] as String? ?? 'a',
        inLibrary: json['in_library'] == true,
      );

  final String title;
  final String artist;
  final String year;
  final String thumbnail;
  final String url;
  final int itemId;
  final int bandId;

  /// `a` pour un album, `t` pour un titre publié seul.
  final String itemType;

  /// Le serveur a reconnu cette sortie dans la bibliothèque.
  final bool inLibrary;

  bool get isTrack => itemType == 't';
}

/// Artiste (ou label) trouvé sur Bandcamp.
class BcArtist {
  const BcArtist({
    required this.name,
    required this.bandId,
    required this.thumbnail,
    required this.location,
    this.isLabel = false,
  });

  factory BcArtist.fromJson(Map<String, dynamic> json) => BcArtist(
        name: json['name'] as String? ?? '',
        bandId: (json['bandId'] as num?)?.toInt() ?? 0,
        thumbnail: json['thumbnail'] as String? ?? '',
        location: json['location'] as String? ?? '',
        isLabel: json['isLabel'] == true,
      );

  final String name;
  final int bandId;
  final String thumbnail;

  /// D'où vient l'artiste (« Montreal, Québec ») — Bandcamp l'affiche partout,
  /// et c'est souvent ce qui distingue deux groupes du même nom.
  final String location;
  final bool isLabel;
}

/// Titre trouvé seul sur Bandcamp (pré-écoutable et téléchargeable à l'unité).
class BcSong {
  const BcSong({
    required this.title,
    required this.artist,
    required this.album,
    required this.thumbnail,
    required this.url,
    required this.trackId,
    required this.bandId,
    this.inLibrary = false,
  });

  factory BcSong.fromJson(Map<String, dynamic> json) => BcSong(
        title: json['title'] as String? ?? '',
        artist: json['artist'] as String? ?? '',
        album: json['album'] as String? ?? '',
        thumbnail: json['thumbnail'] as String? ?? '',
        url: json['url'] as String? ?? '',
        trackId: (json['itemId'] as num?)?.toInt() ?? 0,
        bandId: (json['bandId'] as num?)?.toInt() ?? 0,
        inLibrary: json['in_library'] == true,
      );

  final String title;
  final String artist;
  final String album;
  final String thumbnail;
  final String url;
  final int trackId;
  final int bandId;
  final bool inLibrary;

  /// Identité de ce titre pour la pré-écoute (voir `previewPlayerProvider`) :
  /// préfixée, elle ne peut pas se confondre avec un identifiant YouTube.
  String get previewId => 'bc:$trackId';
}

/// Album ou titre Bandcamp résolu : tout ce qu'il faut pour la fenêtre de
/// confirmation, puis pour la mise en file.
class BcResolved {
  const BcResolved({
    required this.url,
    required this.artist,
    required this.title,
    required this.album,
    required this.year,
    required this.trackCount,
    required this.thumbnail,
    required this.isTrack,
  });

  factory BcResolved.fromJson(Map<String, dynamic> json) => BcResolved(
        url: json['url'] as String? ?? '',
        artist: json['artist'] as String? ?? '',
        title: json['title'] as String? ?? '',
        album: json['album'] as String? ?? '',
        year: '${json['year'] ?? ''}',
        trackCount: (json['track_count'] as num?)?.toInt() ?? 0,
        thumbnail: json['thumbnail'] as String? ?? '',
        isTrack: json['is_track'] == true,
      );

  final String url;
  final String artist;
  final String title;
  final String album;
  final String year;
  final int trackCount;
  final String thumbnail;

  /// Vrai pour un titre publié seul : il rejoint « Singles », comme sur
  /// YouTube, et le doublon se juge alors sur le titre et non sur l'album.
  final bool isTrack;

  /// Sous quel album ranger cette sortie dans la bibliothèque.
  String get albumName =>
      album.isNotEmpty ? album : (isTrack ? 'Singles' : title);
}

/// Recherche Bandcamp (idée #110). Les téléchargements partent ensuite dans la
/// même file que YouTube — voir [YtDownloadsRepository.start].
class BandcampRepository {
  BandcampRepository(this._client);

  final ApiClient _client;

  Future<List<BcRelease>> searchAlbums(String query, {int limit = 10}) async {
    final data = await _client.get(
      'download.php',
      query: {
        'action': 'search_bandcamp',
        'type': 'albums',
        'query': query,
        'limit': '$limit',
      },
    ) as Map<String, dynamic>;
    final albums = data['albums'] as List<dynamic>? ?? [];
    return albums
        .cast<Map<String, dynamic>>()
        .map(BcRelease.fromJson)
        .where((a) => a.title.isNotEmpty)
        .toList();
  }

  Future<List<BcSong>> searchSongs(String query, {int limit = 10}) async {
    final data = await _client.get(
      'download.php',
      query: {
        'action': 'search_bandcamp',
        'type': 'songs',
        'query': query,
        'limit': '$limit',
      },
    ) as Map<String, dynamic>;
    final songs = data['songs'] as List<dynamic>? ?? [];
    return songs
        .cast<Map<String, dynamic>>()
        .map(BcSong.fromJson)
        .where((s) => s.url.isNotEmpty)
        .toList();
  }

  Future<List<BcArtist>> searchArtists(String query, {int limit = 10}) async {
    final data = await _client.get(
      'download.php',
      query: {
        'action': 'search_bandcamp',
        'type': 'artists',
        'query': query,
        'limit': '$limit',
      },
    ) as Map<String, dynamic>;
    final artists = data['artists'] as List<dynamic>? ?? [];
    return artists
        .cast<Map<String, dynamic>>()
        .map(BcArtist.fromJson)
        .where((a) => a.bandId > 0)
        .toList();
  }

  /// Discographie d'un artiste Bandcamp (albums et titres isolés, du plus
  /// récent au plus ancien).
  Future<List<BcRelease>> artistAlbums(int bandId, {int limit = 50}) async {
    final data = await _client.get(
      'download.php',
      query: {
        'action': 'bandcamp_artist_albums',
        'band_id': '$bandId',
        'limit': '$limit',
      },
    ) as Map<String, dynamic>;
    final albums = data['albums'] as List<dynamic>? ?? [];
    return albums
        .cast<Map<String, dynamic>>()
        .map(BcRelease.fromJson)
        .where((a) => a.title.isNotEmpty)
        .toList();
  }

  /// Résout une sortie par ses identifiants (recherche, discographie) ou par
  /// un lien collé.
  Future<BcResolved> resolve({
    int bandId = 0,
    int itemId = 0,
    String itemType = 'a',
    String url = '',
  }) async {
    final data = await _client.get(
      'download.php',
      query: {
        'action': 'resolve_bandcamp',
        if (bandId > 0 && itemId > 0) ...{
          'band_id': '$bandId',
          'item_id': '$itemId',
          'item_type': itemType,
        } else
          'url': url,
      },
    ) as Map<String, dynamic>;
    return BcResolved.fromJson(data);
  }

  /// URL de pré-écoute d'un titre Bandcamp : le serveur proxifie son flux
  /// (signé et daté chez Bandcamp). Endpoint legacy comme celui de YouTube —
  /// la réponse est binaire, pas une envelope JSON.
  String previewUrl(BcSong song) => _client.resourceUrl(
        'api/download.php?action=bandcamp_preview'
        '&band_id=${song.bandId}&track_id=${song.trackId}',
      );
}
