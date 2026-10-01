import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/update_repository.dart';
import 'auth.dart';

final updateRepositoryProvider = Provider<UpdateRepository>(
  (ref) => UpdateRepository(ref.watch(apiClientProvider)),
);

/// L'état de mise à jour du serveur.
///
/// Interrogé à l'ouverture de l'écran, et redemandé pendant qu'une mise à
/// jour se fait : le serveur tombe au milieu de l'opération, donc l'erreur
/// de réseau qu'on reçoit alors est attendue, et c'est son retour qui dit
/// que c'est fini.
final serverUpdateProvider = FutureProvider<ServerUpdate>(
  (ref) => ref.watch(updateRepositoryProvider).etat(),
);
