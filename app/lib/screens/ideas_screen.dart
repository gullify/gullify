import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/ideas.dart';

/// Carnet d'idées de développement : ajout rapide + liste cochable.
/// Partagé avec Claude (lit/écrit les mêmes idées côté serveur).
class IdeasScreen extends ConsumerStatefulWidget {
  const IdeasScreen({super.key});

  @override
  ConsumerState<IdeasScreen> createState() => _IdeasScreenState();
}

class _IdeasScreenState extends ConsumerState<IdeasScreen> {
  final _controller = TextEditingController();
  bool _adding = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    setState(() => _adding = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(ideasRepositoryProvider).add(text);
      _controller.clear();
      ref.invalidate(ideasProvider);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Échec : $e')));
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ideas = ref.watch(ideasProvider);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Mes idées')),
      body: Column(
        children: [
          // Ajout rapide.
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    minLines: 1,
                    maxLines: 4,
                    textInputAction: TextInputAction.newline,
                    decoration: const InputDecoration(
                      hintText: 'Une nouvelle idée…',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _adding
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : IconButton.filled(
                        icon: const Icon(Icons.add),
                        onPressed: _add,
                      ),
              ],
            ),
          ),
          Expanded(
            child: ideas.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Erreur : $e')),
              data: (list) {
                if (list.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text(
                        'Aucune idée pour l\'instant.\n'
                        'Note tes idées ici; dis à Claude « va voir mes '
                        'idées » depuis un ordinateur.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: scheme.onSurfaceVariant),
                      ),
                    ),
                  );
                }
                return RefreshIndicator(
                  onRefresh: () => ref.refresh(ideasProvider.future),
                  child: ListView.builder(
                    padding: EdgeInsets.only(
                      bottom: MediaQuery.paddingOf(context).bottom + 16,
                    ),
                    itemCount: list.length,
                    itemBuilder: (context, i) {
                      final idea = list[i];
                      return Dismissible(
                        key: ValueKey(idea.id),
                        direction: DismissDirection.endToStart,
                        background: Container(
                          color: scheme.errorContainer,
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 20),
                          child: Icon(Icons.delete, color: scheme.onErrorContainer),
                        ),
                        onDismissed: (_) async {
                          await ref
                              .read(ideasRepositoryProvider)
                              .delete(idea.id);
                          ref.invalidate(ideasProvider);
                        },
                        child: CheckboxListTile(
                          value: idea.done,
                          onChanged: (v) async {
                            await ref
                                .read(ideasRepositoryProvider)
                                .setDone(idea.id, v ?? false);
                            ref.invalidate(ideasProvider);
                          },
                          title: Text(
                            idea.text,
                            style: TextStyle(
                              decoration: idea.done
                                  ? TextDecoration.lineThrough
                                  : null,
                              color: idea.done ? scheme.onSurfaceVariant : null,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
