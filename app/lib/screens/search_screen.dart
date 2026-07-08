import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../api/yt_downloads_repository.dart';
import '../models/server_user.dart';
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

/// Où chercher.
enum _Source { library, youtube }

/// Quoi chercher (le filtre disponible dépend de la source).
enum _Kind { all, songs, albums, artists }

class _SearchScreenState extends ConsumerState<SearchScreen> {
  Timer? _debounce;
  final _focusNode = FocusNode();
  _Source _source = _Source.library;
  _Kind _kind = _Kind.all;
  // Artiste YouTube choisi : on affiche alors SA discographie (via browseId)
  // plutôt qu'une recherche d'albums par nom. Effacé dès que la requête ou la
  // source change.
  YtArtist? _ytArtist;
  late final TextEditingController _controller =
      TextEditingController(text: ref.read(searchQueryProvider));

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    // Nouvelle frappe → on quitte la discographie d'un artiste éventuel.
    if (_ytArtist != null) setState(() => _ytArtist = null);
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (mounted) ref.read(searchQueryProvider.notifier).set(value);
    });
  }

  void _clear() {
    _debounce?.cancel();
    _controller.clear();
    setState(() => _ytArtist = null);
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
      // Le dialogue vit sur le navigateur RACINE; le fermer via le
      // navigateur de l'onglet dépilait l'écran de recherche lui-même
      // (« tout disparaît, juste le fond »).
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
      messenger.showSnackBar(
        SnackBar(content: Text("Impossible de résoudre l'album : $e")),
      );
      return;
    }
    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pop();

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

    // Focus demandé depuis la barre de l'accueil : ouvre le clavier direct.
    ref.listen(searchFocusRequestProvider, (_, _) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focusNode.requestFocus();
      });
    });

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
                focusNode: _focusNode,
                hasQuery: hasQuery,
                onChanged: _onChanged,
                onClear: _clear,
              ),
            ),
            if (!hasQuery) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 40, 20, 8),
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
              ),
              const _OtherUsersSection(),
            ] else ...[
              // Où chercher : bibliothèque locale ou YouTube Music.
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 6, 20, 6),
                child: SegmentedButton<_Source>(
                  segments: const [
                    ButtonSegment(
                      value: _Source.library,
                      icon: Icon(Icons.library_music_rounded, size: 20),
                      label: Text('Ma bibliothèque'),
                    ),
                    ButtonSegment(
                      value: _Source.youtube,
                      icon: Icon(Icons.play_circle_outline, size: 20),
                      label: Text('YouTube'),
                    ),
                  ],
                  selected: {_source},
                  showSelectedIcon: false,
                  onSelectionChanged: (s) => setState(() {
                    _source = s.first;
                    _kind = _Kind.all; // réinitialise le type au changement
                    _ytArtist = null; // quitte la discographie d'un artiste
                  }),
                ),
              ),
              // Quoi chercher : puces de type (dépend de la source). Masquées
              // en mode discographie d'un artiste (le type est alors imposé).
              if (_ytArtist == null)
                SizedBox(
                  height: 42,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    children: [
                      for (final k in _kindsFor(_source))
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: ChoiceChip(
                            label: Text(_kindLabel(k)),
                            selected: _kind == k,
                            onSelected: (_) => setState(() => _kind = k),
                          ),
                        ),
                    ],
                  ),
                ),
              const SizedBox(height: 4),
              if (_source == _Source.library)
                ..._localResults()
              else if (_ytArtist != null)
                ..._ytArtistDiscography(_ytArtist!)
              else
                ..._ytResults(query.trim()),
            ],
          ],
        ),
      ),
    );
  }

  // Types disponibles selon la source.
  List<_Kind> _kindsFor(_Source s) => s == _Source.library
      ? const [_Kind.all, _Kind.songs, _Kind.albums, _Kind.artists]
      : const [_Kind.all, _Kind.songs, _Kind.albums, _Kind.artists];

  String _kindLabel(_Kind k) => switch (k) {
        _Kind.all => 'Tout',
        _Kind.songs => 'Titres',
        _Kind.albums => 'Albums',
        _Kind.artists => 'Artistes',
      };

  bool get _showArtists => _kind == _Kind.all || _kind == _Kind.artists;
  bool get _showAlbums => _kind == _Kind.all || _kind == _Kind.albums;
  bool get _showSongs => _kind == _Kind.all || _kind == _Kind.songs;

  // ─────────────── Résultats « Ma bibliothèque » ───────────────

  List<Widget> _localResults() {
    final results = ref.watch(searchResultsProvider);
    final songLimit = ref.watch(searchLocalLimitProvider);
    return results.when(
      loading: () => const [_LoadingRow()],
      error: (e, _) => [_MessageRow('Erreur : $e')],
      data: (r) {
        if (r.isEmpty) {
          return const [_MessageRow('Aucun résultat dans votre bibliothèque')];
        }
        // En mode « Tout », on sépare les trois familles par un intertitre.
        final headers = _kind == _Kind.all;
        final rows = <Widget>[];

        if (_showArtists && r.artists.isNotEmpty) {
          if (headers) rows.add(const _SectionHeader('Artistes'));
          for (final artist in r.artists) {
            rows.add(_ResultRow(
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
            ));
          }
        }

        if (_showAlbums && r.albums.isNotEmpty) {
          if (headers) rows.add(const _SectionHeader('Albums'));
          for (final album in r.albums) {
            rows.add(_ResultRow(
              artwork:
                  Artwork(url: album.artworkUrl, size: 46, borderRadius: 12),
              title: album.name,
              subtitle: album.artistName ?? 'Album',
              trailing:
                  const Icon(Icons.chevron_right, color: Color(0xFFB6BAC1)),
              onTap: () => context.push('/album/${album.id}'),
            ));
          }
        }

        if (_showSongs && r.songs.isNotEmpty) {
          if (headers) rows.add(const _SectionHeader('Titres'));
          // Dévoilement progressif : on affiche les [songLimit] premiers
          // titres, « Charger plus » en révèle davantage (index alignés sur
          // r.songs, donc startIndex reste correct).
          final shown = r.songs.take(songLimit).toList();
          for (final (i, song) in shown.indexed) {
            rows.add(SongTile(
              song: song,
              subtitle: _songSubtitle(song),
              onTap: () => ref
                  .read(playerActionsProvider)
                  .playSongs(r.songs, startIndex: i),
              onLongPress: () => showSongMenu(context, song),
            ));
          }
          if (r.songs.length > shown.length) {
            rows.add(_LoadMoreButton(
              onPressed: () =>
                  ref.read(searchLocalLimitProvider.notifier).more(),
            ));
          }
        }

        return rows;
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

  /// Artiste YouTube tapé : ouvre SA discographie réelle (albums + singles via
  /// son browseId), d'où l'utilisateur peut télécharger un album.
  void _openYtArtist(YtArtist artist) {
    _debounce?.cancel();
    _controller.text = artist.name;
    setState(() {
      _source = _Source.youtube;
      _kind = _Kind.albums;
      _ytArtist = artist;
    });
  }

  /// Discographie de l'artiste choisi (via browseId), avec un en-tête
  /// permettant de revenir à la recherche.
  List<Widget> _ytArtistDiscography(YtArtist artist) {
    final albumsAsync = ref.watch(ytArtistDiscographyProvider(artist.browseId));
    final header = _YtArtistHeader(
      artist: artist,
      onBack: () => setState(() => _ytArtist = null),
    );
    return albumsAsync.when(
      loading: () => [header, const _LoadingRow()],
      error: (e, _) => [header, _MessageRow('Erreur : $e')],
      data: (albums) {
        if (albums.isEmpty) {
          return [
            header,
            const _MessageRow('Aucun album trouvé pour cet artiste'),
          ];
        }
        return [
          header,
          for (final a in albums)
            _ResultRow(
              artwork: Artwork(
                url: a.thumbnail.isEmpty ? null : a.thumbnail,
                size: 46,
                borderRadius: 12,
              ),
              title: a.title,
              subtitle: [
                if (a.year.isNotEmpty) a.year,
                'Album',
              ].join(' · '),
              trailing: const Icon(Icons.download_outlined),
              onTap: () => _confirmAlbumDownload(a),
            ),
        ];
      },
    );
  }

  // ─────────────── Résultats « YouTube Music » ───────────────

  List<Widget> _ytResults(String query) {
    if (query.length < 2) {
      return const [_MessageRow('Requête trop courte')];
    }
    final albumsAsync = ref.watch(ytAlbumSearchProvider(query));
    final songsAsync = ref.watch(ytSongSearchProvider(query));
    final artistsAsync = ref.watch(ytArtistSearchProvider(query));
    final limit = ref.watch(searchYtLimitProvider);
    final headers = _kind == _Kind.all;

    // Valeurs déjà connues : conservées pendant un « Charger plus » (le
    // provider repasse en loading mais garde sa dernière donnée).
    final songs = _showSongs
        ? (songsAsync.value ?? const <YtSong>[])
        : const <YtSong>[];
    final albums = _showAlbums
        ? (albumsAsync.value ?? const <YtAlbum>[])
        : const <YtAlbum>[];
    final artists = _showArtists
        ? (artistsAsync.value ?? const <YtArtist>[])
        : const <YtArtist>[];

    final loading = (_showSongs && songsAsync.isLoading) ||
        (_showAlbums && albumsAsync.isLoading) ||
        (_showArtists && artistsAsync.isLoading);
    final hasAnyData = (_showSongs && songsAsync.hasValue) ||
        (_showAlbums && albumsAsync.hasValue) ||
        (_showArtists && artistsAsync.hasValue);

    // Tout premier chargement (rien encore à afficher).
    if (!hasAnyData && loading) {
      return const [_LoadingRow()];
    }

    final rows = <Widget>[];

    if (_showArtists && artistsAsync.hasError && artists.isEmpty) {
      rows.add(_MessageRow('Artistes : erreur — ${artistsAsync.error}'));
    }
    if (_showSongs && songsAsync.hasError && songs.isEmpty) {
      rows.add(_MessageRow('Chansons : erreur — ${songsAsync.error}'));
    }
    if (_showAlbums && albumsAsync.hasError && albums.isEmpty) {
      rows.add(_MessageRow('Albums : erreur — ${albumsAsync.error}'));
    }

    if (artists.isNotEmpty) {
      if (headers) rows.add(const _SectionHeader('Artistes'));
      for (final a in artists) {
        rows.add(_ResultRow(
          artwork: Artwork(
            url: a.thumbnail.isEmpty ? null : a.thumbnail,
            size: 46,
            borderRadius: 23,
            icon: Icons.person,
          ),
          title: a.name,
          subtitle: 'Artiste',
          trailing:
              const Icon(Icons.chevron_right, color: Color(0xFFB6BAC1)),
          onTap: () => _openYtArtist(a),
        ));
      }
    }

    if (songs.isNotEmpty) {
      if (headers) rows.add(const _SectionHeader('Titres'));
      for (final s in songs) {
        rows.add(_ResultRow(
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
        ));
      }
    }

    if (albums.isNotEmpty) {
      if (headers) rows.add(const _SectionHeader('Albums'));
      for (final a in albums) {
        rows.add(_ResultRow(
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
        ));
      }
    }

    if (rows.isEmpty && !loading) {
      return const [_MessageRow('Aucun résultat sur YouTube Music')];
    }

    // « Charger plus » tant qu'une des sections demandées a renvoyé une page
    // pleine (donc potentiellement d'autres résultats) et sous le plafond.
    final canLoadMore = limit < 50 &&
        ((_showSongs && songs.length >= limit) ||
            (_showAlbums && albums.length >= limit) ||
            (_showArtists && artists.length >= limit));
    if (loading) {
      rows.add(const _LoadingRow());
    } else if (canLoadMore) {
      rows.add(_LoadMoreButton(
        onPressed: () => ref.read(searchYtLimitProvider.notifier).more(),
      ));
    }
    return rows;
  }
}

/// Champ de recherche en verre (design) : radius 18, icône search,
/// croix d'effacement.
class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.focusNode,
    required this.hasQuery,
    required this.onChanged,
    required this.onClear,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
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
                focusNode: focusNode,
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

/// Découverte : les bibliothèques des autres utilisateurs du serveur.
/// Affichée dans l'onglet Recherche quand le champ est vide.
class _OtherUsersSection extends ConsumerWidget {
  const _OtherUsersSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final users = ref.watch(serverUsersProvider);
    return users.when(
      // Discret tant que ça charge / échoue : c'est une section secondaire.
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (list) {
        if (list.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionTitle(
              'Autres utilisateurs',
              padding: EdgeInsets.fromLTRB(20, 18, 20, 2),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 6),
              child: Text(
                'Explorez les bibliothèques du serveur',
                style: TextStyle(fontSize: 12.5, color: Color(0xFF8A8F98)),
              ),
            ),
            for (final u in list) _UserRow(user: u),
          ],
        );
      },
    );
  }
}

class _UserRow extends StatelessWidget {
  const _UserRow({required this.user});

  final ServerUser user;

  @override
  Widget build(BuildContext context) {
    final counts = [
      '${user.artistCount} artiste${user.artistCount > 1 ? 's' : ''}',
      '${user.songCount} titre${user.songCount > 1 ? 's' : ''}',
    ].join(' · ');
    return _ResultRow(
      artwork: Artwork(
        url: user.avatarUrl,
        size: 46,
        borderRadius: 23,
        icon: Icons.person,
      ),
      title: user.displayName,
      subtitle: counts,
      trailing: const Icon(Icons.chevron_right, color: Color(0xFFB6BAC1)),
      onTap: () => context.push('/user-library', extra: user),
    );
  }
}

/// En-tête de la discographie d'un artiste YouTube : sa photo, son nom, et
/// une flèche pour revenir aux résultats de recherche.
class _YtArtistHeader extends StatelessWidget {
  const _YtArtistHeader({required this.artist, required this.onBack});

  final YtArtist artist;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Retour aux résultats',
            icon: const Icon(Icons.arrow_back),
            onPressed: onBack,
          ),
          const SizedBox(width: 4),
          Artwork(
            url: artist.thumbnail.isEmpty ? null : artist.thumbnail,
            size: 46,
            borderRadius: 23,
            icon: Icons.person,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  artist.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                  ),
                ),
                Text(
                  'Discographie',
                  style: TextStyle(
                    fontSize: 12.5,
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

/// Intertitre de section (« Artistes », « Albums », « Titres ») en mode Tout.
class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return SectionTitle(text, padding: const EdgeInsets.fromLTRB(20, 14, 20, 2));
  }
}

/// Bouton « Charger plus » (même langage que l'écran des téléchargements).
class _LoadMoreButton extends StatelessWidget {
  const _LoadMoreButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: const Icon(Icons.expand_more),
        label: const Text('Charger plus'),
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
