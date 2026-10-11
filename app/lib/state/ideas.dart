import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/ideas_inbox_repository.dart';
import '../api/ideas_repository.dart';
import 'auth.dart';

final ideasRepositoryProvider = Provider<IdeasRepository>(
  (ref) => IdeasRepository(ref.watch(apiClientProvider)),
);

final ideasProvider = FutureProvider<Carnet>(
  (ref) => ref.watch(ideasRepositoryProvider).list(),
);

final ideasInboxRepositoryProvider = Provider<IdeasInboxRepository>(
  (ref) => IdeasInboxRepository(ref.watch(apiClientProvider)),
);

/// Ce que les autres serveurs ont envoyé au développeur.
///
/// Vide pour tout le monde sauf lui — et vide, et non en panne, si le
/// serveur ne répond pas : un carnet personnel ne doit pas disparaître de
/// l'écran parce que la boîte d'un autre est injoignable.
final ideasInboxProvider = FutureProvider<List<IdeeRecue>>((ref) async {
  try {
    return await ref.watch(ideasInboxRepositoryProvider).list();
  } catch (_) {
    return const [];
  }
});

/// En-têtes d'authentification pour afficher une pièce jointe (idée #84) :
/// ses octets sont servis par `serve_idea_file.php`, hors de l'API v2, donc
/// hors du client Dio qui pose le jeton lui-même.
final ideaFileHeadersProvider = Provider<Map<String, String>>((ref) {
  final token = ref.watch(authProvider).token;
  return token == null || token.isEmpty
      ? const {}
      : {'Authorization': 'Bearer $token'};
});
