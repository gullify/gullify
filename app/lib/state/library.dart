import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/library_repository.dart';
import '../models/album.dart';
import '../models/artist.dart';
import '../models/song.dart';
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

/// « Les plus populaires » de l'accueil (top écoutes).
final popularSongsProvider = FutureProvider<List<Song>>(
  (ref) => ref.watch(libraryRepositoryProvider).popularSongs(limit: 10),
);

final suggestionsProvider = FutureProvider<Suggestions>(
  (ref) => ref.watch(libraryRepositoryProvider).suggestions(),
);

final artistDetailProvider = FutureProvider.family<ArtistDetail, int>(
  (ref, id) => ref.watch(libraryRepositoryProvider).artistDetail(id),
);

/// Bio + actus, par nom d'artiste (sources externes — peut être vide).
final artistExtrasProvider = FutureProvider.family<ArtistExtras, String>(
  (ref, name) => ref.watch(libraryRepositoryProvider).artistExtras(name),
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

final lyricsProvider = FutureProvider.family<String?, String>(
  (ref, filePath) => ref.watch(libraryRepositoryProvider).lyrics(filePath),
);

final searchResultsProvider = FutureProvider<SearchResults>((ref) {
  final query = ref.watch(searchQueryProvider);
  return ref.watch(libraryRepositoryProvider).search(query);
});
