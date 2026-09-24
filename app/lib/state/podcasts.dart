import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/podcasts_repository.dart';
import '../audio/audio_handler.dart';
import 'auth.dart';
import 'player.dart';

final podcastsRepositoryProvider = Provider<PodcastsRepository>(
  (ref) => PodcastsRepository(ref.watch(apiClientProvider)),
);

/// Les catégories du palmarès (idée #112).
final podcastGenresProvider = FutureProvider<List<PodcastGenre>>(
  (ref) => ref.watch(podcastsRepositoryProvider).genres(),
);

/// Les abonnements de l'utilisateur.
final podcastSubscriptionsProvider = FutureProvider<List<PodcastShow>>(
  (ref) => ref.watch(podcastsRepositoryProvider).subscriptions(),
);

/// Les podcasts trouvés pour une requête.
final podcastSearchProvider = FutureProvider.family<List<PodcastShow>, String>(
  (ref, query) => query.trim().isEmpty
      ? Future.value(const <PodcastShow>[])
      : ref.watch(podcastsRepositoryProvider).search(query.trim()),
);

/// Le palmarès d'une catégorie — la liste « à découvrir ».
final podcastDiscoverProvider = FutureProvider.family<List<PodcastShow>, int>(
  (ref, genreId) => ref.watch(podcastsRepositoryProvider).discover(genreId),
);

/// La catégorie affichée dans « À découvrir ». Les crimes réels en tête, comme
/// chez Apple : c'est le palmarès le plus consulté.
class PodcastGenreChoice extends Notifier<int> {
  @override
  int build() => 1488;

  void select(int genreId) => state = genreId;
}

final podcastGenreChoiceProvider =
    NotifierProvider<PodcastGenreChoice, int>(PodcastGenreChoice.new);

/// La série et ses épisodes, lus dans le flux (clé = l'adresse du flux).
final podcastFeedProvider = FutureProvider.family<PodcastFeed, String>(
  (ref, feedUrl) => ref.watch(podcastsRepositoryProvider).episodes(feedUrl),
);

/// Toutes les 20 secondes d'écoute : un podcast se reprend à la seconde près,
/// sur cet appareil comme sur le suivant. Plus souvent serait du bavardage
/// réseau pour rien.
const _kSaveEvery = Duration(seconds: 20);

/// Un épisode dont il reste moins que ça est compté comme écouté : la fin
/// d'un épisode, c'est le générique et les remerciements.
const _kEndSlack = Duration(seconds: 30);

/// Retient où l'on en est dans l'épisode qui joue (idée #112).
///
/// Vit dans la coque, comme le widget d'écran d'accueil : l'écran d'un podcast
/// n'a pas à rester ouvert pour que la position soit retenue — on écoute un
/// épisode en faisant autre chose, c'est même la règle.
final podcastProgressSyncProvider = Provider<void>((ref) {
  /// L'épisode suivi et ce qu'on sait de lui.
  String? feedUrl;
  String? guid;
  Duration duration = Duration.zero;
  Duration position = Duration.zero;
  Duration saved = Duration.zero;

  Future<void> push({required bool completed}) async {
    final feed = feedUrl;
    final episode = guid;
    if (feed == null || episode == null) return;
    if (!completed && position.inSeconds <= 0) return;
    saved = position;
    try {
      // Lu au moment de l'envoi (et non à la construction) : un écran de test
      // ne doit pas avoir à monter un client d'API pour afficher la coque.
      await ref.read(podcastsRepositoryProvider).saveProgress(
            feedUrl: feed,
            guid: episode,
            position: completed ? 0 : position.inSeconds,
            duration: duration.inSeconds,
            completed: completed,
          );
    } catch (_) {
      // Sans réseau, la position est perdue : sans conséquence, on la
      // réécrira à la prochaine occasion.
    }
  }

  /// L'épisode est-il assez avancé pour être dit écouté ?
  bool atEnd() => duration > Duration.zero && position >= duration - _kEndSlack;

  void follow(MediaItem? item) {
    final extras = item?.extras;
    final nextGuid = extras?[kPodcastEpisode] as String?;
    final nextFeed = extras?[kPodcastFeed] as String?;
    if (nextGuid == guid && nextFeed == feedUrl) {
      // Même épisode : seule sa durée a pu se préciser (les flux ne la
      // donnent pas tous, le lecteur la découvre en chargeant le fichier).
      final known = item?.duration;
      if (known != null && known > Duration.zero) duration = known;
      return;
    }
    // On quitte un épisode : sa position part maintenant, sinon elle est
    // perdue pour de bon.
    if (guid != null) unawaited(push(completed: atEnd()));
    feedUrl = nextFeed;
    guid = nextGuid;
    duration = item?.duration ?? Duration.zero;
    position = Duration.zero;
    saved = Duration.zero;
  }

  ref.listen(currentMediaItemProvider, (_, next) => follow(next.value));

  ref.listen(positionProvider, (_, next) {
    if (guid == null) return;
    final now = next.value;
    if (now == null) return;
    position = now;
    // Un saut en arrière (recul de 30 s, scrubber) doit partir tout de suite :
    // sinon une reprise à froid rejouerait ce qu'on venait de passer.
    final jumped = now < saved;
    if (jumped || now - saved >= _kSaveEvery) unawaited(push(completed: false));
  });

  // L'app se ferme, ou l'utilisateur se déconnecte : dernière position connue.
  ref.onDispose(() {
    if (guid != null) unawaited(push(completed: atEnd()));
  });
});
