/// Ce que le serveur a mesuré aux bords d'un titre (idée #79), en lisant son
/// niveau sonore fenêtre par fenêtre — voir src/TransitionAnalysis.php. Le
/// lecteur s'en sert pour tailler le fondu enchaîné sur le morceau plutôt que
/// sur le chronomètre : voir `crossfadePlan` dans audio/fade.dart.
class TrackEdges {
  const TrackEdges({
    this.tail = Duration.zero,
    this.decay = Duration.zero,
    this.lead = Duration.zero,
  });

  /// Blanc de fin de fichier : il n'y a plus rien à croiser là-dessus.
  final Duration tail;

  /// Descente naturelle de fin — le titre s'éteint déjà tout seul.
  final Duration decay;

  /// Entrée en matière : ce que le début du titre met à monter en puissance.
  final Duration lead;
}
