import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/playlist_repository.dart';
import 'auth.dart';

final playlistRepositoryProvider = Provider<PlaylistRepository>(
  (ref) => PlaylistRepository(ref.watch(apiClientProvider)),
);

final playlistsProvider = FutureProvider<List<Playlist>>(
  (ref) => ref.watch(playlistRepositoryProvider).playlists(),
);

final playlistSongsProvider = FutureProvider.family<List<PlaylistEntry>, int>(
  (ref, id) => ref.watch(playlistRepositoryProvider).songs(id),
);

class PlaylistActions {
  PlaylistActions(this._ref);

  final Ref _ref;

  PlaylistRepository get _repo => _ref.read(playlistRepositoryProvider);

  Future<int> create(String name) async {
    final id = await _repo.create(name);
    _ref.invalidate(playlistsProvider);
    return id;
  }

  Future<void> rename(int id, String name) async {
    await _repo.rename(id, name);
    _ref.invalidate(playlistsProvider);
  }

  Future<void> delete(int id) async {
    await _repo.delete(id);
    _ref.invalidate(playlistsProvider);
  }

  Future<void> addSong(int playlistId, int songId) async {
    await _repo.addSong(playlistId, songId);
    _ref.invalidate(playlistsProvider);
    _ref.invalidate(playlistSongsProvider(playlistId));
  }

  Future<void> removeSong(int playlistId, int playlistSongId) async {
    await _repo.removeSong(playlistSongId);
    _ref.invalidate(playlistsProvider);
    _ref.invalidate(playlistSongsProvider(playlistId));
  }
}

final playlistActionsProvider = Provider<PlaylistActions>(PlaylistActions.new);
