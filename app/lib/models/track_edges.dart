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
  });

  /// Blanc de fin de fichier : il n'y a plus rien à croiser là-dessus.
  final Duration tail;

  /// Descente naturelle de fin — le titre s'éteint déjà tout seul.
  final Duration decay;

  /// Entrée en matière : ce que le début du titre met à monter en puissance.
  final Duration lead;

  /// Niveau de référence du titre, en décibels (toujours négatif) : le RMS de
  /// son troisième quartile. Deux morceaux ne sont pas gravés au même volume —
  /// sur cette bibliothèque, du plus discret au plus fort, plus de vingt
  /// décibels séparent les extrêmes. C'est ce niveau-là qui donne à chaque
  /// titre son volume, celui qui l'amène sur la cible commune et qu'il tient
  /// de sa première à sa dernière note — voir `trackVolumeFor` dans
  /// audio/fade.dart (idée #108).
  ///
  /// Le volume ne se décide plus par rapport au titre d'avant, comme le
  /// faisaient les idées #101 à #104 : une correction relative ne peut que
  /// descendre (au-delà du plein volume, un lecteur sature), si bien qu'elle
  /// butait sur ses bornes plus d'un passage sur trois, et que l'écart passait
  /// alors tel quel dans les oreilles.
  ///
  /// Null quand le serveur n'a pas su le dire — vieux profil en cache, mesure
  /// impossible : le titre garde alors le volume du précédent.
  ///
  /// Le serveur mesure aussi le niveau des deux BORDS du titre (`endDb`,
  /// `startDb`, idée #102) ; l'app ne les lit plus. Un bord, c'est un instant,
  /// et un instant ne justifie pas un volume qu'on tient trois minutes.
  final double? level;
}
