import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../api/notifications_repository.dart';
import '../state/notifications.dart';
import '../widgets/glass_box.dart';
import '../widgets/mascot_empty.dart';

/// Le carnet d'idées vit sous les paramètres — c'est là que mènent les
/// notifications de Claude.
const _ideasRoute = '/settings/ideas';

/// Apparence d'une notification selon son type : une icône, une couleur, et
/// l'écran vers lequel elle mène. Tout ce qui n'est pas connu retombe sur
/// l'info neutre — une notification inattendue reste lisible.
({IconData icon, Color? color, String? route}) _look(
  String type,
  ColorScheme scheme,
) =>
    switch (type) {
      'idea_done' => (
          icon: Icons.auto_awesome,
          color: scheme.primary,
          route: _ideasRoute,
        ),
      'idea_review' => (
          icon: Icons.help_outline,
          color: scheme.tertiary,
          route: _ideasRoute,
        ),
      'ideas_paused' => (
          icon: Icons.pause_circle_outline,
          color: scheme.error,
          route: _ideasRoute,
        ),
      'error' => (icon: Icons.error_outline, color: scheme.error, route: null),
      'warning' => (
          icon: Icons.warning_amber,
          color: scheme.tertiary,
          route: null,
        ),
      'scan' => (
          icon: Icons.library_music_outlined,
          color: scheme.primary,
          route: null,
        ),
      _ => (icon: Icons.info_outline, color: null, route: null),
    };

/// « il y a 3 h » plutôt qu'une date brute : ce qui compte, sur une
/// notification, c'est sa fraîcheur.
String _ago(String? createdAt) {
  if (createdAt == null) return '';
  // MySQL rend « 2026-08-04 11:20:06 », à l'heure du serveur.
  final at = DateTime.tryParse(createdAt.replaceFirst(' ', 'T'));
  if (at == null) return createdAt.split(' ').first;
  final d = DateTime.now().difference(at);
  if (d.isNegative || d.inMinutes < 1) return "à l'instant";
  if (d.inMinutes < 60) return 'il y a ${d.inMinutes} min';
  if (d.inHours < 24) return 'il y a ${d.inHours} h';
  if (d.inDays < 7) return 'il y a ${d.inDays} j';
  return createdAt.split(' ').first;
}

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
            return const MascotEmpty(message: 'Aucune notification');
          }
          return RefreshIndicator(
            onRefresh: () => ref.refresh(notificationsProvider.future),
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
              itemCount: p.items.length,
              itemBuilder: (context, i) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _NotificationCard(notification: p.items[i]),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Une notification en carte de verre : icône colorée par type, titre en gras
/// tant qu'elle n'est pas lue, et un tap qui la marque lue puis ouvre l'écran
/// concerné (le carnet d'idées, pour tout ce qui vient de Claude).
class _NotificationCard extends ConsumerWidget {
  const _NotificationCard({required this.notification});

  final AppNotification notification;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final look = _look(notification.type, scheme);
    final unread = !notification.isRead;

    return GlassBox(
      radius: 18,
      blur: false,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () async {
          // Le routeur est saisi avant l'aller-retour serveur : passé l'await,
          // le contexte de la carte peut avoir disparu (liste rebâtie).
          final router = GoRouter.maybeOf(context);
          if (unread) {
            await ref
                .read(notificationsRepositoryProvider)
                .markRead(notification.id);
            ref.invalidate(notificationsProvider);
          }
          if (look.route != null) router?.push(look.route!);
        },
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                look.icon,
                color: unread
                    ? (look.color ?? scheme.primary)
                    : scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            notification.title,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight:
                                  unread ? FontWeight.w700 : FontWeight.w500,
                              letterSpacing: -0.2,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _ago(notification.createdAt),
                          style: TextStyle(
                            fontSize: 11,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                    if ((notification.message ?? '').isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        notification.message!,
                        maxLines: 5,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.3,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    if (look.route == _ideasRoute) ...[
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(Icons.lightbulb_outline,
                              size: 14, color: scheme.primary),
                          const SizedBox(width: 4),
                          Text(
                            'Voir le carnet d\'idées',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: scheme.primary,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
