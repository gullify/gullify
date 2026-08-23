import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/song.dart';
import '../../state/library.dart';
import '../../state/player.dart';
import 'tv_kit.dart';

/// Un artiste : un bandeau, ses albums en rangée, ses titres phares dessous.
class TvArtistScreen extends ConsumerWidget {
  const TvArtistScreen({super.key, required this.artistId});

  final int artistId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final detail = ref.watch(artistDetailProvider(artistId));
    final current = ref.watch(currentMediaItemProvider).value;

    return TvScaffold(
      child: detail.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => TvEmpty(
          message: 'Artiste injoignable',
          hint: '$e',
          icon: Icons.cloud_off_rounded,
        ),
        data: (d) => ListView(
          padding: const EdgeInsets.only(bottom: 40),
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                TvArtwork(url: d.artist.imageUrl, size: 240, borderRadius: 120),
                const SizedBox(width: 40),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        d.artist.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 62,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -1.9,
                          height: 1.02,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        '${d.albums.length} albums · ${d.artist.songCount} titres',
                        style: TextStyle(
                          fontSize: 26,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 24),
                      Row(
                        children: [
                          TvPill(
                            label: 'Écouter',
                            icon: Icons.play_arrow_rounded,
                            autofocus: true,
                            onPressed: () =>
                                _play(context, ref, d.topTracks, 0),
                          ),
                          const SizedBox(width: 14),
                          TvPill(
                            label: 'Mélanger',
                            icon: Icons.shuffle_rounded,
                            accent: false,
                            onPressed: () => _play(
                              context,
                              ref,
                              [...d.topTracks]..shuffle(),
                              0,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 50),
            if (d.albums.isNotEmpty)
              TvShelf(
                label: 'Albums',
                itemCount: d.albums.length,
                itemBuilder: (context, i, onFocus) => TvCard(
                  title: d.albums[i].name,
                  subtitle: d.albums[i].year?.toString(),
                  artwork: TvArtwork(
                    url: d.albums[i].artworkUrl,
                    size: 250,
                    borderRadius: 0,
                  ),
                  onFocusChange: (f) {
                    if (f) onFocus();
                  },
                  onPressed: () => context.push('/tv/album/${d.albums[i].id}'),
                ),
              ),
            if (d.topTracks.isNotEmpty) ...[
              const SizedBox(height: 46),
              const TvShelfLabel('Titres phares'),
              for (var i = 0; i < d.topTracks.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: TvTrackTile(
                    index: i + 1,
                    title: d.topTracks[i].title,
                    subtitle: d.topTracks[i].albumName,
                    duration: _mmss(d.topTracks[i].duration),
                    playing: current?.id == '${d.topTracks[i].id}',
                    onPressed: () => _play(context, ref, d.topTracks, i),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _play(
    BuildContext context,
    WidgetRef ref,
    List<Song> songs,
    int index,
  ) async {
    if (songs.isEmpty) return;
    await ref.read(playerActionsProvider).playSongs(songs, startIndex: index);
    if (context.mounted) context.push('/tv/playing');
  }
}

String _mmss(int seconds) {
  final m = seconds ~/ 60;
  final s = (seconds % 60).toString().padLeft(2, '0');
  return '$m:$s';
}
