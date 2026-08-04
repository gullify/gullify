import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import '../api/library_repository.dart';
import '../state/library.dart';

/// Gestion des genres : en ajouter un que la liste principale ne couvre pas,
/// renommer (partout) ou supprimer (mise à NULL).
///
/// La liste montre les genres de la bibliothèque, et à leur suite ceux qu'on a
/// ajoutés sans encore les avoir donnés à personne — sans quoi un genre tout
/// juste créé n'apparaîtrait nulle part.
class GenresScreen extends ConsumerWidget {
  const GenresScreen({super.key});

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Ajouter un genre'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'Nom du genre',
            hintText: 'Ce que la liste ne couvre pas…',
          ),
          onSubmitted: (v) => Navigator.pop(context, v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Ajouter'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty || !context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(libraryRepositoryProvider).addGenre(name);
    } on ApiException catch (e) {
      // Le serveur dit lui-même ce qui cloche (nom vide, genre déjà là).
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
      return;
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Échec : $e')));
      return;
    }
    _invalidate(ref);
    messenger.showSnackBar(SnackBar(content: Text('Genre « $name » ajouté')));
  }

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

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    GenreCount genre,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Supprimer le genre « ${genre.name} » ?'),
        content: Text(
          genre.artistCount == 0
              ? 'Le genre sera retiré de la liste. Personne ne le porte : '
                  'rien d\'autre ne change.'
              : 'Le genre sera retiré de tous les albums et artistes concernés '
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
    await ref.read(libraryRepositoryProvider).deleteGenre(genre.name);
    _invalidate(ref);
  }

  void _invalidate(WidgetRef ref) {
    ref.invalidate(genresProvider);
    ref.invalidate(genreTaxonomyProvider);
    ref.invalidate(artistsProvider);
  }

  /// Les genres de la bibliothèque, puis ceux qu'on a ajoutés et qui n'ont
  /// pas encore d'artiste.
  List<GenreCount> _entries(List<GenreCount> inLibrary, List<String> custom) {
    final known = {for (final g in inLibrary) g.name};

    return [
      ...inLibrary,
      for (final name in custom)
        if (!known.contains(name)) GenreCount(name, 0),
    ];
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final genres = ref.watch(genresProvider);
    // Les genres ajoutés à la main ne valent pas d'écran d'erreur : la liste
    // de la bibliothèque reste lisible sans eux.
    final custom = ref.watch(genreTaxonomyProvider).value?.custom ?? const [];

    return Scaffold(
      appBar: AppBar(title: const Text('Gérer les genres')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _add(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('Ajouter'),
      ),
      body: genres.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Erreur : $e')),
        data: (inLibrary) {
          final list = _entries(inLibrary, custom);
          if (list.isEmpty) {
            return const Center(child: Text('Aucun genre'));
          }
          return ListView.separated(
            padding: EdgeInsets.only(
              bottom: MediaQuery.paddingOf(context).bottom + 88,
            ),
            itemCount: list.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final g = list[i];
              return ListTile(
                leading: const Icon(Icons.label_outline),
                title: Text(g.name),
                subtitle: Text(
                  g.artistCount == 0
                      ? 'Aucun artiste'
                      : '${g.artistCount} artiste${g.artistCount > 1 ? 's' : ''}',
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
                      onPressed: () => _delete(context, ref, g),
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
