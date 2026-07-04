import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api/library_repository.dart';
import '../api/yt_downloads_repository.dart';
import '../state/library.dart';
import '../state/player.dart';
import '../state/yt_downloads.dart';
import '../widgets/artwork.dart';
import '../widgets/glass_kit.dart';
import '../widgets/mini_player.dart';
import '../widgets/song_menu.dart';
import '../widgets/song_tile.dart';

class ArtistScreen extends ConsumerWidget {
  const ArtistScreen({super.key, required this.artistId});

  final int artistId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(artistDetailProvider(artistId));
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      bottomNavigationBar: const MiniPlayer(),
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
                padding: const EdgeInsets.fromLTRB(14, 10, 20, 0),
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
            const SizedBox(height: 14),
            Center(
              child: DecoratedBox(
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Color(0x59141932),
                      blurRadius: 40,
                      offset: Offset(0, 18),
                    ),
                  ],
                ),
                child: Artwork(
                  url: d.artist.imageUrl,
                  size: 118,
                  borderRadius: 59,
                  icon: Icons.person,
                ),
              ),
            ),
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                d.artist.name,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                ),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '${d.albums.length} album${d.albums.length > 1 ? 's' : ''}',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            _ArtistPlayBar(detail: d),
            if (d.albums.isNotEmpty) ...[
              const SectionTitle('Albums'),
              SizedBox(
                height: 216,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
                  itemCount: d.albums.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 13),
                  itemBuilder: (context, i) {
                    final album = d.albums[i];
                    return InkWell(
                      onTap: () => context.push('/album/${album.id}'),
                      borderRadius: BorderRadius.circular(20),
                      child: SizedBox(
                        width: 140,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            DecoratedBox(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(20),
                                boxShadow: const [
                                  BoxShadow(
                                    color: Color(0x40141932),
                                    blurRadius: 26,
                                    offset: Offset(0, 14),
                                  ),
                                ],
                              ),
                              child: Artwork(
                                url: album.artworkUrl,
                                size: 140,
                                borderRadius: 20,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              album.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 13.5,
                              ),
                            ),
                            if (album.year != null)
                              Text(
                                '${album.year}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
            if (d.topTracks.isNotEmpty) ...[
              const SectionTitle('Titres populaires'),
              const SizedBox(height: 6),
              for (final (i, track) in d.topTracks.indexed)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: SongTile(
                    song: track,
                    showArtwork: false,
                    leadingNumber: i + 1,
                    subtitle: track.albumName,
                    onTap: () => ref
                        .read(playerActionsProvider)
                        .playSongs(d.topTracks, startIndex: i),
                    onLongPress: () => showSongMenu(context, track),
                  ),
                ),
            ],
            _YtSuggestions(detail: d),
            _ArtistExtras(name: d.artist.name),
          ],
        ),
      ),
    );
  }
}

/// Albums YouTube Music non possédés, téléchargeables en un tap.
class _YtSuggestions extends ConsumerWidget {
  const _YtSuggestions({required this.detail});

  final ArtistDetail detail;

  String _normalize(String s) => s
      .toLowerCase()
      .replaceAll(RegExp(r'\s*\((deluxe|remaster(ed)?|edition)[^)]*\)'), '')
      .replaceAll(RegExp(r'[^a-z0-9]'), '');

  Future<void> _download(
    BuildContext context,
    WidgetRef ref,
    YtAlbum album,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    YtResolvedAlbum resolved;
    try {
      resolved = await ref
          .read(ytDownloadsRepositoryProvider)
          .resolveAlbum(album.browseId);
    } catch (e) {
      if (context.mounted) Navigator.pop(context);
      messenger.showSnackBar(SnackBar(content: Text('Erreur : $e')));
      return;
    }
    if (!context.mounted) return;
    Navigator.pop(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(resolved.title),
        content: Text(
          '${resolved.artist} · ${resolved.trackCount} pistes\n\n'
          'Télécharger cet album dans votre bibliothèque ?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Télécharger'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(ytQueueProvider.notifier).start(resolved);
      messenger.showSnackBar(
        SnackBar(content: Text('Téléchargement démarré : ${resolved.title}')),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Échec : $e')));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final suggestions = ref.watch(ytArtistAlbumsProvider(detail.artist.name));
    final owned = {for (final a in detail.albums) _normalize(a.name)};
    final artistKey = _normalize(detail.artist.name);

    return suggestions.maybeWhen(
      data: (albums) {
        final missing = albums
            .where((a) =>
                _normalize(a.artist) == artistKey &&
                !owned.contains(_normalize(a.title)))
            .toList();
        if (missing.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Text(
                'À découvrir sur YouTube Music',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            SizedBox(
              height: 180,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: missing.length,
                separatorBuilder: (_, _) => const SizedBox(width: 12),
                itemBuilder: (context, i) {
                  final a = missing[i];
                  return InkWell(
                    onTap: () => _download(context, ref, a),
                    borderRadius: BorderRadius.circular(10),
                    child: SizedBox(
                      width: 120,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Stack(
                            children: [
                              Artwork(url: a.thumbnail, size: 120),
                              Positioned(
                                right: 4,
                                bottom: 4,
                                child: CircleAvatar(
                                  radius: 14,
                                  backgroundColor:
                                      Theme.of(context).colorScheme.primary,
                                  child: Icon(
                                    Icons.download,
                                    size: 16,
                                    color:
                                        Theme.of(context).colorScheme.onPrimary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            a.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
      orElse: () => const SizedBox.shrink(),
    );
  }
}

/// Bio (Last.fm) et actualités (Google News) — meilleur effort.
class _ArtistExtras extends ConsumerWidget {
  const _ArtistExtras({required this.name});

  final String name;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final extras = ref.watch(artistExtrasProvider(name));
    final scheme = Theme.of(context).colorScheme;

    return extras.maybeWhen(
      data: (e) {
        if (e.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (e.bio != null && e.bio!.trim().isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Text(
                  'À propos',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _ExpandableText(e.bio!.trim()),
              ),
            ],
            if (e.articles.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: Text(
                  'Actualités',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              for (final article in e.articles)
                ListTile(
                  leading: const Icon(Icons.article_outlined),
                  title: Text(
                    article.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 14),
                  ),
                  subtitle: Text(
                    article.source,
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                  onTap: () => launchUrl(
                    Uri.parse(article.url),
                    mode: LaunchMode.externalApplication,
                  ),
                ),
            ],
          ],
        );
      },
      orElse: () => const SizedBox.shrink(),
    );
  }
}

class _ExpandableText extends StatefulWidget {
  const _ExpandableText(this.text);

  final String text;

  @override
  State<_ExpandableText> createState() => _ExpandableTextState();
}

class _ExpandableTextState extends State<_ExpandableText> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => setState(() => _expanded = !_expanded),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.text,
            maxLines: _expanded ? null : 4,
            overflow: _expanded ? null : TextOverflow.ellipsis,
            style: const TextStyle(height: 1.5),
          ),
          Text(
            _expanded ? 'Réduire' : 'Lire plus',
            style: TextStyle(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// « Tout lire » / « Aléatoire » : toutes les chansons de l'artiste,
/// dans l'ordre des albums ou mélangées.
class _ArtistPlayBar extends ConsumerStatefulWidget {
  const _ArtistPlayBar({required this.detail});

  final ArtistDetail detail;

  @override
  ConsumerState<_ArtistPlayBar> createState() => _ArtistPlayBarState();
}

class _ArtistPlayBarState extends ConsumerState<_ArtistPlayBar> {
  bool _busy = false;

  Future<void> _playAll({required bool shuffle}) async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final repo = ref.read(libraryRepositoryProvider);
      final details = await Future.wait([
        for (final a in widget.detail.albums) repo.albumDetail(a.id),
      ]);
      final songs = [for (final det in details) ...det.songs];
      if (songs.isEmpty) return;
      if (shuffle) songs.shuffle();
      await ref.read(playerActionsProvider).playSongs(songs);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Erreur : $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.detail.albums.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          GlassIconButton(
            icon: Icons.shuffle,
            tooltip: 'Tout lire aléatoirement',
            size: 48,
            onPressed: _busy ? null : () => _playAll(shuffle: true),
          ),
          const SizedBox(width: 12),
          _busy
              ? const SizedBox(
                  width: 52,
                  height: 52,
                  child: Padding(
                    padding: EdgeInsets.all(15),
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : AccentPlayButton(
                  label: 'Tout lire',
                  onPressed: () => _playAll(shuffle: false),
                ),
        ],
      ),
    );
  }
}
