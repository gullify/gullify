import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/offline.dart';
import '../state/player.dart';
import '../widgets/play_pair.dart';
import '../widgets/song_tile.dart';
import '../widgets/mascot_empty.dart';
import 'settings_screen.dart' show formatBytes;

class DownloadsScreen extends ConsumerWidget {
  const DownloadsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final offline = ref.watch(offlineProvider).value ?? {};
    final songs = [for (final o in offline.values) o.song]
      ..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Téléchargements'),
        actions: [
          if (offline.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep_outlined),
              tooltip: 'Tout supprimer',
              onPressed: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Supprimer tous les téléchargements ?'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Annuler'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('Supprimer'),
                      ),
                    ],
                  ),
                );
                if (ok == true) {
                  await ref.read(offlineProvider.notifier).clear();
                }
              },
            ),
        ],
      ),
      body: songs.isEmpty
          ? const MascotEmpty(
              message: 'Aucun titre téléchargé',
              hint: 'Télécharge des titres pour les écouter hors-ligne.',
            )
          : ListView.builder(
              itemCount: songs.length + 1,
              itemBuilder: (context, i) {
                // Ce qui est déjà sur le téléphone se lance sans rien
                // charger : la paire est en tête, comme sur les favoris.
                if (i == 0) {
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                    child: PaireDeLecture(
                      vide: 'Aucun titre téléchargé',
                      titres: ({required bool shuffle}) async =>
                          shuffle ? (songs.toList()..shuffle()) : songs,
                    ),
                  );
                }
                final song = songs[i - 1];
                final size = offline[song.id]?.size ?? 0;
                return SongTile(
                  song: song,
                  subtitle:
                      '${song.artistName ?? ''} · ${formatBytes(size)}',
                  onTap: () => ref
                      .read(playerActionsProvider)
                      .playSongs(songs, startIndex: i - 1),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () =>
                        ref.read(offlineProvider.notifier).remove(song.id),
                  ),
                );
              },
            ),
    );
  }
}
