import 'api_client.dart';

class AppNotification {
  const AppNotification({
    required this.id,
    required this.type,
    required this.title,
    this.message,
    this.readAt,
    this.createdAt,
  });

  final int id;
  final String type;
  final String title;
  final String? message;
  final String? readAt;
  final String? createdAt;

  bool get isRead => readAt != null;
}

class NotificationsPage {
  const NotificationsPage({required this.items, required this.unread});

  final List<AppNotification> items;
  final int unread;
}

class NotificationsRepository {
  NotificationsRepository(this._client);

  final ApiClient _client;

  Future<NotificationsPage> list({int limit = 30}) async {
    final data = await _client.get('notifications.php', query: {
      'action': 'list',
      'limit': limit,
    }) as Map<String, dynamic>;
    return NotificationsPage(
      items: [
        for (final e in (data['data'] as List<dynamic>? ?? [])
            .cast<Map<String, dynamic>>())
          AppNotification(
            id: (e['id'] as num).toInt(),
            type: e['type'] as String? ?? 'info',
            title: e['title'] as String? ?? '',
            message: e['message'] as String?,
            readAt: e['read_at'] as String?,
            createdAt: e['created_at'] as String?,
          ),
      ],
      unread: (data['unread'] as num?)?.toInt() ?? 0,
    );
  }

  /// id = 0 marks everything as read.
  Future<void> markRead(int id) => _client.post(
        'notifications.php',
        query: {'action': 'mark_read', 'id': id},
      );

  /// id = 0 clears everything.
  Future<void> clear(int id) => _client.post(
        'notifications.php',
        query: {'action': 'clear', 'id': id},
      );
}
