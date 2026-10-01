import 'api_client.dart';

/// Où en est le serveur : sa version, celle qui est publiée, et s'il sait se
/// mettre à jour tout seul.
///
/// Un serveur posé par l'installateur ne contient pas le code — il tire une
/// image déjà construite, et un petit service à côté de lui la remplace sur
/// demande. Un serveur installé depuis le dépôt de code, lui, se met à jour
/// par `./update.sh` sur sa machine : [possible] est alors faux et l'app ne
/// propose pas de bouton qui ne marcherait pas.
class ServerUpdate {
  const ServerUpdate({
    required this.installee,
    required this.disponible,
    required this.aJour,
    required this.possible,
    required this.enCours,
    required this.journal,
  });

  factory ServerUpdate.fromJson(Map<String, dynamic> json) => ServerUpdate(
    installee: json['installee'] as String?,
    disponible: json['disponible'] as String?,
    aJour: json['aJour'] as bool?,
    possible: json['possible'] as bool? ?? false,
    enCours: json['enCours'] as bool? ?? false,
    journal: (json['journal'] as List?)?.cast<String>() ?? const [],
  );

  /// La version de ce serveur, ou null s'il a été construit à la main.
  final String? installee;

  /// La plus haute version publiée, ou null si le dépôt n'a pas répondu.
  final String? disponible;

  /// Null quand on ne sait pas : ne pas savoir n'est pas être à jour.
  final bool? aJour;

  final bool possible;
  final bool enCours;
  final List<String> journal;

  /// Une mise à jour n'est offerte que si l'on sait qu'elle existe ET que le
  /// serveur sait la faire.
  bool get offerte => possible && aJour == false;
}

class UpdateRepository {
  UpdateRepository(this._client);

  final ApiClient _client;

  Future<ServerUpdate> etat() async =>
      ServerUpdate.fromJson(await _client.get('update.php') as Map<String, dynamic>);

  /// Demande un geste au compagnon qui tourne sur la machine du serveur :
  /// `maj` pour aller chercher la version suivante, `redemarrer` pour
  /// simplement relever le serveur.
  Future<void> lancer({String action = 'maj'}) async =>
      _client.post('update.php', body: {'action': action});
}
