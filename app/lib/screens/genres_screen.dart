import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/library.dart';

/// Gestion des genres : renommer (partout) ou supprimer (mise à NULL).
class GenresScreen extends ConsumerWidget {
  const GenresScreen({super.key});

  Future<void> _rename(BuildContext context, WidgetRef ref, String from) async {
    final controller = TextEditingController(text: from);
    final to = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Renommer le genre'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Nouveau nom'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Renommer'),
          ),
        ],
      ),
    );
    if (to == null || to.isEmpty || to == from) return;
    await ref.read(libraryRepositoryProvider).renameGenre(from, to);
    _invalidate(ref);
  }

  Future<void> _delete(BuildContext context, WidgetRef ref, String genre) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Supprimer le genre « $genre » ?'),
        content: const Text(
          'Le genre sera retiré de tous les albums et artistes concernés '
          '(les titres, eux, ne sont pas supprimés).',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(libraryRepositoryProvider).deleteGenre(genre);
    _invalidate(ref);
  }

  void _invalidate(WidgetRef ref) {
    ref.invalidate(genresProvider);
    ref.invalidate(artistsProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final genres = ref.watch(genresProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Gérer les genres')),
      body: genres.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Erreur : $e')),
        data: (list) {
          if (list.isEmpty) {
            return const Center(child: Text('Aucun genre'));
          }
          return ListView.separated(
            padding: EdgeInsets.only(
              bottom: MediaQuery.paddingOf(context).bottom + 16,
            ),
            itemCount: list.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final g = list[i];
              return ListTile(
                leading: const Icon(Icons.label_outline),
                title: Text(g.name),
                subtitle: Text(
                  '${g.artistCount} artiste${g.artistCount > 1 ? 's' : ''}',
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'Renommer',
                      icon: const Icon(Icons.edit_outlined),
                      onPressed: () => _rename(context, ref, g.name),
                    ),
                    IconButton(
                      tooltip: 'Supprimer',
                      icon: Icon(Icons.delete_outline,
                          color: Theme.of(context).colorScheme.error),
                      onPressed: () => _delete(context, ref, g.name),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
