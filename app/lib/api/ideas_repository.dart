import 'api_client.dart';

/// Une idée de développement (carnet partagé, stocké côté serveur).
class Idea {
  const Idea({
    required this.id,
    required this.text,
    required this.done,
  });

  factory Idea.fromJson(Map<String, dynamic> json) => Idea(
        id: (json['id'] as num?)?.toInt() ?? 0,
        text: json['text'] as String? ?? '',
        done: (json['status'] as String?) == 'done',
      );

  final int id;
  final String text;
  final bool done;
}

class IdeasRepository {
  IdeasRepository(this._client);

  final ApiClient _client;

  Future<List<Idea>> list() async {
    final data = await _client.get('ideas.php', query: {'action': 'list'})
        as Map<String, dynamic>;
    return (data['ideas'] as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>>()
        .map(Idea.fromJson)
        .toList();
  }

  Future<void> add(String text) => _client.post(
        'ideas.php',
        query: {'action': 'add'},
        body: {'text': text},
      );

  Future<void> setDone(int id, bool done) => _client.post(
        'ideas.php',
        query: {'action': 'set_status'},
        body: {'id': id, 'status': done ? 'done' : 'todo'},
      );

  Future<void> update(int id, String text) => _client.post(
        'ideas.php',
        query: {'action': 'update'},
        body: {'id': id, 'text': text},
      );

  Future<void> delete(int id) => _client.post(
        'ideas.php',
        query: {'action': 'delete'},
        body: {'id': id},
      );
}
