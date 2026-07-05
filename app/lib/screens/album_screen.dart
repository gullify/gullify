import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/song.dart';
import '../state/library.dart';
import '../state/offline.dart';
import '../state/player.dart';
import '../widgets/artwork.dart';
import '../widgets/glass_kit.dart';
import '../widgets/mini_player.dart';
import '../widgets/song_menu.dart';
import '../widgets/song_tile.dart';

class AlbumScreen extends ConsumerWidget {
  const AlbumScreen({super.key, required this.albumId});

  final int albumId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(albumDetailProvider(albumId));
    final currentSongId = ref
        .watch(currentMediaItemProvider)
        .value
        ?.extras?['songId'] as int?;

    return Scaffold(
      bottomNavigationBar: const SafeArea(top: false, child: MiniPlayer()),
      body: detail.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Erreur: $e')),
        data: (d) => ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            // Retour : rond de verre, comme le design (pas d'AppBar).
            SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 20, 6),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: GlassIconButton(
                    icon: Icons.chevron_left,
                    tooltip: 'Retour',
                    onPressed: () => context.pop(),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(22),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x47141932),
                          blurRadius: 40,
                          offset: Offset(0, 18),
                        ),
                      ],
                    ),
                    child: Artwork(
                      url: d.album.artworkUrl,
                      size: 120,
                      borderRadius: 22,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          d.album.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 23,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.5,
                            height: 1.08,
                          ),
                        ),
                        if (d.album.artistName != null)
                          InkWell(
                            onTap: d.album.artistId != null
                                ? () => context
                                    .push('/artist/${d.album.artistId}')
                                : null,
                            child: Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Flexible(
                                    child: Text(
                                      d.album.artistName!,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .primary,
                                      ),
                                    ),
                                  ),
                                  Icon(
                                    Icons.chevron_right,
                                    size: 18,
                                    color:
                                        Theme.of(context).colorScheme.primary,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        Text(
                          [
                            if (d.album.year != null) '${d.album.year}',
                            '${d.songs.length} titre${d.songs.length > 1 ? 's' : ''}',
                          ].join(' · '),
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 6),
              child: Row(
                children: [
                  Expanded(
                    child: AccentPlayButton(
                      onPressed: d.songs.isEmpty
                          ? null
                          : () => ref
                              .read(playerActionsProvider)
                              .playSongs(d.songs),
                    ),
                  ),
                  const SizedBox(width: 12),
                  GlassIconButton(
                    icon: Icons.shuffle,
                    tooltip: 'Lecture aléatoire',
                    size: 50,
                    onPressed: d.songs.isEmpty
                        ? null
                        : () => ref
                            .read(playerActionsProvider)
                            .playSongs(d.songs.toList()..shuffle()),
                  ),
                  if (offlineSupported) ...[
                    const SizedBox(width: 12),
                    _DownloadAlbumButton(songs: d.songs),
                  ],
                ],
              ),
            ),
            for (final (i, song) in d.songs.indexed)
              SongTile(
                song: song,
                showArtwork: false,
                leadingNumber: song.trackNumber ?? i + 1,
                isPlaying: song.id == currentSongId,
                onTap: () => ref
                    .read(playerActionsProvider)
                    .playSongs(d.songs, startIndex: i),
                onLongPress: () => showSongMenu(context, song),
              ),
          ],
        ),
      ),
    );
  }
}

class _DownloadAlbumButton extends ConsumerStatefulWidget {
  const _DownloadAlbumButton({required this.songs});

  final List<Song> songs;

  @override
  ConsumerState<_DownloadAlbumButton> createState() =>
      _DownloadAlbumButtonState();
}

class _DownloadAlbumButtonState extends ConsumerState<_DownloadAlbumButton> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final offline = ref.watch(offlineProvider).value ?? {};
    final allDownloaded = widget.songs.isNotEmpty &&
        widget.songs.every((s) => offline.containsKey(s.id));

    if (_busy) {
      return const SizedBox(
        width: 50,
        height: 50,
        child: Padding(
          padding: EdgeInsets.all(14),
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    return GlassIconButton(
      size: 50,
      tooltip: allDownloaded ? 'Album téléchargé' : "Télécharger l'album",
      icon: allDownloaded ? Icons.download_done : Icons.download_outlined,
      onPressed: allDownloaded || widget.songs.isEmpty
          ? null
          : () async {
              setState(() => _busy = true);
              final messenger = ScaffoldMessenger.of(context);
              try {
                await ref
                    .read(offlineProvider.notifier)
                    .downloadAll(widget.songs);
                messenger.showSnackBar(
                  const SnackBar(content: Text('Album téléchargé')),
                );
              } catch (_) {
                messenger.showSnackBar(
                  const SnackBar(content: Text('Échec du téléchargement')),
                );
              } finally {
                if (mounted) setState(() => _busy = false);
              }
            },
    );
  }
}
