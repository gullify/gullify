import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/notifications.dart';

class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final page = ref.watch(notificationsProvider);
    final repo = ref.read(notificationsRepositoryProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          IconButton(
            icon: const Icon(Icons.done_all),
            tooltip: 'Tout marquer comme lu',
            onPressed: () async {
              await repo.markRead(0);
              ref.invalidate(notificationsProvider);
            },
          ),
          IconButton(
            icon: const Icon(Icons.delete_sweep_outlined),
            tooltip: 'Tout effacer',
            onPressed: () async {
              await repo.clear(0);
              ref.invalidate(notificationsProvider);
            },
          ),
        ],
      ),
      body: page.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Erreur: $e')),
        data: (p) {
          if (p.items.isEmpty) {
            return const Center(child: Text('Aucune notification'));
          }
          return RefreshIndicator(
            onRefresh: () => ref.refresh(notificationsProvider.future),
            child: ListView.builder(
              itemCount: p.items.length,
              itemBuilder: (context, i) {
                final n = p.items[i];
                return ListTile(
                  leading: Icon(
                    switch (n.type) {
                      'error' => Icons.error_outline,
                      'warning' => Icons.warning_amber,
                      'scan' => Icons.library_music_outlined,
                      _ => Icons.info_outline,
                    },
                    color: n.isRead
                        ? Theme.of(context).colorScheme.onSurfaceVariant
                        : Theme.of(context).colorScheme.primary,
                  ),
                  title: Text(
                    n.title,
                    style: n.isRead
                        ? null
                        : const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: n.message != null ? Text(n.message!) : null,
                  trailing: n.createdAt != null
                      ? Text(
                          n.createdAt!.split(' ').first,
                          style: TextStyle(
                            fontSize: 11,
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        )
                      : null,
                  onTap: n.isRead
                      ? null
                      : () async {
                          await repo.markRead(n.id);
                          ref.invalidate(notificationsProvider);
                        },
                );
              },
            ),
          );
        },
      ),
    );
  }
}
