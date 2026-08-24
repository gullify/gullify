import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../api/playlist_repository.dart';
import '../../models/song.dart';
import '../../state/library.dart';
import '../../state/player.dart';
import '../../state/playlists.dart';
import 'tv_kit.dart';

/// Un genre : ses albums, puis ses artistes.
class TvGenreScreen extends ConsumerWidget {
  const TvGenreScreen({super.key, required this.genre});

  final String genre;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final albums = ref.watch(albumsByGenreProvider(genre));
    final artists = ref.watch(artistsByGenreProvider(genre));
    final albumList = albums.value ?? const [];
    final artistList = artists.value ?? const [];

    return TvScaffold(
      title: genre,
      child: albums.isLoading && artists.isLoading
          ? const Center(child: CircularProgressIndicator())
          : albumList.isEmpty && artistList.isEmpty
          ? TvEmpty(
              message: 'Rien sous « $genre »',
              hint:
                  'Ce genre n\'est encore attribué à aucun album de ta '
                  'bibliothèque.',
              icon: Icons.label_off_rounded,
            )
          : ListView(
              padding: const EdgeInsets.only(bottom: 40),
              children: [
                if (albumList.isNotEmpty)
                  TvShelf(
                    label: 'Albums',
                    itemCount: albumList.length,
                    itemBuilder: (context, i, onFocus) => TvCard(
                      title: albumList[i].name,
                      subtitle: albumList[i].artistName,
                      autofocus: i == 0,
                      artwork: TvArtwork(
                        url: albumList[i].artworkUrl,
                        size: 250,
                        borderRadius: 0,
                      ),
                      onFocusChange: (f) {
                        if (f) onFocus();
                      },
                      onPressed: () =>
                          context.push('/tv/album/${albumList[i].id}'),
                    ),
                  ),
                if (artistList.isNotEmpty) ...[
                  const SizedBox(height: 46),
                  TvShelf(
                    label: 'Artistes',
                    itemCount: artistList.length,
                    itemBuilder: (context, i, onFocus) => TvCard(
                      title: artistList[i].name,
                      subtitle: '${artistList[i].albumCount} albums',
                      round: true,
                      icon: Icons.person_rounded,
                      artwork: TvArtwork(
                        url: artistList[i].imageUrl,
                        size: 250,
                        borderRadius: 0,
                      ),
                      onFocusChange: (f) {
                        if (f) onFocus();
                      },
                      onPressed: () =>
                          context.push('/tv/artist/${artistList[i].id}'),
                    ),
                  ),
                ],
              ],
            ),
    );
  }
}

/// Une playlist : sa liste de titres, la pochette du titre visé en grand.
class TvPlaylistScreen extends ConsumerStatefulWidget {
  const TvPlaylistScreen({super.key, required this.id, required this.name});

  final int id;
  final String name;

  @override
  ConsumerState<TvPlaylistScreen> createState() => _TvPlaylistScreenState();
}

class _TvPlaylistScreenState extends ConsumerState<TvPlaylistScreen> {
  int _preview = 0;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final entries = ref.watch(playlistSongsProvider(widget.id));
    final songs = <Song>[
      for (final e in entries.value ?? const <PlaylistEntry>[]) e.song,
    ];
    final current = ref.watch(currentMediaItemProvider).value;

    return TvScaffold(
      title: widget.name,
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
      child: entries.isLoading
          ? const Center(child: CircularProgressIndicator())
          : songs.isEmpty
          ? const TvEmpty(
              message: 'Playlist vide',
              hint: 'Ajoute-lui des titres depuis l\'app mobile.',
              icon: Icons.queue_music_rounded,
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
                      const SizedBox(height: 20),
                      Text(
                        '${songs.length} titres',
                        style: TextStyle(
                          fontSize: 24,
                          color: scheme.onSurfaceVariant,
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
