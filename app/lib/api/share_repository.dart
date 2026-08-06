import 'api_client.dart';

/// Un lien d'écoute partagé (`/api/v2/share.php`).
///
/// Le serveur ouvre le lien, en fixe l'échéance et le referme tout seul :
/// l'app ne fait que le demander, le montrer et — si on change d'avis — le
/// couper avant l'heure.
class SongShareLink {
  const SongShareLink({
    required this.token,
    required this.url,
    required this.title,
    required this.artist,
    required this.remaining,
    this.artworkUrl,
    this.plays = 0,
  });

  factory SongShareLink.fromJson(Map<String, dynamic> json) {
    final artwork = json['artworkUrl'] as String? ?? '';
    return SongShareLink(
      token: json['token'] as String? ?? '',
      url: json['url'] as String? ?? '',
      title: json['title'] as String? ?? '',
      artist: json['artist'] as String? ?? '',
      remaining: Duration(
        milliseconds: (json['remainingMs'] as num?)?.toInt() ?? 0,
      ),
      artworkUrl: artwork.isEmpty ? null : artwork,
      plays: (json['plays'] as num?)?.toInt() ?? 0,
    );
  }

  final String token;
  final String url;
  final String title;
  final String artist;

  /// Ce qu'il reste à vivre au lien au moment où le serveur a répondu.
  final Duration remaining;

  final String? artworkUrl;

  /// Nombre d'écoutes déjà servies par ce lien.
  final int plays;

  /// « 24 h », « 3 h 20 », « 45 min » — la durée telle qu'on l'annonce.
  String get remainingLabel {
    final minutes = remaining.inMinutes;
    if (minutes < 1) return 'moins d\'une minute';
    if (minutes < 60) return '$minutes min';
    final hours = minutes ~/ 60;
    final rest = minutes % 60;
    return rest > 0 ? '$hours h $rest' : '$hours h';
  }
}

/// Partage d'une chanson par lien éphémère (API v2 `share.php`).
class ShareRepository {
  ShareRepository(this._client);

  final ApiClient _client;

  /// Ouvre un lien vers [songId], valable 24 h.
  Future<SongShareLink> create(int songId) async {
    final data = await _client.post(
      'share.php',
      query: {'action': 'create'},
      body: {'songId': songId},
    );
    return SongShareLink.fromJson(data as Map<String, dynamic>);
  }

  /// Mes liens encore ouverts.
  Future<List<SongShareLink>> mine() async {
    final data =
        await _client.get('share.php', query: {'action': 'mine'})
            as List<dynamic>;
    return data
        .map((e) => SongShareLink.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Coupe un lien avant son échéance.
  Future<void> revoke(String token) => _client.post(
    'share.php',
    query: {'action': 'revoke'},
    body: {'token': token},
  );
}
