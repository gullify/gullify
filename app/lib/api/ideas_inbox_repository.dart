import 'api_client.dart';

/// Une idée reçue d'ailleurs, en attente dans la boîte du développeur.
class IdeeRecue {
  const IdeeRecue({
    required this.id,
    required this.serveur,
    required this.utilisateur,
    required this.texte,
    required this.recueLe,
  });

  factory IdeeRecue.fromJson(Map<String, dynamic> json) => IdeeRecue(
    id: (json['id'] as num?)?.toInt() ?? 0,
    serveur: json['serveur'] as String? ?? '',
    utilisateur: json['utilisateur'] as String? ?? '',
    texte: json['texte'] as String? ?? '',
    recueLe: json['recueLe'] as String? ?? '',
  );

  final int id;

  /// D'où elle vient : l'adresse du serveur, et le nom de qui l'a écrite.
  /// Vides si ce serveur-là ne les a pas donnés.
  final String serveur;
  final String utilisateur;

  final String texte;
  final String recueLe;

  /// « bob · chez-eux.ca », ou ce qu'on en sait.
  String get provenance {
    final hote = serveur
        .replaceFirst(RegExp(r'^https?://'), '')
        .replaceFirst(RegExp(r'/$'), '');
    if (utilisateur.isEmpty && hote.isEmpty) return 'origine inconnue';
    if (hote.isEmpty) return utilisateur;
    if (utilisateur.isEmpty) return hote;
    return '$utilisateur · $hote';
  }
}

/// La boîte du développeur : ce que les autres serveurs lui ont envoyé.
///
/// Un seul compte peut la lire — celui que le serveur désigne. Pour tous les
/// autres, et sur tous les serveurs qui ne sont pas une boîte, [list] rend
/// une liste vide plutôt qu'une erreur : ce n'est pas une panne de ne pas
/// être le développeur.
class IdeasInboxRepository {
  IdeasInboxRepository(this._client);

  final ApiClient _client;

  static const _endpoint = 'ideas-inbox.php';

  Future<List<IdeeRecue>> list() async {
    try {
      final data = await _client.get(_endpoint, query: {'action': 'list'})
          as Map<String, dynamic>;
      return (data['idees'] as List<dynamic>? ?? [])
          .cast<Map<String, dynamic>>()
          .map(IdeeRecue.fromJson)
          .toList();
    } on ApiException catch (e) {
      // 403 : la boîte n'est pas la vôtre. 404 : ce serveur n'en est pas une.
      if (e.statusCode == 403 || e.statusCode == 404) return const [];
      rethrow;
    }
  }

  /// Verse l'idée dans le carnet du développeur, d'où il pourra la confier
  /// à Claude comme les siennes.
  Future<void> adopter(int id) =>
      _client.post(_endpoint, query: {'action': 'adopter'}, body: {'id': id});

  Future<void> rejeter(int id) =>
      _client.post(_endpoint, query: {'action': 'rejeter'}, body: {'id': id});
}
