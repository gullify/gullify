import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/player.dart';

/// La file d'attente : ce qui passe, ce qui suit, dans l'ordre. On y saute à
/// un titre, on la réordonne à la poignée, on en retire un titre d'un geste.
///
/// Partagée par la feuille du téléphone et le panneau du lecteur sur grand
/// écran : une seule liste à entretenir.
class QueueList extends ConsumerWidget {
  const QueueList({super.key, this.scrollController, this.showHeader = true});

  final ScrollController? scrollController;

  /// L'en-tête « File d'attente · N » et son bouton « Vider ». Le panneau du
  /// grand écran le garde ; il pourrait s'en passer sous un onglet déjà nommé.
  final bool showHeader;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final queue = ref.watch(queueProvider).value ?? [];
    final currentId = ref.watch(currentMediaItemProvider).value?.id;
    final actions = ref.read(playerActionsProvider);
    final scheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        if (showHeader)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
            child: Row(
              children: [
                Text(
                  "File d'attente · ${queue.length}",
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: queue.length > 1
                      ? () => actions.clearQueue()
                      : null,
                  icon: const Icon(Icons.clear_all, size: 18),
                  label: const Text('Vider'),
                ),
              ],
            ),
          ),
        Expanded(
          child: ReorderableListView.builder(
            scrollController: scrollController,
            // La poignée est dessinée à droite de chaque titre. Sur un
            // ordinateur, Flutter en ajouterait une seconde : on l'en empêche.
            // Au téléphone, sa « poignée » à lui est l'appui long pour
            // déplacer un titre — celle-là, on la garde.
            buildDefaultDragHandles: switch (Theme.of(context).platform) {
              TargetPlatform.android ||
              TargetPlatform.iOS ||
              TargetPlatform.fuchsia => true,
              _ => false,
            },
            itemCount: queue.length,
            onReorderItem: (from, to) => actions.moveQueueItem(from, to),
            itemBuilder: (context, i) {
              final q = queue[i];
              final isCurrent = q.id == currentId;
              return Dismissible(
                key: ValueKey('queue-$i-${q.id}'),
                direction: isCurrent
                    ? DismissDirection.none
                    : DismissDirection.endToStart,
                background: Container(
                  color: scheme.errorContainer,
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 20),
                  child: const Icon(Icons.close),
                ),
                onDismissed: (_) => actions.removeQueueItemAt(i),
                child: ListTile(
                  leading: isCurrent
                      ? Icon(Icons.graphic_eq, color: scheme.primary)
                      : Text(
                          '${i + 1}',
                          style: TextStyle(color: scheme.onSurfaceVariant),
                        ),
                  title: Text(
                    q.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: isCurrent
                        ? TextStyle(
                            color: scheme.primary,
                            fontWeight: FontWeight.w600,
                          )
                        : null,
                  ),
                  subtitle: q.artist != null ? Text(q.artist!) : null,
                  trailing: ReorderableDragStartListener(
                    index: i,
                    child: Icon(Icons.drag_handle, color: scheme.outline),
                  ),
                  onTap: () => actions.skipToQueueItem(i),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
