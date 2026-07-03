import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../state/favorites.dart';
import '../state/player.dart';
import '../state/playlists.dart';
import '../widgets/song_menu.dart';
import '../widgets/song_tile.dart';
import 'albums_screen.dart';
import 'artists_screen.dart';

class LibraryScreen extends StatelessWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Bibliothèque'),
          actions: [
            IconButton(
              icon: const Icon(Icons.add_circle_outline),
              tooltip: 'Ajouter de la musique',
              onPressed: () => context.push('/yt-downloads'),
            ),
          ],
          bottom: const TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(text: 'Artistes'),
              Tab(text: 'Albums'),
              Tab(text: 'Favoris'),
              Tab(text: 'Playlists'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            ArtistsTab(),
            AlbumsTab(),
            _FavoritesTab(),
            _PlaylistsTab(),
          ],
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
