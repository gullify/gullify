import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/album.dart';
import '../models/game_source.dart';
import '../state/library.dart';
import '../state/player.dart';
import '../widgets/album_card.dart';
import '../widgets/artist_row.dart';
import '../widgets/genre_mosaic.dart';
import '../widgets/glass_kit.dart';
import '../widgets/mascot_empty.dart';
import 'shell_screen.dart';

/// Un genre en entier : mosaïque de ses pochettes, lecture aléatoire du
/// genre, puis ses albums (grille) et ses artistes (liste).
class GenreScreen extends ConsumerWidget {
  const GenreScreen({super.key, required this.genre});

  final String genre;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final albums = ref.watch(albumsByGenreProvider(genre));
    final artists = ref.watch(artistsByGenreProvider(genre));

    final albumList = albums.value ?? const <Album>[];
    final artistList = artists.value ?? const [];
    final loading = albums.isLoading || artists.isLoading;
    final error = albums.error ?? artists.error;
    final empty = !loading && albumList.isEmpty && artistList.isEmpty;

    return Scaffold(
      appBar: AppBar(title: Text(genre)),
      bottomNavigationBar: const DetailDock(),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(albumsByGenreProvider(genre));
          ref.invalidate(artistsByGenreProvider(genre));
          await Future.wait([
            ref.read(albumsByGenreProvider(genre).future),
            ref.read(artistsByGenreProvider(genre).future),
          ]);
        },
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: _GenreHeader(
                genre: genre,
                albums: albumList,
                artistCount: artistList.length,
              ),
            ),
            if (error != null)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text('Erreur: $error'),
                ),
              ),
            if (loading)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 40),
                  child: Center(child: CircularProgressIndicator()),
                ),
              ),
            if (empty)
              const SliverToBoxAdapter(
                child: MascotEmpty(
                  message: 'Rien dans ce genre',
                  hint: 'Assigne ce genre à un artiste depuis sa fiche.',
                ),
              ),
            if (albumList.isNotEmpty) ...[
              SliverToBoxAdapter(
                child: SectionTitle('Albums · ${albumList.length}'),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
                sliver: SliverGrid(
                  gridDelegate:
                      const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 200,
                    childAspectRatio: 0.75,
                    mainAxisSpacing: 16,
                    crossAxisSpacing: 16,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, i) => AlbumGridCard(album: albumList[i]),
                    childCount: albumList.length,
                  ),
                ),
              ),
            ],
            if (artistList.isNotEmpty) ...[
              SliverToBoxAdapter(
                child: SectionTitle('Artistes · ${artistList.length}'),
              ),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, i) => ArtistRow(artist: artistList[i]),
                    childCount: artistList.length,
                  ),
                ),
              ),
            ],
            SliverToBoxAdapter(
              child: SizedBox(
                height: MediaQuery.paddingOf(context).bottom + 24,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// En-tête : mosaïque des pochettes du genre, ce qu'il contient et la
/// lecture aléatoire.
class _GenreHeader extends StatelessWidget {
  const _GenreHeader({
    required this.genre,
    required this.albums,
    required this.artistCount,
  });

  final String genre;
  final List<Album> albums;
  final int artistCount;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final urls = [
      for (final a in albums) ?a.artworkUrl,
    ].take(4).toList();
    final counts = [
      if (artistCount > 0)
        '$artistCount artiste${artistCount > 1 ? 's' : ''}',
      if (albums.isNotEmpty)
        '${albums.length} album${albums.length > 1 ? 's' : ''}',
    ].join(' · ');

    // Le nom du genre est déjà dans la barre du haut : ici, ce qu'il
    // contient et de quoi le lancer.
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
      child: Row(
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              boxShadow: const [kArtShadow],
            ),
            child: GenreMosaic(urls: urls, size: 104),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (counts.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      counts,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ShuffleGenreButton(genre: genre),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Lance un échantillon aléatoire du genre (mélangé côté serveur, comme la
/// lecture aléatoire de toute la bibliothèque).
class ShuffleGenreButton extends ConsumerStatefulWidget {
  const ShuffleGenreButton({super.key, required this.genre});

  final String genre;

  @override
  ConsumerState<ShuffleGenreButton> createState() => _ShuffleGenreButtonState();
}

class _ShuffleGenreButtonState extends ConsumerState<ShuffleGenreButton> {
  bool _busy = false;

  Future<void> _play() async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final songs = await ref.read(libraryRepositoryProvider).randomSongs(
            source: GameSource(
              mode: GameSourceMode.genres,
              genres: [widget.genre],
            ),
          );
      if (songs.isEmpty) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Aucun titre dans ce genre')),
        );
        return;
      }
      await ref.read(playerActionsProvider).playSongs(songs);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Erreur : $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AccentPlayButton(
      label: _busy ? 'Chargement…' : 'Lecture aléatoire',
      icon: Icons.shuffle,
      onPressed: _busy ? null : _play,
    );
  }
}
