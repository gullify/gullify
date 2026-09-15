import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/bandcamp_repository.dart';
import 'auth.dart';
import 'library.dart';

final bandcampRepositoryProvider = Provider<BandcampRepository>(
  (ref) => BandcampRepository(ref.watch(apiClientProvider)),
);

/// Nombre de résultats Bandcamp demandés dans l'onglet Recherche (albums,
/// titres et artistes partagent la même page). Grandit via « Charger plus »,
/// repart du minimum à chaque nouvelle requête. Plafonné à 50 côté serveur.
const int _kBandcampPageSize = 10;

class _BandcampLimit extends Notifier<int> {
  @override
  int build() {
    // Toute nouvelle requête réinitialise la pagination.
    ref.watch(searchQueryProvider);
    return _kBandcampPageSize;
  }

  void more() =>
      state = (state + _kBandcampPageSize).clamp(_kBandcampPageSize, 50);
}

final searchBandcampLimitProvider =
    NotifierProvider<_BandcampLimit, int>(_BandcampLimit.new);

/// Albums Bandcamp pour une requête.
final bcAlbumSearchProvider = FutureProvider.family<List<BcRelease>, String>(
  (ref, query) => ref.watch(bandcampRepositoryProvider).searchAlbums(
        query,
        limit: ref.watch(searchBandcampLimitProvider),
      ),
);

/// Titres seuls Bandcamp pour une requête.
final bcSongSearchProvider = FutureProvider.family<List<BcSong>, String>(
  (ref, query) => ref.watch(bandcampRepositoryProvider).searchSongs(
        query,
        limit: ref.watch(searchBandcampLimitProvider),
      ),
);

/// Artistes Bandcamp pour une requête.
final bcArtistSearchProvider = FutureProvider.family<List<BcArtist>, String>(
  (ref, query) => ref.watch(bandcampRepositoryProvider).searchArtists(
        query,
        limit: ref.watch(searchBandcampLimitProvider),
      ),
);

/// Discographie d'un artiste Bandcamp (clé = son `bandId`).
final bcArtistDiscographyProvider =
    FutureProvider.family<List<BcRelease>, int>(
  (ref, bandId) => ref.watch(bandcampRepositoryProvider).artistAlbums(bandId),
);
