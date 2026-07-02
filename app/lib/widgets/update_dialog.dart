import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/app_update.dart';

/// Dialogue de mise à jour : changelog, puis progression du téléchargement.
/// L'installation est déléguée à l'installeur système Android.
Future<void> showUpdateDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (context) => const _UpdateDialog(),
  );
}

class _UpdateDialog extends ConsumerWidget {
  const _UpdateDialog();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final update = ref.watch(appUpdateProvider);
    final info = update.available;
    if (info == null) return const SizedBox.shrink();

    final downloading = update.status == UpdateStatus.downloading;

    return AlertDialog(
      title: Text('Mise à jour ${info.versionName}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (info.changelog != null && info.changelog!.isNotEmpty)
            Flexible(
              child: SingleChildScrollView(
                child: Text(info.changelog!),
              ),
            ),
          if (downloading) ...[
            const SizedBox(height: 16),
            LinearProgressIndicator(value: update.progress),
            const SizedBox(height: 8),
            Text(
              update.progress != null
                  ? '${(update.progress! * 100).round()} %'
                  : 'Téléchargement…',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          if (update.status == UpdateStatus.error) ...[
            const SizedBox(height: 16),
            Text(
              update.message ?? 'Une erreur est survenue',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          if (update.status == UpdateStatus.readyToInstall) ...[
            const SizedBox(height: 16),
            const Text(
              "Si l'installation ne s'est pas ouverte, autorisez "
              "« installer des applications inconnues » pour Gullify "
              'puis réessayez.',
            ),
          ],
        ],
      ),
      actions: [
        if (!downloading)
          TextButton(
            onPressed: () {
              ref.read(appUpdateProvider.notifier).dismiss();
              Navigator.pop(context);
            },
            child: const Text('Plus tard'),
          ),
        if (update.status == UpdateStatus.available ||
            update.status == UpdateStatus.error)
          FilledButton(
            onPressed: () =>
                ref.read(appUpdateProvider.notifier).downloadAndInstall(),
            child: const Text('Installer'),
          ),
        if (update.status == UpdateStatus.readyToInstall)
          FilledButton(
            onPressed: () => ref.read(appUpdateProvider.notifier).install(),
            child: const Text('Réessayer'),
          ),
      ],
    );
  }
}
