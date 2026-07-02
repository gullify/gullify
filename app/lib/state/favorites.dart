import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/song.dart';
import 'library.dart';

/// Set of favorite song ids, with optimistic toggle.
class FavoriteIds extends AsyncNotifier<Set<int>> {
  @override
  Future<Set<int>> build() =>
      ref.watch(libraryRepositoryProvider).favoriteIds();

  Future<void> toggle(int songId) async {
    final current = state.value ?? {};
    final wasFavorite = current.contains(songId);
    state = AsyncData({
      ...current.where((id) => id != songId),
      if (!wasFavorite) songId,
    });
    try {
      await ref.read(libraryRepositoryProvider).toggleFavorite(songId);
      ref.invalidate(allFavoritesProvider);
    } catch (_) {
      state = AsyncData(current);
    }
  }
}

final favoriteIdsProvider = AsyncNotifierProvider<FavoriteIds, Set<int>>(
  FavoriteIds.new,
);

final allFavoritesProvider = FutureProvider<List<Song>>(
  (ref) => ref.watch(libraryRepositoryProvider).allFavorites(),
);
