import '../models/song.dart';
import 'api_client.dart';

class Playlist {
  const Playlist({required this.id, required this.name, this.songCount = 0});

  final int id;
  final String name;
  final int songCount;
}

/// A song inside a playlist, with the row id needed to remove it.
class PlaylistEntry {
  const PlaylistEntry({required this.song, required this.playlistSongId});

  final Song song;
  final int playlistSongId;
}

class PlaylistRepository {
  PlaylistRepository(this._client);

  final ApiClient _client;

  String? _abs(String? url) {
    if (url == null || url.isEmpty) return null;
    if (url.startsWith('http://') || url.startsWith('https://')) return url;
    return _client.resourceUrl(url);
  }

  Future<List<Playlist>> playlists() async {
    final data = await _client.get('playlists.php', query: {'action': 'list'})
        as List<dynamic>;
    return [
      for (final e in data.cast<Map<String, dynamic>>())
        Playlist(
          id: (e['id'] as num).toInt(),
          name: e['name'] as String,
          songCount: (e['songCount'] as num?)?.toInt() ?? 0,
        ),
    ];
  }

  Future<List<PlaylistEntry>> songs(int playlistId) async {
    final data = await _client.get('playlists.php', query: {
      'action': 'songs',
      'id': playlistId,
    }) as List<dynamic>;
    return [
      for (final e in data.cast<Map<String, dynamic>>())
        PlaylistEntry(
          song: Song.fromJson(e)
              .copyWith(artworkUrl: _abs(e['artworkUrl'] as String?)),
          playlistSongId: (e['playlistSongId'] as num).toInt(),
        ),
    ];
  }

  Future<int> create(String name) async {
    final data = await _client.post(
      'playlists.php',
      query: {'action': 'create'},
      body: {'name': name},
    ) as Map<String, dynamic>;
    return (data['id'] as num).toInt();
  }

  Future<void> rename(int id, String name) => _client.post(
        'playlists.php',
        query: {'action': 'rename'},
        body: {'id': id, 'name': name},
      );

  Future<void> delete(int id) => _client.post(
        'playlists.php',
        query: {'action': 'delete'},
        body: {'id': id},
      );

  Future<void> addSong(int playlistId, int songId) => _client.post(
        'playlists.php',
        query: {'action': 'add_song'},
        body: {'id': playlistId, 'song_id': songId},
      );

  /// Ajoute tout un album d'un coup et rend le nombre de titres ajoutés
  /// (ceux qui y étaient déjà ne comptent pas).
  Future<int> addAlbum(int playlistId, int albumId) async {
    final data = await _client.post(
      'playlists.php',
      query: {'action': 'add_album'},
      body: {'id': playlistId, 'album_id': albumId},
    ) as Map<String, dynamic>;
    return (data['added'] as num?)?.toInt() ?? 0;
  }

  Future<void> removeSong(int playlistSongId) => _client.post(
        'playlists.php',
        query: {'action': 'remove_song'},
        body: {'playlist_song_id': playlistSongId},
      );
}
