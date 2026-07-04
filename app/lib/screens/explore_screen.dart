import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../api/radio_repository.dart';
import '../models/song.dart';
import '../state/library.dart';
import '../state/player.dart';
import '../state/radio.dart';
import '../widgets/album_card.dart';
import '../widgets/artwork.dart';
import '../widgets/glass_box.dart';
import '../widgets/glass_kit.dart';
import '../widgets/song_menu.dart';
import '../widgets/song_tile.dart';

/// Onglet « Explorer » (design Liquid Glass Player, section EXPLORE) :
/// titre 30/800, champ de recherche en verre; sans recherche : ajout de
/// musique (YouTube), radios et suggestions; avec recherche : résultats.
class ExploreScreen extends ConsumerStatefulWidget {
  const ExploreScreen({super.key});

  @override
  ConsumerState<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends ConsumerState<ExploreScreen> {
  Timer? _debounce;
  late final TextEditingController _controller =
      TextEditingController(text: ref.read(searchQueryProvider));

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (mounted) ref.read(searchQueryProvider.notifier).set(value);
    });
  }

  void _clear() {
    _debounce?.cancel();
    _controller.clear();
    ref.read(searchQueryProvider.notifier).set('');
  }

  @override
  Widget build(BuildContext context) {
    final query = ref.watch(searchQueryProvider);
    final hasQuery = query.trim().isNotEmpty;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: () {
            ref.invalidate(suggestionsProvider);
            return ref.refresh(radioStationsProvider.future);
          },
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.only(
              bottom: MediaQuery.paddingOf(context).bottom + 18,
            ),
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 14, 20, 4),
                child: Text(
                  'Explorer',
                  style: TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.6,
                    height: 1.02,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 8),
                child: _SearchField(
                  controller: _controller,
                  hasQuery: hasQuery,
                  onChanged: _onChanged,
                  onClear: _clear,
                ),
              ),
              if (!hasQuery) ..._browseSections(context) else ..._results(query),
            ],
          ),
        ),
      ),
    );
  }

  // Sections « découverte » quand aucune recherche n'est en cours.
  List<Widget> _browseSections(BuildContext context) {
    final stations = ref.watch(radioStationsProvider);
    final suggestions = ref.watch(suggestionsProvider);
    final currentId = ref.watch(currentMediaItemProvider).value?.id;

    return [
      const SectionTitle(
        'Ajouter de la musique',
        padding: EdgeInsets.fromLTRB(20, 12, 20, 2),
      ),
      const Padding(
        padding: EdgeInsets.fromLTRB(20, 12, 20, 6),
        child: _YtDownloadsCard(),
      ),
      const SectionTitle('Radios', padding: EdgeInsets.fromLTRB(20, 14, 20, 6)),
      ...stations.when(
        loading: () => const [
          Padding(
            padding: EdgeInsets.all(28),
            child: Center(child: CircularProgressIndicator()),
          ),
        ],
        error: (e, _) => [
          Padding(
            padding: const EdgeInsets.all(20),
            child: Center(child: Text('Erreur: $e')),
          ),
        ],
        data: (list) {
          if (list.isEmpty) {
            return const [
              Padding(
                padding: EdgeInsets.all(20),
                child: Center(child: Text('Aucune station')),
              ),
            ];
          }
          final sorted = [...list]
            ..sort((a, b) {
              if (a.favorite != b.favorite) return a.favorite ? -1 : 1;
              return a.name.toLowerCase().compareTo(b.name.toLowerCase());
            });
          return [
            for (final s in sorted)
              _StationRow(station: s, currentId: currentId),
          ];
        },
      ),
      ...suggestions.maybeWhen(
        data: (s) => s.albums.isEmpty
            ? const <Widget>[]
            : [
                SectionTitle(
                  s.genre != null ? 'Suggestions · ${s.genre}' : 'Suggestions',
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 2),
                ),
                SizedBox(
                  height: 226,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 18),
                    itemCount: s.albums.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 13),
                    itemBuilder: (context, i) =>
                        AlbumCard(album: s.albums[i], size: 150),
                  ),
                ),
              ],
        orElse: () => const <Widget>[],
      ),
    ];
  }

  // Résultats de la recherche générale (artistes, albums, titres).
  List<Widget> _results(String query) {
    final results = ref.watch(searchResultsProvider);
    return results.when(
      loading: () => const [
        Padding(
          padding: EdgeInsets.all(40),
          child: Center(child: CircularProgressIndicator()),
        ),
      ],
      error: (e, _) => [
        Padding(
          padding: const EdgeInsets.all(20),
          child: Center(child: Text('Erreur: $e')),
        ),
      ],
      data: (r) {
        if (r.isEmpty) {
          return [_NoResults(query: query)];
        }
        return [
          const SizedBox(height: 4),
          for (final artist in r.artists)
            _ResultRow(
              artwork: Artwork(
                url: artist.imageUrl,
                size: 46,
                borderRadius: 23,
                icon: Icons.person,
              ),
              title: artist.name,
              subtitle: 'Artiste',
              onTap: () => context.push('/artist/${artist.id}'),
            ),
          for (final album in r.albums)
            _ResultRow(
              artwork: Artwork(url: album.artworkUrl, size: 46,
                  borderRadius: 12),
              title: album.name,
              subtitle: album.artistName ?? 'Album',
              onTap: () => context.push('/album/${album.id}'),
            ),
          for (final (i, song) in r.songs.indexed)
            SongTile(
              song: song,
              subtitle: _songSubtitle(song),
              onTap: () => ref
                  .read(playerActionsProvider)
                  .playSongs(r.songs, startIndex: i),
              onLongPress: () => showSongMenu(context, song),
            ),
        ];
      },
    );
  }
}

/// « Artiste · Album » pour les résultats, ou null si rien à afficher.
String? _songSubtitle(Song song) {
  final parts = [
    if (song.artistName != null) song.artistName!,
    if (song.albumName != null) song.albumName!,
  ];
  return parts.isEmpty ? null : parts.join(' · ');
}

/// Champ de recherche en verre (design) : radius 18, icône search,
/// « Titres, artistes, ambiances… », croix d'effacement.
class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.hasQuery,
    required this.onChanged,
    required this.onClear,
  });

  final TextEditingController controller;
  final bool hasQuery;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GlassBox(
      radius: 18,
      blur: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 15),
        child: Row(
          children: [
            Icon(Icons.search, size: 22, color: scheme.onSurfaceVariant),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: controller,
                onChanged: onChanged,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
                decoration: const InputDecoration(
                  hintText: 'Titres, artistes, ambiances…',
                  filled: false,
                  isDense: true,
                  border: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
            if (hasQuery)
              IconButton(
                tooltip: 'Effacer',
                padding: EdgeInsets.zero,
                constraints:
                    const BoxConstraints(minWidth: 32, minHeight: 32),
                icon: Icon(Icons.close,
                    size: 20, color: scheme.onSurfaceVariant),
                onPressed: onClear,
              ),
          ],
        ),
      ),
    );
  }
}

/// Carte de verre vers le téléchargement YouTube (/yt-downloads).
class _YtDownloadsCard extends StatelessWidget {
  const _YtDownloadsCard();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GlassBox(
      radius: 18,
      blur: false,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => context.push('/yt-downloads'),
        child: Padding(
          padding: const EdgeInsets.all(11),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: scheme.primary.withValues(alpha: 0.14),
                ),
                child:
                    Icon(Icons.smart_display_outlined, color: scheme.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Depuis YouTube',
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      'Rechercher et télécharger de nouveaux titres',
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

/// Rangée de station radio : lecture au tap, favori en action.
class _StationRow extends ConsumerWidget {
  const _StationRow({required this.station, required this.currentId});

  final RadioStation station;
  final String? currentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final isPlaying = currentId == station.streamUrl;
    final subtitle = [
      if (station.country != null) station.country!,
      if (station.genres.isNotEmpty) station.genres.take(2).join(', '),
    ].join(' · ');

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => ref.read(playerActionsProvider).playRadio(
              url: station.streamUrl,
              title: station.name,
              logo: station.logo,
            ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          child: Row(
            children: [
              Artwork(
                url: station.logo,
                size: 46,
                borderRadius: 12,
                icon: Icons.radio,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      station.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        color: isPlaying ? scheme.primary : null,
                      ),
                    ),
                    if (subtitle.isNotEmpty)
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
              IconButton(
                tooltip: 'Favori',
                icon: Icon(
                  station.favorite ? Icons.favorite : Icons.favorite_border,
                  color: station.favorite ? scheme.primary : scheme.outline,
                ),
                onPressed: () async {
                  await ref
                      .read(radioRepositoryProvider)
                      .toggleFavorite(station.id);
                  ref.invalidate(radioStationsProvider);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Rangée de résultat (artiste ou album), même langage que les titres.
class _ResultRow extends StatelessWidget {
  const _ResultRow({
    required this.artwork,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final Widget artwork;
  final String title;
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
              artwork,
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
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

class _NoResults extends StatelessWidget {
  const _NoResults({required this.query});

  final String query;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 50, 20, 20),
      child: Column(
        children: [
          Icon(
            Icons.search_off,
            size: 40,
            color: scheme.onSurfaceVariant.withValues(alpha: 0.6),
          ),
          const SizedBox(height: 12),
          Text(
            'Aucun résultat pour « $query »',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
