import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/admin_repository.dart';
import 'auth.dart';

final adminRepositoryProvider = Provider<AdminRepository>(
  (ref) => AdminRepository(ref.watch(apiClientProvider)),
);

/// Les comptes du serveur. Réservé aux administrateurs : le serveur répond
/// 403 aux autres.
final adminUsersProvider = FutureProvider<List<AdminUser>>(
  (ref) => ref.watch(adminRepositoryProvider).users(),
);

/// Les dossiers de musique proposables. Chargés à l'ouverture d'une fiche,
/// pour éviter de faire taper un chemin à la main.
final musicDirectoriesProvider = FutureProvider<MusicDirectories>(
  (ref) => ref.watch(adminRepositoryProvider).directories(),
);

/// L'utilisateur connecté est-il administrateur ? Commande l'entrée
/// « Utilisateurs » des Paramètres.
final isAdminProvider = Provider<bool>(
  (ref) => ref.watch(authProvider).user?.isAdmin ?? false,
);
