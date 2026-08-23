import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../state/library.dart';
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

enum _Kind { albums, artists }

class _TvLibraryPageState extends ConsumerState<TvLibraryPage> {
  _Kind _kind = _Kind.albums;

  @override
  Widget build(BuildContext context) {
    final albums = ref.watch(albumsProvider);
    final artists = ref.watch(artistsProvider);
    final loading = _kind == _Kind.albums
        ? albums.isLoading
        : artists.isLoading;
    final count = _kind == _Kind.albums
        ? (albums.value?.length ?? 0)
        : (artists.value?.length ?? 0);

    return TvScaffold(
      title: 'Bibliothèque',
      trailing: Row(
        children: [
          TvPill(
            label: 'Albums',
            accent: _kind == _Kind.albums,
            onPressed: () => setState(() => _kind = _Kind.albums),
          ),
          const SizedBox(width: 12),
          TvPill(
            label: 'Artistes',
            accent: _kind == _Kind.artists,
            onPressed: () => setState(() => _kind = _Kind.artists),
          ),
        ],
      ),
      child: loading
          ? const Center(child: CircularProgressIndicator())
          : count == 0
          ? const TvEmpty(
              message: 'Rien à écouter pour l\'instant',
              hint:
                  'Lance un scan de la bibliothèque depuis l\'app mobile, puis '
                  'reviens ici.',
              icon: Icons.library_music_rounded,
            )
          // La largeur d'une case se calcule, elle ne se devine pas : c'est
          // elle qui fixe la taille de la pochette ET le rapport d'aspect,
          // sinon les deux lignes de texte se font rogner.
          : LayoutBuilder(
              builder: (context, box) {
                const columns = 6;
                const gap = 26.0;
                final cell = (box.maxWidth - gap * (columns - 1)) / columns;
                return GridView.builder(
                  padding: const EdgeInsets.only(top: 8, bottom: 40),
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
                    if (_kind == _Kind.albums) {
                      final a = albums.value![i];
                      return TvCard(
                        title: a.name,
                        subtitle: a.artistName,
                        size: cell,
                        autofocus: i == 0,
                        artwork: TvArtwork(url: a.artworkUrl, borderRadius: 0),
                        onPressed: () => context.push('/tv/album/${a.id}'),
                      );
                    }
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
                  },
                );
              },
            ),
    );
  }
}
