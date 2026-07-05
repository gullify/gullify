import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/album.dart';
import '../models/artist.dart';
import '../state/favorites.dart';
import '../state/library.dart';
import '../state/player.dart';
import '../state/playlists.dart';
import '../widgets/album_card.dart' show kArtShadow;
import '../widgets/alpha_grid.dart';
import '../widgets/artwork.dart';
import '../widgets/glass_box.dart';
import '../widgets/glass_kit.dart';
import '../widgets/shuffle_library_button.dart';
import '../widgets/song_menu.dart';
import '../widgets/song_tile.dart';

/// Vues du contrôle segmenté de la bibliothèque.
enum _LibView { artistes, albums, favoris, playlists }

/// Onglet « Bibliothèque » : titre + bouton d'ajout, contrôle segmenté en
/// verre Artistes / Albums / Favoris / Playlists. Filtre instantané,
/// barre A-Z et aléatoire global conservés sur Artistes et Albums.
class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  _LibView _view = _LibView.artistes;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
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
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: _SegmentedControl(
                view: _view,
                onViewChanged: (v) => setState(() => _view = v),
              ),
            ),
            Expanded(
              child: switch (_view) {
                _LibView.artistes => const _ArtistsView(),
                _LibView.albums => const _AlbumsView(),
                _LibView.favoris => const _FavoritesView(),
                _LibView.playlists => const _PlaylistsView(),
              },
            ),
          ],
        ),
      ),
    );
  }
}

// ───────────────────────── Contrôle segmenté ─────────────────────────

class _SegmentedControl extends StatelessWidget {
  const _SegmentedControl({required this.view, required this.onViewChanged});

  final _LibView view;
  final ValueChanged<_LibView> onViewChanged;

  static const _labels = {
    _LibView.artistes: 'Artistes',
    _LibView.albums: 'Albums',
    _LibView.favoris: 'Favoris',
    _LibView.playlists: 'Playlists',
  };

  @override
  Widget build(BuildContext context) {
    return GlassBox(
      radius: 16,
      blur: false,
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Row(
          children: [
            for (final v in _LibView.values)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: _SegmentButton(
                    label: _labels[v]!,
                    selected: v == view,
                    onTap: () => onViewChanged(v),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SegmentButton extends StatelessWidget {
  const _SegmentButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
      height: 38,
      decoration: BoxDecoration(
        color: selected ? scheme.primary : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Center(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
              color: selected ? scheme.onPrimary : scheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}

// ───────────────────────── Vue Artistes ─────────────────────────

class _ArtistsView extends ConsumerWidget {
  const _ArtistsView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final artists = ref.watch(artistsProvider);
    return artists.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Erreur: $e')),
      data: (list) => AlphaGrid<Artist>(
        items: list,
        nameOf: (a) => a.name,
        hintText: 'Filtrer les artistes…',
        trailing: const ShuffleLibraryButton(),
        rowExtent: 72,
        onRefresh: () => ref.refresh(artistsProvider.future),
        itemBuilder: (context, artist) => _ArtistRow(artist: artist),
      ),
    );
  }
}

/// Rangée d'artiste (design) : avatar rond 54 + ombre, nom 15.5/700,
/// « N albums » 12.5 gris, chevron.
class _ArtistRow extends StatelessWidget {
  const _ArtistRow({required this.artist});

  final Artist artist;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => context.push('/artist/${artist.id}'),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        child: Row(
          children: [
            DecoratedBox(
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Color(0x29000000),
                    blurRadius: 12,
                    offset: Offset(0, 5),
                  ),
                ],
              ),
              child: Artwork(
                url: artist.imageUrl,
                size: 54,
                borderRadius: 27,
                icon: Icons.person,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    artist.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    '${artist.albumCount} album'
                    '${artist.albumCount > 1 ? 's' : ''}',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, size: 24, color: Color(0xFFB6BAC1)),
          ],
        ),
      ),
    );
  }
}

// ───────────────────────── Vue Albums ─────────────────────────

class _AlbumsView extends ConsumerWidget {
  const _AlbumsView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final albums = ref.watch(albumsProvider);
    return albums.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Erreur: $e')),
      data: (list) => AlphaGrid<Album>(
        items: list,
        nameOf: (a) => a.name,
        hintText: 'Filtrer les albums…',
        trailing: const ShuffleLibraryButton(),
        // 2 colonnes sur téléphone : (largeur − 52) / 2 ≈ 180.
        maxCrossAxisExtent: 200,
        childAspectRatio: 0.75,
        onRefresh: () => ref.refresh(albumsProvider.future),
        itemBuilder: (context, album) => _AlbumGridCard(album: album),
      ),
    );
  }
}

/// Carte d'album de la grille (design) : pochette carrée radius 20 + ombre,
/// nom 14/700, « artiste · année » 12 gris.
class _AlbumGridCard extends StatelessWidget {
  const _AlbumGridCard({required this.album});

  final Album album;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final subtitle = [
      if (album.artistName != null) album.artistName!,
      if (album.year != null) '${album.year}',
    ].join(' · ');

    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () => context.push('/album/${album.id}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 1,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                boxShadow: const [kArtShadow],
              ),
              child: Artwork(url: album.artworkUrl, borderRadius: 20),
            ),
          ),
          const SizedBox(height: 9),
          Text(
            album.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          ),
          if (subtitle.isNotEmpty)
            Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
        ],
      ),
    );
  }
}

// ───────────────────────── Vue Favoris ─────────────────────────

class _FavoritesView extends ConsumerWidget {
  const _FavoritesView();

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
            padding: EdgeInsets.only(
              bottom: MediaQuery.paddingOf(context).bottom + 18,
            ),
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

// ───────────────────────── Vue Playlists ─────────────────────────

class _PlaylistsView extends ConsumerWidget {
  const _PlaylistsView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playlists = ref.watch(playlistsProvider);

    return playlists.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Erreur: $e')),
      data: (list) => RefreshIndicator(
        onRefresh: () => ref.refresh(playlistsProvider.future),
        child: ListView(
          padding: EdgeInsets.only(
            top: 8,
            bottom: MediaQuery.paddingOf(context).bottom + 18,
          ),
          children: [
            _PlaylistRow(
              vignette: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: Theme.of(context)
                      .colorScheme
                      .primary
                      .withValues(alpha: 0.14),
                ),
                child: Icon(
                  Icons.add,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              name: 'Nouvelle playlist',
              subtitle: 'Créer',
              onTap: () async {
                final name = await promptPlaylistName(context);
                if (name == null) return;
                await ref.read(playlistActionsProvider).create(name);
              },
            ),
            for (final p in list)
              _PlaylistRow(
                vignette: Artwork(
                  url: null,
                  size: 44,
                  borderRadius: 12,
                  icon: Icons.queue_music,
                ),
                name: p.name,
                subtitle: '${p.songCount} titre${p.songCount > 1 ? 's' : ''}',
                onTap: () => context.push(
                  '/playlist/${p.id}'
                  '?name=${Uri.encodeQueryComponent(p.name)}',
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Rangée de playlist : vignette 44 r12, nom 14.5/700, « N titres » gris.
class _PlaylistRow extends StatelessWidget {
  const _PlaylistRow({
    required this.vignette,
    required this.name,
    required this.subtitle,
    required this.onTap,
  });

  final Widget vignette;
  final String name;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
          child: Row(
            children: [
              vignette,
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right,
                  size: 24, color: Color(0xFFB6BAC1)),
            ],
          ),
        ),
      ),
    );
  }
}

// (promptPlaylistName vit dans widgets/song_menu.dart.)
