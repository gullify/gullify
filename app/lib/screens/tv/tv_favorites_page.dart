import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/song.dart';
import '../../state/favorites.dart';
import '../../state/player.dart';
import 'tv_kit.dart';

/// Les favoris : une liste de titres, la pochette du titre visé en grand.
///
/// Le grand aperçu n'est pas décoratif — sur une liste de cent lignes lues à
/// trois mètres, c'est la pochette qui dit où on en est, bien avant le texte.
class TvFavoritesPage extends ConsumerStatefulWidget {
  const TvFavoritesPage({super.key});

  @override
  ConsumerState<TvFavoritesPage> createState() => _TvFavoritesPageState();
}

class _TvFavoritesPageState extends ConsumerState<TvFavoritesPage> {
  int _preview = 0;

  @override
  Widget build(BuildContext context) {
    final favorites = ref.watch(allFavoritesProvider);
    final songs = favorites.value ?? const <Song>[];
    final current = ref.watch(currentMediaItemProvider).value;

    return TvScaffold(
      title: 'Favoris',
      trailing: songs.isEmpty
          ? null
          : Row(
              children: [
                TvPill(
                  label: 'Tout lire',
                  icon: Icons.play_arrow_rounded,
                  onPressed: () => _play(songs, 0),
                ),
                const SizedBox(width: 12),
                TvPill(
                  label: 'Mélanger',
                  icon: Icons.shuffle_rounded,
                  accent: false,
                  onPressed: () => _play([...songs]..shuffle(), 0),
                ),
              ],
            ),
      child: favorites.isLoading
          ? const Center(child: CircularProgressIndicator())
          : songs.isEmpty
          ? const TvEmpty(
              message: 'Aucun favori',
              hint:
                  'Le cœur du lecteur — sur le téléphone, dans la voiture ou '
                  'ici — remplit cette liste.',
              icon: Icons.favorite_border_rounded,
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 380,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TvArtwork(
                        url: songs[_preview.clamp(0, songs.length - 1)]
                            .artworkUrl,
                        size: 380,
                        borderRadius: 28,
                      ),
                      const SizedBox(height: 22),
                      Text(
                        songs[_preview.clamp(0, songs.length - 1)].albumName ??
                            '',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w700,
                          height: 1.15,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${songs.length} titres',
                        style: TextStyle(
                          fontSize: tvMinText,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 56),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.only(bottom: 40),
                    itemCount: songs.length,
                    itemBuilder: (context, i) => Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: TvTrackTile(
                        index: i + 1,
                        title: songs[i].title,
                        subtitle: songs[i].artistName,
                        duration: _mmss(songs[i].duration),
                        autofocus: i == 0,
                        playing: current?.id == '${songs[i].id}',
                        onFocusChange: (f) {
                          if (f && mounted) setState(() => _preview = i);
                        },
                        onPressed: () => _play(songs, i),
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Future<void> _play(List<Song> songs, int index) async {
    await ref.read(playerActionsProvider).playSongs(songs, startIndex: index);
    if (mounted) context.push('/tv/playing');
  }
}

String _mmss(int seconds) {
  final m = seconds ~/ 60;
  final s = (seconds % 60).toString().padLeft(2, '0');
  return '$m:$s';
}
