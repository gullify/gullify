import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/yt_downloads_repository.dart';
import 'auth.dart';
import 'library.dart';

final ytDownloadsRepositoryProvider = Provider<YtDownloadsRepository>(
  (ref) => YtDownloadsRepository(ref.watch(apiClientProvider)),
);

/// Résultats de la recherche d'albums YouTube Music.
final ytSearchQueryProvider = NotifierProvider<_YtSearchQuery, String>(
  _YtSearchQuery.new,
);

class _YtSearchQuery extends Notifier<String> {
  @override
  String build() => '';

  void set(String query) {
    final trimmed = query.trim();
    if (trimmed == state) return;
    // Nouvelle requête → on repart de la première page de résultats.
    ref.read(ytSearchLimitProvider.notifier).reset();
    state = trimmed;
  }
}

/// Nombre d'albums demandés pour la requête courante. Grandit via « Charger
/// plus », se remet à [_kYtPageSize] quand la requête change.
const int _kYtPageSize = 10;

final ytSearchLimitProvider = NotifierProvider<_YtSearchLimit, int>(
  _YtSearchLimit.new,
);

class _YtSearchLimit extends Notifier<int> {
  @override
  int build() => _kYtPageSize;

  void more() => state = (state + _kYtPageSize).clamp(_kYtPageSize, 50);

  void reset() => state = _kYtPageSize;
}

final ytSearchResultsProvider = FutureProvider<List<YtAlbum>>((ref) {
  final query = ref.watch(ytSearchQueryProvider);
  if (query.length < 2) return Future.value(const <YtAlbum>[]);
  final limit = ref.watch(ytSearchLimitProvider);
  return ref.watch(ytDownloadsRepositoryProvider).searchAlbums(
        query,
        limit: limit,
      );
});

/// Nombre de résultats YouTube demandés dans l'onglet Recherche (albums et
/// chansons partagent la même page). Grandit via « Charger plus », repart du
/// minimum à chaque nouvelle requête. Plafonné à 50 côté serveur.
const int _kSearchYtPageSize = 10;

class _SearchYtLimit extends Notifier<int> {
  @override
  int build() {
    // Toute nouvelle requête réinitialise la pagination.
    ref.watch(searchQueryProvider);
    return _kSearchYtPageSize;
  }

  void more() =>
      state = (state + _kSearchYtPageSize).clamp(_kSearchYtPageSize, 50);
}

final searchYtLimitProvider =
    NotifierProvider<_SearchYtLimit, int>(_SearchYtLimit.new);

/// Albums YouTube Music pour une requête (onglet Recherche).
final ytAlbumSearchProvider = FutureProvider.family<List<YtAlbum>, String>(
  (ref, query) => ref.watch(ytDownloadsRepositoryProvider).searchAlbums(
        query,
        limit: ref.watch(searchYtLimitProvider),
      ),
);

/// Chansons seules YouTube Music pour une requête (onglet Recherche).
final ytSongSearchProvider = FutureProvider.family<List<YtSong>, String>(
  (ref, query) => ref.watch(ytDownloadsRepositoryProvider).searchSongs(
        query,
        limit: ref.watch(searchYtLimitProvider),
      ),
);

/// Artistes YouTube Music pour une requête (onglet Recherche).
final ytArtistSearchProvider = FutureProvider.family<List<YtArtist>, String>(
  (ref, query) => ref.watch(ytDownloadsRepositoryProvider).searchArtists(
        query,
        limit: ref.watch(searchYtLimitProvider),
      ),
);

/// Albums YouTube Music d'un artiste (suggestions sur sa page).
final ytArtistAlbumsProvider = FutureProvider.family<List<YtAlbum>, String>(
  (ref, artistName) =>
      ref.watch(ytDownloadsRepositoryProvider).searchAlbums(artistName),
);

/// Artistes similaires (YouTube Music) pour un nom d'artiste.
final relatedArtistsProvider = FutureProvider.family<List<YtArtist>, String>(
  (ref, artistName) =>
      ref.watch(ytDownloadsRepositoryProvider).relatedArtists(artistName),
);

/// File de téléchargement serveur, rafraîchie tant qu'un item est actif.
final ytQueueProvider =
    AsyncNotifierProvider<YtQueueNotifier, List<ServerDownload>>(
  YtQueueNotifier.new,
);

class YtQueueNotifier extends AsyncNotifier<List<ServerDownload>> {
  Timer? _timer;

  @override
  Future<List<ServerDownload>> build() async {
    ref.onDispose(() => _timer?.cancel());
    final items = await ref.watch(ytDownloadsRepositoryProvider).list();
    _schedule(items);
    return items;
  }

  void _schedule(List<ServerDownload> items) {
    _timer?.cancel();
    if (items.any((d) => d.isActive)) {
      _timer = Timer(const Duration(seconds: 3), refresh);
    }
  }

  Future<void> refresh() async {
    try {
      final items = await ref.read(ytDownloadsRepositoryProvider).list();
      state = AsyncData(items);
      _schedule(items);
    } catch (e, st) {
      // Garde la dernière liste connue; réessaie au prochain refresh manuel.
      if (state.value == null) state = AsyncError(e, st);
    }
  }

  Future<String> start(YtResolvedAlbum album) async {
    final id = await ref.read(ytDownloadsRepositoryProvider).start(
          url: album.playlistUrl,
          artistName: album.artist,
          albumName: album.title,
        );
    await refresh();
    return id;
  }

  /// Met en file un lien YouTube collé (le serveur extrait les métadonnées).
  Future<String> startUrl(String url) async {
    final id = await ref.read(ytDownloadsRepositoryProvider).startUrl(url);
    await refresh();
    return id;
  }

  Future<void> cancel(String id) async {
    await ref.read(ytDownloadsRepositoryProvider).cancel(id);
    await refresh();
  }

  Future<void> retry(String id) async {
    await ref.read(ytDownloadsRepositoryProvider).retry(id);
    await refresh();
  }

  Future<void> delete(String id) async {
    await ref.read(ytDownloadsRepositoryProvider).delete(id);
    await refresh();
  }
}
