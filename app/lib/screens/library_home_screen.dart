import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../api/playlist_repository.dart';
import '../models/album.dart';
import '../models/artist.dart';
import '../state/auth.dart';
import '../state/favorites.dart';
import '../state/library.dart';
import '../state/notifications.dart';
import '../state/player.dart';
import '../state/playlists.dart';
import '../widgets/album_card.dart';
import '../widgets/alpha_grid.dart';
import '../widgets/artwork.dart';
import '../widgets/glass_box.dart';
import '../widgets/glass_kit.dart';
import '../widgets/shuffle_library_button.dart';
import '../widgets/song_menu.dart';
import '../widgets/song_tile.dart';

/// Vues du contrôle segmenté de la bibliothèque.
enum _LibView { titres, artistes, albums, favoris }

/// Onglet « Bibliothèque » (design Liquid Glass Player, section LIBRARY) :
/// en-tête salutation + boutons de verre, carrousel « Écoutés récemment »,
/// grille « Vos playlists », contrôle segmenté Titres/Artistes/Albums/Favoris.
class LibraryHomeScreen extends ConsumerStatefulWidget {
  const LibraryHomeScreen({super.key});

  @override
  ConsumerState<LibraryHomeScreen> createState() => _LibraryHomeScreenState();
}

class _LibraryHomeScreenState extends ConsumerState<LibraryHomeScreen> {
  _LibView _view = _LibView.titres;

  /// Rafraîchit les sections communes de l'en-tête.
  void _invalidateHeader() {
    ref.invalidate(recentAlbumsProvider);
    ref.invalidate(playlistsProvider);
  }

  @override
  Widget build(BuildContext context) {
    final header = _Header(
      view: _view,
      onViewChanged: (v) => setState(() => _view = v),
    );
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: switch (_view) {
          _LibView.titres =>
            _TracksView(header: header, onRefreshHeader: _invalidateHeader),
          _LibView.favoris =>
            _FavoritesView(header: header, onRefreshHeader: _invalidateHeader),
          _LibView.artistes =>
            _ArtistsView(header: header, onRefreshHeader: _invalidateHeader),
          _LibView.albums =>
            _AlbumsView(header: header, onRefreshHeader: _invalidateHeader),
        },
      ),
    );
  }
}

// ───────────────────────── En-tête commun ─────────────────────────

class _Header extends ConsumerWidget {
  const _Header({required this.view, required this.onViewChanged});

  final _LibView view;
  final ValueChanged<_LibView> onViewChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    final recent = ref.watch(recentAlbumsProvider);
    final playlists = ref.watch(playlistsProvider);
    final scheme = Theme.of(context).colorScheme;

    final hour = DateTime.now().hour;
    final greeting = hour >= 18 || hour < 5 ? 'Bonsoir' : 'Bonjour';
    final userName = auth.user?.fullName ?? auth.user?.username;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Salutation + « Bibliothèque » + boutons de verre 42.
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      userName == null ? greeting : '$greeting, $userName',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.2,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const Text(
                      'Bibliothèque',
                      style: TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.6,
                        height: 1.02,
                      ),
                    ),
                  ],
                ),
              ),
              GlassIconButton(
                icon: Icons.bar_chart,
                tooltip: 'Statistiques',
                size: 42,
                onPressed: () => context.push('/stats'),
              ),
              const SizedBox(width: 8),
              const _NotificationsButton(),
              const SizedBox(width: 8),
              GlassIconButton(
                icon: Icons.person_outlined,
                tooltip: 'Paramètres',
                size: 42,
                onPressed: () => context.push('/settings'),
              ),
            ],
          ),
        ),
        const SectionTitle(
          'Écoutés récemment',
          padding: EdgeInsets.fromLTRB(20, 14, 20, 2),
        ),
        SizedBox(
          height: 208,
          child: recent.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Erreur: $e')),
            data: (albums) => albums.isEmpty
                ? const Center(child: Text('Aucun album'))
                : ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                    itemCount: albums.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 13),
                    itemBuilder: (context, i) => AlbumCard(album: albums[i]),
                  ),
          ),
        ),
        const SectionTitle(
          'Vos playlists',
          padding: EdgeInsets.fromLTRB(20, 8, 20, 2),
        ),
        playlists.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) => Padding(
            padding: const EdgeInsets.all(20),
            child: Text('Erreur: $e'),
          ),
          data: (list) => GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              mainAxisExtent: 64,
            ),
            itemCount: list.length + 1,
            itemBuilder: (context, i) => i < list.length
                ? _PlaylistCard(playlist: list[i])
                : const _NewPlaylistCard(),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 6, 20, 4),
          child: _SegmentedControl(view: view, onViewChanged: onViewChanged),
        ),
      ],
    );
  }
}

class _NotificationsButton extends ConsumerWidget {
  const _NotificationsButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = ref.watch(notificationsProvider).value?.unread ?? 0;
    return Badge(
      isLabelVisible: unread > 0,
      label: Text('$unread'),
      child: GlassIconButton(
        icon: Icons.notifications_outlined,
        tooltip: 'Notifications',
        size: 42,
        onPressed: () => context.push('/notifications'),
      ),
    );
  }
}

// ───────────────────────── Playlists ─────────────────────────

class _PlaylistCard extends StatelessWidget {
  const _PlaylistCard({required this.playlist});

  final Playlist playlist;

  @override
  Widget build(BuildContext context) {
    return _PlaylistCardBase(
      vignette: Artwork(
        url: null,
        size: 44,
        borderRadius: 12,
        icon: Icons.queue_music,
      ),
      name: playlist.name,
      subtitle:
          '${playlist.songCount} titre${playlist.songCount > 1 ? 's' : ''}',
      onTap: () => context.push(
        '/playlist/${playlist.id}'
        '?name=${Uri.encodeQueryComponent(playlist.name)}',
      ),
    );
  }
}

class _NewPlaylistCard extends ConsumerWidget {
  const _NewPlaylistCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    return _PlaylistCardBase(
      vignette: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: scheme.primary.withValues(alpha: 0.14),
        ),
        child: Icon(Icons.add, color: scheme.primary),
      ),
      name: 'Nouvelle playlist',
      subtitle: 'Créer',
      onTap: () async {
        final name = await promptPlaylistName(context);
        if (name == null) return;
        await ref.read(playlistActionsProvider).create(name);
      },
    );
  }
}

/// Carte de verre d'une playlist (design) : radius 18, padding 9,
/// vignette 44 radius 12 avec ombre, nom 13.5/700, sous-titre 11.5 gris.
class _PlaylistCardBase extends StatelessWidget {
  const _PlaylistCardBase({
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
    return GlassBox(
      radius: 18,
      blur: false,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(9),
          child: Row(
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x26000000),
                      blurRadius: 10,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
                child: vignette,
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
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

// ───────────────────────── Contrôle segmenté ─────────────────────────

class _SegmentedControl extends StatelessWidget {
  const _SegmentedControl({required this.view, required this.onViewChanged});

  final _LibView view;
  final ValueChanged<_LibView> onViewChanged;

  static const _labels = {
    _LibView.titres: 'Titres',
    _LibView.artistes: 'Artistes',
    _LibView.albums: 'Albums',
    _LibView.favoris: 'Favoris',
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

// ───────────────────────── Vue Titres ─────────────────────────

class _TracksView extends ConsumerWidget {
  const _TracksView({required this.header, required this.onRefreshHeader});

  final Widget header;
  final VoidCallback onRefreshHeader;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final popular = ref.watch(popularSongsProvider);
    return RefreshIndicator(
      onRefresh: () {
        onRefreshHeader();
        return ref.refresh(popularSongsProvider.future);
      },
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(child: header),
          ...popular.when(
            loading: () => const [SliverToBoxAdapter(child: _SectionLoader())],
            error: (e, _) => [
              SliverToBoxAdapter(child: _SectionError(error: e)),
            ],
            data: (songs) => [
              if (songs.isEmpty)
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.all(28),
                    child: Center(child: Text('Aucune écoute pour l’instant')),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
                  sliver: SliverList.builder(
                    itemCount: songs.length,
                    itemBuilder: (context, i) => SongTile(
                      song: songs[i],
                      onTap: () => ref
                          .read(playerActionsProvider)
                          .playSongs(songs, startIndex: i),
                      onLongPress: () => showSongMenu(context, songs[i]),
                    ),
                  ),
                ),
            ],
          ),
          SliverToBoxAdapter(
            child:
                SizedBox(height: MediaQuery.paddingOf(context).bottom + 18),
          ),
        ],
      ),
    );
  }
}

// ───────────────────────── Vue Favoris ─────────────────────────

class _FavoritesView extends ConsumerWidget {
  const _FavoritesView({required this.header, required this.onRefreshHeader});

  final Widget header;
  final VoidCallback onRefreshHeader;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final favorites = ref.watch(allFavoritesProvider);
    return RefreshIndicator(
      onRefresh: () {
        onRefreshHeader();
        return ref.refresh(allFavoritesProvider.future);
      },
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(child: header),
          ...favorites.when(
            loading: () => const [SliverToBoxAdapter(child: _SectionLoader())],
            error: (e, _) => [
              SliverToBoxAdapter(child: _SectionError(error: e)),
            ],
            data: (songs) => [
              if (songs.isEmpty)
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.all(28),
                    child: Center(child: Text('Aucun favori')),
                  ),
                )
              else ...[
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                    child: Row(
                      children: [
                        FilledButton.icon(
                          onPressed: () => ref
                              .read(playerActionsProvider)
                              .playSongs(songs),
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
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(4, 0, 4, 0),
                  sliver: SliverList.builder(
                    itemCount: songs.length,
                    itemBuilder: (context, i) => SongTile(
                      song: songs[i],
                      onTap: () => ref
                          .read(playerActionsProvider)
                          .playSongs(songs, startIndex: i),
                      onLongPress: () => showSongMenu(context, songs[i]),
                    ),
                  ),
                ),
              ],
            ],
          ),
          SliverToBoxAdapter(
            child:
                SizedBox(height: MediaQuery.paddingOf(context).bottom + 18),
          ),
        ],
      ),
    );
  }
}

// ───────────────────────── Vue Artistes ─────────────────────────

class _ArtistsView extends ConsumerWidget {
  const _ArtistsView({required this.header, required this.onRefreshHeader});

  final Widget header;
  final VoidCallback onRefreshHeader;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final artists = ref.watch(artistsProvider);
    return artists.when(
      loading: () => ListView(children: [header, const _SectionLoader()]),
      error: (e, _) =>
          ListView(children: [header, _SectionError(error: e)]),
      data: (list) => AlphaGrid<Artist>(
        items: list,
        nameOf: (a) => a.name,
        hintText: 'Filtrer les artistes…',
        trailing: const ShuffleLibraryButton(),
        header: header,
        rowExtent: 72,
        onRefresh: () {
          onRefreshHeader();
          return ref.refresh(artistsProvider.future);
        },
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
  const _AlbumsView({required this.header, required this.onRefreshHeader});

  final Widget header;
  final VoidCallback onRefreshHeader;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final albums = ref.watch(albumsProvider);
    return albums.when(
      loading: () => ListView(children: [header, const _SectionLoader()]),
      error: (e, _) =>
          ListView(children: [header, _SectionError(error: e)]),
      data: (list) => AlphaGrid<Album>(
        items: list,
        nameOf: (a) => a.name,
        hintText: 'Filtrer les albums…',
        trailing: const ShuffleLibraryButton(),
        header: header,
        // 2 colonnes sur téléphone : (largeur − 52) / 2 ≈ 180.
        maxCrossAxisExtent: 200,
        childAspectRatio: 0.75,
        onRefresh: () {
          onRefreshHeader();
          return ref.refresh(albumsProvider.future);
        },
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

// ───────────────────────── Petits états ─────────────────────────

class _SectionLoader extends StatelessWidget {
  const _SectionLoader();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(28),
      child: Center(child: CircularProgressIndicator()),
    );
  }
}

class _SectionError extends StatelessWidget {
  const _SectionError({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Center(child: Text('Erreur: $error')),
    );
  }
}
