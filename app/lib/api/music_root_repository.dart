import 'api_client.dart';

/// Un dossier de la machine, vu par le compagnon.
class DossierServeur {
  const DossierServeur({
    required this.nom,
    required this.chemin,
    required this.musique,
  });

  factory DossierServeur.fromJson(Map<String, dynamic> json) => DossierServeur(
        nom: json['nom'] as String? ?? '',
        chemin: json['chemin'] as String? ?? '',
        musique: (json['musique'] as num?)?.toInt() ?? 0,
      );

  final String nom;
  final String chemin;

  /// Combien de fichiers audio ont été trouvés près de la surface. Le
  /// compagnon s'arrête à cinquante : c'est un indice (« il y a de la musique
  /// là-dedans »), pas un inventaire.
  ///
  /// `-1` quand il n'a pas regardé : dans un dossier qui en compte des
  /// centaines, sonder chacun coûtait des secondes à l'ouverture. Ne pas
  /// savoir ne se dit pas comme « il n'y a rien ».
  final int musique;

  bool get aDeLaMusique => musique > 0;
  bool get sondeInconnu => musique < 0;
}

/// Ce qu'on voit d'un dossier : lui, son parent, et ce qu'il contient.
class VueDossier {
  const VueDossier({
    required this.chemin,
    required this.dossiers,
    required this.actuelle,
    this.parent,
    this.depart = false,
    this.erreur,
    this.musique = 0,
    this.tronque = false,
  });

  factory VueDossier.fromJson(Map<String, dynamic> json) => VueDossier(
        chemin: json['chemin'] as String? ?? '',
        parent: json['parent'] as String?,
        depart: json['depart'] as bool? ?? false,
        erreur: json['erreur'] as String?,
        musique: (json['musique'] as num?)?.toInt() ?? 0,
        tronque: json['tronque'] as bool? ?? false,
        actuelle: json['actuelle'] as String? ?? '',
        dossiers: [
          for (final d in (json['dossiers'] as List?) ?? const [])
            DossierServeur.fromJson(d as Map<String, dynamic>),
        ],
      );

  /// Vide sur l'écran de départ : on y propose les disques, pas un dossier.
  final String chemin;
  final String? parent;

  /// Le premier écran : les disques montés, le dossier personnel, la racine
  /// d'aujourd'hui. De quoi trouver une clé USB sans en connaître le nom.
  final bool depart;

  final String? erreur;
  final int musique;

  /// Là où le serveur lit en ce moment.
  final String actuelle;

  /// La liste a été écourtée : aucun écran ne déroule mille dossiers.
  final bool tronque;

  final List<DossierServeur> dossiers;

  bool get aDeLaMusique => musique > 0;
}

/// Le dossier de musique du serveur — celui que Docker monte, pas un réglage.
///
/// Le conteneur ne voit que ce qui lui est déjà monté : c'est donc le
/// compagnon, sur la machine, qui regarde pour lui et qui remonte la pile
/// ensuite. Sans compagnon, le serveur répond 409 et l'app le dit.
class MusicRootRepository {
  MusicRootRepository(this._client);

  final ApiClient _client;

  /// Les dossiers d'un chemin. Sans chemin : les points de départ.
  Future<VueDossier> parcourir({String? chemin}) async => VueDossier.fromJson(
        await _client.get(
          'musique-racine.php',
          query: {if (chemin != null && chemin.isNotEmpty) 'chemin': chemin},
        ) as Map<String, dynamic>,
      );

  /// Change la racine. Le serveur tombe aussitôt après : c'est le compagnon
  /// qui le relève, et son journal qu'on suit ensuite.
  Future<void> choisir(String chemin) =>
      _client.post('musique-racine.php', body: {'chemin': chemin});
}
