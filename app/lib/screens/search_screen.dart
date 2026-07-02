import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../state/library.dart';
import '../state/player.dart';
import '../widgets/artwork.dart';
import '../widgets/song_tile.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      ref.read(searchQueryProvider.notifier).set(value);
    });
  }

  @override
  Widget build(BuildContext context) {
    final results = ref.watch(searchResultsProvider);
    final query = ref.watch(searchQueryProvider);

    return Scaffold(
      appBar: AppBar(
        title: TextField(
          autofocus: false,
          onChanged: _onChanged,
          decoration: const InputDecoration(
            hintText: 'Artistes, albums, chansons…',
            prefixIcon: Icon(Icons.search),
          ),
        ),
      ),
      body: query.trim().isEmpty
          ? const Center(child: Text('Recherchez dans votre bibliothèque'))
          : results.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Erreur: $e')),
              data: (r) {
                if (r.isEmpty) {
                  return const Center(child: Text('Aucun résultat'));
                }
                return ListView(
                  children: [
                    for (final artist in r.artists)
                      ListTile(
                        leading: Artwork(
                          url: artist.imageUrl,
                          size: 44,
                          borderRadius: 22,
                          icon: Icons.person,
                        ),
                        title: Text(artist.name),
                        subtitle: const Text('Artiste'),
                        onTap: () => context.push('/artist/${artist.id}'),
                      ),
                    for (final album in r.albums)
                      ListTile(
                        leading: Artwork(url: album.artworkUrl, size: 44),
                        title: Text(album.name),
                        subtitle: Text(album.artistName ?? 'Album'),
                        onTap: () => context.push('/album/${album.id}'),
                      ),
                    for (final (i, song) in r.songs.indexed)
                      SongTile(
                        song: song,
                        onTap: () => ref
                            .read(playerActionsProvider)
                            .playSongs(r.songs, startIndex: i),
                      ),
                  ],
                );
              },
            ),
    );
  }
}
