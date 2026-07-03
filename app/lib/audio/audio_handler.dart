import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import '../api/library_repository.dart';
import '../api/radio_repository.dart';
import '../models/song.dart';

bool get equalizerSupported => !kIsWeb && Platform.isAndroid;

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
  static const favorites = 'FAVORITES';
  static const recent = 'RECENT';
  static const radios = 'RADIOS';
  static String album(int id) => 'ALBUM_$id';
  static String artist(int id) => 'ARTIST_$id';
  static String radio(String id) => 'RADIO_$id';
}

class GullifyAudioHandler extends BaseAudioHandler
    with QueueHandler, SeekHandler {
  GullifyAudioHandler() {
    _player.playbackEventStream.listen(_broadcastState);
    _player.currentIndexStream.listen((index) {
      final q = queue.value;
      if (index == null || index < 0 || index >= q.length) return;
      // setAudioSources can emit the same index more than once.
      if (index == _queueIndex && identical(q, _trackedQueue)) return;
      _queueIndex = index;
      _trackedQueue = q;
      _flushPlay();
      _startTracking(q[index]);
      mediaItem.add(q[index]);
    });
    _player.positionStream.listen((pos) {
      if (_trackedSongId != null) _lastPosition = pos;
    });
    _player.processingStateStream.listen((s) {
      if (s == ProcessingState.completed) {
        _lastPosition = _trackedDuration;
        stop();
      }
    });
  }

  /// Android-only equalizer (a pipeline breaks playback on web).
  final equalizer = AndroidEqualizer();

  // Buffer tuning proven by the previous Android client (PixelPlay fork):
  // min 30s / max 60s / playback start after 5s.
  late final _player = AudioPlayer(
    audioPipeline: equalizerSupported
        ? AudioPipeline(androidAudioEffects: [equalizer])
        : null,
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

  /// Set after login — stations web radio pour Android Auto.
  RadioRepository? radioRepository;

  // Caches du browse tree : évitent un second aller-réseau entre le
  // listing (getChildren) et la lecture (playFromMediaId).
  final _albumSongsCache = <int, List<Song>>{};
  List<Song>? _favoritesCache;
  List<RadioStation>? _stationsCache;

  /// songId → local file path for downloaded songs (kept in sync by
  /// audioHandlerBinderProvider). Preferred over streaming when present.
  Map<int, String> offlinePaths = const {};

  AudioPlayer get player => _player;

  // ── Play tracking (play_history / song_stats server-side) ──────────────────

  int? _trackedSongId;
  Duration _trackedDuration = Duration.zero;
  Duration _lastPosition = Duration.zero;
  DateTime _trackedSince = DateTime.now();
  int? _queueIndex;
  List<MediaItem>? _trackedQueue;

  void _startTracking(MediaItem item) {
    _trackedSongId = item.extras?['songId'] as int?;
    _trackedDuration = item.duration ?? Duration.zero;
    _lastPosition = Duration.zero;
    _trackedSince = DateTime.now();
  }

  /// Report the song being tracked, if it was played for at least 5 seconds.
  void _flushPlay() {
    final songId = _trackedSongId;
    // Position updates can lag behind track changes — never report more
    // than the wall-clock time spent on this track.
    final elapsed = DateTime.now().difference(_trackedSince);
    final played = _lastPosition <= elapsed ? _lastPosition : elapsed;
    _trackedSongId = null;
    if (songId == null || played < const Duration(seconds: 5)) return;
    final completed = _trackedDuration > Duration.zero &&
        played >= _trackedDuration - const Duration(seconds: 5);
    repository
        ?.trackPlay(
          songId: songId,
          seconds: played.inSeconds,
          completed: completed,
        )
        .catchError((_) {});
  }

  MediaItem _toMediaItem(Song s) => MediaItem(
        id: offlinePaths.containsKey(s.id)
            ? Uri.file(offlinePaths[s.id]!).toString()
            : repository!.streamUrl(s),
        title: s.title,
        artist: s.artistName,
        album: s.albumName,
        duration: Duration(seconds: s.duration),
        artUri: s.artworkUrl != null ? Uri.parse(s.artworkUrl!) : null,
        extras: {'songId': s.id, 'filePath': s.filePath},
      );

  /// Vrai pendant le remplacement de la file : just_audio repasse alors par
  /// `idle`, qu'il ne faut pas relayer (Android Auto lit STATE_NONE comme
  /// « rien ne joue » et abandonne la sélection en cours).
  bool _switchingSource = false;

  Future<void> playSongs(List<Song> songs, {int startIndex = 0}) async {
    _flushPlay();
    _switchingSource = true;
    final items = songs.map(_toMediaItem).toList();
    queue.add(items);
    await _player.setAudioSources(
      [for (final item in items) AudioSource.uri(Uri.parse(item.id))],
      initialIndex: startIndex,
    );
    await play();
  }

  Future<void> playRadio({
    required String url,
    required String title,
    String? logo,
  }) async {
    _flushPlay();
    _switchingSource = true;
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
    await play();
  }

  // ── Manipulation de la file de lecture ─────────────────────────────────────

  /// Insère juste après la piste en cours.
  Future<void> playNext(Song song) async {
    final item = _toMediaItem(song);
    final index = (_player.currentIndex ?? -1) + 1;
    final q = [...queue.value]..insert(index.clamp(0, queue.value.length), item);
    queue.add(q);
    await _player.insertAudioSource(
      index.clamp(0, q.length - 1),
      AudioSource.uri(Uri.parse(item.id)),
    );
  }

  /// Ajoute en fin de file.
  Future<void> addToQueue(Song song) async {
    final item = _toMediaItem(song);
    queue.add([...queue.value, item]);
    await _player.addAudioSource(AudioSource.uri(Uri.parse(item.id)));
  }

  Future<void> moveQueueItem(int from, int to) async {
    final q = [...queue.value];
    if (from < 0 || from >= q.length || to < 0 || to >= q.length) return;
    q.insert(to, q.removeAt(from));
    queue.add(q);
    await _player.moveAudioSource(from, to);
  }

  @override
  Future<void> removeQueueItemAt(int index) async {
    final q = [...queue.value];
    if (index < 0 || index >= q.length) return;
    q.removeAt(index);
    queue.add(q);
    await _player.removeAudioSourceAt(index);
  }

  /// Vide la file en gardant la piste en cours.
  Future<void> clearQueueExceptCurrent() async {
    final current = _player.currentIndex;
    if (current == null) return;
    final q = queue.value;
    if (current < q.length - 1) {
      await _player.removeAudioSourceRange(current + 1, q.length);
    }
    if (current > 0) {
      await _player.removeAudioSourceRange(0, current);
    }
    queue.add([q[current]]);
  }

  /// Fondu de volume court : reprise et pause en douceur plutôt qu'à sec.
  /// (Un vrai crossfade entre pistes exigerait deux lecteurs simultanés.)
  Future<void> _fadeTo(double target) async {
    const steps = 8;
    const stepDelay = Duration(milliseconds: 30);
    final start = _player.volume;
    for (var i = 1; i <= steps; i++) {
      await _player.setVolume(start + (target - start) * i / steps);
      await Future<void>.delayed(stepDelay);
    }
  }

  @override
  Future<void> play() async {
    await _player.setVolume(0);
    // play() de just_audio ne se résout qu'à la pause/fin — ne pas attendre.
    unawaited(_player.play());
    await _fadeTo(1);
  }

  @override
  Future<void> pause() async {
    await _fadeTo(0);
    await _player.pause();
    await _player.setVolume(1);
  }

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
    await play();
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
    _flushPlay();
    _switchingSource = false;
    await _player.stop();
    await super.stop();
  }

  // ── Media browser tree (Android Auto) ──────────────────────────────────────

  MediaItem _browsableAlbum(int id, String name, String? artist, String? art) =>
      MediaItem(
        id: BrowseIds.album(id),
        title: name,
        artist: artist,
        artUri: art != null ? Uri.parse(art) : null,
        playable: false,
      );

  /// Entrées « Tout lire » / « Aléatoire » en tête d'une liste de pistes.
  List<MediaItem> _playAllItems(String prefix, {String playLabel = 'Tout lire'}) => [
        MediaItem(id: '${prefix}_PLAY', title: playLabel, playable: true),
        MediaItem(
          id: '${prefix}_SHUFFLE',
          title: 'Lecture aléatoire',
          playable: true,
        ),
      ];

  List<MediaItem> _trackItems(String prefix, List<Song> songs) => [
        for (final (i, s) in songs.indexed)
          MediaItem(
            id: '${prefix}_TRACK_$i',
            title: s.title,
            artist: s.artistName,
            album: s.albumName,
            duration: Duration(seconds: s.duration),
            artUri: s.artworkUrl != null ? Uri.parse(s.artworkUrl!) : null,
            playable: true,
          ),
      ];

  @override
  Future<List<MediaItem>> getChildren(
    String parentMediaId, [
    Map<String, dynamic>? options,
  ]) async {
    final repo = repository;
    if (repo == null) return [];

    switch (parentMediaId) {
      case BrowseIds.root:
        return const [
          MediaItem(id: BrowseIds.favorites, title: 'Favoris', playable: false),
          MediaItem(id: BrowseIds.recent, title: 'Nouveautés', playable: false),
          MediaItem(id: BrowseIds.albums, title: 'Albums', playable: false),
          MediaItem(id: BrowseIds.artists, title: 'Artistes', playable: false),
          MediaItem(id: BrowseIds.radios, title: 'Radios', playable: false),
        ];

      case BrowseIds.favorites:
        final songs = await repo.allFavorites();
        _favoritesCache = songs;
        if (songs.isEmpty) return [];
        return [..._playAllItems('FAV'), ..._trackItems('FAV', songs)];

      case BrowseIds.recent:
        final albums = await repo.recentAlbums();
        return [
          for (final a in albums)
            _browsableAlbum(a.id, a.name, a.artistName, a.artworkUrl),
        ];

      case BrowseIds.albums:
        final albums = await repo.albums();
        return [
          for (final a in albums)
            _browsableAlbum(a.id, a.name, a.artistName, a.artworkUrl),
        ];

      case BrowseIds.artists:
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

      case BrowseIds.radios:
        final stations = await radioRepository?.stations() ?? [];
        _stationsCache = stations;
        // Favoris d'abord, comme dans l'app.
        stations.sort((a, b) {
          if (a.favorite != b.favorite) return a.favorite ? -1 : 1;
          return a.name.compareTo(b.name);
        });
        return [
          for (final s in stations)
            MediaItem(
              id: BrowseIds.radio(s.id),
              title: s.name,
              artist: s.genres.isNotEmpty ? s.genres.join(', ') : s.country,
              artUri: s.logo != null ? Uri.parse(s.logo!) : null,
              playable: true,
            ),
        ];
    }

    if (parentMediaId.startsWith('ALBUM_')) {
      final id = int.parse(parentMediaId.substring('ALBUM_'.length));
      final detail = await repo.albumDetail(id);
      _albumSongsCache[id] = detail.songs;
      return [
        ..._playAllItems('ALBUM_$id', playLabel: "Lire l'album"),
        ..._trackItems('ALBUM_$id', detail.songs),
      ];
    }

    if (parentMediaId.startsWith('ARTIST_')) {
      final id = int.parse(parentMediaId.substring('ARTIST_'.length));
      final detail = await repo.artistDetail(id);
      return [
        ..._playAllItems('ARTIST_$id'),
        for (final a in detail.albums)
          _browsableAlbum(a.id, a.name, detail.artist.name, a.artworkUrl),
      ];
    }

    return [];
  }

  /// Toutes les chansons d'un artiste, dans l'ordre des albums.
  Future<List<Song>> _artistSongs(LibraryRepository repo, int artistId) async {
    final detail = await repo.artistDetail(artistId);
    final albums = await Future.wait(
      [for (final a in detail.albums) repo.albumDetail(a.id)],
    );
    return [for (final a in albums) ...a.songs];
  }

  Future<List<Song>> _albumSongs(LibraryRepository repo, int albumId) async =>
      _albumSongsCache[albumId] ?? (await repo.albumDetail(albumId)).songs;

  Future<List<Song>> _favorites(LibraryRepository repo) async =>
      _favoritesCache ?? await repo.allFavorites();

  /// Selon la version d'Android Auto, la sélection d'un item passe par
  /// prepareFromMediaId (puis play) plutôt que playFromMediaId. Le défaut du
  /// plugin est un no-op silencieux — exactement le symptôme « impossible de
  /// charger la sélection ». On joue directement : c'est ce qu'attend l'auto.
  @override
  Future<void> prepareFromMediaId(
    String mediaId, [
    Map<String, dynamic>? extras,
  ]) =>
      playFromMediaId(mediaId, extras);

  /// Android Auto peut demander le détail d'un item avant de le jouer;
  /// le défaut (null) fait échouer la sélection.
  @override
  Future<MediaItem?> getMediaItem(String mediaId) async {
    final m =
        RegExp(r'^(?:ALBUM_(\d+)|FAV)_TRACK_(\d+)$').firstMatch(mediaId);
    if (m != null) {
      final repo = repository;
      if (repo == null) return null;
      final songs = m.group(1) != null
          ? await _albumSongs(repo, int.parse(m.group(1)!))
          : await _favorites(repo);
      final index = int.parse(m.group(2)!);
      if (index < 0 || index >= songs.length) return null;
      final s = songs[index];
      return _toMediaItem(s).copyWith(id: mediaId);
    }
    if (mediaId.startsWith('RADIO_')) {
      final id = mediaId.substring('RADIO_'.length);
      final s = (_stationsCache ?? []).where((s) => s.id == id).firstOrNull;
      if (s == null) return null;
      return MediaItem(
        id: mediaId,
        title: s.name,
        artist: 'Radio',
        isLive: true,
        artUri: s.logo != null ? Uri.parse(s.logo!) : null,
      );
    }
    // File de lecture courante (ids = URL de flux).
    return queue.value.where((i) => i.id == mediaId).firstOrNull;
  }

  /// Recherche vocale (« Joue X sur Gullify ») : meilleur artiste, sinon
  /// album, sinon titres trouvés.
  @override
  Future<void> playFromSearch(
    String query, [
    Map<String, dynamic>? extras,
  ]) async {
    final repo = repository;
    if (repo == null || query.trim().isEmpty) return;
    playbackState.add(playbackState.value.copyWith(
      processingState: AudioProcessingState.loading,
      playing: false,
    ));
    try {
      final r = await repo.search(query);
      if (r.artists.isNotEmpty) {
        await playSongs(await _artistSongs(repo, r.artists.first.id));
      } else if (r.albums.isNotEmpty) {
        await playSongs(await _albumSongs(repo, r.albums.first.id));
      } else if (r.songs.isNotEmpty) {
        await playSongs(r.songs);
      } else {
        playbackState.add(playbackState.value.copyWith(
          processingState: AudioProcessingState.idle,
        ));
      }
    } catch (_) {
      playbackState.add(playbackState.value.copyWith(
        processingState: AudioProcessingState.idle,
      ));
    }
  }

  @override
  Future<void> prepareFromSearch(
    String query, [
    Map<String, dynamic>? extras,
  ]) =>
      playFromSearch(query, extras);

  @override
  Future<void> playFromMediaId(
    String mediaId, [
    Map<String, dynamic>? extras,
  ]) async {
    final repo = repository;
    if (repo == null) return;

    // Android Auto attend une réaction immédiate de la session, sinon il
    // affiche « impossible de lire la sélection ». On publie l'état de
    // chargement avant tout aller-réseau.
    playbackState.add(playbackState.value.copyWith(
      processingState: AudioProcessingState.loading,
      playing: false,
    ));

    final m = RegExp(r'^(ALBUM_(\d+)|ARTIST_(\d+)|FAV)(?:_(PLAY|SHUFFLE|TRACK_(\d+)))?$')
        .firstMatch(mediaId);

    try {
      if (mediaId.startsWith('RADIO_')) {
        final id = mediaId.substring('RADIO_'.length);
        final stations = _stationsCache ?? await radioRepository?.stations() ?? [];
        final s = stations.where((s) => s.id == id).firstOrNull;
        if (s != null) {
          await playRadio(url: s.streamUrl, title: s.name, logo: s.logo);
        }
        return;
      }

      if (m == null) return;

      final List<Song> songs;
      if (m.group(2) != null) {
        songs = await _albumSongs(repo, int.parse(m.group(2)!));
      } else if (m.group(3) != null) {
        songs = await _artistSongs(repo, int.parse(m.group(3)!));
      } else {
        songs = await _favorites(repo);
      }
      if (songs.isEmpty) return;

      final action = m.group(4) ?? 'PLAY';
      if (action == 'SHUFFLE') {
        await playSongs(songs.toList()..shuffle());
      } else if (action.startsWith('TRACK_')) {
        final index = int.parse(m.group(5)!);
        await playSongs(songs, startIndex: index.clamp(0, songs.length - 1));
      } else {
        await playSongs(songs);
      }
    } catch (_) {
      // Retombe sur idle pour qu'Android Auto ne reste pas bloqué en
      // chargement si le serveur ne répond pas.
      playbackState.add(playbackState.value.copyWith(
        processingState: AudioProcessingState.idle,
      ));
    }
  }

  void _broadcastState(PlaybackEvent event) {
    final playing = _player.playing;
    var processingState = switch (_player.processingState) {
      ProcessingState.idle => AudioProcessingState.idle,
      ProcessingState.loading => AudioProcessingState.loading,
      ProcessingState.buffering => AudioProcessingState.buffering,
      ProcessingState.ready => AudioProcessingState.ready,
      ProcessingState.completed => AudioProcessingState.completed,
    };
    if (_switchingSource) {
      if (processingState == AudioProcessingState.idle) {
        processingState = AudioProcessingState.loading;
      } else if (processingState == AudioProcessingState.ready ||
          processingState == AudioProcessingState.buffering) {
        _switchingSource = false;
      }
    }
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
        processingState: processingState,
        playing: playing,
        updatePosition: _player.position,
        bufferedPosition: _player.bufferedPosition,
        speed: _player.speed,
        queueIndex: event.currentIndex,
      ),
    );
  }
}
