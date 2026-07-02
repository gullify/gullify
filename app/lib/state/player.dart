import 'package:audio_service/audio_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../audio/audio_handler.dart';
import '../models/song.dart';
import 'auth.dart';
import 'library.dart';

/// Overridden in main() with the handler created by AudioService.init().
final audioHandlerProvider = Provider<GullifyAudioHandler>(
  (ref) => throw UnimplementedError('audioHandlerProvider must be overridden'),
);

/// Keeps the handler's repository in sync with auth (needed by Android Auto).
final audioHandlerBinderProvider = Provider<void>((ref) {
  final handler = ref.watch(audioHandlerProvider);
  final auth = ref.watch(authProvider);
  handler.repository = auth.status == AuthStatus.authenticated
      ? ref.watch(libraryRepositoryProvider)
      : null;
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
}

final playerActionsProvider = Provider<PlayerActions>(
  (ref) => PlayerActions(ref.watch(audioHandlerProvider)),
);
