import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/track_edges.dart';

// Les mesures du serveur voyagent avec la décision qui les consomme : qui lit
// crossfadePlan n'a qu'un fichier à importer.
export '../models/track_edges.dart';

const _storage = FlutterSecureStorage();
const _kEnabled = 'gullify_fade_enabled';
const _kSeconds = 'gullify_fade_seconds';
const _kTracks = 'gullify_fade_tracks';
const _kSmart = 'gullify_fade_smart';

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

/// La loi qui gouverne un croisement : à chaque instant, les deux rampes
/// vérifient `sortant^k + entrant^k = 1`.
///
/// k = 2, c'est la puissance constante — chaque titre à −3 dB au milieu du
/// passage. Sur le papier c'est le bon choix : deux sons sans rapport ajoutent
/// leurs puissances, la somme fait donc exactement un titre. À l'oreille, non :
/// deux musiques différentes qui jouent ensemble ne s'entendent pas comme une
/// seule de même puissance, elles s'additionnent aussi en sonie, et le passage
/// enfle d'environ deux décibels (idée #101).
///
/// k = 1, ce sont deux droites (−6 dB au milieu) : là, c'est le creux.
///
/// k = 4/3 met chaque titre à −4,5 dB à mi-croisement — le compromis classique
/// des tables de montage. La puissance réunie descend d'un décibel et demi,
/// juste de quoi compenser l'addition des deux sonies : le passage ne sonne ni
/// plus fort ni plus faible que les titres qu'il relie.
const kCrossfadeLaw = 4 / 3;

/// La façon dont une rampe de volume relie son départ à sa cible.
enum FadeCurve {
  /// Volume linéaire, comme le fondu court d'origine : lecture, pause, fin de
  /// piste. Sur un son seul, c'est la courbe qui s'entend le mieux.
  linear,

  /// La loi du croisement ([kCrossfadeLaw]), faite pour croiser DEUX sons —
  /// fondu enchaîné et medley : deux rampes qui se croisent doivent se
  /// compléter, ce qu'une paire de droites ne fait pas. Sur un son seul, à
  /// l'inverse, c'est elle qui creuserait.
  crossing,

  /// Linéaire en décibels : à chaque pas, le volume gagne le même nombre de
  /// décibels et non la même amplitude. C'est ce qu'il faut à une correction
  /// de niveau qui doit passer inaperçue — l'oreille entend des décibels, pas
  /// des amplitudes. Voir [crossfadeRestore].
  ///
  /// Une rampe en décibels ne peut ni partir ni arriver au silence : à zéro
  /// il n'y a plus de décibels du tout. Ces cas-là retombent sur [linear].
  decibels,
}

/// Les volumes successifs d'un fondu de [from] vers [to] étalé sur [over], un
/// par [tick]. Le dernier vaut exactement [to] — un fondu ne finit jamais
/// « presque » à sa cible, sinon la lecture reprendrait à 0,98 pour toujours.
///
/// [curve] choisit la forme de la rampe : voir [FadeCurve].
///
/// [tick] est l'écart entre deux pas. Le fondu du lecteur garde [kFadeTick] ;
/// la montée du réveil (idée #81), qui s'étale sur plusieurs minutes, prend un
/// pas plus large — des milliers d'appels de volume pour une différence que
/// l'oreille n'entend pas. La remontée d'après-croisement aussi
/// ([kCrossfadeRestoreTick]).
List<double> fadeRamp({
  required double from,
  required double to,
  required Duration over,
  FadeCurve curve = FadeCurve.linear,
  Duration tick = kFadeTick,
}) {
  if (over <= Duration.zero) return [to];
  final steps = (over.inMicroseconds / tick.inMicroseconds).round();
  if (steps <= 1) return [to];
  final law = curve == FadeCurve.crossing;
  // Une rampe en décibels a besoin de deux volumes audibles pour avoir un sens.
  final db = curve == FadeCurve.decibels && from > 0 && to > 0;
  // Le croisement s'interpole dans le domaine de la loi, pas sur le volume :
  // c'est ce qui rend les deux rampes complémentaires. La rampe en décibels,
  // elle, s'interpole sur le rapport des deux volumes.
  final start = law ? pow(from, kCrossfadeLaw).toDouble() : 0.0;
  final end = law ? pow(to, kCrossfadeLaw).toDouble() : 0.0;
  double at(int i) {
    if (law) {
      final x = (start + (end - start) * i / steps).clamp(0.0, 1.0);
      return pow(x, 1 / kCrossfadeLaw).toDouble();
    }
    if (db) return from * pow(to / from, i / steps).toDouble();
    return from + (to - from) * i / steps;
  }

  return [for (var i = 1; i <= steps; i++) at(i).clamp(0.0, 1.0)];
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

// ─────────────────────────────────────────────────── le fondu enchaîné (#76) ──

/// Combien de temps à l'avance le titre suivant est chargé sur le lecteur d'à
/// côté. Le lecteur principal remplit trente secondes de tampon avant la
/// première note (voir tuned_player.dart) : sans cette avance, le titre entrant
/// démarrerait en retard et le croisement se ferait dans le vide.
const kCrossfadePreroll = Duration(seconds: 10);

/// Ce qu'un fondu enchaîné peut prendre d'un titre : jamais plus du tiers.
/// Avec un fondu de huit secondes, un interlude de vingt secondes serait
/// autrement croisé de bout en bout — on ne l'entendrait jamais seul.
Duration crossfadeSpan(Duration fade, Duration total) {
  final most = total ~/ 3;
  return fade > most ? most : fade;
}

/// Ce que le fondu enchaîné doit faire à un instant donné de la piste en cours.
enum Crossfade {
  /// Rien à faire.
  none,

  /// Charger le titre suivant sur le lecteur d'à côté, sans le lancer.
  arm,

  /// Lancer le croisement : le suivant monte pendant que celui-ci descend.
  start,

  /// Le titre préparé ne sert plus (retour en arrière, pause, réglage éteint) :
  /// on rend son tampon.
  disarm,
}

/// Décide du fondu enchaîné (idée #76). Comme [trackFadeAt], la décision est
/// prise ici, à part du lecteur, pour être vérifiable : c'est elle qui met deux
/// titres dans les oreilles en même temps.
///
/// [span] est le reste de piste à partir duquel le croisement part — nul quand
/// le réglage est éteint. Il sort de [crossfadePlan], qui l'a déjà borné.
/// [armed] dit si le titre suivant est déjà chargé à côté, [running] si le
/// croisement est déjà lancé.
Crossfade crossfadeAt({
  required Duration position,
  required Duration? total,
  required Duration span,
  required bool playing,
  required bool live,
  required bool hasNext,
  required bool armed,
  required bool running,
}) {
  // Un croisement en cours se pilote lui-même jusqu'au bout.
  if (running) return Crossfade.none;
  // Rien à croiser : radio (pas de fin), durée inconnue, dernier titre de la
  // file, lecture arrêtée, ou réglage éteint.
  final crossable = span > Duration.zero &&
      !live &&
      hasNext &&
      playing &&
      total != null &&
      total > Duration.zero;
  if (!crossable) return armed ? Crossfade.disarm : Crossfade.none;

  final remaining = total - position;
  if (remaining <= Duration.zero) return Crossfade.none;
  if (remaining <= span) return Crossfade.start;
  if (remaining <= span + kCrossfadePreroll) {
    return armed ? Crossfade.none : Crossfade.arm;
  }
  // On s'est éloigné de la fin (retour en arrière) : le tampon préparé ne sert
  // plus à rien, et le garder tiendrait le réseau pour rien.
  return armed ? Crossfade.disarm : Crossfade.none;
}

// ──────────────────────────────────── le fondu enchaîné intelligent (#79) ──

/// Ce qu'un titre entrant peut se voir donner d'avance à cause de son entrée
/// en matière. Au-delà, on ne « cale » plus la transition : on couvre l'intro
/// du titre suivant, qui a le droit de s'entendre.
const kSmartLeadMax = Duration(seconds: 3);

/// Silence de fin qu'on accepte de sauter. Un blanc plus long qu'une gorgée
/// est le signe d'un fichier bizarre (piste cachée, plage de fin) : on ne
/// démarre pas le titre suivant une éternité avant la fin annoncée.
const kSmartTailMax = Duration(seconds: 6);

/// Le croisement intelligent ne s'écarte jamais de plus du double de la durée
/// réglée : le réglage reste le maître, la mesure ne fait que l'étirer pour
/// couvrir une longue descente naturelle.
const kSmartStretch = 2;

/// Ce qu'un titre entrant peut se voir retirer de volume pour ne pas arriver
/// plus fort que celui qu'il remplace (idée #101). Six décibels, c'est déjà la
/// moitié de l'amplitude : au-delà, ce n'est plus une mise à niveau, c'est un
/// titre qu'on n'entend plus arriver.
const kCrossfadeDuckMaxDb = 6.0;

/// Jamais plus bas que ça : le volume auquel un titre retenu au maximum
/// ([kCrossfadeDuckMaxDb]) se retrouve. Sert de plancher aux croisements qui
/// s'enchaînent — sans lui, une série de morceaux gravés fort ferait descendre
/// le volume d'un cran à chaque passage.
final kCrossfadeDuckFloor = pow(10, -kCrossfadeDuckMaxDb / 20).toDouble();

/// À quelle vitesse un titre retenu retrouve son propre niveau, en décibels
/// par seconde (idée #104).
///
/// C'est ici que se jouait ce qui restait d'enflure. Un morceau finit presque
/// toujours plus bas qu'il n'a joué — cinq décibels en médiane —, donc presque
/// TOUS les croisements retiennent le titre entrant de quelques décibels
/// (idée #102), et la remontée qui suit était une seconde transition, six
/// secondes après la première : cinq décibels en six secondes, c'est près d'un
/// décibel par seconde, et ça s'entend comme quelqu'un qui monte le son.
///
/// Un quart de décibel par seconde, non : à cette vitesse, l'oreille ne suit
/// plus le niveau absolu, elle entend la musique. La remontée complète prend
/// alors une vingtaine de secondes — le temps d'un couplet, largement dans le
/// titre, et sans que rien ne se remarque.
const kCrossfadeRestoreRateDb = 0.25;

/// Pas de la remontée. Large, parce qu'elle est lente : à un quart de décibel
/// par seconde, chaque pas ne pèse que cinq centièmes de décibel — mille fois
/// moins que ce que l'oreille sait entendre, pour cinq appels de volume par
/// seconde au lieu de vingt-cinq.
const kCrossfadeRestoreTick = Duration(milliseconds: 200);

/// Le temps que met un titre laissé à [volume] pour retrouver son plein niveau
/// sans que la remontée s'entende. Nul quand il n'y a rien à remonter.
Duration crossfadeRestore(double volume) {
  if (volume <= 0 || volume >= 1) return Duration.zero;
  final db = -20 * log(volume) / ln10;
  return Duration(
    milliseconds: (db / kCrossfadeRestoreRateDb * 1000).round(),
  );
}

/// La forme d'un croisement : quand il part, et comment les deux volumes se
/// croisent une fois parti.
class CrossfadePlan {
  const CrossfadePlan({
    required this.trigger,
    required this.rise,
    required this.fall,
    this.ceiling = 1,
  });

  /// Le croisement part quand il ne reste plus que ça du titre en cours.
  final Duration trigger;

  /// Montée du titre entrant.
  final Duration rise;

  /// Descente du titre sortant. Plus courte que [rise] quand le titre entrant
  /// démarre en avance à cause de son entrée en matière.
  final Duration fall;

  /// L'attente que les DEUX rampes observent avant de se croiser : le temps
  /// que le titre entrant met à sortir de son entrée en matière. Le sortant y
  /// tient son plein volume, l'entrant y reste muet — le laisser monter
  /// pendant que l'autre joue encore à fond additionnerait deux musiques, et
  /// le passage sonnerait plus fort que les titres qu'il relie (idée #91).
  Duration get hold => rise - fall;

  /// Ce que le titre entrant a le droit de faire entendre pendant le
  /// croisement, RELATIVEMENT au titre sortant : 1 en temps normal, moins
  /// quand son début a été mesuré plus fort que la fin du titre sortant
  /// (idées #101 et #102).
  ///
  /// C'est une proportion, pas un volume : le volume visé se calcule au moment
  /// du croisement, quand on sait à quel volume le sortant joue vraiment —
  /// voir [crossfadeTarget]. Le titre entrant retrouve son plein niveau
  /// ensuite, une fois le passage terminé (voir [crossfadeRestore]).
  final double ceiling;

  bool get idle => trigger <= Duration.zero;
}

/// De combien retenir le titre entrant pour qu'il croise au niveau du sortant
/// (idées #101 et #102). Les deux niveaux sont des RMS en décibels, tels que
/// le serveur les mesure (voir src/TransitionAnalysis.php).
///
/// Ce sont les niveaux des BORDS qu'on compare — la fin du sortant, le début
/// de l'entrant —, pas les niveaux de référence des deux morceaux : un
/// croisement ne fait pas jouer les titres en moyenne, il fait jouer la fin de
/// l'un et le début de l'autre. Voir [crossfadePlan] et [TrackEdges.endLevel].
///
/// On ne retient QUE ce qui est trop fort : pousser un titre gravé bas
/// au-dessus de son niveau le ferait saturer, et un passage un peu discret ne
/// s'entend pas comme un défaut — un passage qui enfle, si.
double crossfadeCeiling({double? outgoing, double? incoming}) {
  if (outgoing == null || incoming == null) return 1;
  final tooLoud = incoming - outgoing;
  if (tooLoud <= 0) return 1;
  final ducked = tooLoud > kCrossfadeDuckMaxDb ? kCrossfadeDuckMaxDb : tooLoud;
  return pow(10, -ducked / 20).toDouble();
}

/// Le volume auquel le titre entrant monte pendant le croisement : le plafond
/// mesuré ([CrossfadePlan.ceiling]) appliqué au volume auquel le titre sortant
/// joue VRAIMENT à cet instant (idée #104).
///
/// Les niveaux mesurés disent comment les deux morceaux sont gravés ; ils ne
/// disent pas à quel volume le lecteur les fait sortir. Or le sortant n'est
/// pas toujours à fond : il peut être lui-même en train de remonter de son
/// propre croisement, quelques secondes plus tôt ([crossfadeRestore]). Caler
/// l'entrant sur le seul niveau du fichier le faisait alors arriver au-dessus
/// de ce qu'on entendait — l'enflure revenait par la porte de derrière, sur
/// les titres qui s'enchaînent vite.
///
/// Deux garde-fous : jamais plus fort que ce que le sortant fait entendre, et
/// jamais sous [kCrossfadeDuckFloor], pour qu'une longue série de morceaux
/// gravés fort ne fasse pas descendre le volume marche après marche.
double crossfadeTarget({required double ceiling, required double outgoing}) {
  // Sortant muet (fondu d'entrée en cours, volume inconnu) : il n'y a rien à
  // égaler, on s'en tient à ce que la mesure a dit.
  if (outgoing <= 0) return ceiling.clamp(0.0, 1.0);
  final playing = outgoing > 1 ? 1.0 : outgoing;
  final matched = ceiling.clamp(0.0, 1.0) * playing;
  final floor = playing < kCrossfadeDuckFloor ? playing : kCrossfadeDuckFloor;
  return matched < floor ? floor : matched;
}

/// Taille le croisement sur ce que le serveur a mesuré (idée #79).
///
/// Sans mesure — serveur muet, titre sur un stockage distant, réglage
/// « intelligent » éteint —, on retombe exactement sur le croisement fixe de
/// l'idée #76 : la durée réglée, jamais plus du tiers du titre.
///
/// Avec mesure :
///   - le blanc de fin du titre sortant est sauté (le suivant part avant) ;
///   - le croisement s'étire pour couvrir une longue descente naturelle,
///     sans jamais dépasser le double de la durée réglée ;
///   - le titre entrant part en avance de son entrée en matière, pour que sa
///     première vraie note tombe à la fin de la précédente. Le sortant, lui,
///     garde son volume pendant cette avance : ce n'est pas une raison pour
///     l'effacer plus tôt. Le croisement à proprement parler n'a lieu qu'après
///     ([hold] puis [fall]) : voir [CrossfadePlan.hold] ;
///   - un titre entrant qui arriverait plus fort que le sortant est retenu à
///     son niveau le temps du passage, puis rendu à son propre volume
///     (idée #101) : voir [CrossfadePlan.ceiling]. La comparaison se fait sur
///     les BORDS croisés — la fin du sortant, le début de l'entrant —, et non
///     sur les niveaux de référence des deux morceaux : un morceau finit
///     presque toujours plus bas qu'il n'a joué, et se caler sur sa moyenne
///     faisait arriver l'entrant plus fort que ce que le sortant jouait
///     encore (idée #102).
CrossfadePlan crossfadePlan({
  required Duration fade,
  required Duration? total,
  TrackEdges? current,
  TrackEdges? next,
}) {
  const none = CrossfadePlan(
    trigger: Duration.zero,
    rise: Duration.zero,
    fall: Duration.zero,
  );
  if (fade <= Duration.zero || total == null || total <= Duration.zero) {
    return none;
  }

  final plain = crossfadeSpan(fade, total);
  if (current == null && next == null) {
    return CrossfadePlan(trigger: plain, rise: plain, fall: plain);
  }

  // Jamais plus du tiers du titre dans les oreilles à deux : la règle de
  // l'idée #76 tient toujours, silence de fin non compris (il ne s'entend pas).
  final third = total ~/ 3;

  final decay = current?.decay ?? Duration.zero;
  var overlap = decay > fade ? decay : fade;
  if (overlap > fade * kSmartStretch) overlap = fade * kSmartStretch;
  if (overlap > third) overlap = third;

  var lead = next?.lead ?? Duration.zero;
  if (lead > kSmartLeadMax) lead = kSmartLeadMax;
  if (overlap + lead > third) lead = third - overlap;
  if (lead < Duration.zero) lead = Duration.zero;

  var tail = current?.tail ?? Duration.zero;
  if (tail > kSmartTailMax) tail = kSmartTailMax;

  final rise = overlap + lead;
  var trigger = rise + tail;
  // Un croisement ne mange jamais plus de la moitié du titre, blanc compris :
  // sur une piste courte au long blanc de fin, mieux vaut laisser du silence
  // que de faire disparaître le morceau. (La montée, elle, tient déjà dans le
  // tiers : ce plafond ne peut pas passer sous elle.)
  final half = total ~/ 2;
  if (trigger > half) trigger = half;

  return CrossfadePlan(
    trigger: trigger,
    rise: rise,
    fall: overlap,
    // Les bords, et non les niveaux de référence (idée #102) : ce qui se
    // croise, c'est la fin d'un morceau et le début d'un autre. Un vieux
    // profil en cache, mesuré avant que le serveur ne rende ces niveaux-là,
    // retombe sur le niveau de référence — le croisement de l'idée #101,
    // mieux que rien.
    ceiling: crossfadeCeiling(
      outgoing: current?.endLevel ?? current?.level,
      incoming: next?.startLevel ?? next?.level,
    ),
  );
}

/// Réglage du fondu à la lecture, à la pause et entre les titres (idée #75).
///
/// Vit à côté du lecteur, comme l'égaliseur : le handler le lit à chaque
/// fondu, l'écran de réglage le modifie, et il se mémorise seul.
class PlaybackFade extends ChangeNotifier {
  bool _enabled = true;
  double _seconds = kFadeDefaultSeconds;
  bool _betweenTracks = false;
  bool _smart = true;
  bool _loaded = false;

  /// Fondu à la lecture et à la pause.
  bool get enabled => _enabled;

  /// Durée d'un fondu, en secondes.
  double get seconds => _seconds;

  /// Croiser les titres : le suivant monte pendant que celui en cours descend,
  /// les deux dans les oreilles en même temps (idée #76). Réservé à qui le
  /// demande : un titre qui s'efface avant sa dernière note ne plaît pas à tout
  /// le monde.
  bool get betweenTracks => _betweenTracks;

  /// Tailler le croisement sur le titre plutôt que sur le chronomètre
  /// (idée #79) : le serveur mesure les bords des morceaux, l'app saute les
  /// blancs de fin, couvre les descentes naturelles et donne au titre suivant
  /// l'avance que réclame son intro. Sans serveur ni mesure, le croisement
  /// reste celui de la durée réglée.
  bool get smart => _smart;

  /// Durée effective d'un fondu — nulle quand le réglage est éteint, ce qui
  /// rend la lecture et la pause franches.
  Duration get duration => _enabled
      ? Duration(milliseconds: (_seconds * 1000).round())
      : Duration.zero;

  /// Fondu enchaîné réellement actif.
  bool get fadesTracks => _betweenTracks && duration > Duration.zero;

  /// Croisement intelligent réellement actif : il n'a de sens que là où il y a
  /// un croisement.
  bool get measuresTracks => _smart && fadesTracks;

  /// De combien un titre peut être déclaré fini avant sa vraie fin. Sert au
  /// suivi d'écoute : un titre croisé n'est pas un titre abandonné. Le
  /// croisement intelligent peut partir plus tôt que la durée réglée (blanc de
  /// fin sauté, descente couverte, avance donnée au suivant).
  Duration get crossfadeReach => !fadesTracks
      ? Duration.zero
      : _smart
          ? duration * kSmartStretch + kSmartLeadMax + kSmartTailMax
          : duration;

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
      final smart = await _storage.read(key: _kSmart);
      if (smart != null) _smart = smart == '1';
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

  Future<void> setSmart(bool value) async {
    _smart = value;
    notifyListeners();
    await _save(_kSmart, value ? '1' : '0');
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
