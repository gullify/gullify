import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../api/yt_downloads_repository.dart';
import '../models/song.dart';
import '../state/library.dart';
import '../state/player.dart';
import '../state/yt_downloads.dart';
import '../widgets/artwork.dart';
import '../widgets/glass_box.dart';
import '../widgets/glass_kit.dart';
import '../widgets/song_menu.dart';
import '../widgets/song_tile.dart';

/// Onglet « Recherche » : champ en verre, résultats en deux groupes —
/// « Ma bibliothèque » (recherche locale) et « YouTube Music » (albums et
/// chansons seules, téléchargeables). La file d'attente reste sur
/// /yt-downloads (bouton en en-tête).
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  Timer? _debounce;
  late final TextEditingController _controller =
      TextEditingController(text: ref.read(searchQueryProvider));

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (mounted) ref.read(searchQueryProvider.notifier).set(value);
    });
  }

  void _clear() {
    _debounce?.cancel();
    _controller.clear();
    ref.read(searchQueryProvider.notifier).set('');
  }

  // ─────────────── Téléchargements YouTube Music ───────────────

  /// Album : résolution du browseId, confirmation, mise en file.
  Future<void> _confirmAlbumDownload(YtAlbum album) async {
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
      if (mounted) Navigator.pop(context);
      messenger.showSnackBar(
        SnackBar(content: Text("Impossible de résoudre l'album : $e")),
      );
      return;
    }
    if (!mounted) return;
    Navigator.pop(context);

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(resolved.title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(resolved.artist),
            const SizedBox(height: 4),
            Text(
              [
                if (resolved.year.isNotEmpty) resolved.year,
                '${resolved.trackCount} piste'
                    '${resolved.trackCount > 1 ? 's' : ''}',
              ].join(' · '),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            const Text(
              "Le serveur télécharge cet album puis l'ajoute "
              'à la bibliothèque.',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.download),
            label: const Text('Télécharger'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    try {
      await ref.read(ytQueueProvider.notifier).start(resolved);
      _notifyStarted(messenger, resolved.title);
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Échec du démarrage : $e')),
      );
    }
  }

  /// Chanson seule : confirmation puis mise en file avec l'URL watch?v=.
  Future<void> _confirmSongDownload(YtSong song) async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(song.title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(song.artist),
            const SizedBox(height: 4),
            Text(
              [
                if (song.album.isNotEmpty) song.album,
                if (song.duration.isNotEmpty) song.duration,
              ].join(' · '),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            const Text(
              "Le serveur télécharge cette chanson puis l'ajoute "
              'à la bibliothèque.',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.download),
            label: const Text('Télécharger'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    try {
      await ref.read(ytDownloadsRepositoryProvider).start(
            url: song.watchUrl,
            artistName: song.artist,
            albumName: song.album.isEmpty ? 'Singles' : song.album,
          );
      ref.invalidate(ytQueueProvider);
      _notifyStarted(messenger, song.title);
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Échec du démarrage : $e')),
      );
    }
  }

  void _notifyStarted(ScaffoldMessengerState messenger, String title) {
    messenger.showSnackBar(
      SnackBar(
        content: Text('Téléchargement démarré : $title'),
        action: SnackBarAction(
          label: 'Suivre',
          onPressed: () {
            if (mounted) context.push('/yt-downloads');
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final query = ref.watch(searchQueryProvider);
    final hasQuery = query.trim().isNotEmpty;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: EdgeInsets.only(
            bottom: MediaQuery.paddingOf(context).bottom + 18,
          ),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Recherche',
                      style: TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.6,
                        height: 1.02,
                      ),
                    ),
                  ),
                  GlassIconButton(
                    icon: Icons.downloading,
                    tooltip: 'Téléchargements',
                    size: 42,
                    onPressed: () => context.push('/yt-downloads'),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 8),
              child: _SearchField(
                controller: _controller,
                hasQuery: hasQuery,
                onChanged: _onChanged,
                onClear: _clear,
              ),
            ),
            if (!hasQuery)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 60, 20, 20),
                child: Column(
                  children: [
                    Icon(
                      Icons.search,
                      size: 40,
                      color: Theme.of(context)
                          .colorScheme
                          .onSurfaceVariant
                          .withValues(alpha: 0.6),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Recherchez dans votre bibliothèque\n'
                      'et sur YouTube Music',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              )
            else ...[
              const SectionTitle(
                'Ma bibliothèque',
                padding: EdgeInsets.fromLTRB(20, 10, 20, 4),
              ),
              ..._localResults(),
              const SectionTitle(
                'YouTube Music',
                padding: EdgeInsets.fromLTRB(20, 14, 20, 4),
              ),
              ..._ytResults(query.trim()),
            ],
          ],
        ),
      ),
    );
  }

  // ─────────────── Résultats « Ma bibliothèque » ───────────────

  List<Widget> _localResults() {
    final results = ref.watch(searchResultsProvider);
    return results.when(
      loading: () => const [_LoadingRow()],
      error: (e, _) => [_MessageRow('Erreur : $e')],
      data: (r) {
        if (r.isEmpty) {
          return const [_MessageRow('Aucun résultat dans votre bibliothèque')];
        }
        return [
          for (final artist in r.artists)
            _ResultRow(
              artwork: Artwork(
                url: artist.imageUrl,
                size: 46,
                borderRadius: 23,
                icon: Icons.person,
              ),
              title: artist.name,
              subtitle: 'Artiste',
              trailing:
                  const Icon(Icons.chevron_right, color: Color(0xFFB6BAC1)),
              onTap: () => context.push('/artist/${artist.id}'),
            ),
          for (final album in r.albums)
            _ResultRow(
              artwork:
                  Artwork(url: album.artworkUrl, size: 46, borderRadius: 12),
              title: album.name,
              subtitle: album.artistName ?? 'Album',
              trailing:
                  const Icon(Icons.chevron_right, color: Color(0xFFB6BAC1)),
              onTap: () => context.push('/album/${album.id}'),
            ),
          for (final (i, song) in r.songs.indexed)
            SongTile(
              song: song,
              subtitle: _songSubtitle(song),
              onTap: () => ref
                  .read(playerActionsProvider)
                  .playSongs(r.songs, startIndex: i),
              onLongPress: () => showSongMenu(context, song),
            ),
        ];
      },
    );
  }

  String? _songSubtitle(Song song) {
    final parts = [
      if (song.artistName != null) song.artistName!,
      if (song.albumName != null) song.albumName!,
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }

  // ─────────────── Résultats « YouTube Music » ───────────────

  List<Widget> _ytResults(String query) {
    if (query.length < 2) {
      return const [_MessageRow('Requête trop courte')];
    }
    final albums = ref.watch(ytAlbumSearchProvider(query));
    final songs = ref.watch(ytSongSearchProvider(query));

    final albumRows = albums.when(
      loading: () => const <Widget>[_LoadingRow()],
      error: (e, _) => [_MessageRow('Albums : erreur — $e')],
      data: (list) => [
        for (final a in list)
          _ResultRow(
            artwork: Artwork(
              url: a.thumbnail.isEmpty ? null : a.thumbnail,
              size: 46,
              borderRadius: 12,
            ),
            title: a.title,
            subtitle: [
              a.artist,
              if (a.year.isNotEmpty) a.year,
              'Album',
            ].join(' · '),
            trailing: const Icon(Icons.download_outlined),
            onTap: () => _confirmAlbumDownload(a),
          ),
      ],
    );

    final songRows = songs.when(
      loading: () => const <Widget>[_LoadingRow()],
      error: (e, _) => [_MessageRow('Chansons : erreur — $e')],
      data: (list) => [
        for (final s in list)
          _ResultRow(
            artwork: Artwork(
              url: s.thumbnail.isEmpty ? null : s.thumbnail,
              size: 46,
              borderRadius: 12,
              icon: Icons.music_note,
            ),
            title: s.title,
            subtitle: [
              s.artist,
              if (s.album.isNotEmpty) s.album,
              if (s.duration.isNotEmpty) s.duration,
            ].join(' · '),
            trailing: const Icon(Icons.download_outlined),
            onTap: () => _confirmSongDownload(s),
          ),
      ],
    );

    if (albumRows.isEmpty && songRows.isEmpty) {
      return const [_MessageRow('Aucun résultat sur YouTube Music')];
    }
    return [...songRows, ...albumRows];
  }
}

/// Champ de recherche en verre (design) : radius 18, icône search,
/// croix d'effacement.
class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.hasQuery,
    required this.onChanged,
    required this.onClear,
  });

  final TextEditingController controller;
  final bool hasQuery;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GlassBox(
      radius: 18,
      blur: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 15),
        child: Row(
          children: [
            Icon(Icons.search, size: 22, color: scheme.onSurfaceVariant),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: controller,
                onChanged: onChanged,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
                decoration: const InputDecoration(
                  hintText: 'Titres, artistes, albums…',
                  filled: false,
                  isDense: true,
                  border: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
            if (hasQuery)
              IconButton(
                tooltip: 'Effacer',
                padding: EdgeInsets.zero,
                constraints:
                    const BoxConstraints(minWidth: 32, minHeight: 32),
                icon: Icon(Icons.close,
                    size: 20, color: scheme.onSurfaceVariant),
                onPressed: onClear,
              ),
          ],
        ),
      ),
    );
  }
}

/// Rangée de résultat générique, même langage que les titres.
class _ResultRow extends StatelessWidget {
  const _ResultRow({
    required this.artwork,
    required this.title,
    required this.subtitle,
    required this.trailing,
    required this.onTap,
  });

  final Widget artwork;
  final String title;
  final String subtitle;
  final Widget trailing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
          child: Row(
            children: [
              artwork,
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              trailing,
            ],
          ),
        ),
      ),
    );
  }
}

class _LoadingRow extends StatelessWidget {
  const _LoadingRow();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(20),
      child: Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2.5),
        ),
      ),
    );
  }
}

class _MessageRow extends StatelessWidget {
  const _MessageRow(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      child: Text(
        message,
        style: TextStyle(
          fontSize: 13,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
