import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/ideas_repository.dart';
import 'auth.dart';

final ideasRepositoryProvider = Provider<IdeasRepository>(
  (ref) => IdeasRepository(ref.watch(apiClientProvider)),
);

final ideasProvider = FutureProvider<List<Idea>>(
  (ref) => ref.watch(ideasRepositoryProvider).list(),
);

/// En-têtes d'authentification pour afficher une pièce jointe (idée #84) :
/// ses octets sont servis par `serve_idea_file.php`, hors de l'API v2, donc
/// hors du client Dio qui pose le jeton lui-même.
final ideaFileHeadersProvider = Provider<Map<String, String>>((ref) {
  final token = ref.watch(authProvider).token;
  return token == null || token.isEmpty
      ? const {}
      : {'Authorization': 'Bearer $token'};
});
