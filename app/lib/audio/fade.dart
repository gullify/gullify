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
const _kNormalize = 'gullify_fade_normalize';

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
/// l'oreille n'entend pas.
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
  // Le croisement s'interpole dans le domaine de la loi, pas sur le volume :
  // c'est ce qui rend les deux rampes complémentaires.
  final start = law ? pow(from, kCrossfadeLaw).toDouble() : 0.0;
  final end = law ? pow(to, kCrossfadeLaw).toDouble() : 0.0;
  double at(int i) {
    if (law) {
      final x = (start + (end - start) * i / steps).clamp(0.0, 1.0);
      return pow(x, 1 / kCrossfadeLaw).toDouble();
    }
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

/// La forme d'un croisement : quand il part, et comment les deux volumes se
/// croisent une fois parti.
class CrossfadePlan {
  const CrossfadePlan({
    required this.trigger,
    required this.rise,
    required this.fall,
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

  bool get idle => trigger <= Duration.zero;
}

// ────────────────────────────────────── la normalisation du volume (#108) ──
//
// Les idées #101, #102 et #104 ont toutes cherché à faire jouer le titre
// ENTRANT au niveau du SORTANT : une correction relative, décidée au moment du
// passage, transmise de titre en titre. Elle ne pouvait pas tenir, pour une
// raison qui n'apparaît qu'en la mesurant sur toute une file.
//
// Un volume ne peut que descendre — au-delà de 1, un lecteur sature. Le
// premier titre d'une file joue donc à plein, et la chaîne n'a plus qu'un sens
// pour se rattraper : vers le bas. Simulation sur les 581 profils mesurés de
// la bibliothèque, files de quarante titres tirés au sort : la correction bute
// sur une de ses bornes 38 % du temps, et chaque fois qu'elle bute, l'écart
// passe tel quel dans les oreilles. Résultat, 8,6 % des passages font entrer
// le titre suivant plus de deux décibels au-dessus du précédent, et le
// centile 99 monte à ONZE décibels. C'est l'enflure « dans certains cas » de
// l'idée #108 : elle n'est pas dans la forme des rampes, elle est dans le
// principe même d'une correction relative bornée.
//
// D'où le renversement : le volume d'un titre ne se décide plus par rapport à
// son voisin, mais par rapport à un niveau de référence FIXE — c'est ce qu'on
// appelle normaliser. Chaque titre reçoit le sien dès sa première note, le
// garde jusqu'à la dernière, et le retrouve identique la fois d'après quoi
// qu'on ait écouté avant. Deux titres qui se croisent sont alors déjà au même
// niveau : le passage n'a plus rien à corriger, et le titre qui s'achève ne
// voit plus rien lui passer au-dessus.
//
// Ce que ça coûte : la même simulation donne un niveau entendu médian de
// −18 dB au lieu de −15,7, soit 2,3 décibels de moins qu'aujourd'hui. Ce que
// ça rapporte : l'étalement du niveau entendu (centiles 10 à 90) tombe de
// 4,8 dB à ZÉRO. Un niveau global plus bas se rattrape une fois avec le bouton
// de volume ; un écart entre deux titres se subit à chaque passage.

/// Le niveau auquel le lecteur amène tous les titres, en décibels. C'est un
/// niveau de RMS de référence, comparable à ce que le serveur mesure (voir
/// `levelDb` dans src/TransitionAnalysis.php).
///
/// −18 dB, c'est le décile inférieur de la bibliothèque mesurée : neuf titres
/// sur dix y arrivent exactement. Viser plus haut laisserait remonter l'écart
/// (à −16, un passage sur douze enfle encore de plus de deux décibels) ; viser
/// plus bas ne gagnerait presque rien et coûterait du niveau à tout le monde,
/// puisque le dernier dixième — les vieux enregistrements discrets — ne peut
/// de toute façon pas être remonté.
const kNormalizeTargetDb = -18.0;

/// Ce qu'on accepte de retirer au plus à un titre. Dix décibels suffisent à
/// amener le morceau le plus fort de la bibliothèque (−7,8 dB) sur la cible ;
/// au-delà, on ne normaliserait plus, on éteindrait.
const kNormalizeMaxCutDb = 10.0;

/// Le volume le plus bas qu'une normalisation puisse poser — celui d'un titre
/// retenu au maximum ([kNormalizeMaxCutDb]).
final kNormalizeVolumeFloor = pow(10, -kNormalizeMaxCutDb / 20).toDouble();

/// Le volume propre d'un titre (idée #108) : celui qui l'amène sur
/// [kNormalizeTargetDb], et qu'il garde de sa première à sa dernière note.
///
/// [level] est le niveau de gravure mesuré par le serveur, toujours négatif.
/// Renvoie null quand il manque — serveur muet, hors ligne, titre
/// inanalysable : sans mesure, on ne DEVINE pas un volume, on garde celui du
/// titre d'avant (voir l'appelant). Poser le plein volume à la place ferait
/// passer le titre non mesuré au-dessus de toute une file normalisée, ce qui
/// est exactement le défaut qu'on corrige.
///
/// Le volume ne dépasse jamais 1 : un titre gravé sous la cible reste sous la
/// cible plutôt que de saturer. C'est la limite du procédé — on ne sait que
/// retenir, jamais pousser.
/// Jusqu'où dans un titre on accepte encore de poser son volume normalisé.
///
/// La mesure est demandée dès qu'une piste commence, et une piste à l'avance :
/// elle est donc là avant la première note, sauf pour le tout premier titre
/// d'une session, où elle voyage encore. Cinq secondes suffisent largement à
/// l'attendre, et une correction posée dans l'entrée en matière d'un morceau
/// ne s'entend pas. Plus tard, on laisse le titre tranquille : une marche de
/// volume sous une musique installée s'entend comme quelqu'un qui monte le
/// son (idée #104).
const kNormalizeGrace = Duration(seconds: 5);

double? trackVolumeFor(double? level) {
  // Un RMS est toujours négatif : zéro ou positif, c'est « jamais mesuré ».
  if (level == null || level >= 0) return null;
  final cut = (kNormalizeTargetDb - level).clamp(-kNormalizeMaxCutDb, 0.0);
  return pow(10, cut / 20).toDouble();
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
///     ([hold] puis [fall]) : voir [CrossfadePlan.hold].
///
/// Le plan ne dit plus rien du volume : depuis l'idée #108, les deux titres
/// arrivent au croisement déjà normalisés, chacun au niveau que sa gravure lui
/// vaut (voir [trackVolumeFor]). Le passage n'a donc plus de mise à niveau à
/// faire — il ne fait plus que croiser deux rampes.
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

  return CrossfadePlan(trigger: trigger, rise: rise, fall: overlap);
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
  bool _normalize = true;
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

  /// Amener tous les titres au même niveau (idée #108) : le serveur mesure la
  /// gravure de chaque morceau, le lecteur retient les plus forts pour qu'ils
  /// jouent au niveau des autres. Le volume est posé à la première note et
  /// tenu jusqu'à la dernière.
  ///
  /// Vit ici parce qu'il se sert de la même mesure que le croisement
  /// intelligent, et se règle au même endroit — mais il ne dépend d'aucun
  /// fondu : il vaut aussi pour qui écoute sans le moindre croisement.
  bool get normalizes => _normalize;

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

  /// Le lecteur a besoin de ce que le serveur mesure : pour tailler ses
  /// croisements (idée #79), pour normaliser le volume (idée #108), ou les
  /// deux. Sinon, rien à demander.
  bool get needsMeasures => measuresTracks || _normalize;

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
      final normalize = await _storage.read(key: _kNormalize);
      if (normalize != null) _normalize = normalize == '1';
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

  Future<void> setNormalize(bool value) async {
    _normalize = value;
    notifyListeners();
    await _save(_kNormalize, value ? '1' : '0');
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
