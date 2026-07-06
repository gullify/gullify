import 'api_client.dart';

/// Une idée de développement (carnet partagé, stocké côté serveur).
class Idea {
  const Idea({
    required this.id,
    required this.text,
    required this.status,
  });

  factory Idea.fromJson(Map<String, dynamic> json) => Idea(
        id: (json['id'] as num?)?.toInt() ?? 0,
        text: json['text'] as String? ?? '',
        status: json['status'] as String? ?? 'todo',
      );

  final int id;
  final String text;

  /// 'todo' | 'requested' | 'in_progress' | 'needs_review' | 'done'
  final String status;

  bool get done => status == 'done';
  bool get pending => status == 'requested' || status == 'in_progress';
  bool get needsReview => status == 'needs_review';
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

  /// Confie l'idée à Claude (le cron serveur la réalisera).
  Future<void> request(int id) => _client.post(
        'ideas.php',
        query: {'action': 'request'},
        body: {'id': id},
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
