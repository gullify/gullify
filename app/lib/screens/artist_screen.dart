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
import 'shell_screen.dart';
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
      bottomNavigationBar: const DetailDock(),
      body: detail.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Erreur: $e')),
        data: (d) => ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            // En-tête : image de l'artiste plein cadre, fondu vers le fond,
            // nom en surimpression, retour en rond de verre.
            _ArtistHeader(
              imageUrl: d.artist.imageUrl,
              name: d.artist.name,
              albumCount: d.albums.length,
              onMenu: () => _artistMenu(context, ref, d),
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
            _SimilarArtists(name: d.artist.name),
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
    // Rangée d'action alignée : « Tout lire » pleine largeur + aléatoire.
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
      child: Row(
        children: [
          Expanded(
            child: _busy
                ? const SizedBox(
                    height: 52,
                    child: Center(
                      child: SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  )
                : AccentPlayButton(
                    label: 'Tout lire',
                    onPressed: () => _playAll(shuffle: false),
                  ),
          ),
          const SizedBox(width: 12),
          GlassIconButton(
            icon: Icons.shuffle,
            tooltip: 'Tout lire aléatoirement',
            size: 52,
            onPressed: _busy ? null : () => _playAll(shuffle: true),
          ),
        ],
      ),
    );
  }
}

/// Artistes similaires (YouTube Music) : carrousel d'avatars ronds. Un tap
/// lance une recherche sur ce nom pour l'explorer / télécharger.
class _SimilarArtists extends ConsumerWidget {
  const _SimilarArtists({required this.name});

  final String name;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final related = ref.watch(relatedArtistsProvider(name));
    return related.maybeWhen(
      data: (artists) {
        if (artists.isEmpty) return const SizedBox.shrink();
        final scheme = Theme.of(context).colorScheme;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionTitle('Artistes similaires'),
            SizedBox(
              height: 148,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
                itemCount: artists.length,
                separatorBuilder: (_, _) => const SizedBox(width: 14),
                itemBuilder: (context, i) {
                  final a = artists[i];
                  return SizedBox(
                    width: 92,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(46),
                      onTap: () {
                        ref.read(searchQueryProvider.notifier).set(a.name);
                        context.go('/search');
                      },
                      child: Column(
                        children: [
                          DecoratedBox(
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: Color(0x33000000),
                                  blurRadius: 14,
                                  offset: Offset(0, 6),
                                ),
                              ],
                            ),
                            child: Artwork(
                              url: a.thumbnail.isEmpty ? null : a.thumbnail,
                              size: 88,
                              borderRadius: 44,
                              icon: Icons.person,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            a.name,
                            maxLines: 1,
                            textAlign: TextAlign.center,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: scheme.onSurface,
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

/// Menu d'un artiste : suppression définitive (fichiers + base).
void _artistMenu(BuildContext context, WidgetRef ref, ArtistDetail d) {
  showModalBottomSheet<void>(
    context: context,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.label_outline),
            title: const Text('Définir le genre'),
            subtitle: d.artist.genre != null && d.artist.genre!.isNotEmpty
                ? Text(d.artist.genre!)
                : null,
            onTap: () {
              Navigator.pop(sheetContext);
              _setGenreDialog(context, ref, d.artist.id, d.artist.genre);
            },
          ),
          const Divider(height: 1),
          ListTile(
            leading: Icon(Icons.delete_outline,
                color: Theme.of(sheetContext).colorScheme.error),
            title: Text(
              "Supprimer l'artiste",
              style:
                  TextStyle(color: Theme.of(sheetContext).colorScheme.error),
            ),
            subtitle: const Text('Tous ses albums et titres'),
            onTap: () async {
              final messenger = ScaffoldMessenger.of(context);
              Navigator.pop(sheetContext);
              final ok = await confirmDelete(
                context,
                'Supprimer « ${d.artist.name} » ?',
                'Tous les albums et titres de cet artiste seront effacés du '
                    'serveur. Action irréversible.',
              );
              if (ok != true) return;
              try {
                await ref
                    .read(libraryRepositoryProvider)
                    .deleteArtist(d.artist.id);
                invalidateLibrary(ref);
                if (context.mounted) {
                  context.go('/library');
                  messenger.showSnackBar(
                    SnackBar(content: Text('« ${d.artist.name} » supprimé')),
                  );
                }
              } catch (e) {
                messenger.showSnackBar(SnackBar(content: Text('Échec : $e')));
              }
            },
          ),
        ],
      ),
    ),
  );
}

/// Dialogue « Définir le genre » : champ libre + suggestions des genres
/// déjà présents dans la bibliothèque.
void _setGenreDialog(
  BuildContext context,
  WidgetRef ref,
  int artistId,
  String? current,
) {
  final controller = TextEditingController(text: current ?? '');
  showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Genre de l\'artiste'),
      content: Consumer(
        builder: (context, ref, _) {
          final genres = ref.watch(genresProvider).value ?? [];
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: controller,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Genre',
                  hintText: 'Ex. Rock, Jazz, Folk…',
                ),
              ),
              if (genres.isNotEmpty) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final g in genres.take(12))
                      ActionChip(
                        label: Text(g.name),
                        onPressed: () => controller.text = g.name,
                      ),
                  ],
                ),
              ],
            ],
          );
        },
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: () async {
            final messenger = ScaffoldMessenger.of(context);
            Navigator.pop(dialogContext);
            try {
              await ref
                  .read(libraryRepositoryProvider)
                  .setArtistGenre(artistId, controller.text.trim());
              ref.invalidate(artistDetailProvider(artistId));
              ref.invalidate(genresProvider);
              ref.invalidate(artistsProvider);
              messenger.showSnackBar(
                const SnackBar(content: Text('Genre mis à jour')),
              );
            } catch (e) {
              messenger.showSnackBar(SnackBar(content: Text('Échec : $e')));
            }
          },
          child: const Text('Enregistrer'),
        ),
      ],
    ),
  );
}

/// En-tête d'artiste : image plein cadre qui se fond dans le fond de l'app,
/// nom en surimpression bas-gauche, bouton retour en verre.
class _ArtistHeader extends StatelessWidget {
  const _ArtistHeader({
    required this.imageUrl,
    required this.name,
    required this.albumCount,
    required this.onMenu,
  });

  final String? imageUrl;
  final String name;
  final int albumCount;
  final VoidCallback onMenu;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final topInset = MediaQuery.paddingOf(context).top;

    return SizedBox(
      height: 440,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // L'image se DISSOUT en transparence vers le bas (ShaderMask) :
          // le vrai dégradé de fond de l'app transparaît en continu, sans
          // couleur intermédiaire ni couture.
          ShaderMask(
            shaderCallback: (rect) => const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              stops: [0.0, 0.5, 1.0],
              colors: [Colors.white, Colors.white, Colors.transparent],
            ).createShader(rect),
            blendMode: BlendMode.dstIn,
            child: Artwork(url: imageUrl, borderRadius: 0, icon: Icons.person),
          ),
          // Voile sombre discret en haut pour la lisibilité du bouton retour.
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
            right: 14,
            top: topInset + 8,
            child: GlassIconButton(
              icon: Icons.more_vert,
              tooltip: 'Options',
              onPressed: onMenu,
            ),
          ),
          Positioned(
            left: 20,
            right: 20,
            bottom: 12,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 34,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.8,
                    height: 1.02,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$albumCount album${albumCount > 1 ? 's' : ''}',
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
