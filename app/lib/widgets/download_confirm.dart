import 'package:flutter/material.dart';

import '../api/yt_downloads_repository.dart';

/// Fenêtre de confirmation d'un téléchargement YouTube Music.
///
/// Quand le serveur a reconnu un doublon (album déjà dans la bibliothèque,
/// titre déjà là, ou téléchargement déjà en file), il est annoncé ici : on ne
/// retélécharge plus par distraction. Un doublon déjà EN FILE ne se force
/// jamais — deux yt-dlp qui écrivent le même dossier en même temps, c'est
/// justement ce qui fabriquait les pistes en double.
///
/// Renvoie true si l'utilisateur veut lancer le téléchargement.
Future<bool> showDownloadConfirm(
  BuildContext context, {
  required String title,
  required String subtitle,
  String details = '',
  required String body,
  YtDuplicate? duplicate,
}) async {
  final blocked = duplicate?.isQueued ?? false;

  final ok = await showDialog<bool>(
    context: context,
    builder: (context) {
      final theme = Theme.of(context);
      return AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(subtitle),
            if (details.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(details, style: theme.textTheme.bodySmall),
            ],
            const SizedBox(height: 12),
            if (duplicate != null)
              _DuplicateNotice(duplicate: duplicate)
            else
              Text(body),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(blocked ? 'Fermer' : 'Annuler'),
          ),
          if (!blocked)
            FilledButton.icon(
              onPressed: () => Navigator.pop(context, true),
              icon: const Icon(Icons.download),
              label: Text(
                duplicate == null ? 'Télécharger' : 'Télécharger quand même',
              ),
            ),
        ],
      );
    },
  );
  return ok == true;
}

/// Encart d'avertissement : ce qui est déjà là, et ce qu'il se passe si on
/// insiste malgré tout.
class _DuplicateNotice extends StatelessWidget {
  const _DuplicateNotice({required this.duplicate});

  final YtDuplicate duplicate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.tertiaryContainer.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            duplicate.isQueued ? Icons.downloading : Icons.library_add_check,
            size: 20,
            color: scheme.onTertiaryContainer,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  duplicate.message,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: scheme.onTertiaryContainer),
                ),
                const SizedBox(height: 4),
                Text(
                  duplicate.isQueued
                      ? 'Suivez-le dans l\'onglet Téléchargements.'
                      : 'Le retélécharger écrase les fichiers existants.',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: scheme.onTertiaryContainer),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Pastille « Déjà dans la bibliothèque » posée sur un résultat de recherche.
class InLibraryBadge extends StatelessWidget {
  const InLibraryBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: scheme.tertiaryContainer.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check, size: 12, color: scheme.onTertiaryContainer),
          const SizedBox(width: 4),
          Text(
            'Déjà là',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: scheme.onTertiaryContainer,
                  fontWeight: FontWeight.w600,
                ),
          ),
        ],
      ),
    );
  }
}
