import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import '../api/library_repository.dart';
import '../api/playlist_repository.dart';
import '../api/radio_repository.dart';
import '../api/yt_downloads_repository.dart';
import '../models/song.dart';
import 'equalizer.dart';
import 'tuned_player.dart';

export 'equalizer.dart' show equalizerSupported;

Future<GullifyAudioHandler> initAudioHandler() {
  return AudioService.init(
    builder: GullifyAudioHandler.new,
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'app.gullify.audio',
      androidNotificationChannelName: 'Lecture Gullify',
      // Icône monochrome dédiée : le mipmap adaptatif du launcher (défaut)
      // est refusé silencieusement comme petite icône par plusieurs
      // appareils → aucune notification média, app gelée en veille.
      androidNotificationIcon: 'drawable/ic_notification',
      androidNotificationOngoing: true,
      androidStopForegroundOnPause: true,
    ),
  );
}

/// Marque, dans les extras d'une fiche du lecteur principal, la pré-écoute
/// d'un titre YouTube (idée #59) : c'est à ça que la recherche reconnaît « son »
/// titre dans ce que joue le lecteur principal.
const kPreviewVideoId = 'previewVideoId';

/// Media IDs used for the Android Auto / media browser tree.
class BrowseIds {
  static const root = AudioService.browsableRootId;
  static const home = 'HOME';
  static const library = 'LIBRARY';
  static const albums = 'ALBUMS';
  static const artists = 'ARTISTS';
  static const favorites = 'FAVORITES';
  static const recent = 'RECENT';
  static const popular = 'POPULAR';
  static const recentPlays = 'RECENTPLAYS';
  static const radios = 'RADIOS';
  static const playlists = 'PLAYLISTS';
  static const genres = 'GENRES';
  static String album(int id) => 'ALBUM_$id';
  static String artist(int id) => 'ARTIST_$id';
  static String playlist(int id) => 'PLAYLIST_$id';
  static String genre(String name) => 'GENRE_$name';
  static String radio(String id) => 'RADIO_$id';
}

class GullifyAudioHandler extends BaseAudioHandler
    with QueueHandler, SeekHandler {
  GullifyAudioHandler() {
    // Marqueur de démarrage : si Android tue le process en veille (Doze /
    // optimisation batterie) puis le relance, le journal repart d'ici — c'est
    // LE signal d'un arrêt « écran éteint » causé par le système, pas par la
    // lecture elle-même.
    logPlayback('— démarrage de l\'app —');
    _player.playbackEventStream.listen(
      _broadcastState,
      // Une erreur du lecteur (flux coupé en veille, source injoignable…) est
      // la cause typique d'un arrêt écran éteint : on la journalise.
      onError: (Object e, StackTrace _) =>
          logPlayback('ERREUR lecteur : $e'),
    );
    // Changement d'état « joue / ne joue pas ». Capte AUSSI les pauses
    // spontanées (perte de focus audio, coupure système) qui ne passent pas
    // par notre pause() — exactement le symptôme à diagnostiquer en veille.
    _player.playerStateStream.listen((s) {
      if (s.playing == _lastLoggedPlaying) return;
      _lastLoggedPlaying = s.playing;
      // (Le verrou réseau qui garde la Wi-Fi et le CPU actifs écran éteint est
      // tenu par le lecteur lui-même — voir tuned_player.dart, où tous les
      // lecteurs de l'app le prennent désormais.)
      // Le titre courant permet de savoir quelle piste s'est arrêtée (utile
      // quand l'arrêt suit un changement de source ou une piste précise).
      final title = mediaItem.value?.title;
      final suffix = title != null ? ' : « $title »' : '';
      logPlayback(s.playing
          ? '▶ lecture$suffix'
          : '⏸ pause à ${_fmtPos(_player.position)}$suffix');
    });
    // Transitions du cycle de lecture (mise en tampon = stall réseau, etc.).
    _player.processingStateStream.listen((s) {
      if (s != _lastLoggedProcessing) {
        _lastLoggedProcessing = s;
        logPlayback('état : ${_processingLabel(s)}');
      }
    });
    _watchAudioSession();
    // La session audio n'existe qu'une fois la lecture lancée (ExoPlayer la
    // génère en tâche de fond) : c'est le seul moment où l'égaliseur peut
    // s'accrocher. Une nouvelle session = un nouvel effet à recréer.
    if (equalizerSupported) {
      _player.androidAudioSessionIdStream.listen((id) {
        if (id == null) return;
        logPlayback('égaliseur : session audio $id');
        equalizer.attachSession(id);
      });
    }
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
      // Rafraîchit le cœur (favori) pour la nouvelle piste courante.
      playbackState.add(
        playbackState.value.copyWith(
          controls: _controls(playbackState.value.playing),
        ),
      );
    });
    _player.positionStream.listen((pos) {
      if (_trackedSongId != null) _lastPosition = pos;
    });
    // La durée d'un flux qu'on ne connaît pas d'avance (la pré-écoute d'un titre
    // YouTube : le serveur la découvre en le transcodant) n'arrive qu'une fois
    // le titre chargé. On complète alors sa fiche, sans quoi le scrubber du
    // lecteur et la barre de la recherche n'auraient jamais de fin. Une radio
    // n'en a pas non plus, mais elle est en direct : le lecteur ne rend rien.
    _player.durationStream.listen((duration) {
      final item = mediaItem.value;
      if (duration == null || item == null || item.duration != null) return;
      mediaItem.add(item.copyWith(duration: duration));
    });
    _player.processingStateStream.listen((s) {
      if (s == ProcessingState.completed) {
        _lastPosition = _trackedDuration;
        stop();
      }
    });
  }

  /// Égaliseur système (Android). Volontairement HORS de l'AudioPipeline de
  /// just_audio : celui-ci lisait les bandes avant qu'ExoPlayer n'ait de
  /// session audio, et l'exception empoisonnait le lecteur — plus aucune
  /// lecture possible (idée #47). Voir equalizer.dart.
  final equalizer = GullifyEqualizer();

  // Réglage des tampons et verrou réseau : voir tuned_player.dart, d'où sortent
  // tous les lecteurs de l'app.
  late final _player = createGullifyPlayer(use: PlayerUse.streaming);

  /// Set after login so the media browser (Android Auto) can list the library.
  LibraryRepository? repository;

  /// Set after login — stations web radio pour Android Auto.
  RadioRepository? radioRepository;

  /// Set after login — repli YouTube pour la recherche vocale (Android Auto)
  /// quand rien n'est trouvé en local : télécharge puis joue.
  YtDownloadsRepository? ytRepository;

  /// Set after login — playlists pour Android Auto.
  PlaylistRepository? playlistRepository;
  final _playlistSongsCache = <int, List<Song>>{};

  /// Derniers résultats de recherche AA (pour lecture au tap d'un résultat).
  List<Song> _searchCache = const [];
  // Caches des listes jouables (pour TRACK_i cohérent avec l'affichage).
  List<Song> _popularCache = const [];
  List<Song> _recentPlaysCache = const [];

  /// Journal d'événements Android Auto (dernier en tête), consultable dans
  /// l'app (Paramètres → Diagnostic Android Auto). Permet de diagnostiquer
  /// « Aucune sélection » sans brancher d'ordinateur.
  final List<String> aaLog = <String>[];

  void logAA(String msg) {
    final t = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    aaLog.insert(0, '${two(t.hour)}:${two(t.minute)}:${two(t.second)}  $msg');
    if (aaLog.length > 80) aaLog.removeRange(80, aaLog.length);
    if (kDebugMode) debugPrint('[Gullify][AA] $msg');
  }

  /// Journal des événements de lecture (dernier en tête), consultable dans
  /// l'app (Paramètres → Diagnostic de lecture). Sert à comprendre pourquoi
  /// la musique s'arrête parfois écran éteint : on y voit l'enchaînement
  /// pause spontanée / erreur de flux / interruption audio / passage en veille
  /// juste avant l'arrêt, sans avoir à brancher un ordinateur.
  final List<String> playbackLog = <String>[];

  bool? _lastLoggedPlaying;
  ProcessingState? _lastLoggedProcessing;

  void logPlayback(String msg) {
    final t = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    playbackLog.insert(
      0,
      '${two(t.hour)}:${two(t.minute)}:${two(t.second)}  $msg',
    );
    if (playbackLog.length > 120) {
      playbackLog.removeRange(120, playbackLog.length);
    }
    if (kDebugMode) debugPrint('[Gullify][Lecture] $msg');
  }

  static String _fmtPos(Duration d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.inMinutes)}:${two(d.inSeconds % 60)}';
  }

  static String _processingLabel(ProcessingState s) => switch (s) {
        ProcessingState.idle => 'inactif',
        ProcessingState.loading => 'chargement',
        ProcessingState.buffering => 'mise en tampon (réseau ?)',
        ProcessingState.ready => 'prêt',
        ProcessingState.completed => 'piste terminée',
      };

  /// Instantané de l'état courant du lecteur, pour l'en-tête du diagnostic :
  /// le journal ne montre que les *changements*, pas l'état à l'instant t. Sans
  /// ça, impossible de dire « la musique joue-t-elle vraiment maintenant ? »
  /// après un incident. Renvoie une liste (libellé, valeur) prête à afficher.
  List<(String, String)> diagnosticSnapshot() {
    final item = mediaItem.value;
    final dur = item?.duration ?? _player.duration ?? Duration.zero;
    return [
      ('État', _player.playing ? '▶ lecture' : '⏸ en pause'),
      ('Traitement', _processingLabel(_player.processingState)),
      if (item != null)
        (
          'Piste',
          item.artist != null && item.artist!.isNotEmpty
              ? '${item.title} — ${item.artist}'
              : item.title,
        ),
      (
        'Position',
        dur > Duration.zero
            ? '${_fmtPos(_player.position)} / ${_fmtPos(dur)}'
            : _fmtPos(_player.position),
      ),
      ('Tampon', _fmtPos(_player.bufferedPosition)),
    ];
  }

  /// Journalise les interruptions audio (perte de focus : appel, autre appli,
  /// assistant vocal…) et le débranchement de la sortie (« becoming noisy »).
  /// Ce sont des causes fréquentes d'un arrêt en veille — audio_service a déjà
  /// configuré la session, on se contente d'écouter, sans la reconfigurer.
  Future<void> _watchAudioSession() async {
    try {
      final session = await AudioSession.instance;
      session.interruptionEventStream.listen((e) {
        final type = switch (e.type) {
          AudioInterruptionType.duck => 'atténuation',
          AudioInterruptionType.pause => 'pause',
          AudioInterruptionType.unknown => 'inconnue',
        };
        logPlayback(e.begin
            ? 'interruption audio — début ($type)'
            : 'interruption audio — fin ($type)');
      });
      session.becomingNoisyEventStream.listen(
        (_) => logPlayback('sortie audio débranchée (casque/BT)'),
      );
    } catch (e) {
      logPlayback('écoute session audio indisponible : $e');
    }
  }

  /// Appelé par l'observateur du cycle de vie de l'app (main.dart) : trace les
  /// passages en arrière-plan / veille, à corréler avec un éventuel arrêt.
  void logLifecycle(String state) => logPlayback('app : $state');

  // Catégories du browse tree dont un chargement réseau a échoué (hors
  // ligne) : un réessai est en cours en arrière-plan. Évite de lancer
  // plusieurs boucles de réessai pour la même catégorie.
  final _reloading = <String>{};

  // Caches du browse tree : évitent un second aller-réseau entre le
  // listing (getChildren) et la lecture (playFromMediaId).
  final _albumSongsCache = <int, List<Song>>{};
  List<Song>? _favoritesCache;
  List<RadioStation>? _stationsCache;

  /// songId → local file path for downloaded songs (kept in sync by
  /// audioHandlerBinderProvider). Preferred over streaming when present.
  Map<int, String> offlinePaths = const {};

  /// Ids des favoris, tenus à jour par audioHandlerBinderProvider. Sert à
  /// afficher le cœur plein ou vide dans la notification / Android Auto.
  Set<int> favoriteIds = const {};

  /// Branché par le binder sur l'état Riverpod des favoris. Appelé quand
  /// l'utilisateur tape le cœur dans la notification média ou Android Auto.
  Future<void> Function(int songId)? onToggleFavorite;

  /// Rafraîchit la liste des favoris et rediffuse les contrôles média pour
  /// que l'icône cœur reflète immédiatement l'état courant.
  void updateFavorites(Set<int> ids) {
    favoriteIds = ids;
    playbackState.add(
      playbackState.value.copyWith(
        controls: _controls(playbackState.value.playing),
      ),
    );
  }

  int? get _currentSongId => mediaItem.value?.extras?['songId'] as int?;

  bool get _currentIsFavorite {
    final id = _currentSongId;
    return id != null && favoriteIds.contains(id);
  }

  /// Cœur plein (favori) / vide (non favori) à la place du bouton stop, qui
  /// n'apportait rien depuis la notification et Android Auto.
  static final _favoriteControl = MediaControl.custom(
    androidIcon: 'drawable/ic_heart_outline',
    label: 'Ajouter aux favoris',
    name: 'toggleFavorite',
  );
  static final _unfavoriteControl = MediaControl.custom(
    androidIcon: 'drawable/ic_heart_filled',
    label: 'Retirer des favoris',
    name: 'toggleFavorite',
  );

  List<MediaControl> _controls(bool playing) => [
        MediaControl.skipToPrevious,
        if (playing) MediaControl.pause else MediaControl.play,
        MediaControl.skipToNext,
        _currentIsFavorite ? _unfavoriteControl : _favoriteControl,
      ];

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

  /// Côté maison (`serve_image.php`), la source n'est pas redimensionnée : bon
  /// nombre de pochettes sont des vignettes non carrées (miniatures 16:9). Dans
  /// l'app c'est masqué par `BoxFit.cover`, mais Android Auto et la notification
  /// système affichent l'image brute → petit et cadré de bandes. On demande donc
  /// au serveur une version carrée recadrée (`size=`) pour toute l'artwork
  /// exposée au système. Les URLs externes (logos radio, images Deezer) passent
  /// inchangées.
  static const int _sysArtSize = 512;
  Uri? _artUri(String? url) {
    if (url == null || url.isEmpty) return null;
    final uri = Uri.tryParse(url);
    if (uri == null) return null;
    if (!uri.path.endsWith('serve_image.php')) return uri;
    return uri.replace(queryParameters: {
      ...uri.queryParameters,
      'size': '$_sysArtSize',
    });
  }

  MediaItem _toMediaItem(Song s) => MediaItem(
        id: offlinePaths.containsKey(s.id)
            ? Uri.file(offlinePaths[s.id]!).toString()
            : repository!.streamUrl(s),
        title: s.title,
        artist: s.artistName,
        album: s.albumName,
        duration: Duration(seconds: s.duration),
        artUri: _artUri(s.artworkUrl),
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
      artUri: _artUri(logo),
      extras: const {'radio': true},
    );
    queue.add([item]);
    await _player.setAudioSources([AudioSource.uri(Uri.parse(url))]);
    await play();
  }

  /// Pré-écoute d'un titre YouTube trouvé dans la recherche (idée #59). Elle
  /// avait son propre lecteur, à l'écart : rien ne s'ouvrait, rien ne
  /// s'affichait en notification, et l'écran éteint la coupait — hors du
  /// service de premier plan, Android suspend l'app et le son avec. Elle passe
  /// maintenant par le lecteur principal, comme une chanson : mini-lecteur,
  /// écran verrouillé, veille, et un seul son à la fois pour de bon.
  ///
  /// Comme une radio, elle remplace la file : on ne fait pas écouter un titre
  /// qui n'est pas encore dans la bibliothèque au milieu de ceux qui y sont.
  Future<void> playPreview({
    required String videoId,
    required String url,
    required String title,
    String? artist,
    String? artwork,
  }) async {
    _flushPlay();
    _switchingSource = true;
    final item = MediaItem(
      id: url,
      title: title,
      artist: artist,
      album: 'Pré-écoute YouTube',
      // La durée arrive avec le flux (voir durationStream, plus haut).
      artUri: _artUri(artwork),
      extras: {kPreviewVideoId: videoId},
    );
    queue.add([item]);
    // Annoncé tout de suite, avant même le chargement : la rangée de la
    // recherche doit passer en « chargement » au doigt levé, et non à la
    // première note. `currentIndexStream` la réannoncera à l'identique.
    mediaItem.add(item);
    playbackState.add(playbackState.value
        .copyWith(processingState: AudioProcessingState.loading));
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
        artUri: _artUri(art),
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

  // Les pochettes/images s'affichent sur les tuiles de navigation (albums,
  // artistes). Sur les listes de pistes complètes (album, playlist, favoris,
  // populaires, derniers joués), on n'ajoute PAS de pochette par piste : c'est
  // redondant (même album) et lourd à charger sur de longues listes en voiture.
  List<MediaItem> _trackItems(String prefix, List<Song> songs) => [
        for (final (i, s) in songs.indexed)
          MediaItem(
            id: '${prefix}_TRACK_$i',
            title: s.title,
            artist: s.artistName,
            album: s.albumName,
            duration: Duration(seconds: s.duration),
            playable: true,
          ),
      ];

  /// Au lancement par Android Auto (téléphone verrouillé), la restauration
  /// de session prend quelques secondes : on attend le repository plutôt
  /// que de répondre « vide » (AA ne re-demande pas).
  Future<LibraryRepository?> _awaitRepository() async {
    // Attend jusqu'à ~25 s que la session soit restaurée (lancement voiture
    // sans écran : l'auth se restaure de façon asynchrone).
    for (var i = 0; i < 100 && repository == null; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    if (repository == null) logAA('repository TOUJOURS absent après attente');
    return repository;
  }

  @override
  Future<List<MediaItem>> getChildren(
    String parentMediaId, [
    Map<String, dynamic>? options,
  ]) async {
    logAA('getChildren($parentMediaId)');
    // La racine est statique : toujours répondre, même avant l'auth.
    if (parentMediaId == BrowseIds.root) {
      logAA('→ racine statique (onglets)');
      // Miroir de l'app mobile : Accueil, Bibliothèque, Radios, Favoris.
      return const [
        MediaItem(id: BrowseIds.home, title: 'Accueil', playable: false),
        MediaItem(id: BrowseIds.library, title: 'Bibliothèque', playable: false),
        MediaItem(id: BrowseIds.radios, title: 'Radios', playable: false),
        MediaItem(id: BrowseIds.favorites, title: 'Favoris', playable: false),
      ];
    }

    try {
      final repo = await _awaitRepository();
      if (repo == null) {
        logAA('→ [] (pas de repository)');
        _scheduleReload(parentMediaId);
        return [];
      }
      final items = await _getCategory(parentMediaId, repo);
      logAA('→ ${items.length} items');
      return items;
    } catch (e) {
      // Pas de signal (le fetch réseau lève) : on renvoie vide pour l'instant
      // mais on réessaie en arrière-plan, sinon Android Auto reste bloqué sur
      // « Aucun élément » même quand le réseau revient (il ne re-demande pas).
      logAA('ERREUR getChildren: $e');
      _scheduleReload(parentMediaId);
      return [];
    }
  }

  /// Un chargement de catégorie a échoué (hors ligne). On réessaie en
  /// arrière-plan avec un intervalle croissant ; dès qu'un essai aboutit, on
  /// prévient Android Auto que les enfants ont changé pour qu'il rappelle
  /// [getChildren] et remplace « Aucun élément » par la vraie liste (au lieu
  /// de rester figé, faute de nouvelle demande spontanée). Miroir du
  /// comportement de YouTube Music qui se recomplète au retour du signal.
  void _scheduleReload(String parentMediaId) {
    if (parentMediaId == BrowseIds.root) return;
    if (!_reloading.add(parentMediaId)) return; // réessai déjà en cours
    unawaited(() async {
      const delays = [
        Duration(seconds: 3),
        Duration(seconds: 6),
        Duration(seconds: 12),
        Duration(seconds: 20),
        Duration(seconds: 30),
        Duration(seconds: 60),
      ];
      for (final d in delays) {
        await Future<void>.delayed(d);
        final repo = repository;
        if (repo == null) continue; // session pas encore restaurée
        try {
          await _getCategory(parentMediaId, repo);
        } catch (e) {
          logAA('réessai $parentMediaId échoué: $e');
          continue; // toujours hors ligne : essai suivant
        }
        logAA('réessai $parentMediaId réussi → rechargement Android Auto');
        // Demande à Android Auto de recharger cette catégorie.
        // ignore: deprecated_member_use
        await AudioServiceBackground.notifyChildrenChanged(parentMediaId);
        break;
      }
      _reloading.remove(parentMediaId);
    }());
  }

  Future<List<MediaItem>> _getCategory(
    String parentMediaId,
    LibraryRepository repo,
  ) async {
    switch (parentMediaId) {

      // ── Onglet Accueil ──
      case BrowseIds.home:
        return const [
          MediaItem(id: 'ALL_SHUFFLE', title: 'Lecture aléatoire',
              playable: true),
          MediaItem(id: 'DISCOVERY_SHUFFLE', title: 'Découverte',
              playable: true),
          MediaItem(id: BrowseIds.recent, title: 'Nouveautés',
              playable: false),
          MediaItem(id: BrowseIds.popular, title: 'Les plus populaires',
              playable: false),
          MediaItem(id: BrowseIds.recentPlays, title: 'Derniers joués',
              playable: false),
        ];

      // ── Onglet Bibliothèque ──
      case BrowseIds.library:
        return const [
          MediaItem(id: BrowseIds.artists, title: 'Artistes', playable: false),
          MediaItem(id: BrowseIds.albums, title: 'Albums', playable: false),
          MediaItem(id: BrowseIds.favorites, title: 'Favoris', playable: false),
          MediaItem(id: BrowseIds.playlists, title: 'Playlists',
              playable: false),
          MediaItem(id: BrowseIds.genres, title: 'Genres', playable: false),
        ];

      case BrowseIds.popular:
        final songs = await repo.popularSongs(limit: 100);
        _popularCache = songs;
        if (songs.isEmpty) return [];
        return [
          ..._playAllItems('POPULAR', playLabel: 'Tout lire'),
          ..._trackItems('POPULAR', songs),
        ];

      case BrowseIds.recentPlays:
        final songs = await repo.recentSongs(limit: 50);
        _recentPlaysCache = songs;
        if (songs.isEmpty) return [];
        return [
          ..._playAllItems('RECENTPLAYS', playLabel: 'Tout lire'),
          ..._trackItems('RECENTPLAYS', songs),
        ];

      case BrowseIds.genres:
        final genres = await repo.genres();
        return [
          for (final g in genres)
            MediaItem(
              id: BrowseIds.genre(g.name),
              title: '${g.name} (${g.artistCount})',
              playable: false,
            ),
        ];

      case BrowseIds.favorites:
        final songs = await repo.allFavorites();
        _favoritesCache = songs;
        if (songs.isEmpty) return [];
        return [..._playAllItems('FAV'), ..._trackItems('FAV', songs)];

      case BrowseIds.recent:
        final albums = await repo.recentAlbums();
        return [
          ..._playAllItems('RECENT', playLabel: 'Lire les nouveautés'),
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
          // « Tout lire / aléatoire » = toute la bibliothèque.
          ..._playAllItems('ALL', playLabel: 'Tout lire'),
          for (final ar in artists)
            MediaItem(
              id: BrowseIds.artist(ar.id),
              title: ar.name,
              artUri: _artUri(ar.imageUrl),
              playable: false,
            ),
        ];

      case BrowseIds.playlists:
        final lists = await playlistRepository?.playlists() ?? [];
        return [
          for (final p in lists)
            MediaItem(
              id: BrowseIds.playlist(p.id),
              title: p.name,
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
              artUri: _artUri(s.logo),
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

    if (parentMediaId.startsWith('PLAYLIST_')) {
      final id = int.parse(parentMediaId.substring('PLAYLIST_'.length));
      final entries = await playlistRepository?.songs(id) ?? [];
      final songs = [for (final e in entries) e.song];
      _playlistSongsCache[id] = songs;
      if (songs.isEmpty) return [];
      return [
        ..._playAllItems('PLAYLIST_$id', playLabel: 'Lire la playlist'),
        ..._trackItems('PLAYLIST_$id', songs),
      ];
    }

    if (parentMediaId.startsWith('GENRE_')) {
      final name = parentMediaId.substring('GENRE_'.length);
      final artists = await repo.artistsByGenre(name);
      return [
        for (final ar in artists)
          MediaItem(
            id: BrowseIds.artist(ar.id),
            title: ar.name,
            artUri: _artUri(ar.imageUrl),
            playable: false,
          ),
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
      final repo = await _awaitRepository();
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
        artUri: _artUri(s.logo),
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
    logAA('recherche vocale : « $query »');
    final repo = await _awaitRepository();
    if (repo == null || query.trim().isEmpty) {
      logAA('→ recherche annulée (repo=${repo == null ? "absent" : "ok"})');
      return;
    }
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
        // Rien en local → repli YouTube : télécharge puis joue.
        await _youtubeFallback(repo, query);
      }
    } catch (_) {
      playbackState.add(playbackState.value.copyWith(
        processingState: AudioProcessingState.idle,
      ));
    }
  }

  /// Recherche vocale sans résultat local : cherche sur YouTube Music,
  /// télécharge le meilleur titre, attend la fin, puis le joue. Le temps de
  /// téléchargement (quelques dizaines de secondes) est couvert par l'état
  /// « chargement ». Android Auto uniquement, sur choix de l'utilisateur.
  Future<void> _youtubeFallback(LibraryRepository repo, String query) async {
    final yt = ytRepository;
    if (yt == null) {
      playbackState.add(playbackState.value
          .copyWith(processingState: AudioProcessingState.idle));
      return;
    }
    try {
      final songs = await yt.searchSongs(query);
      if (songs.isEmpty) {
        playbackState.add(playbackState.value
            .copyWith(processingState: AudioProcessingState.idle));
        return;
      }
      final pick = songs.first;
      final downloadId = await yt.start(
        url: pick.watchUrl,
        artistName: pick.artist,
        albumName: pick.album.isEmpty ? 'Singles' : pick.album,
      );
      // Attend la fin du téléchargement + scan (max ~120s).
      var done = false;
      for (var i = 0; i < 40 && !done; i++) {
        await Future<void>.delayed(const Duration(seconds: 3));
        final list = await yt.list();
        final d = list.where((e) => e.id == downloadId);
        if (d.isNotEmpty) {
          if (d.first.isError || d.first.isCancelled) break;
          done = d.first.isDone;
        }
      }
      if (!done) {
        playbackState.add(playbackState.value
            .copyWith(processingState: AudioProcessingState.idle));
        return;
      }
      // Le titre est maintenant dans la bibliothèque : on le retrouve et joue.
      final after = await repo.search(pick.title);
      if (after.songs.isNotEmpty) {
        await playSongs(after.songs);
      } else if (after.artists.isNotEmpty) {
        await playSongs(await _artistSongs(repo, after.artists.first.id));
      } else {
        playbackState.add(playbackState.value
            .copyWith(processingState: AudioProcessingState.idle));
      }
    } catch (_) {
      playbackState.add(playbackState.value
          .copyWith(processingState: AudioProcessingState.idle));
    }
  }

  @override
  Future<void> prepareFromSearch(
    String query, [
    Map<String, dynamic>? extras,
  ]) =>
      playFromSearch(query, extras);

  /// Recherche navigable Android Auto : active le bouton recherche (vocal ou
  /// clavier) et renvoie titres (jouables), albums et artistes (navigables).
  @override
  Future<List<MediaItem>> search(
    String query, [
    Map<String, dynamic>? extras,
  ]) async {
    logAA('search AA : « $query »');
    final repo = await _awaitRepository();
    if (repo == null || query.trim().isEmpty) return [];
    try {
      final r = await repo.search(query);
      _searchCache = r.songs;
      final items = <MediaItem>[
        for (final s in r.songs)
          MediaItem(
            id: 'SONG_${s.id}',
            title: s.title,
            artist: s.artistName,
            album: s.albumName,
            duration: Duration(seconds: s.duration),
            artUri: _artUri(s.artworkUrl),
            playable: true,
          ),
        for (final a in r.albums)
          _browsableAlbum(a.id, a.name, a.artistName, a.artworkUrl),
        for (final ar in r.artists)
          MediaItem(
            id: BrowseIds.artist(ar.id),
            title: ar.name,
            artUri: ar.imageUrl != null ? Uri.parse(ar.imageUrl!) : null,
            playable: false,
          ),
      ];
      logAA('→ ${items.length} résultats');
      return items;
    } catch (e) {
      logAA('search AA erreur : $e');
      return [];
    }
  }

  @override
  Future<void> playFromMediaId(
    String mediaId, [
    Map<String, dynamic>? extras,
  ]) async {
    final repo = await _awaitRepository();
    if (repo == null) return;

    // Android Auto attend une réaction immédiate de la session, sinon il
    // affiche « impossible de lire la sélection ». On publie l'état de
    // chargement avant tout aller-réseau.
    playbackState.add(playbackState.value.copyWith(
      processingState: AudioProcessingState.loading,
      playing: false,
    ));

    final m = RegExp(
      r'^(ALBUM_(\d+)|ARTIST_(\d+)|PLAYLIST_(\d+)'
      r'|FAV|RECENT|ALL|DISCOVERY|POPULAR|RECENTPLAYS)'
      r'(?:_(PLAY|SHUFFLE|TRACK_(\d+)))?$',
    ).firstMatch(mediaId);

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

      // Résultat de recherche AA : joue la liste à partir du titre choisi.
      if (mediaId.startsWith('SONG_')) {
        final id = int.parse(mediaId.substring('SONG_'.length));
        final idx = _searchCache.indexWhere((s) => s.id == id);
        if (idx >= 0) {
          await playSongs(_searchCache, startIndex: idx);
        }
        return;
      }

      if (m == null) return;

      final prefix = m.group(1)!;
      final List<Song> songs;
      if (m.group(2) != null) {
        songs = await _albumSongs(repo, int.parse(m.group(2)!));
      } else if (m.group(3) != null) {
        songs = await _artistSongs(repo, int.parse(m.group(3)!));
      } else if (m.group(4) != null) {
        final pid = int.parse(m.group(4)!);
        songs = _playlistSongsCache[pid] ??
            [for (final e in (await playlistRepository?.songs(pid) ?? [])) e.song];
      } else if (prefix == 'RECENT') {
        // Toutes les chansons des ~10 albums les plus récents.
        final albums = await repo.recentAlbums();
        final all = <Song>[];
        for (final a in albums.take(10)) {
          all.addAll(await _albumSongs(repo, a.id));
        }
        songs = all;
      } else if (prefix == 'ALL') {
        songs = await repo.randomSongs();
      } else if (prefix == 'DISCOVERY') {
        songs = await repo.discoverySongs();
      } else if (prefix == 'POPULAR') {
        songs = _popularCache.isNotEmpty
            ? _popularCache
            : await repo.popularSongs(limit: 100);
      } else if (prefix == 'RECENTPLAYS') {
        songs = _recentPlaysCache.isNotEmpty
            ? _recentPlaysCache
            : await repo.recentSongs(limit: 50);
      } else {
        songs = await _favorites(repo);
      }
      if (songs.isEmpty) return;

      final action = m.group(5) ?? 'PLAY';
      if (action == 'SHUFFLE') {
        await playSongs(songs.toList()..shuffle());
      } else if (action.startsWith('TRACK_')) {
        final index = int.parse(m.group(6)!);
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

  @override
  Future<dynamic> customAction(String name,
      [Map<String, dynamic>? extras]) async {
    if (name == 'toggleFavorite') {
      final id = _currentSongId;
      if (id == null) return;
      final cb = onToggleFavorite;
      if (cb != null) {
        // Passe par l'état Riverpod : bascule serveur + mise à jour optimiste,
        // que le binder répercute dans favoriteIds (donc sur l'icône).
        try {
          await cb(id);
        } catch (_) {}
      } else if (repository != null) {
        // Repli si l'app n'est pas liée (rare) : bascule directe via le dépôt.
        try {
          final nowFav = await repository!.toggleFavorite(id);
          updateFavorites({
            ...favoriteIds.where((e) => e != id),
            if (nowFav) id,
          });
        } catch (_) {}
      }
      return;
    }
    return super.customAction(name, extras);
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
        controls: _controls(playing),
        systemActions: const {
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
          // Annonce la recherche (bouton loupe / vocal Android Auto).
          MediaAction.playFromSearch,
          MediaAction.playFromMediaId,
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
