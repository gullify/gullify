import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/library.dart';
import '../state/player.dart';
import '../widgets/glass_kit.dart';
import 'shell_screen.dart';
import '../widgets/song_menu.dart';
import '../widgets/song_tile.dart';

/// Liste complète des titres les plus écoutés (90 derniers jours), avec
/// « Lecture » et « Lecture aléatoire ».
class PopularScreen extends ConsumerWidget {
  const PopularScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final popular = ref.watch(popularSongsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Les plus populaires')),
      bottomNavigationBar: const DetailDock(),
      body: popular.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Erreur: $e')),
        data: (songs) {
          if (songs.isEmpty) {
            return const Center(child: Text('Rien pour l\'instant'));
          }
          final actions = ref.read(playerActionsProvider);
          return ListView.builder(
            padding: EdgeInsets.only(
              bottom: MediaQuery.paddingOf(context).bottom + 12,
            ),
            itemCount: songs.length + 1,
            itemBuilder: (context, i) {
              if (i == 0) {
                return Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: AccentPlayButton(
                          onPressed: () => actions.playSongs(songs),
                        ),
                      ),
                      const SizedBox(width: 12),
                      GlassIconButton(
                        icon: Icons.shuffle,
                        tooltip: 'Lecture aléatoire',
                        size: 50,
                        onPressed: () =>
                            actions.playSongs(songs.toList()..shuffle()),
                      ),
                    ],
                  ),
                );
              }
              final song = songs[i - 1];
              return SongTile(
                song: song,
                onTap: () => actions.playSongs(songs, startIndex: i - 1),
                onLongPress: () => showSongMenu(context, song),
              );
            },
          );
        },
      ),
    );
  }
}
