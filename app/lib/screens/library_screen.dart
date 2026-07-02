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
            itemCount: songs.length,
            itemBuilder: (context, i) => SongTile(
              song: songs[i],
              onTap: () => ref
                  .read(playerActionsProvider)
                  .playSongs(songs, startIndex: i),
              onLongPress: () => showSongMenu(context, songs[i]),
            ),
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
