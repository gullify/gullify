import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../api/admin_repository.dart';
import '../../state/admin.dart';
import '../../state/auth.dart';

/// Les comptes du serveur : qui existe, qui est administrateur, qui est
/// suspendu, et où chacun range sa musique.
///
/// Cette vue remplace la page d'administration du site web : c'était la
/// dernière chose qui obligeait à ouvrir un navigateur en plus de l'app.
class AdminUsersScreen extends ConsumerWidget {
  const AdminUsersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final users = ref.watch(adminUsersProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Utilisateurs'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Actualiser',
            onPressed: () => ref.invalidate(adminUsersProvider),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/settings/users/new'),
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text('Nouveau'),
      ),
      body: users.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _Error(
          message: '$e',
          onRetry: () => ref.invalidate(adminUsersProvider),
        ),
        data: (list) => RefreshIndicator(
          onRefresh: () async => ref.invalidate(adminUsersProvider),
          child: ListView.separated(
            padding: const EdgeInsets.only(bottom: 96),
            itemCount: list.length,
            separatorBuilder: (_, _) => const Divider(height: 1, indent: 72),
            itemBuilder: (context, i) => _UserRow(user: list[i]),
          ),
        ),
      ),
    );
  }
}

class _UserRow extends ConsumerWidget {
  const _UserRow({required this.user});

  final AdminUser user;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    // Son propre compte : le serveur en interdit la suppression, la
    // suspension et le changement de rôle. Autant le dire.
    final isSelf = ref.watch(authProvider).user?.id == user.id;

    final tags = [
      if (user.isAdmin) ('Administrateur', scheme.primary),
      if (!user.isActive) ('Suspendu', scheme.error),
      if (user.isSftp) ('SFTP', scheme.tertiary),
      if (isSelf) ('Vous', scheme.outline),
    ];

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: user.isActive
            ? scheme.primaryContainer
            : scheme.surfaceContainerHighest,
        foregroundColor: user.isActive
            ? scheme.onPrimaryContainer
            : scheme.onSurfaceVariant,
        child: Text(
          user.username.characters.first.toUpperCase(),
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      title: Text(
        user.displayName,
        style: TextStyle(
          fontWeight: FontWeight.w600,
          color: user.isActive ? null : scheme.onSurfaceVariant,
        ),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            user.musicDirectory ?? 'Aucun dossier de musique',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: user.musicDirectory == null ? scheme.error : null,
            ),
          ),
          if (tags.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (final (label, color) in tags) _Tag(label, color),
                ],
              ),
            ),
        ],
      ),
      isThreeLine: tags.isNotEmpty,
      trailing: const Icon(Icons.chevron_right),
      onTap: () => context.push('/settings/users/${user.id}', extra: user),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag(this.label, this.color);

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.14),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      label,
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: color,
      ),
    ),
  );
}

class _Error extends StatelessWidget {
  const _Error({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lock_outline, size: 40, color: scheme.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            FilledButton.tonal(
              onPressed: onRetry,
              child: const Text('Réessayer'),
            ),
          ],
        ),
      ),
    );
  }
}
