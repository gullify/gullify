import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../state/favorites.dart';
import '../state/player.dart';
import '../state/playlists.dart';
import '../widgets/glass_box.dart';
import '../widgets/glass_kit.dart';
import '../widgets/song_menu.dart';
import '../widgets/song_tile.dart';
import 'albums_screen.dart';
import 'artists_screen.dart';

class LibraryScreen extends StatelessWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 12, 4),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Bibliothèque',
                        style: TextStyle(
                          fontSize: 30,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.6,
                          height: 1.02,
                        ),
                      ),
                    ),
                    GlassIconButton(
                      icon: Icons.add,
                      tooltip: 'Ajouter de la musique',
                      size: 42,
                      onPressed: () => context.push('/yt-downloads'),
                    ),
                  ],
                ),
              ),
              // Segments de verre (design) : onglet actif en pilule accent.
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: GlassBox(
                  radius: 16,
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: TabBar(
                      dividerColor: Colors.transparent,
                      indicatorSize: TabBarIndicatorSize.tab,
                      indicator: BoxDecoration(
                        color: scheme.primary,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      labelColor: scheme.onPrimary,
                      unselectedLabelColor: scheme.onSurfaceVariant,
                      labelStyle: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13.5,
                      ),
                      splashBorderRadius: BorderRadius.circular(12),
                      tabs: const [
                        Tab(height: 38, text: 'Artistes'),
                        Tab(height: 38, text: 'Albums'),
                        Tab(height: 38, text: 'Favoris'),
                        Tab(height: 38, text: 'Playlists'),
                      ],
                    ),
                  ),
                ),
              ),
              const Expanded(
                child: TabBarView(
                  children: [
                    ArtistsTab(),
                    AlbumsTab(),
                    _FavoritesTab(),
                    _PlaylistsTab(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FavoritesTab extends ConsumerWidget {
  const _FavoritesTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final favorites = ref.watch(allFavoritesProvider);

    return favorites.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Erreur: $e')),
      data: (songs) {
        if (songs.isEmpty) {
          return const Center(child: Text('Aucun favori'));
        }
        return RefreshIndicator(
          onRefresh: () => ref.refresh(allFavoritesProvider.future),
          child: ListView.builder(
            itemCount: songs.length + 1,
            itemBuilder: (context, i) {
              if (i == 0) {
                return Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Row(
                    children: [
                      FilledButton.icon(
                        onPressed: () =>
                            ref.read(playerActionsProvider).playSongs(songs),
                        icon: const Icon(Icons.play_arrow),
                        label: const Text('Lecture'),
                      ),
                      const SizedBox(width: 8),
                      IconButton.outlined(
                        tooltip: 'Lecture aléatoire',
                        icon: const Icon(Icons.shuffle),
                        onPressed: () => ref
                            .read(playerActionsProvider)
                            .playSongs(songs.toList()..shuffle()),
                      ),
                      const Spacer(),
                      Text(
                        '${songs.length} titre${songs.length > 1 ? 's' : ''}',
                        style: TextStyle(
                          color:
                              Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                );
              }
              final song = songs[i - 1];
              return SongTile(
                song: song,
                onTap: () => ref
                    .read(playerActionsProvider)
                    .playSongs(songs, startIndex: i - 1),
                onLongPress: () => showSongMenu(context, song),
              );
            },
          ),
        );
      },
    );
  }
}

class _PlaylistsTab extends ConsumerWidget {
  const _PlaylistsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playlists = ref.watch(playlistsProvider);

    return playlists.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Erreur: $e')),
      data: (list) => RefreshIndicator(
        onRefresh: () => ref.refresh(playlistsProvider.future),
        child: ListView(
          children: [
            ListTile(
              leading: const CircleAvatar(child: Icon(Icons.add)),
              title: const Text('Nouvelle playlist'),
              onTap: () async {
                final name = await promptPlaylistName(context);
                if (name == null) return;
                await ref.read(playlistActionsProvider).create(name);
              },
            ),
            for (final p in list)
              ListTile(
                leading: const CircleAvatar(child: Icon(Icons.queue_music)),
                title: Text(p.name),
                subtitle:
                    Text('${p.songCount} titre${p.songCount > 1 ? 's' : ''}'),
                onTap: () => context.push('/playlist/${p.id}?name=${Uri.encodeQueryComponent(p.name)}'),
              ),
          ],
        ),
      ),
    );
  }
}
