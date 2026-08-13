import 'package:dio/dio.dart';

import 'api_client.dart';

/// Un fichier joint à une idée (capture d'écran, maquette, log…).
class IdeaAttachment {
  const IdeaAttachment({
    required this.id,
    required this.name,
    required this.mime,
    required this.size,
    required this.url,
  });

  factory IdeaAttachment.fromJson(Map<String, dynamic> json) => IdeaAttachment(
        id: (json['id'] as num?)?.toInt() ?? 0,
        name: json['name'] as String? ?? 'fichier',
        mime: json['mime'] as String? ?? 'application/octet-stream',
        size: (json['size'] as num?)?.toInt() ?? 0,
        url: json['url'] as String? ?? '',
      );

  final int id;
  final String name;
  final String mime;
  final int size;

  /// URL relative au serveur (`serve_idea_file.php?id=…`).
  final String url;

  bool get isImage => mime.startsWith('image/');

  /// Taille lisible (« 1,4 Mo »).
  String get prettySize {
    if (size <= 0) return '';
    if (size < 1024) return '$size o';
    if (size < 1024 * 1024) return '${(size / 1024).round()} ko';
    return '${(size / (1024 * 1024)).toStringAsFixed(1).replaceAll('.', ',')} Mo';
  }
}

/// Une idée de développement (carnet partagé, stocké côté serveur).
class Idea {
  const Idea({
    required this.id,
    required this.text,
    required this.status,
    this.attachments = const [],
  });

  factory Idea.fromJson(Map<String, dynamic> json) => Idea(
        id: (json['id'] as num?)?.toInt() ?? 0,
        text: json['text'] as String? ?? '',
        status: json['status'] as String? ?? 'todo',
        attachments: (json['attachments'] as List<dynamic>? ?? [])
            .whereType<Map<String, dynamic>>()
            .map(IdeaAttachment.fromJson)
            .toList(),
      );

  final int id;
  final String text;

  /// 'todo' | 'requested' | 'in_progress' | 'needs_review' | 'done'
  final String status;

  /// Fichiers joints par Maxime pour illustrer l'idée (idée #84).
  final List<IdeaAttachment> attachments;

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

  /// Ajoute une idée et renvoie son id (0 si le serveur ne le dit pas).
  Future<int> add(String text) async {
    final data = await _client.post(
      'ideas.php',
      query: {'action': 'add'},
      body: {'text': text},
    );
    return data is Map<String, dynamic>
        ? (data['id'] as num?)?.toInt() ?? 0
        : 0;
  }

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

  /// Joint un fichier du téléphone à une idée (idée #84).
  Future<IdeaAttachment> addFile(
    int ideaId,
    String filePath,
    String name,
  ) async {
    final form = FormData();
    form.fields.add(MapEntry('idea_id', '$ideaId'));
    form.files.add(MapEntry(
      'file',
      await MultipartFile.fromFile(
        filePath,
        filename: name,
        contentType: DioMediaType.parse(mimeForName(name)),
      ),
    ));
    final data = await _client.post(
      'ideas.php',
      body: form,
      query: {'action': 'add_file'},
    );
    final json = data is Map<String, dynamic>
        ? data['attachment'] as Map<String, dynamic>?
        : null;
    if (json == null) {
      throw ApiException('upload', "Le serveur n'a pas confirmé l'envoi");
    }
    return IdeaAttachment.fromJson(json);
  }

  Future<void> deleteFile(int fileId) => _client.post(
        'ideas.php',
        query: {'action': 'delete_file'},
        body: {'id': fileId},
      );

  /// URL absolue d'une pièce jointe (les octets sont servis hors de l'API v2).
  /// Sans en-tête possible (ouverture dans le navigateur), passer [token].
  String fileUrl(IdeaAttachment attachment, {String? token}) {
    final base = _client.resourceUrl(attachment.url);
    return token == null || token.isEmpty
        ? base
        : '$base&token=${Uri.encodeQueryComponent(token)}';
  }
}

/// Type MIME déduit de l'extension — le serveur ne garde que ce qu'il sait
/// servir sans risque, mais l'app annonce quand même le bon type.
String mimeForName(String name) {
  final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
  return switch (ext) {
    'jpg' || 'jpeg' => 'image/jpeg',
    'png' => 'image/png',
    'webp' => 'image/webp',
    'gif' => 'image/gif',
    'heic' => 'image/heic',
    'pdf' => 'application/pdf',
    'json' => 'application/json',
    'csv' => 'text/csv',
    'txt' || 'log' || 'md' || 'dart' || 'php' => 'text/plain',
    _ => 'application/octet-stream',
  };
}
