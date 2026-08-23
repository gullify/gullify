import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/song.dart';
import '../../state/library.dart';
import '../../state/player.dart';
import 'tv_kit.dart';

/// Un album : son identité plantée à gauche, ses pistes à droite.
///
/// Deux colonnes plutôt qu'un défilement vertical — la pochette et le titre
/// restent en vue pendant qu'on parcourt les pistes, ce qui évite de perdre
/// le fil sur un écran où l'on ne voit qu'à moitié ce qu'on manipule.
class TvAlbumScreen extends ConsumerWidget {
  const TvAlbumScreen({super.key, required this.albumId});

  final int albumId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final detail = ref.watch(albumDetailProvider(albumId));
    final current = ref.watch(currentMediaItemProvider).value;

    return TvScaffold(
      child: detail.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => TvEmpty(
          message: 'Album injoignable',
          hint: '$e',
          icon: Icons.cloud_off_rounded,
        ),
        data: (d) => Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 430,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TvArtwork(
                    url: d.album.artworkUrl,
                    size: 430,
                    borderRadius: 30,
                  ),
                  const SizedBox(height: 28),
                  Text(
                    d.album.name,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 46,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -1.3,
                      height: 1.06,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    d.album.artistName ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 30,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    [
                      if (d.album.year != null) '${d.album.year}',
                      '${d.songs.length} titres',
                      _total(d.songs),
                    ].join(' · '),
                    style: TextStyle(
                      fontSize: 24,
                      color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
                    ),
                  ),
                  const SizedBox(height: 30),
                  Row(
                    children: [
                      TvPill(
                        label: 'Lecture',
                        icon: Icons.play_arrow_rounded,
                        autofocus: true,
                        onPressed: () => _play(context, ref, d.songs, 0),
                      ),
                      const SizedBox(width: 14),
                      TvPill(
                        label: '',
                        icon: Icons.shuffle_rounded,
                        accent: false,
                        onPressed: () =>
                            _play(context, ref, [...d.songs]..shuffle(), 0),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 64),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.only(bottom: 40),
                itemCount: d.songs.length,
                itemBuilder: (context, i) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: TvTrackTile(
                    index: d.songs[i].trackNumber ?? i + 1,
                    title: d.songs[i].title,
                    // L'interprète n'apparaît que s'il diffère de l'artiste de
                    // l'album : sur une compilation il est indispensable, sur
                    // un album normal il répéterait la colonne de gauche.
                    subtitle:
                        d.songs[i].artistName != null &&
                            d.songs[i].artistName != d.album.artistName
                        ? d.songs[i].artistName
                        : null,
                    duration: _mmss(d.songs[i].duration),
                    playing: current?.id == '${d.songs[i].id}',
                    onPressed: () => _play(context, ref, d.songs, i),
                  ),
                ),
              ),
            ),
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

String _total(List<Song> songs) {
  final seconds = songs.fold<int>(0, (sum, s) => sum + s.duration);
  final minutes = seconds ~/ 60;
  return minutes >= 60
      ? '${minutes ~/ 60} h ${(minutes % 60).toString().padLeft(2, '0')}'
      : '$minutes min';
}

String _mmss(int seconds) {
  final m = seconds ~/ 60;
  final s = (seconds % 60).toString().padLeft(2, '0');
  return '$m:$s';
}
