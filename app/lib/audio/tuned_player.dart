import 'package:just_audio/just_audio.dart';

import 'net_lock.dart';

/// Tous les lecteurs de l'app sortent d'ici (idée #57).
///
/// Un seul lecteur pour tout le monde n'est pas tenable, et ce n'est pas une
/// question de code : le medley croise deux extraits (un fondu enchaîné demande
/// deux sons à la fois), les jeux doivent rester anonymes (le titre en cours ne
/// doit apparaître ni en notification ni dans le mini-lecteur, sinon la manche
/// est donnée), le talkie-walkie des parties parle *par-dessus* l'extrait, et la
/// pré-écoute YouTube ne doit pas jeter la file de lecture en cours. Ce qui se
/// partage, en revanche, c'est le *réglage* du lecteur — c'est tout ce que le
/// lecteur principal avait de plus que les autres, et c'est ce que cette
/// fabrique donne à chacun.
///
/// Deux profils, parce qu'ils n'écoutent pas la même chose.
enum PlayerUse {
  /// Un morceau entier, écouté d'un bout à l'autre : on remplit large pour
  /// traverser un trou de réseau (lecteur principal, pré-écoute YouTube).
  streaming,

  /// Quelques dizaines de secondes qui doivent partir tout de suite (medley,
  /// extraits des jeux, messages du talkie-walkie).
  snippet,
}

/// Réglage éprouvé par l'ancien client Android (fork PixelPlay) : min 30 s /
/// max 60 s de tampon, lecture dès 5 s d'avance.
const _streamingLoad = AudioLoadConfiguration(
  androidLoadControl: AndroidLoadControl(
    minBufferDuration: Duration(seconds: 30),
    maxBufferDuration: Duration(seconds: 60),
    bufferForPlaybackDuration: Duration(seconds: 5),
    bufferForPlaybackAfterRebufferDuration: Duration(seconds: 10),
  ),
);

/// Un extrait ne dure que quelques dizaines de secondes : garder cinquante
/// secondes d'avance (le défaut d'ExoPlayer) revient à télécharger la moitié du
/// morceau pour rien, et attendre deux secondes et demie avant la première note
/// rate le fondu enchaîné qu'on venait de croiser. On remplit moins, on part
/// plus vite.
const _snippetLoad = AudioLoadConfiguration(
  androidLoadControl: AndroidLoadControl(
    minBufferDuration: Duration(seconds: 15),
    maxBufferDuration: Duration(seconds: 30),
    bufferForPlaybackDuration: Duration(milliseconds: 1500),
    bufferForPlaybackAfterRebufferDuration: Duration(seconds: 3),
  ),
);

/// Un lecteur just_audio réglé comme le lecteur principal : le tampon qui va
/// avec l'usage, et surtout le verrou réseau tenu tant qu'il joue — écran
/// éteint, sans lui, la radio Wi-Fi passe en économie d'énergie et le flux cale.
/// Le verrou se relâche à la pause, à l'arrêt et à la disparition du lecteur.
AudioPlayer createGullifyPlayer({required PlayerUse use}) {
  final player = AudioPlayer(
    audioLoadConfiguration:
        use == PlayerUse.streaming ? _streamingLoad : _snippetLoad,
  );
  final lock = NetworkLockHold();
  player.playerStateStream.listen(
    (s) => lock.hold(s.playing),
    // Une erreur de flux ou la fin du lecteur laisserait sinon le verrou tenu
    // pour rien, au détriment de la batterie.
    onError: (Object _, StackTrace _) => lock.hold(false),
    onDone: () => lock.hold(false),
    cancelOnError: false,
  );
  return player;
}
