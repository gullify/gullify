import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/album.dart';
import '../models/song.dart';
import '../state/library.dart';
import '../state/offline.dart';
import '../state/player.dart';
import '../widgets/artwork.dart';
import '../widgets/glass_kit.dart';
import 'shell_screen.dart';
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
      bottomNavigationBar: const DetailDock(),
      body: detail.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Erreur: $e')),
        data: (d) => ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            _AlbumHeader(album: d.album, songCount: d.songs.length),
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

/// En-tête d'album immersif : pochette floutée plein cadre qui se dissout
/// dans le fond de l'app, pochette nette + titre + artiste en surimpression.
class _AlbumHeader extends StatelessWidget {
  const _AlbumHeader({required this.album, required this.songCount});

  final Album album;
  final int songCount;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final topInset = MediaQuery.paddingOf(context).top;

    return SizedBox(
      height: 440,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Pochette plein cadre qui se DISSOUT vers le bas (ShaderMask) —
          // même traitement que la page artiste, sans flou.
          ShaderMask(
            shaderCallback: (rect) => const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              stops: [0.0, 0.5, 1.0],
              colors: [Colors.white, Colors.white, Colors.transparent],
            ).createShader(rect),
            blendMode: BlendMode.dstIn,
            child: Artwork(url: album.artworkUrl, borderRadius: 0),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: topInset + 70,
            child: const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0x33000000), Color(0x00000000)],
                ),
              ),
            ),
          ),
          Positioned(
            left: 14,
            top: topInset + 8,
            child: GlassIconButton(
              icon: Icons.chevron_left,
              tooltip: 'Retour',
              onPressed: () => context.pop(),
            ),
          ),
          Positioned(
            left: 20,
            right: 20,
            bottom: 12,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  album.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.8,
                    height: 1.04,
                  ),
                ),
                if (album.artistName != null)
                  InkWell(
                    onTap: album.artistId != null
                        ? () => context.push('/artist/${album.artistId}')
                        : null,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              album.artistName!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 14.5,
                                fontWeight: FontWeight.w700,
                                color: scheme.primary,
                              ),
                            ),
                          ),
                          Icon(Icons.chevron_right,
                              size: 18, color: scheme.primary),
                        ],
                      ),
                    ),
                  ),
                Text(
                  [
                    if (album.year != null) '${album.year}',
                    '$songCount titre${songCount > 1 ? 's' : ''}',
                  ].join(' · '),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
