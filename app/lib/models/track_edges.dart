/// Ce que le serveur a mesuré aux bords d'un titre (idée #79), en lisant son
/// niveau sonore fenêtre par fenêtre — voir src/TransitionAnalysis.php. Le
/// lecteur s'en sert pour tailler le fondu enchaîné sur le morceau plutôt que
/// sur le chronomètre : voir `crossfadePlan` dans audio/fade.dart.
class TrackEdges {
  const TrackEdges({
    this.tail = Duration.zero,
    this.decay = Duration.zero,
    this.lead = Duration.zero,
    this.level,
    this.endLevel,
    this.startLevel,
  });

  /// Blanc de fin de fichier : il n'y a plus rien à croiser là-dessus.
  final Duration tail;

  /// Descente naturelle de fin — le titre s'éteint déjà tout seul.
  final Duration decay;

  /// Entrée en matière : ce que le début du titre met à monter en puissance.
  final Duration lead;

  /// Niveau de référence du titre, en décibels (toujours négatif) : le RMS de
  /// son troisième quartile. Deux morceaux ne sont pas gravés au même volume —
  /// un vieil album et un remaster peuvent tenir six décibels d'écart. C'est ce
  /// qui permet de croiser deux titres au même niveau plutôt que de laisser
  /// l'entrant sonner plus fort que celui qu'il remplace (idée #101).
  ///
  /// Null quand le serveur n'a pas su le dire — vieux profil en cache, mesure
  /// impossible : le croisement se fait alors sans correction.
  final double? level;

  /// Niveau de la dernière ligne droite du titre, en décibels : ce qu'il joue
  /// vraiment pendant qu'on lui passe dessus, blanc de fin non compris.
  ///
  /// Un morceau finit presque toujours plus bas qu'il n'a joué — sur cette
  /// bibliothèque, cinq décibels de moins en médiane. C'est LUI, et non
  /// [level], que le titre entrant doit rejoindre : sinon il arrive au niveau
  /// moyen du sortant, plus fort que ce que le sortant fait entendre à cet
  /// instant, et la fin du morceau semble enfler (idée #102).
  final double? endLevel;

  /// Niveau de l'entrée du titre, une fois l'intro passée : ce qu'il fera
  /// entendre pendant le croisement, à comparer à l'[endLevel] du sortant.
  final double? startLevel;
}
