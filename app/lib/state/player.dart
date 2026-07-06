import 'package:audio_service/audio_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../audio/audio_handler.dart';
import '../models/song.dart';
import 'auth.dart';
import 'library.dart';
import 'offline.dart';
import 'radio.dart';
import 'yt_downloads.dart';

/// Overridden in main() with the handler created by AudioService.init().
final audioHandlerProvider = Provider<GullifyAudioHandler>(
  (ref) => throw UnimplementedError('audioHandlerProvider must be overridden'),
);

/// Keeps the handler's repository in sync with auth (needed by Android Auto)
/// and its offline map in sync with downloads.
final audioHandlerBinderProvider = Provider<void>((ref) {
  final handler = ref.watch(audioHandlerProvider);
  final auth = ref.watch(authProvider);
  final authenticated = auth.status == AuthStatus.authenticated;
  handler.repository =
      authenticated ? ref.watch(libraryRepositoryProvider) : null;
  handler.radioRepository =
      authenticated ? ref.watch(radioRepositoryProvider) : null;
  handler.ytRepository =
      authenticated ? ref.watch(ytDownloadsRepositoryProvider) : null;
  handler.offlinePaths = {
    for (final o in (ref.watch(offlineProvider).value ?? {}).values)
      o.song.id: o.localPath,
  };
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
