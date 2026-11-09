import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/album.dart';
import '../models/artist.dart';
import '../state/collection_play.dart';
import '../state/library.dart';
import '../widgets/album_card.dart';
import '../widgets/artist_row.dart';
import '../widgets/genre_mosaic.dart';
import '../widgets/glass_kit.dart';
import '../widgets/mascot_empty.dart';
import '../widgets/play_pair.dart';
import 'shell_screen.dart';

/// Un genre en entier : mosaïque de ses pochettes, de quoi le lancer dans
/// l'ordre ou mélangé, puis ses albums (grille) et ses artistes (liste).
///
/// Ou une origine en entier ([origine] au lieu de [genre]) : tout le Québec,
/// toute la France. Sous l'en-tête, une rangée de puces croise l'autre axe :
/// dans « Rock », [Québec] [France]… ; dans « Québec », [Rock] [Folk]… Le
/// filtre vaut pour les albums, les artistes ET les deux boutons de lecture.
class GenreScreen extends ConsumerStatefulWidget {
  const GenreScreen({super.key, this.genre, this.origine})
    : assert(genre != null || origine != null);

  final String? genre;
  final String? origine;

  @override
  ConsumerState<GenreScreen> createState() => _GenreScreenState();
}

class _GenreScreenState extends ConsumerState<GenreScreen> {
  /// La puce choisie : une origine (page d'un genre) ou un genre (page d'une
  /// origine). Nulle = tout.
  String? _filtre;

  bool get _parOrigine => widget.genre == null;
  Facette get _facette => (genre: widget.genre, origine: widget.origine);

  Future<void> _refresh() async {
    if (_parOrigine) {
      ref.invalidate(albumsByFacetProvider(_facette));
      ref.invalidate(artistsByFacetProvider(_facette));
      await Future.wait([
        ref.read(albumsByFacetProvider(_facette).future),
        ref.read(artistsByFacetProvider(_facette).future),
      ]);
    } else {
      ref.invalidate(albumsByGenreProvider(widget.genre!));
      ref.invalidate(artistsByGenreProvider(widget.genre!));
      await Future.wait([
        ref.read(albumsByGenreProvider(widget.genre!).future),
        ref.read(artistsByGenreProvider(widget.genre!).future),
      ]);
    }
  }

  /// Les genres d'un artiste, le principal compris même d'un vieux serveur.
  static List<String> _genresDe(Artist a) =>
      a.genres.isNotEmpty ? a.genres : [?a.genre];

  /// Les puces de l'autre axe, des plus fournies aux plus rares.
  List<(String, int)> _puces(List<Artist> artists) {
    final counts = <String, int>{};
    for (final a in artists) {
      final valeurs = _parOrigine ? _genresDe(a) : [?a.origine];
      for (final v in valeurs) {
        if (v.isEmpty) continue;
        counts[v] = (counts[v] ?? 0) + 1;
      }
    }
    final list = [for (final e in counts.entries) (e.key, e.value)]
      ..sort((x, y) => y.$2 != x.$2 ? y.$2 - x.$2 : x.$1.compareTo(y.$1));
    return list;
  }

  bool _garde(Artist a) => _filtre == null ||
      (_parOrigine ? _genresDe(a).contains(_filtre) : a.origine == _filtre);

  @override
  Widget build(BuildContext context) {
    // Une page de genre garde ses fournisseurs de toujours (ils servent
    // ailleurs, et au volant) ; une page d'origine passe par la facette.
    final AsyncValue<List<Album>> albums = _parOrigine
        ? ref.watch(albumsByFacetProvider(_facette))
        : ref.watch(albumsByGenreProvider(widget.genre!));
    final AsyncValue<List<Artist>> artists = _parOrigine
        ? ref.watch(artistsByFacetProvider(_facette))
        : ref.watch(artistsByGenreProvider(widget.genre!));

    final allArtists = artists.value ?? const <Artist>[];
    final puces = _puces(allArtists);
    // Un filtre qui ne correspond plus à rien (après un rafraîchissement)
    // retombe sur « tout ».
    if (_filtre != null && !puces.any((p) => p.$1 == _filtre)) _filtre = null;

    final artistList = [for (final a in allArtists) if (_garde(a)) a];
    final ids = {for (final a in artistList) a.id};
    final albumList = [
      for (final al in albums.value ?? const <Album>[])
        if (_filtre == null || ids.contains(al.artistId)) al,
    ];
    final loading = albums.isLoading || artists.isLoading;
    final error = albums.error ?? artists.error;
    final empty = !loading && albumList.isEmpty && artistList.isEmpty;

    // Une seule valeur, portée par tout le monde : rien à filtrer.
    final montrerPuces = puces.length > 1 ||
        (puces.length == 1 && puces.first.$2 < allArtists.length);

    final genre = widget.genre ?? (_parOrigine ? _filtre : null);
    final origine = widget.origine ?? (_parOrigine ? null : _filtre);

    return Scaffold(
      appBar: AppBar(title: Text(widget.genre ?? widget.origine!)),
      bottomNavigationBar: const DetailDock(),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: _GenreHeader(
                albums: albumList,
                artistCount: artistList.length,
                play: genre != null
                    ? GenrePlayButtons(genre: genre, origine: origine)
                    : OriginePlayButtons(origine: origine!),
              ),
            ),
            if (montrerPuces)
              SliverToBoxAdapter(
                child: _Puces(
                  puces: puces,
                  total: allArtists.length,
                  choisie: _filtre,
                  onChoix: (v) => setState(() => _filtre = v),
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
              SliverToBoxAdapter(
                child: MascotEmpty(
                  message: _parOrigine
                      ? 'Personne de là pour l\'instant'
                      : 'Rien dans ce genre',
                  hint: _parOrigine
                      ? 'L\'origine se règle depuis la fiche d\'un artiste.'
                      : 'Assigne ce genre à un artiste depuis sa fiche.',
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

/// La rangée de puces qui croise l'autre axe : « Tous », puis chaque valeur
/// et le nombre d'artistes qui la portent. Elle défile de côté.
class _Puces extends StatelessWidget {
  const _Puces({
    required this.puces,
    required this.total,
    required this.choisie,
    required this.onChoix,
  });

  final List<(String, int)> puces;
  final int total;
  final String? choisie;
  final ValueChanged<String?> onChoix;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(17, 6, 17, 2),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: ChoiceChip(
              label: Text('Tous · $total'),
              selected: choisie == null,
              onSelected: (_) => onChoix(null),
            ),
          ),
          for (final (nom, n) in puces)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: ChoiceChip(
                label: Text('$nom · $n'),
                selected: choisie == nom,
                onSelected: (_) => onChoix(choisie == nom ? null : nom),
              ),
            ),
        ],
      ),
    );
  }
}

/// En-tête : mosaïque des pochettes du genre, ce qu'il contient, et les deux
/// façons de le lancer.
class _GenreHeader extends StatelessWidget {
  const _GenreHeader({
    required this.albums,
    required this.artistCount,
    required this.play,
  });

  final List<Album> albums;
  final int artistCount;

  /// Les deux boutons de lecture, déjà réglés sur ce qu'on regarde.
  final Widget play;

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
                play,
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Lance le genre entier : dans l'ordre, ou mélangé par le serveur. C'est le
/// même geste qu'au volant, où les deux entrées ouvrent un genre (idée #109) —
/// et la même liste, repli par artiste compris.
class GenrePlayButtons extends ConsumerWidget {
  const GenrePlayButtons({super.key, required this.genre, this.origine});

  final String genre;

  /// Restreint aux artistes venus de là (la puce choisie sur la page).
  final String? origine;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PaireDeLecture(
      vide: 'Aucun titre dans ce genre',
      titres: ({required bool shuffle}) => titresDuGenre(
        ref.read(libraryRepositoryProvider),
        genre,
        shuffle: shuffle,
        origine: origine,
      ),
    );
  }
}

/// Lance une origine entière (tout le Québec), dans l'ordre ou mélangée.
class OriginePlayButtons extends ConsumerWidget {
  const OriginePlayButtons({super.key, required this.origine});

  final String origine;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PaireDeLecture(
      vide: 'Aucun titre de là',
      titres: ({required bool shuffle}) => titresDeLOrigine(
        ref.read(libraryRepositoryProvider),
        origine,
        shuffle: shuffle,
      ),
    );
  }
}
