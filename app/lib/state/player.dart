import 'package:audio_service/audio_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../audio/audio_handler.dart';
import '../audio/equalizer.dart';
import '../models/song.dart';
import 'auth.dart';
import 'favorites.dart';
import 'library.dart';
import 'offline.dart';
import 'playlists.dart';
import 'radio.dart';
import 'yt_downloads.dart';

/// Overridden in main() with the handler created by AudioService.init().
final audioHandlerProvider = Provider<GullifyAudioHandler>(
  (ref) => throw UnimplementedError('audioHandlerProvider must be overridden'),
);

/// Égaliseur système. Exposé à part du handler : l'écran de réglage n'a besoin
/// que de lui.
final equalizerProvider = Provider<GullifyEqualizer>(
  (ref) => ref.watch(audioHandlerProvider).equalizer,
);

/// Keeps the handler's repository in sync with auth (needed by Android Auto)
/// and its offline map in sync with downloads.
final audioHandlerBinderProvider = Provider<void>((ref) {
  final handler = ref.watch(audioHandlerProvider);
  final auth = ref.watch(authProvider);
  final authenticated = auth.status == AuthStatus.authenticated;
  // Serveur muet au démarrage (voiture sans réseau) : la session n'est pas
  // « authentifiée », mais on connaît le serveur et le jeton. On lie quand
  // même les dépôts — ils échoueront tant qu'il n'y a pas de réseau, puis
  // répondront d'eux-mêmes dès son retour, ce qui recharge Android Auto.
  final usable = auth.serverUrl != null &&
      (auth.token?.isNotEmpty ?? false) &&
      auth.status != AuthStatus.needsServer;
  handler.logAA('binder: auth=${auth.status.name}'
      '${!authenticated && usable ? ' (jeton hors ligne)' : ''}');
  // Chaque liaison est indépendante et protégée : une erreur sur l'une (ex.
  // client YouTube) ne doit jamais empêcher la bibliothèque de se lier ni
  // casser l'initialisation sans écran (voiture).
  try {
    handler.repository = usable ? ref.watch(libraryRepositoryProvider) : null;
    if (usable) handler.logAA('repository lié');
  } catch (e) {
    handler.logAA('ERREUR liaison repository: $e');
  }
  try {
    handler.radioRepository = usable ? ref.watch(radioRepositoryProvider) : null;
  } catch (e) {
    handler.logAA('ERREUR liaison radio: $e');
  }
  try {
    handler.ytRepository =
        usable ? ref.watch(ytDownloadsRepositoryProvider) : null;
  } catch (e) {
    handler.logAA('ERREUR liaison youtube: $e');
  }
  try {
    handler.playlistRepository =
        usable ? ref.watch(playlistRepositoryProvider) : null;
  } catch (e) {
    handler.logAA('ERREUR liaison playlists: $e');
  }
  // Les titres téléchargés : la seule chose qui reste jouable sans réseau,
  // donc ce qu'Android Auto affiche quand la bibliothèque ne répond pas.
  try {
    final downloads = (ref.watch(offlineProvider).value ?? {}).values.toList()
      ..sort((a, b) {
        final artist =
            (a.song.artistName ?? '').compareTo(b.song.artistName ?? '');
        return artist != 0 ? artist : a.song.title.compareTo(b.song.title);
      });
    handler.offlinePaths = {for (final o in downloads) o.song.id: o.localPath};
    handler.offlineSongs = [for (final o in downloads) o.song];
  } catch (_) {}
  // Le réessai d'Android Auto ne se contente pas de redemander la
  // bibliothèque : il rejoue aussi la restauration de session, seule façon de
  // retrouver l'utilisateur et ses favoris quand le réseau revient en route.
  handler.onRetrySession = () => ref.read(authProvider.notifier).refreshSession();
  // Cœur (favoris) dans la notification / Android Auto : bascule via l'état
  // Riverpod et tient l'icône à jour quand les favoris changent.
  try {
    if (authenticated) {
      handler.onToggleFavorite =
          (id) => ref.read(favoriteIdsProvider.notifier).toggle(id);
      handler.updateFavorites(ref.watch(favoriteIdsProvider).value ?? const {});
    } else {
      handler.onToggleFavorite = null;
      handler.updateFavorites(const {});
    }
  } catch (e) {
    handler.logAA('ERREUR liaison favoris: $e');
  }
});

final currentMediaItemProvider = StreamProvider<MediaItem?>(
  (ref) => ref.watch(audioHandlerProvider).mediaItem,
);

final playbackStateProvider = StreamProvider<PlaybackState>(
  (ref) => ref.watch(audioHandlerProvider).playbackState,
);

final positionProvider = StreamProvider<Duration>(
  (ref) => AudioService.position,
);

final queueProvider = StreamProvider<List<MediaItem>>(
  (ref) => ref.watch(audioHandlerProvider).queue,
);

class PlayerActions {
  PlayerActions(this._handler);

  final GullifyAudioHandler _handler;

  Future<void> playSongs(List<Song> songs, {int startIndex = 0}) =>
      _handler.playSongs(songs, startIndex: startIndex);

  Future<void> togglePlayPause() =>
      _handler.playbackState.value.playing ? _handler.pause() : _handler.play();

  Future<void> next() => _handler.skipToNext();
  Future<void> previous() => _handler.skipToPrevious();
  Future<void> seek(Duration position) => _handler.seek(position);
  Future<void> skipToQueueItem(int index) => _handler.skipToQueueItem(index);

  Future<void> playNext(Song song) => _handler.playNext(song);
  Future<void> addToQueue(Song song) => _handler.addToQueue(song);
  Future<void> moveQueueItem(int from, int to) =>
      _handler.moveQueueItem(from, to);
  Future<void> removeQueueItemAt(int index) =>
      _handler.removeQueueItemAt(index);
  Future<void> clearQueue() => _handler.clearQueueExceptCurrent();

  Future<void> playRadio({
    required String url,
    required String title,
    String? logo,
  }) =>
      _handler.playRadio(url: url, title: title, logo: logo);

  Future<void> toggleShuffle() {
    final current = _handler.playbackState.value.shuffleMode;
    return _handler.setShuffleMode(
      current == AudioServiceShuffleMode.none
          ? AudioServiceShuffleMode.all
          : AudioServiceShuffleMode.none,
    );
  }

  Future<void> cycleRepeat() {
    final current = _handler.playbackState.value.repeatMode;
    return _handler.setRepeatMode(switch (current) {
      AudioServiceRepeatMode.none => AudioServiceRepeatMode.all,
      AudioServiceRepeatMode.all ||
      AudioServiceRepeatMode.group =>
        AudioServiceRepeatMode.one,
      AudioServiceRepeatMode.one => AudioServiceRepeatMode.none,
    });
  }
}

final playerActionsProvider = Provider<PlayerActions>(
  (ref) => PlayerActions(ref.watch(audioHandlerProvider)),
);
