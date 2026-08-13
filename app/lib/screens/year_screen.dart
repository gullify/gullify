import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/album.dart';
import '../state/library.dart';
import '../state/player.dart';
import '../widgets/album_card.dart';
import '../widgets/genre_mosaic.dart';
import '../widgets/glass_kit.dart';
import '../widgets/mascot_empty.dart';
import 'shell_screen.dart';

/// Une année de la bibliothèque (idée #80) : sa radio « machine à remonter le
/// temps » — les titres sortis cette année-là, mélangés — puis les albums qui
/// la composent.
class YearScreen extends ConsumerWidget {
  const YearScreen({super.key, required this.year});

  final int year;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final albums = ref.watch(albumsByYearProvider(year));
    final albumList = albums.value ?? const <Album>[];

    return Scaffold(
      appBar: AppBar(title: Text('$year')),
      bottomNavigationBar: const DetailDock(),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(albumsByYearProvider(year).future),
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: _YearHeader(year: year, albums: albumList),
            ),
            if (albums.hasError)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text('Erreur: ${albums.error}'),
                ),
              ),
            if (albums.isLoading)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 40),
                  child: Center(child: CircularProgressIndicator()),
                ),
              ),
            if (!albums.isLoading && albumList.isEmpty)
              const SliverToBoxAdapter(
                child: MascotEmpty(
                  message: 'Rien de cette année-là',
                  hint: 'L\'année vient de l\'album : complète sa date depuis '
                      'l\'éditeur de tags pour le retrouver ici.',
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

/// En-tête : mosaïque des pochettes de l'année, ce qu'elle contient et le
/// bouton qui lance sa radio.
class _YearHeader extends StatelessWidget {
  const _YearHeader({required this.year, required this.albums});

  final int year;
  final List<Album> albums;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final urls = [for (final a in albums) ?a.artworkUrl].take(4).toList();
    final count = albums.isEmpty
        ? ''
        : '${albums.length} album${albums.length > 1 ? 's' : ''}';

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
      child: Row(
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              boxShadow: const [kArtShadow],
            ),
            child: GenreMosaic(urls: urls, size: 104, icon: Icons.history),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (count.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      count,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                YearRadioButton(year: year),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Lance la radio d'une année : ses titres, mélangés côté serveur, comme la
/// lecture aléatoire d'un genre.
class YearRadioButton extends ConsumerStatefulWidget {
  const YearRadioButton({super.key, required this.year});

  final int year;

  @override
  ConsumerState<YearRadioButton> createState() => _YearRadioButtonState();
}

class _YearRadioButtonState extends ConsumerState<YearRadioButton> {
  bool _busy = false;

  Future<void> _play() async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final songs =
          await ref.read(libraryRepositoryProvider).yearSongs(widget.year);
      if (songs.isEmpty) {
        messenger.showSnackBar(
          SnackBar(content: Text('Aucun titre de ${widget.year}')),
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
      label: _busy ? 'Chargement…' : 'Radio ${widget.year}',
      icon: Icons.radio,
      onPressed: _busy ? null : _play,
    );
  }
}
