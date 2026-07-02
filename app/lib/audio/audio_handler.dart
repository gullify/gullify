import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';

import '../api/library_repository.dart';
import '../models/song.dart';

Future<GullifyAudioHandler> initAudioHandler() {
  return AudioService.init(
    builder: GullifyAudioHandler.new,
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'app.gullify.audio',
      androidNotificationChannelName: 'Lecture Gullify',
      androidNotificationOngoing: true,
      androidStopForegroundOnPause: true,
    ),
  );
}

/// Media IDs used for the Android Auto / media browser tree.
class BrowseIds {
  static const root = AudioService.browsableRootId;
  static const albums = 'ALBUMS';
  static const artists = 'ARTISTS';
  static String album(int id) => 'ALBUM_$id';
  static String artist(int id) => 'ARTIST_$id';
}

class GullifyAudioHandler extends BaseAudioHandler
    with QueueHandler, SeekHandler {
  GullifyAudioHandler() {
    _player.playbackEventStream.listen(_broadcastState);
    _player.currentIndexStream.listen((index) {
      final q = queue.value;
      if (index != null && index >= 0 && index < q.length) {
        mediaItem.add(q[index]);
      }
    });
    _player.processingStateStream.listen((s) {
      if (s == ProcessingState.completed) stop();
    });
  }

  // Buffer tuning proven by the previous Android client (PixelPlay fork):
  // min 30s / max 60s / playback start after 5s.
  final _player = AudioPlayer(
    audioLoadConfiguration: const AudioLoadConfiguration(
      androidLoadControl: AndroidLoadControl(
        minBufferDuration: Duration(seconds: 30),
        maxBufferDuration: Duration(seconds: 60),
        bufferForPlaybackDuration: Duration(seconds: 5),
        bufferForPlaybackAfterRebufferDuration: Duration(seconds: 10),
      ),
    ),
  );

  /// Set after login so the media browser (Android Auto) can list the library.
  LibraryRepository? repository;

  AudioPlayer get player => _player;

  MediaItem _toMediaItem(Song s) => MediaItem(
        id: repository!.streamUrl(s),
        title: s.title,
        artist: s.artistName,
        album: s.albumName,
        duration: Duration(seconds: s.duration),
        artUri: s.artworkUrl != null ? Uri.parse(s.artworkUrl!) : null,
        extras: {'songId': s.id, 'filePath': s.filePath},
      );

  Future<void> playSongs(List<Song> songs, {int startIndex = 0}) async {
    final items = songs.map(_toMediaItem).toList();
    queue.add(items);
    await _player.setAudioSources(
      [for (final item in items) AudioSource.uri(Uri.parse(item.id))],
      initialIndex: startIndex,
    );
    await _player.play();
  }

  Future<void> playRadio({
    required String url,
    required String title,
    String? logo,
  }) async {
    final item = MediaItem(
      id: url,
      title: title,
      artist: 'Radio',
      isLive: true,
      artUri: logo != null ? Uri.parse(logo) : null,
      extras: const {'radio': true},
    );
    queue.add([item]);
    await _player.setAudioSources([AudioSource.uri(Uri.parse(url))]);
    await _player.play();
  }

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> skipToNext() => _player.seekToNext();

  @override
  Future<void> skipToPrevious() async {
    if (_player.position > const Duration(seconds: 3)) {
      await _player.seek(Duration.zero);
    } else {
      await _player.seekToPrevious();
    }
  }

  @override
  Future<void> skipToQueueItem(int index) async {
    await _player.seek(Duration.zero, index: index);
    await _player.play();
  }

  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode shuffleMode) async {
    final enabled = shuffleMode != AudioServiceShuffleMode.none;
    if (enabled) await _player.shuffle();
    await _player.setShuffleModeEnabled(enabled);
    playbackState.add(playbackState.value.copyWith(shuffleMode: shuffleMode));
  }

  @override
  Future<void> setRepeatMode(AudioServiceRepeatMode repeatMode) async {
    await _player.setLoopMode(switch (repeatMode) {
      AudioServiceRepeatMode.one => LoopMode.one,
      AudioServiceRepeatMode.all ||
      AudioServiceRepeatMode.group =>
        LoopMode.all,
      AudioServiceRepeatMode.none => LoopMode.off,
    });
    playbackState.add(playbackState.value.copyWith(repeatMode: repeatMode));
  }

  @override
  Future<void> stop() async {
    await _player.stop();
    await super.stop();
  }

  // ── Media browser tree (Android Auto) ──────────────────────────────────────

  @override
  Future<List<MediaItem>> getChildren(
    String parentMediaId, [
    Map<String, dynamic>? options,
  ]) async {
    final repo = repository;
    if (repo == null) return [];

    if (parentMediaId == BrowseIds.root) {
      return const [
        MediaItem(
          id: BrowseIds.albums,
          title: 'Albums',
          playable: false,
        ),
        MediaItem(
          id: BrowseIds.artists,
          title: 'Artistes',
          playable: false,
        ),
      ];
    }
    if (parentMediaId == BrowseIds.albums) {
      final albums = await repo.albums();
      return [
        for (final a in albums)
          MediaItem(
            id: BrowseIds.album(a.id),
            title: a.name,
            artist: a.artistName,
            artUri: a.artworkUrl != null ? Uri.parse(a.artworkUrl!) : null,
            playable: true,
          ),
      ];
    }
    if (parentMediaId == BrowseIds.artists) {
      final artists = await repo.artists();
      return [
        for (final ar in artists)
          MediaItem(
            id: BrowseIds.artist(ar.id),
            title: ar.name,
            artUri: ar.imageUrl != null ? Uri.parse(ar.imageUrl!) : null,
            playable: false,
          ),
      ];
    }
    if (parentMediaId.startsWith('ARTIST_')) {
      final id = int.parse(parentMediaId.substring('ARTIST_'.length));
      final detail = await repo.artistDetail(id);
      return [
        for (final a in detail.albums)
          MediaItem(
            id: BrowseIds.album(a.id),
            title: a.name,
            artist: detail.artist.name,
            artUri: a.artworkUrl != null ? Uri.parse(a.artworkUrl!) : null,
            playable: true,
          ),
      ];
    }
    return [];
  }

  @override
  Future<void> playFromMediaId(
    String mediaId, [
    Map<String, dynamic>? extras,
  ]) async {
    final repo = repository;
    if (repo == null) return;
    if (mediaId.startsWith('ALBUM_')) {
      final id = int.parse(mediaId.substring('ALBUM_'.length));
      final detail = await repo.albumDetail(id);
      await playSongs(detail.songs);
    }
  }

  void _broadcastState(PlaybackEvent event) {
    final playing = _player.playing;
    playbackState.add(
      playbackState.value.copyWith(
        controls: [
          MediaControl.skipToPrevious,
          if (playing) MediaControl.pause else MediaControl.play,
          MediaControl.skipToNext,
          MediaControl.stop,
        ],
        systemActions: const {
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
        },
        androidCompactActionIndices: const [0, 1, 2],
        processingState: switch (_player.processingState) {
          ProcessingState.idle => AudioProcessingState.idle,
          ProcessingState.loading => AudioProcessingState.loading,
          ProcessingState.buffering => AudioProcessingState.buffering,
          ProcessingState.ready => AudioProcessingState.ready,
          ProcessingState.completed => AudioProcessingState.completed,
        },
        playing: playing,
        updatePosition: _player.position,
        bufferedPosition: _player.bufferedPosition,
        speed: _player.speed,
        queueIndex: event.currentIndex,
      ),
    );
  }
}
