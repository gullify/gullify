import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/song.dart';
import '../state/library.dart';
import '../state/offline.dart';
import '../state/player.dart';
import '../widgets/artwork.dart';
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
      appBar: AppBar(),
      body: detail.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Erreur: $e')),
        data: (d) => ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Artwork(url: d.album.artworkUrl, size: 140),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          d.album.name,
                          style: Theme.of(context)
                              .textTheme
                              .titleLarge
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        if (d.album.artistName != null)
                          Text(
                            d.album.artistName!,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        if (d.album.year != null)
                          Text(
                            '${d.album.year}',
                            style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                          ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            FilledButton.icon(
                              onPressed: d.songs.isEmpty
                                  ? null
                                  : () => ref
                                      .read(playerActionsProvider)
                                      .playSongs(d.songs),
                              icon: const Icon(Icons.play_arrow),
                              label: const Text('Lecture'),
                            ),
                            if (offlineSupported) ...[
                              const SizedBox(width: 8),
                              _DownloadAlbumButton(songs: d.songs),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
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
        width: 40,
        height: 40,
        child: Padding(
          padding: EdgeInsets.all(10),
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    return IconButton.outlined(
      tooltip: allDownloaded ? 'Album téléchargé' : "Télécharger l'album",
      icon: Icon(
        allDownloaded ? Icons.download_done : Icons.download_outlined,
      ),
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
