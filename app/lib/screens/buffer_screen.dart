import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../audio/prefetch.dart';
import '../state/player.dart';
import 'settings_screen.dart' show formatBytes;

/// Réglage du tampon d'avance (idée #90) : les prochains titres de la file
/// descendent sur le disque pendant qu'on écoute, pour que la musique ne
/// s'arrête pas quand le réseau, lui, s'arrête.
class BufferScreen extends ConsumerWidget {
  const BufferScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final buffer = ref.watch(playbackBufferProvider);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Tampon d\'avance')),
      body: ListenableBuilder(
        listenable: buffer,
        builder: (context, _) {
          final on = buffer.ahead != 0;
          return ListView(
            children: [
              ListTile(
                leading: const Icon(Icons.cloud_download_outlined),
                title: const Text('Titres pris d\'avance'),
                subtitle: const Text(
                  'Descendus pendant que tu écoutes le titre précédent',
                ),
                trailing: Text(
                  buffer.ahead == kBufferAll
                      ? 'Toute la file'
                      : buffer.ahead == 0
                          ? 'Aucun'
                          : '${buffer.ahead}',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: on ? scheme.primary : scheme.outline,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Wrap(
                  spacing: 8,
                  children: [
                    for (final choice in kBufferAheadChoices)
                      ChoiceChip(
                        label: Text(switch (choice) {
                          0 => 'Aucun',
                          kBufferAll => 'Toute la file',
                          _ => '$choice',
                        }),
                        selected: buffer.ahead == choice,
                        onSelected: (_) => buffer.setAhead(choice),
                      ),
                  ],
                ),
              ),
              const Divider(height: 32),
              ListTile(
                enabled: on,
                leading: const Icon(Icons.sd_storage_outlined),
                title: const Text('Place réservée'),
                subtitle: const Text(
                  'Au-delà, les plus vieux titres du tampon s\'effacent',
                ),
                trailing: Text(
                  formatBytes(buffer.maxBytes),
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: on ? scheme.primary : scheme.outline,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Wrap(
                  spacing: 8,
                  children: [
                    for (final choice in kBufferMaxBytesChoices)
                      ChoiceChip(
                        label: Text(formatBytes(choice)),
                        selected: buffer.maxBytes == choice,
                        onSelected: on ? (_) => buffer.setMaxBytes(choice) : null,
                      ),
                  ],
                ),
              ),
              const Divider(height: 32),
              ListTile(
                leading: const Icon(Icons.inventory_2_outlined),
                title: const Text('En réserve'),
                subtitle: Text(
                  buffer.count == 0
                      ? 'Rien pour l\'instant'
                      : '${buffer.count} titre${buffer.count > 1 ? 's' : ''}'
                          ' · ${formatBytes(buffer.bytes)}',
                ),
                trailing: buffer.count == 0
                    ? null
                    : TextButton(
                        onPressed: buffer.clear,
                        child: const Text('Vider'),
                      ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                child: Text(
                  'Le lecteur garde déjà une minute de son sous le coude : de '
                  'quoi passer un trou de réseau, pas un tunnel. Comme la file '
                  'dit ce qui va être joué, le tampon descend les titres '
                  'suivants pendant que tu écoutes celui d\'avant — le moment '
                  'venu, ils se jouent depuis le téléphone, sans rien demander '
                  'au réseau.\n\n'
                  'Un titre à la fois, en arrière-plan, pour ne pas gêner ce '
                  'qui joue. Les titres déjà téléchargés ne sont pas repris, '
                  'et le tampon ne descend rien en mode karaoké — c\'est le '
                  'serveur qui rend ces versions-là. Une radio ou une '
                  'pré-écoute n\'a pas de suite : rien à prendre d\'avance. En '
                  'lecture aléatoire non plus : y changer la source d\'un '
                  'titre le replacerait au hasard dans le tirage, et il '
                  'pourrait ne jamais passer. Ce qui est déjà dans le tampon, '
                  'lui, sert dans tous les cas.\n\n'
                  'Le tampon se garde d\'une écoute à l\'autre et s\'efface '
                  'tout seul : les plus vieux titres partent quand la place '
                  'réservée est pleine, sauf ceux de la file en cours. Rien à '
                  'voir avec les téléchargements, qui restent, eux, tant que '
                  'tu ne les supprimes pas.',
                  style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
