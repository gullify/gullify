import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/music_root_repository.dart';
import 'auth.dart';

final musicRootRepositoryProvider = Provider<MusicRootRepository>(
  (ref) => MusicRootRepository(ref.watch(apiClientProvider)),
);

/// Ce qu'il y a dans un dossier de la machine. Le chemin vide = les points de
/// départ (les disques montés, le dossier personnel, la racine actuelle).
final dossiersServeurProvider =
    FutureProvider.family<VueDossier, String>((ref, chemin) async {
  return ref.watch(musicRootRepositoryProvider).parcourir(chemin: chemin);
});
