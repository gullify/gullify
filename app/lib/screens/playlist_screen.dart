import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../state/player.dart';
import '../state/playlists.dart';
import '../widgets/mini_player.dart';
import '../widgets/song_menu.dart';
import '../widgets/song_tile.dart';

class PlaylistScreen extends ConsumerWidget {
  const PlaylistScreen({
    super.key,
    required this.playlistId,
    required this.name,
  });

  final int playlistId;
  final String name;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries = ref.watch(playlistSongsProvider(playlistId));
    final actions = ref.read(playlistActionsProvider);

    return Scaffold(
      bottomNavigationBar: const MiniPlayer(),
      appBar: AppBar(
        title: Text(name),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) async {
              switch (value) {
                case 'rename':
                  final newName =
                      await promptPlaylistName(context, initial: name);
                  if (newName == null) return;
                  await actions.rename(playlistId, newName);
                  if (context.mounted) {
                    context.pushReplacement(
                      '/playlist/$playlistId?name=${Uri.encodeQueryComponent(newName)}',
                    );
                  }
                case 'delete':
                  await actions.delete(playlistId);
                  if (context.mounted) context.pop();
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'rename', child: Text('Renommer')),
              PopupMenuItem(value: 'delete', child: Text('Supprimer')),
            ],
          ),
        ],
      ),
      body: entries.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Erreur: $e')),
        data: (list) {
          if (list.isEmpty) {
            return const Center(child: Text('Playlist vide'));
          }
          final songs = [for (final e in list) e.song];
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        icon: const Icon(Icons.play_arrow),
                        label: const Text('Lecture'),
                        onPressed: () =>
                            ref.read(playerActionsProvider).playSongs(songs),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.outlined(
                      tooltip: 'Lecture aléatoire',
                      icon: const Icon(Icons.shuffle),
                      onPressed: () => ref
                          .read(playerActionsProvider)
                          .playSongs(songs.toList()..shuffle()),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: list.length,
                  itemBuilder: (context, i) => Dismissible(
                    key: ValueKey(list[i].playlistSongId),
                    direction: DismissDirection.endToStart,
                    background: Container(
                      color: Theme.of(context).colorScheme.errorContainer,
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.only(right: 20),
                      child: const Icon(Icons.delete),
                    ),
                    onDismissed: (_) => actions.removeSong(
                      playlistId,
                      list[i].playlistSongId,
                    ),
                    child: SongTile(
                      song: list[i].song,
                      onTap: () => ref
                          .read(playerActionsProvider)
                          .playSongs(songs, startIndex: i),
                      onLongPress: () => showSongMenu(context, list[i].song),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
