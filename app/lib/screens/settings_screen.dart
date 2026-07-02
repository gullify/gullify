import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../state/auth.dart';
import '../state/equalizer.dart';
import '../state/offline.dart';

const appVersion = '2.0.0';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    final offline = ref.watch(offlineProvider).value ?? {};

    return Scaffold(
      appBar: AppBar(title: const Text('Paramètres')),
      body: ListView(
        children: [
          const _SectionHeader('Compte'),
          ListTile(
            leading: const Icon(Icons.person_outline),
            title: Text(auth.user?.fullName ?? auth.user?.username ?? ''),
            subtitle: auth.user != null ? Text(auth.user!.username) : null,
          ),
          ListTile(
            leading: const Icon(Icons.dns_outlined),
            title: const Text('Serveur'),
            subtitle: Text(auth.serverUrl ?? ''),
          ),
          ListTile(
            leading: const Icon(Icons.swap_horiz),
            title: const Text('Changer de serveur'),
            onTap: () => _confirm(
              context,
              'Changer de serveur ?',
              'Vous serez déconnecté et devrez saisir une nouvelle adresse.',
              () => ref.read(authProvider.notifier).changeServer(),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.logout),
            title: const Text('Déconnexion'),
            onTap: () => _confirm(
              context,
              'Se déconnecter ?',
              null,
              () => ref.read(authProvider.notifier).logout(),
            ),
          ),
          const Divider(),
          if (equalizerSupported || offlineSupported)
            const _SectionHeader('Lecture'),
          if (equalizerSupported)
            ListTile(
              leading: const Icon(Icons.equalizer),
              title: const Text('Égaliseur'),
              onTap: () => context.push('/settings/equalizer'),
            ),
          if (offlineSupported)
            ListTile(
              leading: const Icon(Icons.download_outlined),
              title: const Text('Téléchargements'),
              subtitle: Text(
                '${offline.length} titre${offline.length > 1 ? 's' : ''}'
                ' · ${formatBytes(ref.read(offlineProvider.notifier).totalSize())}',
              ),
              onTap: () => context.push('/settings/downloads'),
            ),
          if (equalizerSupported || offlineSupported) const Divider(),
          const _SectionHeader('À propos'),
          const ListTile(
            leading: Icon(Icons.info_outline),
            title: Text('Gullify'),
            subtitle: Text('Version $appVersion'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirm(
    BuildContext context,
    String title,
    String? message,
    Future<void> Function() action,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: message != null ? Text(message) : null,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirmer'),
          ),
        ],
      ),
    );
    if (ok == true) await action();
  }
}

String formatBytes(int bytes) {
  if (bytes >= 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} Go';
  }
  if (bytes >= 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} Mo';
  }
  return '${(bytes / 1024).toStringAsFixed(0)} Ko';
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}
