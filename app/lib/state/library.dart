import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/library_repository.dart';
import '../models/album.dart';
import '../models/artist.dart';
import '../models/server_user.dart';
import '../models/song.dart';
import 'auth.dart';

final libraryRepositoryProvider = Provider<LibraryRepository>(
  (ref) => LibraryRepository(ref.watch(apiClientProvider)),
);

final artistsProvider = FutureProvider<List<Artist>>(
  (ref) => ref.watch(libraryRepositoryProvider).artists(),
);

/// Genres présents dans la bibliothèque (pour le filtre).
final genresProvider = FutureProvider<List<GenreCount>>(
  (ref) => ref.watch(libraryRepositoryProvider).genres(),
);

/// Les genres principaux proposés par le serveur, qu'ils soient déjà utilisés
/// dans la bibliothèque ou non (pour choisir le genre d'un artiste).
final genreTaxonomyProvider = FutureProvider<List<String>>(
  (ref) => ref.watch(libraryRepositoryProvider).genreTaxonomy(),
);

/// Artistes d'un genre donné.
final artistsByGenreProvider = FutureProvider.family<List<Artist>, String>(
  (ref, genre) => ref.watch(libraryRepositoryProvider).artistsByGenre(genre),
);

/// Albums d'un genre donné.
final albumsByGenreProvider = FutureProvider.family<List<Album>, String>(
  (ref, genre) => ref.watch(libraryRepositoryProvider).albums(genre: genre),
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

/// Compteur de « demandes de focus » sur le champ de recherche : la barre
/// de l'accueil l'incrémente avant d'aller à l'onglet Recherche, qui met
/// alors le clavier directement (pas de second tap).
class SearchFocusRequest extends Notifier<int> {
  @override
  int build() => 0;

  void request() => state = state + 1;
}

final searchFocusRequestProvider =
    NotifierProvider<SearchFocusRequest, int>(SearchFocusRequest.new);

final lyricsProvider = FutureProvider.family<String?, String>(
  (ref, filePath) => ref.watch(libraryRepositoryProvider).lyrics(filePath),
);

final searchResultsProvider = FutureProvider<SearchResults>((ref) {
  final query = ref.watch(searchQueryProvider);
  return ref.watch(libraryRepositoryProvider).search(query);
});

/// Nombre de titres locaux affichés dans la recherche. Grandit via « Charger
/// plus », repart du minimum à chaque nouvelle requête (le serveur renvoie
/// jusqu'à 100 titres d'un coup ; on les dévoile progressivement).
const int kSearchPageSize = 20;

class SearchLocalLimit extends Notifier<int> {
  @override
  int build() {
    // Toute nouvelle requête réinitialise la pagination.
    ref.watch(searchQueryProvider);
    return kSearchPageSize;
  }

  void more() => state = state + kSearchPageSize;
}

final searchLocalLimitProvider =
    NotifierProvider<SearchLocalLimit, int>(SearchLocalLimit.new);

/// Les autres utilisateurs du serveur (découverte de leurs bibliothèques).
final serverUsersProvider = FutureProvider<List<ServerUser>>(
  (ref) => ref.watch(libraryRepositoryProvider).serverUsers(),
);

/// La liste des artistes de la bibliothèque d'un autre utilisateur.
final userLibraryProvider = FutureProvider.family<List<Artist>, String>(
  (ref, username) => ref.watch(libraryRepositoryProvider).userLibrary(username),
);
