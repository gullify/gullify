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
