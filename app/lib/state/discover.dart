import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/yt_downloads_repository.dart';
import 'library.dart';
import 'yt_downloads.dart';

/// Un artiste « à découvrir » : un artiste que l'utilisateur ne possède pas,
/// suggéré par YouTube Music à partir d'un artiste qu'il a déjà (`becauseOf`).
class DiscoverArtist {
  const DiscoverArtist({required this.artist, required this.becauseOf});

  /// L'artiste inconnu suggéré (nom + pochette YouTube Music).
  final YtArtist artist;

  /// Le nom de l'artiste de la bibliothèque qui a inspiré la suggestion.
  final String becauseOf;
}

/// « À découvrir » sur l'accueil : prend un artiste de la bibliothèque au
/// hasard, demande à YouTube Music ses artistes similaires, en retire ceux
/// déjà possédés, et en propose un nouveau au hasard. `null` s'il n'y a rien
/// à suggérer (bibliothèque vide ou aucune nouveauté trouvée).
///
/// Invalider le provider (pull-to-refresh, bouton) relance un tirage.
final discoverArtistProvider = FutureProvider<DiscoverArtist?>((ref) async {
  final artists = await ref.watch(artistsProvider.future);
  if (artists.isEmpty) return null;

  String norm(String s) => s.trim().toLowerCase();
  final owned = {for (final a in artists) norm(a.name)};

  final repo = ref.watch(ytDownloadsRepositoryProvider);
  final rng = Random();

  // Essaie plusieurs artistes-graines : certains n'ont pas de « similaires »,
  // ou ne renvoient que des artistes déjà dans la bibliothèque.
  final seeds = [...artists]..shuffle(rng);
  for (final seed in seeds.take(5)) {
    List<YtArtist> related;
    try {
      related = await repo.relatedArtists(seed.name);
    } catch (_) {
      continue;
    }
    final fresh = related
        .where((a) => a.name.isNotEmpty && !owned.contains(norm(a.name)))
        .toList();
    if (fresh.isEmpty) continue;
    return DiscoverArtist(
      artist: fresh[rng.nextInt(fresh.length)],
      becauseOf: seed.name,
    );
  }
  return null;
});
