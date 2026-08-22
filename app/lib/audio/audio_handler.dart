import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import '../api/library_repository.dart';
import '../api/playlist_repository.dart';
import '../api/radio_repository.dart';
import '../api/yt_downloads_repository.dart';
import '../models/game_source.dart';
import '../models/song.dart';
import 'equalizer.dart';
import 'fade.dart';
import 'prefetch.dart';
import 'resume_store.dart';
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

/// L'ordre aléatoire tel qu'il est, repris d'un lecteur par l'autre au moment
/// du fondu enchaîné (idée #76). just_audio retire les titres au sort dès qu'on
/// lui pose une file : le lecteur qui prend l'antenne se retrouverait avec un
/// ordre tout neuf, et rejouerait des titres déjà entendus. Ici le premier tirage
/// est déjà fait — les suivants (bouton aléatoire) retombent sur le tirage
/// normal.
class _KeptShuffleOrder extends DefaultShuffleOrder {
  _KeptShuffleOrder(this._kept);

  final List<int> _kept;
  bool _restored = false;

  @override
  void insert(int index, int count) {
    if (!_restored && index == 0 && indices.isEmpty && count == _kept.length) {
      _restored = true;
      indices.addAll(_kept);
      return;
    }
    super.insert(index, count);
  }
}

/// Marque, dans les extras d'une fiche du lecteur principal, la pré-écoute
/// d'un titre YouTube (idée #59) : c'est à ça que la recherche reconnaît « son »
/// titre dans ce que joue le lecteur principal.
const kPreviewVideoId = 'previewVideoId';

/// Media IDs used for the Android Auto / media browser tree.
class BrowseIds {
  static const root = AudioService.browsableRootId;

  /// La racine « reprise » (minuscules, imposée par Android) : Android Auto la
  /// demande à part, et attend un seul élément jouable — le titre qu'on
  /// écoutait en dernier (idée #103).
  static const resumeRoot = AudioService.recentRootId;

  /// Cet élément-là. Le toucher reprend la file où on l'avait laissée.
  static const resume = 'RESUME';

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
    // Un titre qui vient de descendre dans le tampon d'avance (idée #90) est
    // aussitôt repris dans la file : c'est le fichier qui jouera, pas le flux.
    buffer.onCached = (_) => unawaited(_adoptBuffered());
    // Le réglage de normalisation (idée #108) change le volume du titre en
    // cours : on le suit pour que la bascule s'entende tout de suite, plutôt
    // que d'attendre le titre suivant.
    fade.addListener(() => _applyNormalization());
    _listen();
    _watchAudioSession();
  }

  /// Branche l'app sur le lecteur en cours. Tout ce qui suit l'écoute (fiche
  /// courante, notification, suivi d'écoute, égaliseur, journal) vient d'ici.
  ///
  /// Rejoué à chaque fondu enchaîné : le titre entrant joue sur l'autre lecteur
  /// (idée #76), et c'est LUI qui devient le lecteur courant dès que le
  /// croisement commence. Les abonnements du sortant sont coupés d'abord — sans
  /// quoi sa fin de piste et son propre enchaînement continueraient de piloter
  /// la fiche affichée.
  void _listen() {
    for (final sub in _subs) {
      unawaited(sub.cancel());
    }
    _subs.clear();
    _subs.add(_player.playbackEventStream.listen(
      _broadcastState,
      // Une erreur du lecteur (flux coupé en veille, source injoignable…) est
      // la cause typique d'un arrêt écran éteint : on la journalise.
      onError: (Object e, StackTrace _) =>
          logPlayback('ERREUR lecteur : $e'),
    ));
    // Changement d'état « joue / ne joue pas ». Capte AUSSI les pauses
    // spontanées (perte de focus audio, coupure système) qui ne passent pas
    // par notre pause() — exactement le symptôme à diagnostiquer en veille.
    _subs.add(_player.playerStateStream.listen((s) {
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
      // On s'arrête ici : c'est de là qu'Android Auto devra reprendre.
      if (!s.playing) _rememberPosition();
    }));
    // Transitions du cycle de lecture (mise en tampon = stall réseau, etc.).
    _subs.add(_player.processingStateStream.listen((s) {
      if (s != _lastLoggedProcessing) {
        _lastLoggedProcessing = s;
        logPlayback('état : ${_processingLabel(s)}');
      }
    }));
    // La session audio n'existe qu'une fois la lecture lancée (ExoPlayer la
    // génère en tâche de fond) : c'est le seul moment où l'égaliseur peut
    // s'accrocher. Une nouvelle session = un nouvel effet à recréer — dont
    // celle du lecteur qui prend l'antenne à chaque fondu enchaîné.
    if (equalizerSupported) {
      _subs.add(_player.androidAudioSessionIdStream.listen((id) {
        if (id == null) return;
        logPlayback('égaliseur : session audio $id');
        equalizer.attachSession(id);
      }));
    }
    _subs.add(_player.currentIndexStream.listen((index) {
      final q = queue.value;
      if (index == null || index < 0 || index >= q.length) return;
      // setAudioSources can emit the same index more than once.
      if (index == _queueIndex && identical(q, _trackedQueue)) return;
      _queueIndex = index;
      _trackedQueue = q;
      _fadeInNewTrack();
      _flushPlay();
      _startTracking(q[index]);
      // Ce qu'Android Auto proposera de reprendre, c'est le titre qui commence
      // (idée #103).
      unawaited(resume.rememberCurrent(q[index].extras?['songId'] as int?));
      _prefetchKaraoke(index);
      // Les bords du titre qui commence et de celui qui suit : demandés
      // maintenant, ils seront là bien avant le croisement (idée #79).
      _fetchEdges();
      // Le tampon prend l'avance suivante, et ce qui est déjà descendu passe
      // sur son fichier (idée #90).
      _primeBuffer();
      unawaited(_adoptBuffered());
      mediaItem.add(q[index]);
      // Rafraîchit le cœur (favori) pour la nouvelle piste courante.
      playbackState.add(
        playbackState.value.copyWith(
          controls: _controls(playbackState.value.playing),
        ),
      );
    }));
    _subs.add(_player.positionStream.listen((pos) {
      if (_trackedSongId != null) _lastPosition = pos;
      _watchTrackFade(pos);
    }));
    // La durée d'un flux qu'on ne connaît pas d'avance (la pré-écoute d'un titre
    // YouTube : le serveur la découvre en le transcodant) n'arrive qu'une fois
    // le titre chargé. On complète alors sa fiche, sans quoi le scrubber du
    // lecteur et la barre de la recherche n'auraient jamais de fin. Une radio
    // n'en a pas non plus, mais elle est en direct : le lecteur ne rend rien.
    _subs.add(_player.durationStream.listen((duration) {
      final item = mediaItem.value;
      if (duration == null || item == null || item.duration != null) return;
      mediaItem.add(item.copyWith(duration: duration));
    }));
    _subs.add(_player.processingStateStream.listen((s) {
      if (s == ProcessingState.completed) {
        _lastPosition = _trackedDuration;
        stop();
      }
    }));
  }

  /// Ce qui écoute le lecteur courant, et rien d'autre. Vidé et rebranché à
  /// chaque changement de lecteur (fondu enchaîné).
  final _subs = <StreamSubscription<dynamic>>[];

  /// Égaliseur système (Android). Volontairement HORS de l'AudioPipeline de
  /// just_audio : celui-ci lisait les bandes avant qu'ExoPlayer n'ait de
  /// session audio, et l'exception empoisonnait le lecteur — plus aucune
  /// lecture possible (idée #47). Voir equalizer.dart.
  final equalizer = GullifyEqualizer();

  /// Réglage du fondu à la lecture, à la pause et entre les titres (idée #75).
  /// Réglable dans Paramètres → Lecture → Fondu ; voir fade.dart.
  final fade = PlaybackFade();

  /// Le tampon d'avance (idée #90) : les prochains titres de la file
  /// descendent sur le disque pendant qu'on écoute celui d'avant, et se jouent
  /// de là. Réglable dans Paramètres → Lecture → Tampon d'avance ; voir
  /// prefetch.dart.
  final buffer = PlaybackBuffer();

  /// Ce qu'on écoutait en dernier, gardé sur le disque pour la racine de
  /// reprise d'Android Auto (idée #103) ; voir resume_store.dart.
  final resume = ResumeStore();

  // Réglage des tampons et verrou réseau : voir tuned_player.dart, d'où sortent
  // tous les lecteurs de l'app.
  //
  // Pas `final` : le fondu enchaîné (idée #76) fait jouer le titre entrant sur
  // un second lecteur, et celui-ci devient le lecteur courant dès que le
  // croisement commence. Le sortant finit sa descente en coulisses puis se
  // range comme lecteur de réserve, prêt pour le croisement suivant.
  AudioPlayer _player = createGullifyPlayer(use: PlayerUse.streaming);

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
  void logLifecycle(String state) {
    logPlayback('app : $state');
    // L'app peut ne jamais revenir (système qui la tue en veille) : on note où
    // on en est pendant qu'on peut encore écrire, pour la reprise Android Auto.
    _rememberPosition();
  }

  /// Note où en est la piste courante pour la reprise Android Auto (idée #103).
  void _rememberPosition() => unawaited(
        resume.rememberPosition(_player.position, songId: _currentSongId),
      );

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
    // Un titre croisé avec le suivant (idée #76) est déclaré fini alors qu'il
    // lui reste la durée du fondu à jouer : sans cette marge, un fondu enchaîné
    // long ferait passer chaque écoute complète pour une écoute abandonnée.
    // Le croisement intelligent (idée #79) peut partir plus tôt encore —
    // fade.crossfadeReach dit de combien, au pire.
    final tolerance = const Duration(seconds: 5) + fade.crossfadeReach;
    final completed = _trackedDuration > Duration.zero &&
        played >= _trackedDuration - tolerance;
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
    // Le tampon d'avance (idée #90) : le titre est déjà descendu, on ne
    // redemande pas au réseau ce qui est sur le disque.
    final ahead = buffer.pathFor(s.id);
    if (ahead != null) return Uri.file(ahead).toString();
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
    // Le fichier du titre : celui du téléchargement, sinon celui du tampon
    // d'avance (idée #90) s'il est descendu et toujours là.
    final local = songId == null
        ? null
        : offlinePaths[songId] ?? buffer.pathFor(songId);
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

    await _cancelFade();
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
    // Le tampon d'avance ne descend rien en karaoké, et reprend la main en
    // sortant du mode (idée #90).
    _primeBuffer();
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

  // ── Le tampon d'avance (idée #90) ──────────────────────────────────────────
  //
  // La file dit ce qui va être joué : les prochains titres descendent sur le
  // disque pendant qu'on écoute celui d'avant, puis remplacent leur flux dans
  // la file du lecteur. Une mauvaise connexion ne coupe plus une musique dont
  // le fichier est déjà là. Le réglage (combien d'avance, quelle place) vit
  // dans prefetch.dart.

  /// L'ordre dans lequel le lecteur va vraiment enchaîner la file (tirage
  /// aléatoire compris). Le tirage est celui de just_audio : lui seul sait
  /// dans quel ordre il joue.
  List<int> _playOrder() {
    final length = queue.value.length;
    final order = _player.effectiveIndices;
    if (order.length == length) return order;
    return [for (var i = 0; i < length; i++) i];
  }

  static String _fileExt(String path) {
    final dot = path.lastIndexOf('.');
    final ext = dot >= 0 ? path.substring(dot + 1) : '';
    return ext.isEmpty || ext.length > 5 ? 'mp3' : ext;
  }

  /// Dit au tampon ce qui arrive. Appelé à chaque changement de piste et à
  /// chaque remaniement de la file.
  ///
  /// Rien à descendre sans session, sans file, sur une radio ou une pré-écoute
  /// (pas de titre derrière), ni en mode karaoké : ce que le serveur rend là
  /// n'est pas le fichier du titre. Les titres déjà téléchargés (offline.dart)
  /// sont sur le disque depuis longtemps, on ne les descend pas deux fois.
  void _primeBuffer() {
    if (!bufferSupported) return;
    final repo = repository;
    final q = queue.value;
    final current = _player.currentIndex;
    if (repo == null || _karaoke || q.isEmpty || current == null) {
      buffer.prime(const []);
      return;
    }
    // Les titres de la file en cours ne s'effacent pas du tampon, même quand
    // on ne descend plus rien : le lecteur pointe peut-être déjà dessus.
    final keep = <int>{
      for (final item in q)
        if (item.extras?['songId'] is int) item.extras!['songId'] as int,
    };
    // En lecture aléatoire, aucun titre ne sait basculer sur son fichier (voir
    // _adoptBuffered) : on ne descend rien plutôt que de télécharger pour
    // rien. Ce qui est déjà dans le tampon sert quand même — une file bâtie
    // par-dessus part directement des fichiers (voir _sourceUri).
    if (_player.shuffleModeEnabled) {
      buffer.prime(const [], keep: keep);
      return;
    }
    final wanted = <BufferRequest>[];
    for (final i in bufferTargets(
      order: _playOrder(),
      current: current,
      ahead: buffer.ahead,
      loop: _player.loopMode == LoopMode.all,
      // Seuls les titres qui suivent la piste en cours dans la file savent
      // basculer sur leur fichier (voir _adoptBuffered) : descendre les autres
      // ne ferait que doubler la consommation de données.
      usable: (i) => i > current,
    )) {
      if (i < 0 || i >= q.length) continue;
      final songId = q[i].extras?['songId'] as int?;
      final path = q[i].extras?['filePath'] as String?;
      if (songId == null || path == null) continue;
      if (offlinePaths.containsKey(songId)) continue;
      wanted.add(BufferRequest(
        songId: songId,
        url: repo.streamUrlForPath(path),
        ext: _fileExt(path),
      ));
    }
    buffer.prime(wanted, keep: keep);
  }

  /// Vrai pendant une bascule vers le tampon : deux passages en même temps
  /// travailleraient sur la même file avec des index périmés.
  bool _adopting = false;

  /// Fait jouer depuis le tampon les titres de la file qui y sont descendus.
  ///
  /// Seulement ceux qui viennent APRÈS la piste en cours : remplacer la source
  /// d'un titre placé avant ferait glisser l'index du lecteur le temps de
  /// l'échange, et l'app y lirait un changement de piste qui n'a pas eu lieu
  /// (fiche, notification et suivi d'écoute avec). Le titre en cours, lui, ne
  /// se remplace jamais sous ses pieds — il joue.
  ///
  /// Rien non plus en lecture aléatoire : changer la source d'un titre revient
  /// à le retirer de la file puis à l'y remettre, et just_audio le replace
  /// alors au hasard dans son tirage (DefaultShuffleOrder.insert). Un titre
  /// pourrait ainsi atterrir derrière la piste en cours et ne jamais passer.
  /// Le tampon ne descend donc rien tant que l'aléatoire est actif.
  ///
  /// Rien pendant un croisement (idée #76) : le lecteur d'à côté tient déjà sa
  /// copie de la file. La bascule attendra le prochain changement de piste.
  Future<void> _adoptBuffered() async {
    if (_adopting || !bufferSupported || _karaoke) return;
    if (_switchingSource || _crossfading || _outgoingBusy) return;
    if (_player.shuffleModeEnabled) return;
    final current = _player.currentIndex;
    if (current == null) return;
    final before = queue.value;
    final q = [...before];
    var changed = false;
    _adopting = true;
    try {
      for (var i = current + 1; i < q.length; i++) {
        final songId = q[i].extras?['songId'] as int?;
        if (songId == null || offlinePaths.containsKey(songId)) continue;
        final path = buffer.pathFor(songId);
        if (path == null) continue;
        final url = Uri.file(path).toString();
        if (q[i].id == url) continue;
        // La file a changé sous nous (nouvelle écoute lancée pendant qu'on
        // basculait) : on s'arrête, celle qu'on tient n'existe plus.
        if (!identical(queue.value, before)) break;
        await _player.removeAudioSourceAt(i);
        await _player.insertAudioSource(i, AudioSource.uri(Uri.parse(url)));
        q[i] = q[i].copyWith(id: url);
        changed = true;
      }
    } catch (e) {
      // Ce qui a déjà basculé est publié quand même, plus bas : la file
      // affichée doit dire ce que le lecteur joue vraiment.
      logPlayback('tampon d\'avance : bascule impossible ($e)');
    } finally {
      _adopting = false;
    }
    if (!changed || !identical(queue.value, before)) return;
    // Même file, mêmes titres, même piste en cours : seule la source a changé.
    // Le suivi d'écoute doit suivre la nouvelle liste, sans quoi le prochain
    // battement d'index la prendrait pour une autre file et déclarerait un
    // changement de piste.
    if (identical(_trackedQueue, before)) _trackedQueue = q;
    queue.add(q);
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

  /// Lance une file. [startPosition] ne sert qu'à la reprise Android Auto
  /// (idée #103) : on retombe sur la piste là où on l'avait laissée.
  Future<void> playSongs(
    List<Song> songs, {
    int startIndex = 0,
    Duration? startPosition,
  }) async {
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
    // Une nouvelle file efface tout ce qui jouait, y compris le titre sortant
    // d'un fondu enchaîné en cours.
    await _cancelFade();
    _switchingSource = true;
    final items = songs.map(_toMediaItem).toList();
    queue.add(items);
    // Ce qu'on écoute maintenant est ce qu'Android Auto proposera de reprendre.
    unawaited(resume.remember(songs, index: startIndex));
    await _player.setAudioSources(
      [for (final item in items) AudioSource.uri(Uri.parse(item.id))],
      initialIndex: startIndex,
      initialPosition: startPosition,
    );
    _primeBuffer();
    await play();
  }

  Future<void> playRadio({
    required String url,
    required String title,
    String? logo,
  }) async {
    _flushPlay();
    await _cancelFade();
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
    await _cancelFade();
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

  // ── Le réveil matinal (idée #81) ───────────────────────────────────────────

  /// La sonnerie embarquée dans l'app. Un réveil doit sonner même sans réseau
  /// ni serveur : c'est le seul son de Gullify qui ne vienne pas de la
  /// bibliothèque.
  static const alarmToneAsset = 'asset:///assets/audio/buzz.wav';

  /// Assez de tours pour un quart d'heure de sonnerie. Passé ce délai, un
  /// téléphone oublié cesse de sonner tout seul.
  static const _alarmToneLoops = 350;

  /// Fait sonner la sonnerie, en boucle, par le lecteur principal — service de
  /// premier plan, notification et écran verrouillé compris (idée #57).
  Future<void> playAlarmTone() async {
    _flushPlay();
    await _cancelFade();
    _switchingSource = true;
    final item = MediaItem(
      id: alarmToneAsset,
      title: 'Réveil',
      artist: 'Gullify',
      extras: const {'alarm': true},
    );
    queue.add([item]);
    mediaItem.add(item);
    await _player.setAudioSources([
      // just_audio propose de remplacer LoopingAudioSource par une liste de
      // N fois la même source : ici ce serait 350 entrées de file pour une
      // seule fiche affichée, et la file du lecteur ne collerait plus à celle
      // de l'app (le titre courant se lit par index).
      // ignore: deprecated_member_use
      LoopingAudioSource(
        count: _alarmToneLoops,
        child: AudioSource.uri(Uri.parse(alarmToneAsset)),
      ),
    ]);
    await play();
  }

  /// La montée du réveil : le son entre à volume nul et met [over] à atteindre
  /// le volume plein. À lancer juste après avoir posé la file — c'est un fondu
  /// comme un autre, donc la moindre action (pause, saut, arrêt) le remplace et
  /// rend le volume, plutôt que de laisser la musique en sourdine.
  ///
  /// Ne pas attendre le résultat : la montée dure des minutes.
  Future<void> startWakeFade(Duration over) async {
    if (over <= Duration.zero) return;
    _endFading = false;
    // Plein volume, et non le volume normalisé du titre (idée #108) : un
    // réveil a pour métier de réveiller, pas de se tenir au niveau de la
    // bibliothèque. La musique qui suivra, elle, reprendra le sien.
    _trackVolume = 1;
    // Le jeton d'abord : sans ça, le fondu d'entrée lancé par play() aurait le
    // temps de remonter le volume juste après qu'on l'a mis à zéro.
    final token = ++_fadeToken;
    await _player.setVolume(0);
    if (token != _fadeToken) return;
    // Un pas toutes les deux secondes : sur une montée de plusieurs minutes,
    // les pas de 40 ms du fondu ordinaire feraient des milliers d'appels pour
    // une différence que personne n'entend.
    await _fadeTo(1, over: over, tick: const Duration(seconds: 2));
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
    _primeBuffer();
  }

  /// Ajoute en fin de file.
  Future<void> addToQueue(Song song) async {
    final item = _toMediaItem(song);
    queue.add([...queue.value, item]);
    await _player.addAudioSource(AudioSource.uri(Uri.parse(item.id)));
    _primeBuffer();
  }

  Future<void> moveQueueItem(int from, int to) async {
    final q = [...queue.value];
    if (from < 0 || from >= q.length || to < 0 || to >= q.length) return;
    q.insert(to, q.removeAt(from));
    queue.add(q);
    await _player.moveAudioSource(from, to);
    _primeBuffer();
  }

  @override
  Future<void> removeQueueItemAt(int index) async {
    final q = [...queue.value];
    if (index < 0 || index >= q.length) return;
    q.removeAt(index);
    queue.add(q);
    await _player.removeAudioSourceAt(index);
    _primeBuffer();
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
    _primeBuffer();
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
    await _cancelFade();
    await _player.stop();
    _queueIndex = null;
    _trackedQueue = null;
    queue.add(const []);
    // Plus de file, plus rien à prendre d'avance : le tampon rend le réseau.
    _primeBuffer();
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
    await _cancelFade();
    _switchingSource = true;
    queue.add(items);
    mediaItem.add(items[at]);
    await _player.setAudioSources(
      [for (final item in items) AudioSource.uri(Uri.parse(item.id))],
      initialIndex: at,
      // Une radio n'a pas de position à reprendre : elle est en direct.
      initialPosition: items[at].isLive == true ? Duration.zero : position,
    );
    _primeBuffer();
    await play();
  }

  /// Fondu de fin de piste en cours : le volume est descendu (ou en train de
  /// descendre) parce que le titre se termine, pas parce qu'on met en pause.
  bool _endFading = false;

  /// Marque du fondu en cours. Chaque nouveau fondu la fait avancer, ce qui
  /// abandonne le précédent : deux rampes de volume qui se marchent dessus
  /// laisseraient le lecteur à un volume au hasard.
  int _fadeToken = 0;

  /// Le volume que tient le titre en cours, du début à la fin : celui qui
  /// l'amène au niveau de référence commun à toute la bibliothèque
  /// (idée #108). C'est le « plein volume » de tout ce qui remonte le son —
  /// reprise, retour de fondu de fin, annulation — sans quoi la moindre pause
  /// rendrait au titre les décibels qu'on venait de lui retirer.
  ///
  /// Il se pose à la première note du titre et ne bouge plus : jamais au-dessus
  /// de 1 (un lecteur poussé au-delà sature), jamais sous
  /// [kNormalizeVolumeFloor] (au-delà, on n'égalise plus, on éteint).
  double _trackVolume = 1;

  /// Le volume qu'un titre doit tenir, de sa première à sa dernière note
  /// (idée #108) : celui qui l'amène sur [kNormalizeTargetDb].
  ///
  /// Réglage éteint, le titre joue tel qu'il est gravé. Titre jamais mesuré —
  /// hors ligne, serveur muet —, il garde le volume de celui d'avant : le
  /// poser à plein le ferait passer au-dessus de toute une file normalisée,
  /// c'est-à-dire produirait exactement le saut qu'on corrige.
  double _volumeForSong(int? songId) {
    if (!fade.normalizes) return 1;
    final level = songId == null ? null : _edges[songId]?.level;
    return trackVolumeFor(level) ?? _trackVolume;
  }

  /// Rend au titre en cours le volume que sa gravure lui vaut. Sert deux fois :
  /// quand le réglage bascule (la bascule s'entend tout de suite), et quand la
  /// mesure d'un titre arrive après sa première note — ce qui n'arrive qu'au
  /// tout premier titre d'une session, les suivants étant mesurés d'avance.
  ///
  /// [onlyEarly] limite alors le rattrapage à l'entrée en matière du morceau
  /// ([kNormalizeGrace]) : passé ce délai, mieux vaut un titre au mauvais
  /// volume qu'une marche de volume sous une musique installée (idée #104).
  void _applyNormalization({bool onlyEarly = false}) {
    // Un croisement, une descente de fin : ces passages-là posent eux-mêmes
    // les volumes, on ne leur passe pas devant.
    if (_crossfading || _outgoingBusy || _endFading) return;
    if (onlyEarly && _player.position > kNormalizeGrace) return;
    final volume = _volumeForSong(_currentSongId);
    if ((volume - _trackVolume).abs() < 0.001) return;
    _trackVolume = volume;
    // À l'arrêt, il n'y a rien à corriger : c'est [play] qui posera le volume.
    if (_player.playing) unawaited(_fadeTo(volume));
  }

  /// Fondu de volume du lecteur courant : reprise, pause et changement de titre
  /// en douceur plutôt qu'à sec. Durée réglée par l'utilisateur (idée #75),
  /// sauf [over] imposé — la fin d'une piste se fond sur ce qu'il en reste,
  /// jamais plus. [curve] donne la forme de la rampe : [FadeCurve.crossing]
  /// pour la montée d'un fondu enchaîné, qui se croise avec la descente du
  /// titre sortant.
  ///
  /// Renvoie sa marque : un appelant qui enchaîne (la pause, après son fondu)
  /// la compare à [_fadeToken] pour savoir si quelqu'un lui a pris la main
  /// entre-temps.
  Future<int> _fadeTo(
    double target, {
    Duration? over,
    FadeCurve curve = FadeCurve.linear,
    Duration tick = kFadeTick,
  }) async {
    final token = ++_fadeToken;
    final player = _player;
    final ramp = fadeRamp(
      from: player.volume,
      to: target,
      over: over ?? fade.duration,
      curve: curve,
      tick: tick,
    );
    final instant = ramp.length <= 1;
    for (final volume in ramp) {
      if (!instant) await Future<void>.delayed(tick);
      // Le lecteur a pu changer sous nos pieds (fondu enchaîné) : la rampe
      // d'avant ne doit surtout pas continuer de pousser le volume de celui
      // qui vient de prendre l'antenne.
      if (token != _fadeToken || !identical(player, _player)) return token;
      await player.setVolume(volume);
    }
    return token;
  }

  /// Coupe court au fondu en cours et rend au titre le volume qui est le sien
  /// — un lecteur laissé à mi-fondu jouerait le titre suivant en sourdine.
  /// Coupe aussi le titre sortant d'un fondu enchaîné : dès qu'on reprend la
  /// main (saut, pause, arrêt), il n'a plus rien à faire dans les oreilles.
  Future<void> _cancelFade() async {
    _fadeToken++;
    _endFading = false;
    await _hushOutgoing();
    if (_player.volume != _trackVolume) {
      await _player.setVolume(_trackVolume);
    }
  }

  /// Fin de piste : descend le volume sur ce qu'il reste du titre, et le
  /// remonte dès qu'on n'est plus dans cette dernière ligne droite (titre
  /// suivant, titre rejoué en boucle, retour en arrière). Piloté par la
  /// position plutôt que par une minuterie : c'est la seule façon de se
  /// rattraper tout seul après un saut ou une reprise.
  void _watchTrackFade(Duration position) {
    final total = _player.duration;
    final live = mediaItem.value?.isLive == true;

    // Le titre suivant, s'il y en a un : c'est lui qui décide entre un vrai
    // croisement (deux titres à la fois) et la simple descente de fin de file.
    // Une descente déjà entamée garde la main jusqu'au bout : c'est le repli
    // quand le croisement n'a pas pu se faire, et le relancer à chaque
    // battement de position ne ferait que le rater de nouveau.
    final crossable = fade.fadesTracks && _hasNextTrack && !_endFading;
    if (crossable) {
      // La forme du croisement, taillée sur ce que le serveur a mesuré aux
      // bords des deux titres quand il a su le dire (idée #79).
      final plan = _crossfadePlan(total);
      switch (crossfadeAt(
        position: position,
        total: total,
        span: plan.trigger,
        playing: _player.playing,
        live: live,
        hasNext: _hasNextTrack,
        armed: _armedIndex != null,
        running: _crossfading,
      )) {
        case Crossfade.none:
          break;
        case Crossfade.arm:
          unawaited(_armCrossfade());
        case Crossfade.start:
          unawaited(_startCrossfade(plan, total! - position));
        case Crossfade.disarm:
          unawaited(_disarmCrossfade());
      }
    } else if (_armedIndex != null) {
      // Plus rien à croiser (réglage éteint, dernier titre de la file, descente
      // déjà en cours) : le tampon préparé ne sert plus.
      unawaited(_disarmCrossfade());
    }

    switch (trackFadeAt(
      position: position,
      total: total,
      // Un titre qui a un suivant se croise avec lui (le sortant descend sur
      // son propre lecteur, hors du fondu du lecteur courant) : ici on ne
      // s'occupe plus que du dernier titre de la file, qui n'a personne avec
      // qui se croiser et s'éteint donc tout seul.
      fade: fade.fadesTracks && !crossable ? fade.duration : Duration.zero,
      playing: _player.playing,
      live: live,
      fadingOut: _endFading,
    )) {
      case TrackFade.none:
        break;
      case TrackFade.out:
        _endFading = true;
        // Sur ce qu'il reste du titre, pas plus : le fondu doit finir avec
        // lui, pas déborder sur le suivant.
        unawaited(_fadeTo(0, over: total! - position));
      case TrackFade.back:
        _endFading = false;
        unawaited(_fadeTo(_trackVolume));
    }
  }

  /// Nouvelle piste : elle entre en fondu au lieu de démarrer à plein volume,
  /// que la précédente se soit éteinte d'elle-même ou qu'on ait appuyé sur
  /// « suivant ». Sans lecture en cours, il n'y a rien à fondre — c'est
  /// [play] qui s'en chargera.
  void _fadeInNewTrack() {
    // Pendant un fondu enchaîné — ou juste après, pour le titre qu'il vient de
    // mettre à l'antenne : le battement d'index qui l'annonce peut tomber une
    // fois le croisement rendu —, la montée est déjà faite, et à son niveau à
    // lui. La relancer d'ici la ferait repartir de zéro en plein milieu, et
    // reposer le volume effacerait celui qu'on vient tout juste de calculer
    // pour lui (idée #104).
    final crossfaded = _crossfadedIndex == _queueIndex;
    _crossfadedIndex = null;
    if (_crossfading || crossfaded) return;
    // Le titre qui prend l'antenne autrement qu'en croisant (saut, enchaînement
    // sec, nouvelle file) joue au volume que sa gravure lui vaut, et non à
    // celui du titre d'avant (idée #108).
    _trackVolume = _volumeForSong(_currentSongId);
    // À l'arrêt, [play] posera le volume ; en lecture, il faut le poser ici —
    // sans quoi le titre hériterait de celui du précédent.
    if (!_player.playing) return;
    if (!fade.fadesTracks) {
      // Fondu enchaîné éteint : le volume se pose d'un coup, pour que le titre
      // soit au bon niveau dès sa première note. Au ras d'un changement de
      // piste, une marche de volume ne s'entend pas — ce qui s'entendrait,
      // c'est une demi-seconde de morceau jouée au volume du précédent.
      unawaited(_fadeTo(_trackVolume, over: Duration.zero));
      return;
    }
    _endFading = false;
    unawaited(() async {
      final token = ++_fadeToken;
      await _player.setVolume(0);
      if (token != _fadeToken) return;
      await _fadeTo(_trackVolume);
    }());
  }

  // ────────────────────────────────────────────── le fondu enchaîné (#76) ──

  /// Le lecteur d'à côté : celui qui prépare le titre suivant, puis celui qui
  /// finit de descendre pendant que le suivant monte. Créé au tout premier
  /// croisement — fondu enchaîné éteint, l'app n'allume qu'un seul lecteur,
  /// exactement comme avant.
  AudioPlayer? _spare;

  /// Index du titre chargé d'avance sur [_spare], et la file dans laquelle il
  /// a été choisi (une file remplacée entre-temps le périme).
  int? _armedIndex;
  List<MediaItem>? _armedQueue;

  /// Croisement en cours : les deux titres jouent en même temps.
  bool _crossfading = false;

  /// L'index que le dernier croisement a mis à l'antenne, tant que le battement
  /// d'index qui l'annonce n'est pas passé. Voir [_fadeInNewTrack].
  int? _crossfadedIndex;

  /// Le lecteur d'à côté fait encore du son (il finit sa descente) : on ne lui
  /// charge surtout pas le titre d'après, ça couperait le sortant net.
  bool _outgoingBusy = false;

  /// Marque du titre sortant. L'incrémenter abandonne sa descente : c'est ce
  /// qui le fait taire net quand on saute, met en pause ou arrête.
  int _outgoingToken = 0;

  /// Y a-t-il un titre après celui en cours ? (aléatoire et répétition
  /// compris : c'est just_audio qui sait dans quel ordre il joue.)
  bool get _hasNextTrack {
    final next = _player.nextIndex;
    return next != null && next >= 0 && next < queue.value.length;
  }

  // ─────────────────────────── le croisement intelligent (#79) ──
  //
  // Le serveur mesure les bords des titres (silence de fin, descente
  // naturelle, entrée en matière). L'app les demande dès qu'une piste
  // commence — bien avant d'en avoir besoin — et taille son croisement
  // dessus. Sans réseau, sans serveur ou sur un titre inanalysable, tout
  // retombe sur le croisement à durée fixe de l'idée #76.

  /// Bords mesurés, par id de titre. Une entrée nulle veut dire « demandé,
  /// le serveur n'a rien à en dire » : on ne le redemande pas à chaque piste.
  final _edges = <int, TrackEdges?>{};

  /// Titres dont la mesure est en route (pas deux appels pour le même).
  final _edgesAsked = <int>{};

  int? _songIdAt(int? index) {
    final q = queue.value;
    if (index == null || index < 0 || index >= q.length) return null;
    return q[index].extras?['songId'] as int?;
  }

  /// Demande au serveur les bords du titre en cours et du suivant. Appelé au
  /// changement de piste : la mesure a alors tout le morceau pour arriver.
  void _fetchEdges() {
    final repo = repository;
    if (repo == null || !fade.needsMeasures) return;
    final wanted = <int>[];
    for (final id in [_currentSongId, _songIdAt(_player.nextIndex)]) {
      if (id == null || _edges.containsKey(id)) continue;
      if (_edgesAsked.add(id)) wanted.add(id);
    }
    if (wanted.isEmpty) return;
    unawaited(repo.songTransitions(wanted).then(
      (found) {
        // Un titre absent de la réponse est un titre que le serveur ne sait
        // pas analyser : on le note pour ne plus le redemander.
        for (final id in wanted) {
          _edges[id] = found[id];
        }
        _edgesAsked.removeAll(wanted);
        // La mesure du titre en cours peut arriver après sa première note :
        // on lui pose alors son volume, tant qu'on est encore dans son entrée
        // en matière (idée #108).
        _applyNormalization(onlyEarly: true);
      },
      onError: (Object e) {
        // Hors ligne, ou serveur muet : on réessaiera à la piste suivante.
        _edgesAsked.removeAll(wanted);
      },
    ));
  }

  /// La forme du croisement pour la piste en cours. Le calcul est synchrone —
  /// il tombe à chaque battement de position — et se contente de ce que la
  /// mesure a déjà rapporté.
  CrossfadePlan _crossfadePlan(Duration? total) {
    if (!fade.measuresTracks) {
      return crossfadePlan(fade: fade.duration, total: total);
    }
    final currentId = _currentSongId;
    final nextId = _songIdAt(_player.nextIndex);
    return crossfadePlan(
      fade: fade.duration,
      total: total,
      current: currentId == null ? null : _edges[currentId],
      next: nextId == null ? null : _edges[nextId],
    );
  }

  /// Charge le titre suivant sur le lecteur d'à côté, sans le lancer. Le
  /// tampon a le temps de se remplir : au moment du croisement, il démarre à
  /// la note près au lieu d'arriver en retard.
  Future<void> _armCrossfade() async {
    if (_outgoingBusy) return;
    // Filet de sécurité : si la mesure des bords n'a pas abouti au début du
    // titre (réseau coupé), il reste l'avance de la préparation pour la
    // rattraper avant le croisement.
    _fetchEdges();
    final q = queue.value;
    final next = _player.nextIndex;
    if (next == null || next < 0 || next >= q.length) return;
    if (_armedIndex == next && identical(_armedQueue, q)) return;
    final spare = _spare ??= createGullifyPlayer(use: PlayerUse.streaming);
    _armedIndex = next;
    _armedQueue = q;
    try {
      await spare.setVolume(0);
      await spare.setLoopMode(_player.loopMode);
      await spare.setShuffleModeEnabled(_player.shuffleModeEnabled);
      await spare.setSpeed(_player.speed);
      await spare.setAudioSources(
        [for (final item in q) AudioSource.uri(Uri.parse(item.id))],
        initialIndex: next,
        // Le lecteur qui prend l'antenne hérite de l'ordre aléatoire en cours :
        // sans ça, chaque croisement retirerait les titres au sort et on
        // réentendrait ceux déjà joués.
        shuffleOrder: _KeptShuffleOrder(_player.shuffleIndices),
      );
    } catch (e) {
      logPlayback('fondu enchaîné : préparation impossible ($e)');
      _armedIndex = null;
      _armedQueue = null;
    }
  }

  /// Rend le tampon du titre préparé : il ne sera pas joué.
  Future<void> _disarmCrossfade() async {
    if (_armedIndex == null) return;
    _armedIndex = null;
    _armedQueue = null;
    try {
      await _spare?.stop();
    } catch (_) {}
  }

  /// Croise les deux titres : le suivant monte sur le lecteur d'à côté pendant
  /// que celui en cours descend sur le sien. C'est le lecteur entrant qui
  /// devient tout de suite le lecteur courant — fiche, notification, position
  /// et suivi d'écoute suivent ce qui commence, pas ce qui s'efface.
  ///
  /// [plan] donne la forme du croisement (idée #79) et [remaining] ce qu'il
  /// reste vraiment du titre sortant : les rampes ne débordent jamais dessus.
  Future<void> _startCrossfade(CrossfadePlan plan, Duration remaining) async {
    if (_crossfading) return;
    _crossfading = true;
    final over = plan.rise < remaining ? plan.rise : remaining;
    try {
      final q = queue.value;
      final next = _player.nextIndex;
      if (next == null || next < 0 || next >= q.length) return;
      if (_armedIndex != next || !identical(_armedQueue, q)) {
        // Préparation périmée (file changée) ou jamais faite : on charge
        // maintenant. Le titre entrant partira avec un peu de retard, le
        // croisement sera plus court, mais il aura lieu.
        await _armCrossfade();
      }
      final incoming = _spare;
      if (incoming == null || _armedIndex != next) {
        // Rien à croiser : on retombe sur la descente de fin de piste, qui
        // vaut toujours mieux qu'une coupure nette.
        _endFading = true;
        unawaited(_fadeTo(0, over: over));
        return;
      }

      final outgoing = _player;
      // Le volume du titre entrant se lit AVANT l'échange des lecteurs : après,
      // c'est lui le titre courant et l'index de la file a déjà tourné.
      final incomingVolume = _volumeForSong(_songIdAt(next));
      final token = ++_outgoingToken;
      _outgoingBusy = true;
      await incoming.setVolume(0);
      // play() de just_audio ne se résout qu'à l'arrêt du son : ne pas
      // l'attendre, sinon le croisement ne commence jamais.
      unawaited(incoming.play().catchError((Object e) {
        logPlayback('fondu enchaîné : lecture impossible ($e)');
      }));

      // Le titre entrant prend l'antenne : c'est lui qu'on annonce, et c'est
      // sa position que le lecteur affiche.
      _armedIndex = null;
      _armedQueue = null;
      _crossfadedIndex = next;
      _spare = outgoing;
      _player = incoming;
      _endFading = false;
      _listen();

      // Les deux rampes se croisent en se complétant (loi kCrossfadeLaw) :
      // deux droites qui se croisent creuseraient un trou au milieu du passage.
      //
      // Elles se croisent sur la part du croisement où les deux titres
      // s'entendent vraiment : quand le titre entrant a démarré en avance
      // (intro qui met du temps à venir, idée #79), les DEUX attendent
      // d'autant. Le sortant garde son plein volume pendant cette avance — ce
      // n'est pas parce que le suivant s'installe qu'il faut effacer celui qui
      // joue — et l'entrant y reste muet : le faire monter par-dessus
      // additionnerait deux musiques et rendrait le passage plus fort que les
      // titres qu'il relie (idée #91).
      final fall = over < plan.fall ? over : plan.fall;
      final hold = over - fall;
      unawaited(_fadeOutgoing(outgoing, fall, token, after: hold));
      // Le volume où la montée s'arrête est celui que le titre entrant tiendra
      // jusqu'à sa dernière note : rien ne le rattrape après le passage
      // (idée #104).
      await _fadeIncoming(fall, after: hold, volume: incomingVolume);
    } catch (e) {
      logPlayback('fondu enchaîné : abandon ($e)');
    } finally {
      _crossfading = false;
    }
  }

  /// Montée du titre entrant, en miroir exact de la descente du sortant :
  /// même attente, même durée, courbes complémentaires. À chaque instant, les
  /// deux volumes réunis pèsent un seul titre.
  ///
  /// [after] est l'avance donnée au titre entrant pour son entrée en matière
  /// (idée #79) : il la traverse muet, pendant que le sortant tient son
  /// volume. Monter dès la première note d'intro, alors que le titre d'avant
  /// joue encore à fond, faisait enfler le passage sans raison (idée #91).
  ///
  /// [volume] est le volume propre du titre entrant — celui que sa gravure lui
  /// vaut (idée #108, voir [_volumeForSong]). Il devient [_trackVolume] et
  /// plus rien ne le fera bouger jusqu'au prochain titre : le sortant, lui,
  /// descend depuis le sien. Deux titres déjà normalisés se croisent donc à
  /// niveau égal, sans que le passage ait à corriger quoi que ce soit — et
  /// sans que rien ne vienne recouvrir celui qui s'achève.
  ///
  /// Renvoie la marque du fondu, pour que l'appelant sache si la main lui est
  /// restée jusqu'au bout.
  Future<int> _fadeIncoming(
    Duration over, {
    Duration after = Duration.zero,
    double volume = 1,
  }) async {
    if (after > Duration.zero) {
      // Le jeton est pris AVANT l'attente : tout ce qui reprend la main
      // entre-temps (pause, saut, arrêt) le fait avancer, et cette montée
      // renonce plutôt que de repousser le volume dans le dos de l'autre.
      final token = ++_fadeToken;
      await Future<void>.delayed(after);
      if (token != _fadeToken) return token;
    }
    _trackVolume = volume;
    return _fadeTo(_trackVolume, over: over, curve: FadeCurve.crossing);
  }

  /// Descente du titre sortant, sur son propre lecteur, puis extinction. La
  /// descente finit avec le titre : au-delà, le lecteur sortant partirait tout
  /// seul sur la piste suivante de sa file — celle-là même qui joue déjà.
  ///
  /// [after] retarde la descente : le sortant tient son volume pendant que le
  /// titre entrant traverse son intro (idée #79).
  Future<void> _fadeOutgoing(
    AudioPlayer outgoing,
    Duration over,
    int token, {
    Duration after = Duration.zero,
  }) async {
    if (after > Duration.zero) {
      await Future<void>.delayed(after);
      if (token != _outgoingToken) return;
    }
    final ramp = fadeRamp(
      from: outgoing.volume,
      to: 0,
      over: over,
      curve: FadeCurve.crossing,
    );
    for (final volume in ramp) {
      await Future<void>.delayed(kFadeTick);
      if (token != _outgoingToken) return;
      try {
        await outgoing.setVolume(volume);
      } catch (_) {
        break;
      }
    }
    await _hushOutgoing(token);
  }

  /// Fait taire le titre sortant pour de bon et range son lecteur : il devient
  /// le lecteur de réserve du croisement suivant, rangé muet. Ses deux seuls
  /// réemplois — préparation et croisement — lui posent son volume avant de le
  /// faire jouer. Sans [token], c'est une reprise en main (saut, pause,
  /// arrêt) : le sortant se tait tout de suite.
  Future<void> _hushOutgoing([int? token]) async {
    if (token != null && token != _outgoingToken) return;
    if (token == null) _outgoingToken++;
    _outgoingBusy = false;
    final outgoing = _spare;
    if (outgoing == null) return;
    // Le lecteur d'à côté tenait peut-être le titre suivant tout prêt : il
    // s'arrête aussi, et se rechargera de lui-même à l'approche de la fin.
    _armedIndex = null;
    _armedQueue = null;
    try {
      // Muet AVANT l'arrêt, jamais après : quand on reprend la main en plein
      // croisement (saut, pause, arrêt), le sortant joue encore, et rendre le
      // volume à un lecteur qu'on n'a pas fini d'arrêter lui laisserait le
      // temps d'un éclat à plein volume — une augmentation de la chanson qui
      // termine, très exactement (idée #108).
      await outgoing.setVolume(0);
      await outgoing.stop();
    } catch (_) {}
  }

  @override
  Future<void> play() async {
    _endFading = false;
    final over = fade.duration;
    await _player.setVolume(over > Duration.zero ? 0 : _trackVolume);
    // play() de just_audio ne se résout qu'à la pause/fin — ne pas attendre.
    unawaited(_player.play());
    // Le fondu d'entrée ne se fait pas attendre non plus : il peut durer
    // plusieurs secondes, et tout ce qui lance une file (playSongs, Android
    // Auto) attend cette méthode. Il remonte au volume du titre, pas au plein
    // volume : une reprise ne rend pas les décibels qu'un croisement a retirés
    // (idée #104).
    unawaited(_fadeTo(_trackVolume, over: over));
  }

  @override
  Future<void> pause() async {
    // Pause en plein croisement : le titre sortant se tait tout de suite, le
    // titre courant descend comme d'habitude. Deux titres qui continueraient
    // de jouer pendant qu'on demande le silence, c'est le contraire d'une pause.
    unawaited(_hushOutgoing());
    final token = await _fadeTo(0);
    // Reprise de la lecture pendant le fondu de sortie : la pause n'a plus
    // lieu d'être, quelqu'un a repris la main sur le volume.
    if (token != _fadeToken) return;
    await _player.pause();
    _endFading = false;
    await _player.setVolume(_trackVolume);
  }

  @override
  Future<void> seek(Duration position) async {
    if (_endFading || _outgoingBusy) await _cancelFade();
    await _player.seek(position);
  }

  @override
  Future<void> skipToNext() async {
    if (_endFading || _outgoingBusy) await _cancelFade();
    await _player.seekToNext();
  }

  @override
  Future<void> skipToPrevious() async {
    if (_endFading || _outgoingBusy) await _cancelFade();
    if (_player.position > const Duration(seconds: 3)) {
      await _player.seek(Duration.zero);
    } else {
      await _player.seekToPrevious();
    }
  }

  @override
  Future<void> skipToQueueItem(int index) async {
    if (_endFading || _outgoingBusy) await _cancelFade();
    await _player.seek(Duration.zero, index: index);
    await play();
  }

  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode shuffleMode) async {
    final enabled = shuffleMode != AudioServiceShuffleMode.none;
    if (enabled) await _player.shuffle();
    await _player.setShuffleModeEnabled(enabled);
    playbackState.add(playbackState.value.copyWith(shuffleMode: shuffleMode));
    _primeBuffer();
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
    _primeBuffer();
  }

  @override
  Future<void> stop() async {
    _flushPlay();
    _switchingSource = false;
    // La mise à niveau d'un croisement ne survit pas à l'arrêt : ce qui
    // repartira n'aura personne à égaler.
    _trackVolume = 1;
    await _cancelFade();
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
  List<MediaItem> _playAllItems(
    String prefix, {
    String playLabel = 'Tout lire',
    String shuffleLabel = 'Lecture aléatoire',
  }) =>
      [
        MediaItem(id: '${prefix}_PLAY', title: playLabel, playable: true),
        MediaItem(
          id: '${prefix}_SHUFFLE',
          title: shuffleLabel,
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
    // La racine de reprise, demandée à part par Android Auto au démarrage :
    // elle ne descend jamais au serveur (elle est posée avant la session, et
    // souvent sans réseau) et ne doit JAMAIS repartir vide — c'était là
    // l'« Impossible de charger votre sélection » de l'écran d'accueil de la
    // voiture (idée #103).
    if (parentMediaId == BrowseIds.resumeRoot) {
      final items = await _resumeRoot();
      logAA('→ ${items.length} item de reprise : ${items.first.title}');
      return items;
    }

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

  // ── La racine de reprise (idée #103) ───────────────────────────────────────

  /// Ce qu'on écoutait en dernier, la position vivante du lecteur ayant le
  /// dernier mot : tant que l'app tourne, elle en sait plus que le disque, qui
  /// n'est écrit qu'aux changements de piste et aux pauses.
  Future<ResumePoint?> _resumePoint() async {
    final point = await resume.load();
    if (point == null) return null;
    final live = _player.position;
    final playing = queue.value.isNotEmpty &&
        mediaItem.value?.extras?['songId'] == point.song.id;
    return playing && live > Duration.zero ? point.at(live) : point;
  }

  /// L'unique élément de la racine « recent ». Android Auto y attend un titre
  /// jouable ; une liste vide, et l'accueil de la voiture affiche « Impossible
  /// de charger votre sélection ». Tant qu'on n'a jamais rien écouté, on
  /// propose donc de quoi lancer la musique plutôt que rien.
  Future<List<MediaItem>> _resumeRoot() async {
    final point = await _resumePoint();
    if (point == null) {
      return const [
        MediaItem(
          id: 'ALL_SHUFFLE',
          title: 'Lecture aléatoire',
          playable: true,
        ),
      ];
    }
    final s = point.song;
    final progress = point.progress;
    return [
      MediaItem(
        id: BrowseIds.resume,
        title: s.title,
        artist: s.artistName,
        album: s.albumName,
        duration: Duration(seconds: s.duration),
        artUri: _artUri(s.artworkUrl),
        playable: true,
        // Les deux clés d'androidx.media : la vignette de reprise porte alors
        // la barre de progression là où on s'était arrêté.
        extras: {
          'android.media.extra.PLAYBACK_STATUS': progress > 0 ? 1 : 0,
          if (progress > 0)
            'androidx.media.MediaItem.Extras.COMPLETION_PERCENTAGE': progress,
        },
      ),
    ];
  }

  /// Reprise depuis Android Auto : la file telle qu'on l'avait laissée, à la
  /// piste et à la seconde près.
  Future<void> _playResume() async {
    final point = await _resumePoint();
    if (point == null) {
      logAA('reprise : rien à reprendre');
      return;
    }
    // Un titre téléchargé se joue sans réseau ni session ; les autres ont
    // besoin du dépôt, qui met quelques secondes à revenir au démarrage.
    if (!offlinePaths.containsKey(point.song.id)) {
      playbackState.add(playbackState.value.copyWith(
        processingState: AudioProcessingState.loading,
        playing: false,
      ));
      if (await _awaitRepository() == null) {
        logAA('reprise : pas de session');
        playbackState.add(playbackState.value.copyWith(
          processingState: AudioProcessingState.idle,
        ));
        return;
      }
    }
    logAA('reprise : « ${point.song.title} » à ${_fmtPos(point.position)}');
    await playSongs(
      point.songs,
      startIndex: point.index,
      startPosition: point.position,
    );
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
        if (genres.isEmpty) return [];
        return [
          // Comme sur les artistes et les albums : de quoi lancer la musique
          // sans avoir à descendre d'un cran de plus au volant. Les libellés
          // disent toute la bibliothèque : un cran plus bas, dans un genre,
          // les deux mêmes entrées ne jouent que ce genre (idée #109) et on
          // ne doit pas pouvoir les confondre d'un coup d'œil.
          ..._playAllItems(
            'ALL',
            playLabel: 'Tout lire — toute la bibliothèque',
            shuffleLabel: 'Lecture aléatoire — toute la bibliothèque',
          ),
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
        if (albums.isEmpty) return [];
        return [
          // « Tout lire / aléatoire » = toute la bibliothèque, comme sur les
          // artistes : la liste d'albums est longue, on ne doit pas avoir à la
          // parcourir pour lancer quelque chose.
          ..._playAllItems('ALL', playLabel: 'Tout lire'),
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
      // Ce qu'on vient chercher dans un genre au volant, c'est d'abord « tout
      // ce genre, mélangé » (idée #109) : l'aléatoire passe donc en tête, et
      // les deux entrées portent le nom du genre — un cran plus haut, les
      // mêmes libellés lancent toute la bibliothèque.
      final playAll = _playAllItems(
        parentMediaId,
        playLabel: 'Tout lire — $name',
        shuffleLabel: 'Lecture aléatoire — $name',
      ).reversed.toList();
      try {
        final artists = await repo.artistsByGenre(name);
        return [
          // Tout le genre d'un coup, sans choisir d'artiste. Les entrées
          // restent là même quand le genre ne liste aucun artiste : le vivier
          // du serveur, lui, sait encore quoi jouer.
          ...playAll,
          for (final ar in artists)
            MediaItem(
              id: BrowseIds.artist(ar.id),
              title: ar.name,
              artUri: _artUri(ar.imageUrl),
              playable: false,
            ),
        ];
      } catch (e) {
        // La liste des artistes n'est pas venue : hors de question que le
        // genre devienne injouable pour autant. On garde de quoi le lancer et
        // de quoi réessayer, au lieu de tomber sur le repli hors ligne (qui
        // ne propose que les téléchargements).
        logAA('artistes du genre « $name » indisponibles : $e');
        return [
          ...playAll,
          MediaItem(
            id: BrowseIds.retry(parentMediaId),
            title: 'Réessayer',
            artist: "La liste des artistes n'a pas pu être chargée",
            playable: false,
          ),
        ];
      }
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
    // La vignette de reprise (idée #103) : elle se décrit toute seule, avant
    // même que la session ne soit restaurée.
    if (mediaId == BrowseIds.resume) {
      return (await _resumeRoot()).where((i) => i.id == mediaId).firstOrNull;
    }
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
    // Journalisé comme le reste de la navigation : sans ça, le diagnostic
    // Android Auto montre les listes affichées mais jamais ce qu'on a essayé
    // de jouer — c'est pourtant l'autre moitié de « Impossible de charger
    // votre sélection ».
    logAA('lecture demandée : $mediaId');
    // Les téléchargements se jouent sans réseau ni session : on les sert avant
    // d'attendre quoi que ce soit, sinon la seule chose encore écoutable hors
    // ligne resterait bloquée derrière l'attente du dépôt.
    if (mediaId.startsWith('DOWNLOADS')) {
      await _playDownloads(mediaId);
      return;
    }

    // La vignette de reprise de l'accueil Android Auto (idée #103).
    if (mediaId == BrowseIds.resume) {
      await _playResume();
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

      // « Tout lire » / « Lecture aléatoire » d'un genre. Traité à part : un
      // nom de genre peut contenir n'importe quoi (espaces, tirets bas), il
      // ne se découpe pas à l'expression régulière des autres catégories.
      if (mediaId.startsWith('GENRE_')) {
        final songs = await genreSongs(mediaId, repo);
        if (songs.isEmpty) {
          // Sans ça l'état reste sur « chargement » : dans la voiture, c'est
          // un écran qui tourne sans fin plutôt qu'un échec avouable.
          logAA('→ genre sans titre jouable');
          playbackState.add(playbackState.value.copyWith(
            processingState: AudioProcessingState.idle,
          ));
          return;
        }
        await playSongs(songs);
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

      if (m == null) {
        logAA('→ identifiant non jouable');
        return;
      }

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
      if (songs.isEmpty) {
        logAA('→ aucun titre à jouer');
        return;
      }

      final action = m.group(5) ?? 'PLAY';
      if (action == 'SHUFFLE') {
        await playSongs(songs.toList()..shuffle());
      } else if (action.startsWith('TRACK_')) {
        final index = int.parse(m.group(6)!);
        await playSongs(songs, startIndex: index.clamp(0, songs.length - 1));
      } else {
        await playSongs(songs);
      }
    } catch (e) {
      // Retombe sur idle pour qu'Android Auto ne reste pas bloqué en
      // chargement si le serveur ne répond pas.
      logAA('ERREUR lecture : $e');
      playbackState.add(playbackState.value.copyWith(
        processingState: AudioProcessingState.idle,
      ));
    }
  }

  /// Les titres d'un « Tout lire » / « Lecture aléatoire » de genre, dans
  /// l'ordre où ils doivent s'entendre. Le serveur sait filtrer par genre en
  /// une seule requête (le vivier des jeux) : on évite un détail par artiste
  /// puis par album, impensable au volant sur un genre qui compte cinquante
  /// artistes. Liste vide si l'identifiant n'est pas jouable — un genre seul
  /// se navigue, il ne se joue pas.
  @visibleForTesting
  Future<List<Song>> genreSongs(String mediaId, LibraryRepository repo) async {
    final rest = mediaId.substring('GENRE_'.length);
    final shuffle = rest.endsWith('_SHUFFLE');
    final suffix = shuffle ? '_SHUFFLE' : '_PLAY';
    if (!rest.endsWith(suffix)) return const [];
    final name = rest.substring(0, rest.length - suffix.length);
    if (name.isEmpty) return const [];
    var songs = await repo.randomSongs(
      limit: 500,
      source: GameSource(mode: GameSourceMode.genres, genres: [name]),
    );
    if (songs.isEmpty) {
      // Le vivier du serveur n'a rien rendu pour ce genre. Plutôt que le
      // silence au volant, on rassemble le genre artiste par artiste — c'est
      // lent, d'où le repli seulement, et borné.
      songs = await _genreSongsByArtist(name, repo);
      if (songs.isNotEmpty) songs = songs.toList()..shuffle();
    }
    logAA('genre « $name » : ${songs.length} titres '
        '(${shuffle ? 'aléatoire' : 'tout lire'})');
    // La liste est mélangée (serveur, ou repli) : l'aléatoire se joue telle
    // quelle, « Tout lire » la remet en ordre artiste / album / piste.
    if (shuffle) return songs;
    return songs.toList()
      ..sort((a, b) {
        final artist = (a.artistName ?? '').compareTo(b.artistName ?? '');
        if (artist != 0) return artist;
        final album = (a.albumName ?? '').compareTo(b.albumName ?? '');
        if (album != 0) return album;
        return (a.trackNumber ?? 0).compareTo(b.trackNumber ?? 0);
      });
  }

  /// Repli du genre : ses artistes, puis leurs titres. Un genre peut compter
  /// cinquante artistes et chacun coûte un détail par album — on s'arrête donc
  /// à une poignée d'artistes tirés au hasard, de quoi remplir une file sans
  /// faire attendre la voiture. Un artiste illisible est simplement sauté.
  Future<List<Song>> _genreSongsByArtist(
    String name,
    LibraryRepository repo,
  ) async {
    const maxArtists = 8;
    final artists = await repo.artistsByGenre(name);
    if (artists.isEmpty) return const [];
    final picked = artists.toList()..shuffle();
    final songs = <Song>[];
    for (final ar in picked.take(maxArtists)) {
      try {
        songs.addAll(await _artistSongs(repo, ar.id));
      } catch (e) {
        logAA('genre « $name » : artiste ${ar.name} illisible ($e)');
      }
    }
    logAA('genre « $name » : repli par artiste, ${songs.length} titres');
    return songs;
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
