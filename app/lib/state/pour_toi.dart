import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/pour_toi_repository.dart';
import 'auth.dart';
import 'library.dart';

final pourToiRepositoryProvider = Provider<PourToiRepository>(
  (ref) => PourToiRepository(
    ref.watch(apiClientProvider),
    ref.watch(libraryRepositoryProvider),
  ),
);

/// Les rayons « Pour toi » de l'accueil. Un serveur d'avant (sans
/// `pour-toi.php`) répond une erreur : l'accueil masque alors la section.
final pourToiAccueilProvider = FutureProvider<PourToiAccueil>(
  (ref) => ref.watch(pourToiRepositoryProvider).accueil(),
);

final rayonProvider = FutureProvider.family<RayonDetail, int>(
  (ref, id) => ref.watch(pourToiRepositoryProvider).rayon(id),
);

final goutsProfilProvider = FutureProvider<GoutsProfil>(
  (ref) => ref.watch(pourToiRepositoryProvider).profil(),
);

/// Les artistes proches d'un artiste, tirés du serveur (Last.fm ou YouTube
/// Music). Un serveur d'avant la 1.16.0 répond une erreur : la page de
/// l'artiste retombe alors sur YouTube Music, depuis l'app.
final prochesArtisteProvider = FutureProvider.family<List<Bulle>, String>(
  (ref, nom) => ref.watch(pourToiRepositoryProvider).proches(nom),
  // Une erreur dit « serveur d'avant » : on retombe sur YouTube Music, sans
  // réessayer en boucle.
  retry: (_, _) => null,
);

/// Les artistes suggérés (accueil → Découvrir).
final suggestionsArtistesProvider = FutureProvider<List<ArtisteSuggere>>(
  (ref) => ref.watch(pourToiRepositoryProvider).suggestions(),
  retry: (_, _) => null,
);
