import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

const _storage = FlutterSecureStorage();
const _kEnabled = 'gullify_fade_enabled';
const _kSeconds = 'gullify_fade_seconds';
const _kTracks = 'gullify_fade_tracks';

/// Bornes du réglage de durée. En dessous d'une demi-seconde le fondu ne
/// s'entend plus (autant l'éteindre), au-delà de huit secondes on n'appuie
/// plus sur pause, on négocie avec elle.
const kFadeMinSeconds = 0.5;
const kFadeMaxSeconds = 8.0;

/// Le fondu que l'app faisait avant d'être réglable : assez court pour que
/// pause reste franche.
const kFadeDefaultSeconds = 0.5;

/// Un pas de volume toutes les 40 ms : sous le seuil où l'oreille entend des
/// marches, et sans noyer le lecteur d'appels.
const kFadeTick = Duration(milliseconds: 40);

/// Les volumes successifs d'un fondu de [from] vers [to] étalé sur [over], un
/// par [kFadeTick]. Le dernier vaut exactement [to] — un fondu ne finit jamais
/// « presque » à sa cible, sinon la lecture reprendrait à 0,98 pour toujours.
///
/// Volume linéaire, comme le fondu court d'origine : le fondu à puissance
/// constante (racine carrée) est fait pour croiser DEUX sons (voir le medley),
/// il creuse un trou au milieu quand il n'y en a qu'un.
List<double> fadeRamp({
  required double from,
  required double to,
  required Duration over,
}) {
  if (over <= Duration.zero) return [to];
  final steps = (over.inMicroseconds / kFadeTick.inMicroseconds).round();
  if (steps <= 1) return [to];
  return [
    for (var i = 1; i <= steps; i++)
      (from + (to - from) * i / steps).clamp(0.0, 1.0),
  ];
}

/// Ce que le volume doit faire à un instant donné de la piste en cours.
enum TrackFade {
  /// Rien à changer.
  none,

  /// La piste se termine : descendre sur ce qu'il en reste.
  out,

  /// On n'est plus dans la dernière ligne droite — piste suivante, piste
  /// rejouée en boucle, retour en arrière, ou réglage éteint entre-temps : le
  /// volume remonte. C'est le filet de sécurité du fondu de fin, celui qui
  /// interdit qu'une piste reste en sourdine pour toujours.
  back,
}

/// Décide du fondu de fin de piste. Séparé du lecteur pour être vérifiable :
/// c'est ici que se joue le risque de laisser le son au tapis.
///
/// [fade] est la durée du fondu de fin — nulle quand le réglage est éteint.
/// [fadingOut] dit si la descente est déjà entamée.
TrackFade trackFadeAt({
  required Duration position,
  required Duration? total,
  required Duration fade,
  required bool playing,
  required bool live,
  required bool fadingOut,
}) {
  // Une radio n'a pas de fin, un flux dont on ignore la durée non plus.
  final fadable =
      fade > Duration.zero && !live && total != null && total > Duration.zero;
  final ending = fadable && () {
        final remaining = total - position;
        return remaining > Duration.zero && remaining <= fade;
      }();
  if (fadingOut) return ending ? TrackFade.none : TrackFade.back;
  return ending && playing ? TrackFade.out : TrackFade.none;
}

/// Réglage du fondu à la lecture, à la pause et entre les titres (idée #75).
///
/// Vit à côté du lecteur, comme l'égaliseur : le handler le lit à chaque
/// fondu, l'écran de réglage le modifie, et il se mémorise seul.
class PlaybackFade extends ChangeNotifier {
  bool _enabled = true;
  double _seconds = kFadeDefaultSeconds;
  bool _betweenTracks = false;
  bool _loaded = false;

  /// Fondu à la lecture et à la pause.
  bool get enabled => _enabled;

  /// Durée d'un fondu, en secondes.
  double get seconds => _seconds;

  /// Descendre à la fin d'un titre et remonter au début du suivant. Réservé à
  /// qui le demande : un titre qui s'efface avant sa dernière note ne plaît
  /// pas à tout le monde.
  bool get betweenTracks => _betweenTracks;

  /// Durée effective d'un fondu — nulle quand le réglage est éteint, ce qui
  /// rend la lecture et la pause franches.
  Duration get duration => _enabled
      ? Duration(milliseconds: (_seconds * 1000).round())
      : Duration.zero;

  /// Fondu de fin/début de piste réellement actif.
  bool get fadesTracks => _betweenTracks && duration > Duration.zero;

  /// Relit les réglages mémorisés (au démarrage de l'app).
  Future<void> loadSaved() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final enabled = await _storage.read(key: _kEnabled);
      if (enabled != null) _enabled = enabled == '1';
      final seconds = double.tryParse(await _storage.read(key: _kSeconds) ?? '');
      if (seconds != null) {
        _seconds = seconds.clamp(kFadeMinSeconds, kFadeMaxSeconds);
      }
      _betweenTracks = await _storage.read(key: _kTracks) == '1';
    } catch (_) {
      // Réglages illisibles : on garde le fondu par défaut.
    }
    notifyListeners();
  }

  Future<void> setEnabled(bool value) async {
    _enabled = value;
    notifyListeners();
    await _save(_kEnabled, value ? '1' : '0');
  }

  Future<void> setSeconds(double value) async {
    _seconds = value.clamp(kFadeMinSeconds, kFadeMaxSeconds);
    notifyListeners();
    await _save(_kSeconds, _seconds.toStringAsFixed(1));
  }

  Future<void> setBetweenTracks(bool value) async {
    _betweenTracks = value;
    notifyListeners();
    await _save(_kTracks, value ? '1' : '0');
  }

  Future<void> _save(String key, String value) async {
    _loaded = true;
    try {
      await _storage.write(key: key, value: value);
    } catch (_) {
      // Un échec d'écriture ne doit jamais remonter à l'interface.
    }
  }
}

/// Durée écrite comme l'écran l'affiche : « 0,5 s », « 2 s ».
String formatFadeSeconds(double seconds) {
  final rounded = (seconds * 10).round() / 10;
  final text = rounded == rounded.roundToDouble()
      ? rounded.toStringAsFixed(0)
      : rounded.toStringAsFixed(1).replaceAll('.', ',');
  return '$text s';
}
