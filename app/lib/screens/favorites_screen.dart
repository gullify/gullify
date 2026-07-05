import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/favorites.dart';
import '../state/player.dart';
import '../widgets/glass_kit.dart';
import '../widgets/mascot_empty.dart';
import '../widgets/song_menu.dart';
import '../widgets/song_tile.dart';

/// Onglet « Favoris » : titre + Lecture / aléatoire, liste des titres aimés.
class FavoritesScreen extends ConsumerWidget {
  const FavoritesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final favorites = ref.watch(allFavoritesProvider);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 14, 20, 4),
              child: Text(
                'Favoris',
                style: TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.6,
                  height: 1.02,
                ),
              ),
            ),
            Expanded(
              child: favorites.when(
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text('Erreur: $e')),
                data: (songs) {
                  if (songs.isEmpty) {
                    return const MascotEmpty(
                      message: 'Aucun favori pour l\'instant',
                      hint:
                          'Appuie sur le cœur d\'un titre pour le retrouver ici.',
                    );
                  }
                  final actions = ref.read(playerActionsProvider);
                  return RefreshIndicator(
                    onRefresh: () => ref.refresh(allFavoritesProvider.future),
                    child: ListView.builder(
                      padding: EdgeInsets.only(
                        bottom: MediaQuery.paddingOf(context).bottom + 18,
                      ),
                      itemCount: songs.length + 1,
                      itemBuilder: (context, i) {
                        if (i == 0) {
                          return Padding(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
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
                                  onPressed: () => actions
                                      .playSongs(songs.toList()..shuffle()),
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  '${songs.length}',
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }
                        final song = songs[i - 1];
                        return SongTile(
                          song: song,
                          onTap: () =>
                              actions.playSongs(songs, startIndex: i - 1),
                          onLongPress: () => showSongMenu(context, song),
                        );
                      },
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
