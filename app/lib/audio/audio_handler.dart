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
  static const downloads = 'DOWNLOADS';
  /// Item « Réessayer » proposé quand une catégorie n'a pas pu se charger.
  static String retry(String parentId) => 'RETRY_$parentId';
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
      _prefetchKaraoke(index);
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

  /// Les titres téléchargés, dans l'ordre d'affichage (tenus à jour par
  /// audioHandlerBinderProvider). Sans réseau, c'est tout ce qu'Android Auto
  /// peut encore proposer.
  List<Song> offlineSongs = const [];

  /// Branché par le binder : rejoue la restauration de session. Sans réseau au
  /// démarrage, la session ne se restaure pas — il faut la reprendre quand le
  /// réseau revient, sinon la bibliothèque reste muette même une fois en ligne.
  Future<void> Function()? onRetrySession;

  /// Les téléchargements réellement jouables (fichier connu). Sert à la fois à
  /// l'affichage et à la lecture : les index `DOWNLOADS_TRACK_i` doivent
  /// désigner la même liste des deux côtés.
  List<Song> get downloads =>
      [for (final s in offlineSongs) if (offlinePaths.containsKey(s.id)) s];

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

  /// Mode karaoké (idée #63) : le serveur sert la version voix atténuée des
  /// titres. Le rendu vit sur le serveur — un titre téléchargé passe donc lui
  /// aussi par le réseau tant que le mode est actif.
  bool _karaoke = false;
  bool get karaoke => _karaoke;

  /// Fichier local si le titre est téléchargé, flux du serveur sinon. Sans
  /// session (voiture sans réseau), seuls les téléchargements ont une source :
  /// les autres n'ont rien à jouer plutôt que de faire planter la file.
  ///
  /// Un titre téléchargé garde son fichier même en mode karaoké : une file
  /// bâtie dans la voiture (Android Auto, sans réseau) ne doit jamais se
  /// retrouver à pointer vers le serveur parce que le mode est resté actif.
  /// Le basculement explicite, lui, emmène toute la file en karaoké — voir
  /// setKaraoke().
  String _sourceUri(Song s) {
    final local = offlinePaths[s.id];
    if (local != null) return Uri.file(local).toString();
    if (_karaoke) {
      final karaokeUrl = repository?.streamUrlForPath(s.filePath, karaoke: true);
      if (karaokeUrl != null) return karaokeUrl;
    }
    return repository?.streamUrl(s) ?? '';
  }

  /// La source d'une fiche de la file, avec ou sans karaoké. Une radio ou une
  /// pré-écoute YouTube n'a pas de chemin de fichier : elle ne bouge pas.
  /// Ici le karaoké l'emporte même sur un titre téléchargé — c'est un geste
  /// explicite, fait depuis l'app, réseau en main ; le retour au normal, lui,
  /// rend au titre son fichier local.
  MediaItem _reroute(MediaItem item, {required bool karaoke}) {
    final path = item.extras?['filePath'] as String?;
    final repo = repository;
    if (path == null || repo == null) return item;
    final songId = item.extras?['songId'] as int?;
    final local = songId == null ? null : offlinePaths[songId];
    final url = karaoke
        ? repo.streamUrlForPath(path, karaoke: true)
        : (local != null
            ? Uri.file(local).toString()
            : repo.streamUrlForPath(path));
    return url == item.id ? item : item.copyWith(id: url);
  }

  /// Bascule la file en cours vers la version karaoké (ou en revient) sans
  /// perdre sa place : même file, même piste, même seconde, même lecture en
  /// cours. Les titres dont le rendu n'est pas prêt côté serveur repartent
  /// simplement dans leur version d'origine (stream.php le décide).
  Future<void> setKaraoke(bool on) async {
    if (_karaoke == on) return;
    _karaoke = on;
    // Sortir du mode oublie ce qui a été demandé : y revenir plus tard doit
    // pouvoir relancer un rendu qui aurait échoué entre-temps.
    if (!on) _karaokeAsked.clear();

    final items = queue.value;
    if (items.isEmpty) return;
    final swapped = [for (final item in items) _reroute(item, karaoke: on)];
    final changed = [
      for (var i = 0; i < items.length; i++)
        if (swapped[i].id != items[i].id) i,
    ];
    if (changed.isEmpty) return;

    final index = (_player.currentIndex ?? 0).clamp(0, swapped.length - 1);
    final position = _player.position;
    final wasPlaying = _player.playing;

    // La piste ne change pas : on garde le suivi d'écoute en cours plutôt que
    // de déclarer une lecture partielle et d'en démarrer une autre (le
    // listener de currentIndexStream se tait quand file et index sont déjà
    // ceux qu'il connaît).
    _queueIndex = index;
    _trackedQueue = swapped;

    _switchingSource = true;
    queue.add(swapped);
    mediaItem.add(swapped[index]);
    await _player.setAudioSources(
      [for (final item in swapped) AudioSource.uri(Uri.parse(item.id))],
      initialIndex: index,
      initialPosition: position,
    );
    if (wasPlaying) await play();
    _prefetchKaraoke(index + 1);
  }

  /// Titres dont le rendu karaoké a déjà été demandé au serveur.
  final _karaokeAsked = <String>{};

  /// En mode karaoké, prépare d'avance les titres qui arrivent : le rendu
  /// prend quelques secondes et ExoPlayer précharge la piste suivante bien
  /// avant qu'on l'entende. Sans cette avance, le titre suivant serait servi
  /// dans sa version d'origine.
  void _prefetchKaraoke(int fromIndex) {
    final repo = repository;
    if (!_karaoke || repo == null) return;
    final q = queue.value;
    for (var i = fromIndex; i <= fromIndex + 1 && i < q.length; i++) {
      if (i < 0) continue;
      final path = q[i].extras?['filePath'] as String?;
      if (path == null || !_karaokeAsked.add(path)) continue;
      unawaited(repo.prepareKaraoke(path).then((_) {}, onError: (_) {}));
    }
  }

  MediaItem _toMediaItem(Song s) => MediaItem(
        id: _sourceUri(s),
        title: s.title,
        artist: s.artistName,
        album: s.albumName,
        duration: Duration(seconds: s.duration),
        artUri: _artUri(s.artworkUrl),
        // albumId/artistId : le lecteur y renvoie d'un toucher sur l'album ou
        // l'artiste (idée #64). Absents des compilations sans album connu.
        extras: {
          'songId': s.id,
          'filePath': s.filePath,
          if (s.albumId != null) 'albumId': s.albumId,
          if (s.artistId != null) 'artistId': s.artistId,
        },
      );

  /// Vrai pendant le remplacement de la file : just_audio repasse alors par
  /// `idle`, qu'il ne faut pas relayer (Android Auto lit STATE_NONE comme
  /// « rien ne joue » et abandonne la sélection en cours).
  bool _switchingSource = false;

  Future<void> playSongs(List<Song> songs, {int startIndex = 0}) async {
    // Hors session (voiture sans réseau), un titre non téléchargé n'a aucune
    // source : mieux vaut l'écarter que de bâtir une file qui échoue dès la
    // première piste. En temps normal rien n'est écarté.
    final playable = [for (final s in songs) if (_sourceUri(s).isNotEmpty) s];
    if (playable.isEmpty) return;
    if (playable.length != songs.length) {
      final target =
          startIndex >= 0 && startIndex < songs.length ? songs[startIndex] : null;
      final moved = target == null ? -1 : playable.indexOf(target);
      startIndex = moved < 0 ? 0 : moved;
      songs = playable;
    }
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

  /// Ferme le lecteur : coupe le son, vide la file et efface la piste en
  /// cours. C'est ce qui fait disparaître le mini-lecteur (et la notification
  /// média avec lui) quand on le balaie vers le bas — `stop()` seul laissait
  /// la fiche en place, donc le mini-lecteur aussi.
  ///
  /// Renvoie de quoi revenir en arrière : la file et l'endroit où elle en
  /// était, à repasser à [restoreQueue].
  Future<({List<MediaItem> queue, int index, Duration position})>
      dismiss() async {
    final closed = (
      queue: queue.value,
      index: _player.currentIndex ?? 0,
      position: _player.position,
    );
    _flushPlay();
    _switchingSource = false;
    await _player.stop();
    _queueIndex = null;
    _trackedQueue = null;
    queue.add(const []);
    mediaItem.add(null);
    await super.stop();
    return closed;
  }

  /// Rouvre une file fermée par [dismiss] — l'annulation du balayage, à la
  /// piste et à la seconde près.
  Future<void> restoreQueue(
    List<MediaItem> items, {
    int index = 0,
    Duration position = Duration.zero,
  }) async {
    if (items.isEmpty) return;
    final at = index.clamp(0, items.length - 1);
    _flushPlay();
    _switchingSource = true;
    queue.add(items);
    mediaItem.add(items[at]);
    await _player.setAudioSources(
      [for (final item in items) AudioSource.uri(Uri.parse(item.id))],
      initialIndex: at,
      // Une radio n'a pas de position à reprendre : elle est en direct.
      initialPosition: items[at].isLive == true ? Duration.zero : position,
    );
    await play();
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
  Future<LibraryRepository?> _awaitRepository({Duration? timeout}) async {
    // Attend jusqu'à ~25 s que la session soit restaurée (lancement voiture
    // sans écran : l'auth se restaure de façon asynchrone). Quand on a de quoi
    // répondre sans elle (des téléchargements), on abrège : mieux vaut une
    // liste jouable tout de suite qu'un écran vide au bout d'une demi-minute.
    const step = Duration(milliseconds: 250);
    final steps = (timeout ?? const Duration(seconds: 25)).inMilliseconds ~/
        step.inMilliseconds;
    for (var i = 0; i < steps && repository == null; i++) {
      await Future<void>.delayed(step);
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
    // Les écrans qui ne demandent rien au serveur (racine, onglets, titres
    // téléchargés) répondent tout de suite, même sans session : c'est ce qui
    // reste navigable dans la voiture quand il n'y a pas de réseau.
    final offline = _offlineCategory(parentMediaId);
    if (offline != null) {
      logAA('→ ${offline.length} items (sans réseau)');
      return offline;
    }

    // « Réessayer » : l'utilisateur redemande la catégorie tout de suite. On
    // rejoue la session puis le chargement ; si ça marche, on renvoie
    // directement le contenu (et on prévient Android Auto pour l'écran
    // précédent), sinon on repropose le repli hors ligne.
    if (parentMediaId.startsWith('RETRY_')) {
      final parent = parentMediaId.substring('RETRY_'.length);
      final items = await _retryNow(parent);
      return items ?? _offlineFallback(parent);
    }

    try {
      final repo = await _awaitRepository(
        timeout: downloads.isEmpty ? null : const Duration(seconds: 6),
      );
      if (repo == null) {
        logAA('→ repli hors ligne (pas de repository)');
        _scheduleReload(parentMediaId);
        return _offlineFallback(parentMediaId);
      }
      final items = await _getCategory(parentMediaId, repo);
      logAA('→ ${items.length} items');
      return items;
    } catch (e) {
      // Pas de signal (le fetch réseau lève) : on ne renvoie plus vide — un
      // écran vide, Android Auto le garde tel quel (il ne re-demande pas), et
      // c'est le « Aucune sélection » qui ne s'en va jamais. On sert les
      // téléchargements, jouables sans réseau, plus un « Réessayer », et on
      // relance en arrière-plan jusqu'au retour du signal.
      logAA('ERREUR getChildren: $e');
      _scheduleReload(parentMediaId);
      return _offlineFallback(parentMediaId);
    }
  }

  /// Les catégories servies sans le moindre aller-réseau. `null` pour les
  /// autres, qui ont besoin du dépôt.
  List<MediaItem>? _offlineCategory(String parentMediaId) {
    switch (parentMediaId) {
      // Miroir de l'app mobile : Accueil, Bibliothèque, Radios, Favoris.
      case BrowseIds.root:
        return const [
          MediaItem(id: BrowseIds.home, title: 'Accueil', playable: false),
          MediaItem(id: BrowseIds.library, title: 'Bibliothèque',
              playable: false),
          MediaItem(id: BrowseIds.radios, title: 'Radios', playable: false),
          MediaItem(id: BrowseIds.favorites, title: 'Favoris', playable: false),
        ];
      case BrowseIds.home:
      case BrowseIds.library:
      case BrowseIds.downloads:
        return _staticCategory(parentMediaId);
    }
    return null;
  }

  /// Ce qu'on affiche quand une catégorie n'a pas pu se charger : de quoi
  /// réessayer à la main, et les titres téléchargés — comme YouTube Music, qui
  /// ne montre plus que le local hors ligne et se recomplète tout seul ensuite.
  List<MediaItem> _offlineFallback(String parentMediaId) {
    final local = downloads;
    return [
      MediaItem(
        id: BrowseIds.retry(parentMediaId),
        title: 'Réessayer',
        artist: 'Hors réseau — nouvelle tentative automatique en cours',
        playable: false,
      ),
      if (local.isNotEmpty) ...[
        ..._playAllItems('DOWNLOADS', playLabel: 'Lire les téléchargements'),
        ..._trackItems('DOWNLOADS', local),
      ],
    ];
  }

  /// Réessai immédiat d'une catégorie : session puis chargement. Renvoie les
  /// items en cas de réussite, `null` si c'est encore hors ligne.
  Future<List<MediaItem>?> _retryNow(String parentMediaId) async {
    logAA('réessai demandé : $parentMediaId');
    try {
      await onRetrySession?.call();
    } catch (e) {
      logAA('réessai session échoué : $e');
    }
    final repo = repository;
    if (repo == null) {
      _scheduleReload(parentMediaId);
      return null;
    }
    try {
      final items = await _getCategory(parentMediaId, repo);
      logAA('réessai $parentMediaId réussi → ${items.length} items');
      _notifyChildrenChanged(parentMediaId);
      return items;
    } catch (e) {
      logAA('réessai $parentMediaId échoué : $e');
      _scheduleReload(parentMediaId);
      return null;
    }
  }

  /// Demande à Android Auto de recharger une catégorie : sans ça, il garde
  /// l'écran qu'il a — y compris vide.
  void _notifyChildrenChanged(String parentMediaId) {
    // ignore: deprecated_member_use
    unawaited(AudioServiceBackground.notifyChildrenChanged(parentMediaId)
        .catchError((Object e) => logAA('notifyChildrenChanged: $e')));
  }

  /// Un chargement de catégorie a échoué (hors ligne). On réessaie en
  /// arrière-plan avec un intervalle croissant ; dès qu'un essai aboutit, on
  /// prévient Android Auto que les enfants ont changé pour qu'il rappelle
  /// [getChildren] et remplace « Aucun élément » par la vraie liste (au lieu
  /// de rester figé, faute de nouvelle demande spontanée). Miroir du
  /// comportement de YouTube Music qui se recomplète au retour du signal.
  void _scheduleReload(String parentMediaId) {
    if (parentMediaId == BrowseIds.root) return;
    if (parentMediaId.startsWith('RETRY_')) return;
    if (!_reloading.add(parentMediaId)) return; // réessai déjà en cours
    unawaited(() async {
      // On n'abandonne plus au bout de six essais : un trajet sans réseau dure
      // plus longtemps que deux minutes, et la catégorie doit se remplir toute
      // seule à la première barre de signal retrouvée. L'attente plafonne à une
      // minute, et la boucle s'arrête à la réussite (ou au bout de ~2 h).
      for (var i = 0; i < _maxReloadAttempts; i++) {
        await Future<void>.delayed(reloadDelays[
            i < reloadDelays.length ? i : reloadDelays.length - 1]);
        var repo = repository;
        if (repo == null) {
          // Session jamais restaurée (démarrage sans réseau) : sans ça, la
          // boucle tournerait pour rien jusqu'au bout.
          try {
            await onRetrySession?.call();
          } catch (_) {}
          repo = repository;
          if (repo == null) continue;
        }
        try {
          await _getCategory(parentMediaId, repo);
        } catch (e) {
          logAA('réessai $parentMediaId échoué: $e');
          continue; // toujours hors ligne : essai suivant
        }
        logAA('réessai $parentMediaId réussi → rechargement Android Auto');
        // Demande à Android Auto de recharger cette catégorie.
        _notifyChildrenChanged(parentMediaId);
        // La session peut être restée « hors ligne » alors que le réseau est
        // revenu : on la reprend pour que l'app retrouve son utilisateur.
        try {
          await onRetrySession?.call();
        } catch (_) {}
        break;
      }
      _reloading.remove(parentMediaId);
    }());
  }

  /// Attentes successives entre deux réessais (la dernière se répète).
  /// Modifiable par les tests, qui n'ont pas une minute à perdre.
  @visibleForTesting
  List<Duration> reloadDelays = const [
    Duration(seconds: 3),
    Duration(seconds: 6),
    Duration(seconds: 12),
    Duration(seconds: 20),
    Duration(seconds: 30),
    Duration(seconds: 60),
  ];

  static const _maxReloadAttempts = 120;

  /// Les listes qui ne dépendent que de l'app : les deux onglets de navigation
  /// et les titres téléchargés.
  List<MediaItem>? _staticCategory(String parentMediaId) {
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
        return [
          const MediaItem(id: BrowseIds.artists, title: 'Artistes',
              playable: false),
          const MediaItem(id: BrowseIds.albums, title: 'Albums',
              playable: false),
          const MediaItem(id: BrowseIds.favorites, title: 'Favoris',
              playable: false),
          const MediaItem(id: BrowseIds.playlists, title: 'Playlists',
              playable: false),
          const MediaItem(id: BrowseIds.genres, title: 'Genres',
              playable: false),
          // Seule entrée qui ne demande rien au réseau : elle n'a de sens que
          // s'il y a des titres téléchargés sur le téléphone.
          if (downloads.isNotEmpty)
            const MediaItem(id: BrowseIds.downloads, title: 'Téléchargements',
                playable: false),
        ];

      // Jouable sans réseau ni session : aucune requête ici.
      case BrowseIds.downloads:
        final local = downloads;
        if (local.isEmpty) return const [];
        return [
          ..._playAllItems('DOWNLOADS', playLabel: 'Tout lire'),
          ..._trackItems('DOWNLOADS', local),
        ];
    }
    return null;
  }

  Future<List<MediaItem>> _getCategory(
    String parentMediaId,
    LibraryRepository repo,
  ) async {
    final fixed = _staticCategory(parentMediaId);
    if (fixed != null) return fixed;

    switch (parentMediaId) {
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
        // Dépôt non lié = session pas (encore) restaurée : c'est un échec, pas
        // une bibliothèque vide. Sans ça, Android Auto afficherait un écran
        // vide définitif au lieu du repli hors ligne.
        final playlists = playlistRepository;
        if (playlists == null) throw StateError('playlists non liées');
        final lists = await playlists.playlists();
        return [
          for (final p in lists)
            MediaItem(
              id: BrowseIds.playlist(p.id),
              title: p.name,
              playable: false,
            ),
        ];

      case BrowseIds.radios:
        final radios = radioRepository;
        if (radios == null) throw StateError('radios non liées');
        final stations = await radios.stations();
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
      final playlists = playlistRepository;
      if (playlists == null) throw StateError('playlists non liées');
      final entries = await playlists.songs(id);
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

  /// Recherche dans les seuls titres téléchargés. Renvoie leur index dans
  /// [downloads] pour que le résultat reste jouable sans réseau.
  List<(int, Song)> _searchDownloads(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return const [];
    bool hit(String? s) => s != null && s.toLowerCase().contains(q);
    return [
      for (final (i, s) in downloads.indexed)
        if (hit(s.title) || hit(s.artistName) || hit(s.albumName)) (i, s),
    ];
  }

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
    // Un téléchargement se décrit sans rien demander au serveur.
    final local = RegExp(r'^DOWNLOADS_TRACK_(\d+)$').firstMatch(mediaId);
    if (local != null) {
      final songs = downloads;
      final index = int.parse(local.group(1)!);
      if (index < 0 || index >= songs.length) return null;
      return _toMediaItem(songs[index]).copyWith(id: mediaId);
    }
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
    if (query.trim().isEmpty) return;
    final repo = await _awaitRepository(
      timeout: downloads.isEmpty ? null : const Duration(seconds: 6),
    );
    if (repo == null) {
      logAA('→ pas de session : repli sur les téléchargements');
      await _playSearchedDownloads(query);
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
    } catch (e) {
      // Serveur injoignable : on tente au moins les titres téléchargés.
      logAA('recherche vocale échouée ($e) → téléchargements');
      await _playSearchedDownloads(query);
    }
  }

  /// Recherche vocale hors ligne : joue les téléchargements qui correspondent,
  /// et retombe proprement en « inactif » s'il n'y en a aucun (sans quoi
  /// Android Auto resterait en chargement).
  Future<void> _playSearchedDownloads(String query) async {
    final found = _searchDownloads(query);
    if (found.isEmpty) {
      playbackState.add(playbackState.value.copyWith(
        processingState: AudioProcessingState.idle,
      ));
      return;
    }
    logAA('→ ${found.length} titres téléchargés joués');
    await playSongs([for (final (_, s) in found) s]);
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
    if (query.trim().isEmpty) return [];
    final repo = await _awaitRepository(
      timeout: downloads.isEmpty ? null : const Duration(seconds: 6),
    );
    if (repo == null) return _downloadResults(query);
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
      // Hors ligne : plutôt qu'une page de résultats vide, ce qu'on a sous la
      // main — les téléchargements, jouables sans réseau.
      logAA('search AA erreur : $e');
      return _downloadResults(query);
    }
  }

  /// Résultats de recherche pris dans les téléchargements.
  List<MediaItem> _downloadResults(String query) {
    final found = _searchDownloads(query);
    logAA('→ ${found.length} résultats locaux (hors ligne)');
    return [
      for (final (i, s) in found)
        MediaItem(
          id: 'DOWNLOADS_TRACK_$i',
          title: s.title,
          artist: s.artistName,
          album: s.albumName,
          duration: Duration(seconds: s.duration),
          playable: true,
        ),
    ];
  }

  @override
  Future<void> playFromMediaId(
    String mediaId, [
    Map<String, dynamic>? extras,
  ]) async {
    // Les téléchargements se jouent sans réseau ni session : on les sert avant
    // d'attendre quoi que ce soit, sinon la seule chose encore écoutable hors
    // ligne resterait bloquée derrière l'attente du dépôt.
    if (mediaId.startsWith('DOWNLOADS')) {
      await _playDownloads(mediaId);
      return;
    }

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

  /// « Tout lire », « Lecture aléatoire » ou un titre précis parmi les
  /// téléchargements — la liste jouable quoi qu'il arrive.
  Future<void> _playDownloads(String mediaId) async {
    final songs = downloads;
    if (songs.isEmpty) {
      logAA('téléchargements : aucun titre local');
      return;
    }
    final action = mediaId.substring(BrowseIds.downloads.length);
    if (action == '_SHUFFLE') {
      await playSongs(songs.toList()..shuffle());
      return;
    }
    final m = RegExp(r'^_TRACK_(\d+)$').firstMatch(action);
    final index = m == null
        ? 0
        : int.parse(m.group(1)!).clamp(0, songs.length - 1);
    await playSongs(songs, startIndex: index);
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
