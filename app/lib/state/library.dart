import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/library_repository.dart';
import '../models/album.dart';
import '../models/artist.dart';
import 'auth.dart';

final libraryRepositoryProvider = Provider<LibraryRepository>(
  (ref) => LibraryRepository(ref.watch(apiClientProvider)),
);

final artistsProvider = FutureProvider<List<Artist>>(
  (ref) => ref.watch(libraryRepositoryProvider).artists(),
);

final albumsProvider = FutureProvider<List<Album>>(
  (ref) => ref.watch(libraryRepositoryProvider).albums(),
);

final recentAlbumsProvider = FutureProvider<List<Album>>(
  (ref) => ref.watch(libraryRepositoryProvider).recentAlbums(),
);

final artistDetailProvider = FutureProvider.family<ArtistDetail, int>(
  (ref, id) => ref.watch(libraryRepositoryProvider).artistDetail(id),
);

final albumDetailProvider = FutureProvider.family<AlbumDetail, int>(
  (ref, id) => ref.watch(libraryRepositoryProvider).albumDetail(id),
);

class SearchQuery extends Notifier<String> {
  @override
  String build() => '';

  void set(String value) => state = value;
}

final searchQueryProvider = NotifierProvider<SearchQuery, String>(
  SearchQuery.new,
);

final searchResultsProvider = FutureProvider<SearchResults>((ref) {
  final query = ref.watch(searchQueryProvider);
  return ref.watch(libraryRepositoryProvider).search(query);
});
