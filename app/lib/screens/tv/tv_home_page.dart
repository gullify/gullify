import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/album.dart';
import '../../models/artist.dart';
import '../../models/song.dart';
import '../../state/discover.dart';
import '../../state/favorites.dart';
import '../../state/library.dart';
import '../../state/player.dart';
import 'tv_kit.dart';

/// L'accueil du téléviseur : un bandeau de reprise, puis des rangées.
///
/// La disposition en rangées horizontales n'est pas un choix esthétique —
/// c'est la seule qui se parcourt confortablement à la croix directionnelle :
/// haut/bas pour changer de sujet, gauche/droite pour parcourir. Une grille
/// obligerait à compter les colonnes de tête.
class TvHomePage extends ConsumerWidget {
  const TvHomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final albums = ref.watch(recentAlbumsProvider);
    final popular = ref.watch(popularSongsProvider);
    final artists = ref.watch(artistsProvider);
    final favorites = ref.watch(allFavoritesProvider);

    return ListView(
      padding: const EdgeInsets.only(
        top: tvSafeV,
        bottom: tvSafeV + 40,
        right: tvSafeH,
      ),
      children: [
        _Hero(albums: albums.value ?? const []),
        const SizedBox(height: 54),
        if ((albums.value ?? const []).isNotEmpty)
          _AlbumShelf(label: 'Derniers ajouts', albums: albums.value!),
        if ((popular.value ?? const []).isNotEmpty) ...[
          const SizedBox(height: 46),
          _SongShelf(label: 'Les plus écoutés', songs: popular.value!),
        ],
        if ((favorites.value ?? const []).isNotEmpty) ...[
          const SizedBox(height: 46),
          _SongShelf(label: 'Tes favoris', songs: favorites.value!),
        ],
        if ((artists.value ?? const []).isNotEmpty) ...[
          const SizedBox(height: 46),
          _ArtistShelf(artists: artists.value!),
        ],
        const SizedBox(height: 46),
        const _Discovery(),
        if (albums.isLoading && artists.isLoading)
          const SizedBox(
            height: 360,
            child: Center(child: CircularProgressIndicator()),
          ),
        if (albums.hasError && (albums.value ?? const []).isEmpty)
          const SizedBox(
            height: 360,
            child: TvEmpty(
              message: 'Bibliothèque injoignable',
              hint:
                  'Le serveur ne répond pas. Vérifie que la télé est bien sur '
                  'le réseau, puis rouvre Gullify.',
              icon: Icons.cloud_off_rounded,
            ),
          ),
      ],
    );
  }
}

/// Le bandeau du haut : ce qui joue, ou à défaut le dernier album ajouté.
class _Hero extends ConsumerWidget {
  const _Hero({required this.albums});

  final List<Album> albums;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final current = ref.watch(currentMediaItemProvider).value;
    final playing = ref.watch(playbackStateProvider).value?.playing ?? false;
    final album = albums.isEmpty ? null : albums.first;

    final title = current?.title ?? album?.name ?? 'Ta bibliothèque';
    final by = current?.artist ?? album?.artistName ?? '';
    final art = current?.artUri?.toString() ?? album?.artworkUrl;
    final kicker = current != null
        ? (playing ? 'En lecture' : 'En pause')
        : 'Dernier ajout';

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Container(
          width: 300,
          height: 300,
          decoration: const BoxDecoration(
            boxShadow: [
              BoxShadow(
                color: Color(0x99000000),
                blurRadius: 60,
                offset: Offset(0, 30),
              ),
            ],
          ),
          child: TvArtwork(url: art, size: 300, borderRadius: 26),
        ),
        const SizedBox(width: 44),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  kicker.toUpperCase(),
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 3,
                    color: scheme.primary,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 60,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -1.8,
                    height: 1.02,
                  ),
                ),
                if (by.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    by,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 30,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
                const SizedBox(height: 26),
                // Une seule cible, toujours à la même place : le premier
                // bouton. Au chargement il n'y a que « Tout mélanger », et
                // quand la bibliothèque arrive il devient « Écouter » — le
                // même emplacement, donc le focus ne bouge pas.
                Row(
                  children: [
                    if (current != null)
                      TvPill(
                        label: playing ? 'En cours' : 'Reprendre',
                        icon: playing
                            ? Icons.graphic_eq_rounded
                            : Icons.play_arrow_rounded,
                        autofocus: true,
                        onPressed: () => context.push('/tv/playing'),
                      )
                    else if (album != null)
                      TvPill(
                        label: 'Écouter',
                        icon: Icons.play_arrow_rounded,
                        autofocus: true,
                        onPressed: () => _playAlbum(context, ref, album),
                      )
                    else
                      TvPill(
                        label: 'Tout mélanger',
                        icon: Icons.shuffle_rounded,
                        autofocus: true,
                        onPressed: () => _shuffleAll(context, ref),
                      ),
                    if (current != null || album != null) ...[
                      const SizedBox(width: 16),
                      TvPill(
                        label: 'Tout mélanger',
                        icon: Icons.shuffle_rounded,
                        accent: false,
                        onPressed: () => _shuffleAll(context, ref),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _playAlbum(
    BuildContext context,
    WidgetRef ref,
    Album album,
  ) async {
    final detail = await ref.read(albumDetailProvider(album.id).future);
    if (detail.songs.isEmpty) return;
    await ref.read(playerActionsProvider).playSongs(detail.songs);
    if (context.mounted) context.push('/tv/playing');
  }

  Future<void> _shuffleAll(BuildContext context, WidgetRef ref) async {
    final songs = await ref
        .read(libraryRepositoryProvider)
        .randomSongs(limit: 200);
    if (songs.isEmpty) return;
    await ref.read(playerActionsProvider).playSongs(songs);
    if (context.mounted) context.push('/tv/playing');
  }
}

/// « À découvrir » : un artiste que YouTube rapproche de ceux qu'on écoute.
///
/// Le même mécanisme que sur l'accueil du téléphone — et la même honnêteté :
/// on dit à cause de qui il est proposé, plutôt que de le sortir d'un chapeau.
class _Discovery extends ConsumerWidget {
  const _Discovery();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final discover = ref.watch(discoverArtistProvider);
    final found = discover.value;
    if (found == null) return const SizedBox.shrink();

    return Row(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(110),
          child: SizedBox(
            width: 220,
            height: 220,
            child: found.artist.thumbnail.isEmpty
                ? ColoredBox(
                    color: scheme.surfaceContainerHighest,
                    child: Icon(
                      Icons.person_search_rounded,
                      size: 80,
                      color: scheme.onSurfaceVariant,
                    ),
                  )
                : Image.network(
                    found.artist.thumbnail,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => ColoredBox(
                      color: scheme.surfaceContainerHighest,
                      child: Icon(
                        Icons.person_search_rounded,
                        size: 80,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
          ),
        ),
        const SizedBox(width: 36),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'À DÉCOUVRIR',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 3,
                  color: scheme.primary,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                found.artist.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 48,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -1.4,
                  height: 1.05,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Parce que tu écoutes ${found.becauseOf}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 26, color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 22),
              Row(
                children: [
                  TvPill(
                    label: 'Le chercher',
                    icon: Icons.search_rounded,
                    onPressed: () {
                      ref
                          .read(searchQueryProvider.notifier)
                          .set(found.artist.name);
                      context.push('/tv');
                    },
                  ),
                  const SizedBox(width: 16),
                  TvPill(
                    label: 'Un autre',
                    icon: Icons.refresh_rounded,
                    accent: false,
                    onPressed: () => ref.invalidate(discoverArtistProvider),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _AlbumShelf extends StatelessWidget {
  const _AlbumShelf({required this.label, required this.albums});

  final String label;
  final List<Album> albums;

  @override
  Widget build(BuildContext context) {
    final shown = albums.take(20).toList();
    return TvShelf(
      label: label,
      itemCount: shown.length,
      itemBuilder: (context, i, onFocus) => TvCard(
        title: shown[i].name,
        subtitle: shown[i].artistName,
        artwork: TvArtwork(
          url: shown[i].artworkUrl,
          size: 250,
          borderRadius: 0,
        ),
        onFocusChange: (f) {
          if (f) onFocus();
        },
        onPressed: () => context.push('/tv/album/${shown[i].id}'),
      ),
    );
  }
}

class _SongShelf extends ConsumerWidget {
  const _SongShelf({required this.label, required this.songs});

  final String label;
  final List<Song> songs;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shown = songs.take(20).toList();
    return TvShelf(
      label: label,
      itemCount: shown.length,
      itemBuilder: (context, i, onFocus) => TvCard(
        title: shown[i].title,
        subtitle: shown[i].artistName,
        artwork: TvArtwork(
          url: shown[i].artworkUrl,
          size: 250,
          borderRadius: 0,
        ),
        icon: Icons.music_note_rounded,
        onFocusChange: (f) {
          if (f) onFocus();
        },
        onPressed: () async {
          await ref.read(playerActionsProvider).playSongs(shown, startIndex: i);
          if (context.mounted) context.push('/tv/playing');
        },
      ),
    );
  }
}

class _ArtistShelf extends StatelessWidget {
  const _ArtistShelf({required this.artists});

  final List<Artist> artists;

  @override
  Widget build(BuildContext context) {
    // Les artistes les mieux fournis d'abord : une rangée d'artistes à un
    // album ne dit rien de la bibliothèque.
    final shown = [...artists]
      ..sort((a, b) => b.songCount.compareTo(a.songCount));
    final top = shown.take(20).toList();
    return TvShelf(
      label: 'Tes artistes',
      itemCount: top.length,
      itemBuilder: (context, i, onFocus) => TvCard(
        title: top[i].name,
        subtitle: '${top[i].albumCount} albums',
        round: true,
        icon: Icons.person_rounded,
        artwork: TvArtwork(url: top[i].imageUrl, size: 250, borderRadius: 0),
        onFocusChange: (f) {
          if (f) onFocus();
        },
        onPressed: () => context.push('/tv/artist/${top[i].id}'),
      ),
    );
  }
}
