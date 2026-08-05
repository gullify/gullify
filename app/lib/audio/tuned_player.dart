import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import 'net_lock.dart';

/// Tous les lecteurs de l'app sortent d'ici (idées #57 et #58).
///
/// Un seul lecteur pour tout le monde n'est pas tenable, et ce n'est pas une
/// question de code : le medley croise deux extraits (un fondu enchaîné demande
/// deux sons à la fois), les jeux doivent rester anonymes (le titre en cours ne
/// doit apparaître ni en notification ni dans le mini-lecteur, sinon la manche
/// est donnée), le talkie-walkie des parties parle *par-dessus* l'extrait, et la
/// pré-écoute YouTube ne doit pas jeter la file de lecture en cours. Ce qui se
/// partage, c'est le *réglage* du lecteur (idée #57) — et, depuis l'idée #58,
/// les lecteurs eux-mêmes : plus personne ne garde le sien dans son coin.
///
/// La pré-écoute, le medley, les manches de jeu et les messages des parties
/// **empruntent** un lecteur à la réserve le temps de faire du son, et le
/// rendent en se taisant. Le lecteur rendu est arrêté, remis à plat et prêté au
/// suivant : au repos l'app n'en garde plus un seul allumé, et deux extraits qui
/// se croisent dans un medley se rejouent, la manche d'après, dans les deux
/// mêmes lecteurs. Seul le lecteur principal garde le sien pour de bon — c'est
/// lui qui tient la file et la notification, il ne se prête pas.
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
///
/// Réservé à qui garde son lecteur pour toute la vie de l'app (le lecteur
/// principal). Tous les autres passent par [leaseGullifyPlayer].
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

// ────────────────────────────────────────────────────────────── la réserve ──

/// Emprunte un lecteur à la réserve (idée #58). À rendre par [PlayerLease.give]
/// dès qu'on n'a plus de son à faire : c'est ce qui le rend au suivant.
PlayerLease leaseGullifyPlayer({required PlayerUse use}) => _reserve.take(use);

/// Un lecteur prêté. Tant qu'il n'est pas rendu, il n'est qu'à son emprunteur.
class PlayerLease {
  PlayerLease._(this.use, this.player);

  final PlayerUse use;

  /// Le lecteur emprunté. Ne plus y toucher après [give] : il est déjà reparti
  /// faire du son ailleurs.
  final AudioPlayer player;

  bool _given = false;

  /// Encore à nous ?
  bool get held => !_given;

  /// Rend le lecteur à la réserve. Sans effet la deuxième fois — beaucoup
  /// d'emprunteurs rendent à l'arrêt *et* à leur disparition.
  Future<void> give() async {
    if (_given) return;
    _given = true;
    await _reserve._give(this);
  }
}

/// Combien de lecteurs la réserve garde au chaud par profil. Deux, parce que
/// c'est le maximum qu'on entend à la fois : les deux extraits que croise un
/// fondu de medley, ou l'extrait d'une manche et la voix qui passe par-dessus.
const _keepIdle = 2;

final _reserve = _PlayerReserve();

class _PlayerReserve {
  final Map<PlayerUse, List<AudioPlayer>> _idle = {};
  int _out = 0;

  PlayerLease take(PlayerUse use) {
    final free = _idle[use];
    final player = (free != null && free.isNotEmpty)
        ? free.removeLast()
        : createGullifyPlayer(use: use);
    _out++;
    return PlayerLease._(use, player);
  }

  Future<void> _give(PlayerLease lease) async {
    _out--;
    final player = lease.player;
    try {
      await player.stop();
      // Le volume est la seule chose que les emprunteurs déplacent : un medley
      // rend son lecteur à zéro (il venait d'en faire un fondu de sortie), une
      // manche le rend en sourdine (quelqu'un parlait par-dessus). Le prêter tel
      // quel donnerait un extrait muet au suivant.
      await player.setVolume(1);
    } catch (_) {
      // Remise à plat ratée : on ne sait plus dans quel état il est, on le jette
      // plutôt que de prêter un lecteur à moitié éteint.
      await _drop(player);
      return;
    }
    final free = _idle.putIfAbsent(lease.use, () => []);
    if (free.length >= _keepIdle) {
      await _drop(player);
      return;
    }
    free.add(player);
  }

  Future<void> _drop(AudioPlayer player) async {
    try {
      await player.dispose();
    } catch (_) {}
  }
}

/// Combien de lecteurs sont empruntés en ce moment.
@visibleForTesting
int get leasedPlayerCount => _reserve._out;

/// Combien de lecteurs attendent au chaud dans la réserve.
@visibleForTesting
int idlePlayerCount(PlayerUse use) => _reserve._idle[use]?.length ?? 0;

/// Vide la réserve entre deux tests, pour qu'aucun lecteur ne traîne de l'un à
/// l'autre.
@visibleForTesting
void resetPlayerReserveForTest() {
  for (final free in _reserve._idle.values) {
    for (final player in free) {
      player.dispose();
    }
  }
  _reserve._idle.clear();
  _reserve._out = 0;
}
