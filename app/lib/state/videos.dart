import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/videos_repository.dart';
import 'auth.dart';

final videosRepositoryProvider = Provider<VideosRepository>(
  (ref) => VideosRepository(ref.watch(apiClientProvider)),
);

/// Requête courante de l'onglet Vidéos.
class VideoSearchQuery extends Notifier<String> {
  @override
  String build() => '';

  void set(String value) {
    final trimmed = value.trim();
    if (trimmed != state) state = trimmed;
  }
}

final videoSearchQueryProvider = NotifierProvider<VideoSearchQuery, String>(
  VideoSearchQuery.new,
);

/// Résultats YouTube. Une recherche coûte ~1 s côté serveur (et y est mise en
/// cache) : on n'interroge qu'à partir de deux caractères.
final videoSearchProvider = FutureProvider<List<VideoResult>>((ref) {
  final query = ref.watch(videoSearchQueryProvider);
  if (query.length < 2) return Future.value(const <VideoResult>[]);
  return ref.watch(videosRepositoryProvider).search(query);
});

/// Vidéothèque du serveur. Tant qu'un téléchargement est en cours, on
/// rafraîchit toutes les 5 s pour faire avancer la barre de progression.
final videoLibraryProvider = FutureProvider<List<ServerVideo>>((ref) async {
  final videos = await ref.watch(videosRepositoryProvider).library();
  if (videos.any((v) => v.status == VideoStatus.downloading)) {
    final timer = Timer(const Duration(seconds: 5), () => ref.invalidateSelf());
    ref.onDispose(timer.cancel);
  }
  return videos;
});

/// Entêtes d'authentification pour le lecteur vidéo : il tape l'endpoint de
/// flux directement, hors du client Dio.
final videoStreamHeadersProvider = Provider<Map<String, String>>((ref) {
  final token = ref.watch(authProvider).token;
  return token == null || token.isEmpty
      ? const {}
      : {'Authorization': 'Bearer $token'};
});
