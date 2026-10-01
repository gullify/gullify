import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/update_repository.dart';
import 'auth.dart';

final updateRepositoryProvider = Provider<UpdateRepository>(
  (ref) => UpdateRepository(ref.watch(apiClientProvider)),
);

/// L'état de mise à jour du serveur.
///
/// Interrogé à l'ouverture de l'écran, et redemandé pendant qu'une mise à
/// jour se fait : le serveur tombe au milieu de l'opération, donc le silence
/// qu'on reçoit alors est attendu, et c'est son retour qui dit que c'est
/// fini.
///
/// Ce silence ne doit SURTOUT pas devenir une erreur du provider. Riverpod
/// reprend un provider en panne avec un délai qui double à chaque essai :
/// la carte restait figée sur la dernière réponse reçue — « Récupération du
/// code… » — alors que le serveur avait fini seize secondes plus tard et
/// répondait de nouveau. Un serveur muet est donc une réponse comme une
/// autre.
final serverUpdateProvider = FutureProvider<ServerUpdate>((ref) async {
  try {
    return await ref.watch(updateRepositoryProvider).etat();
  } catch (_) {
    return const ServerUpdate.injoignable();
  }
});
