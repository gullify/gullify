import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../state/library.dart';
import '../../state/playlists.dart';
import 'tv_kit.dart';

/// La bibliothèque en grille : albums ou artistes.
///
/// C'est le seul écran où la grille bat la rangée — on vient y chercher
/// quelque chose de précis, pas se laisser porter, et une grille montre
/// quatre fois plus de pochettes d'un coup d'œil.
class TvLibraryPage extends ConsumerStatefulWidget {
  const TvLibraryPage({super.key});

  @override
  ConsumerState<TvLibraryPage> createState() => _TvLibraryPageState();
}

enum _Kind {
  albums('Albums'),
  artists('Artistes'),
  genres('Genres'),
  playlists('Playlists');

  const _Kind(this.label);

  final String label;
}

class _TvLibraryPageState extends ConsumerState<TvLibraryPage> {
  _Kind _kind = _Kind.albums;

  @override
  Widget build(BuildContext context) {
    final albums = ref.watch(albumsProvider);
    final artists = ref.watch(artistsProvider);
    final genres = ref.watch(genresProvider);
    final playlists = ref.watch(playlistsProvider);
    final source = switch (_kind) {
      _Kind.albums => albums,
      _Kind.artists => artists,
      _Kind.genres => genres,
      _Kind.playlists => playlists,
    };
    final loading = source.isLoading;
    final count = source.value?.length ?? 0;

    return TvScaffold(
      title: 'Bibliothèque',
      trailing: Row(
        children: [
          for (final kind in _Kind.values) ...[
            if (kind != _Kind.values.first) const SizedBox(width: 10),
            TvPill(
              label: kind.label,
              accent: _kind == kind,
              compact: true,
              onPressed: () => setState(() => _kind = kind),
            ),
          ],
        ],
      ),
      child: loading
          ? const Center(child: CircularProgressIndicator())
          : count == 0
          ? TvEmpty(
              message: switch (_kind) {
                _Kind.genres => 'Aucun genre',
                _Kind.playlists => 'Aucune playlist',
                _ => 'Rien à écouter pour l\'instant',
              },
              hint: switch (_kind) {
                _Kind.genres =>
                  'Les genres se règlent depuis l\'app mobile, dans les '
                      'paramètres de la bibliothèque.',
                _Kind.playlists =>
                  'Crée-en une depuis l\'app mobile : elle apparaîtra ici.',
                _ =>
                  'Lance un scan de la bibliothèque depuis l\'app mobile, '
                      'puis reviens ici.',
              },
              icon: switch (_kind) {
                _Kind.genres => Icons.label_outline_rounded,
                _Kind.playlists => Icons.queue_music_rounded,
                _ => Icons.library_music_rounded,
              },
            )
          // La largeur d'une case se calcule, elle ne se devine pas : c'est
          // elle qui fixe la taille de la pochette ET le rapport d'aspect,
          // sinon les deux lignes de texte se font rogner.
          : LayoutBuilder(
              builder: (context, box) {
                const columns = 6;
                const gap = 26.0;
                final cell =
                    (box.maxWidth - tvFocusMargin * 2 - gap * (columns - 1)) /
                    columns;
                return GridView.builder(
                  // Marge de grossissement : sans elle, les vignettes des
                  // bords sont rognées dès qu'on les vise.
                  padding: const EdgeInsets.fromLTRB(
                    tvFocusMargin,
                    tvFocusMargin,
                    tvFocusMargin,
                    40,
                  ),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columns,
                    mainAxisSpacing: 34,
                    crossAxisSpacing: gap,
                    // Pochette carrée + deux lignes de texte.
                    // Une contrainte dégénérée ne doit jamais produire un rapport
                    // nul : en release, il finirait en NaN dans la géométrie.
                    childAspectRatio: cell > 0 ? cell / (cell + 84) : 1,
                  ),
                  itemCount: count,
                  itemBuilder: (context, i) {
                    switch (_kind) {
                      case _Kind.albums:
                        final a = albums.value![i];
                        return TvCard(
                          title: a.name,
                          subtitle: a.artistName,
                          size: cell,
                          autofocus: i == 0,
                          artwork: TvArtwork(
                            url: a.artworkUrl,
                            borderRadius: 0,
                          ),
                          onPressed: () => context.push('/tv/album/${a.id}'),
                        );
                      case _Kind.artists:
                        final a = artists.value![i];
                        return TvCard(
                          title: a.name,
                          subtitle: '${a.albumCount} albums',
                          size: cell,
                          round: true,
                          autofocus: i == 0,
                          icon: Icons.person_rounded,
                          artwork: TvArtwork(url: a.imageUrl, borderRadius: 0),
                          onPressed: () => context.push('/tv/artist/${a.id}'),
                        );
                      case _Kind.genres:
                        final g = genres.value![i];
                        return TvCard(
                          title: g.name,
                          subtitle: '${g.albumCount} albums',
                          size: cell,
                          autofocus: i == 0,
                          icon: Icons.label_rounded,
                          onPressed: () => context.push(
                            '/tv/genre/${Uri.encodeComponent(g.name)}',
                          ),
                        );
                      case _Kind.playlists:
                        final p = playlists.value![i];
                        return TvCard(
                          title: p.name,
                          subtitle: '${p.songCount} titres',
                          size: cell,
                          autofocus: i == 0,
                          icon: Icons.queue_music_rounded,
                          onPressed: () => context.push(
                            '/tv/playlist/${p.id}'
                            '?name=${Uri.encodeComponent(p.name)}',
                          ),
                        );
                    }
                  },
                );
              },
            ),
    );
  }
}
