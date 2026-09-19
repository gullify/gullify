import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../api/bandcamp_repository.dart';
import '../api/yt_downloads_repository.dart';
import '../models/server_user.dart';
import '../state/bandcamp.dart';
import '../state/library.dart';
import '../state/player.dart';
import '../state/preview.dart';
import '../state/yt_downloads.dart';
import '../widgets/artwork.dart';
import '../widgets/bandcamp_download.dart';
import '../widgets/download_confirm.dart';
import '../widgets/glass_box.dart';
import '../widgets/glass_kit.dart';
import '../widgets/song_menu.dart';
import '../widgets/song_tile.dart';

/// Onglet « Recherche » : champ en verre, et trois sources au choix —
/// « Bibliothèque » (recherche locale), « YouTube » et « Bandcamp » (albums,
/// artistes et titres seuls, téléchargeables). La file d'attente reste sur
/// /yt-downloads (bouton en en-tête).
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

/// Où chercher.
enum _Source { library, youtube, bandcamp }

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
  // Idem côté Bandcamp : l'artiste tapé ouvre SA discographie (via bandId).
  BcArtist? _bcArtist;
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
    if (_ytArtist != null || _bcArtist != null) {
      setState(() {
        _ytArtist = null;
        _bcArtist = null;
      });
    }
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (mounted) ref.read(searchQueryProvider.notifier).set(value);
    });
  }

  void _clear() {
    _debounce?.cancel();
    _controller.clear();
    setState(() {
      _ytArtist = null;
      _bcArtist = null;
    });
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
    // Déjà dans la bibliothèque ou déjà en file ? On le dit avant de proposer.
    final duplicate = await ref
        .read(ytDownloadsRepositoryProvider)
        .checkDuplicate(
          artist: resolved.artist,
          album: resolved.title,
          url: resolved.playlistUrl,
        );
    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pop();

    final ok = await showDownloadConfirm(
      context,
      title: resolved.title,
      subtitle: resolved.artist,
      details: [
        if (resolved.year.isNotEmpty) resolved.year,
        '${resolved.trackCount} piste'
            '${resolved.trackCount > 1 ? 's' : ''}',
      ].join(' · '),
      body: "Le serveur télécharge cet album puis l'ajoute "
          'à la bibliothèque.',
      duplicate: duplicate,
    );
    if (!ok || !mounted) return;

    try {
      await ref
          .read(ytQueueProvider.notifier)
          .start(resolved, force: duplicate != null);
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
    // Pour une chanson seule, le doublon se juge sur le titre : elles
    // atterrissent toutes dans « Singles ».
    final duplicate = await ref
        .read(ytDownloadsRepositoryProvider)
        .checkDuplicate(
          artist: song.artist,
          album: song.album.isEmpty ? 'Singles' : song.album,
          url: song.watchUrl,
          title: song.title,
        );
    if (!mounted) return;

    final ok = await showDownloadConfirm(
      context,
      title: song.title,
      subtitle: song.artist,
      details: [
        if (song.album.isNotEmpty) song.album,
        if (song.duration.isNotEmpty) song.duration,
      ].join(' · '),
      body: "Le serveur télécharge cette chanson puis l'ajoute "
          'à la bibliothèque.',
      duplicate: duplicate,
    );
    if (!ok || !mounted) return;

    try {
      await ref.read(ytDownloadsRepositoryProvider).start(
            url: song.watchUrl,
            artistName: song.artist,
            albumName: song.album.isEmpty ? 'Singles' : song.album,
            title: song.title,
            force: duplicate != null,
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
          // Faire défiler les résultats referme le clavier : il masquait la
          // moitié de la liste et laissait sa bande réservée.
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
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
                      'Recherchez dans votre bibliothèque,\n'
                      'sur YouTube Music et sur Bandcamp',
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
              _NewReleasesSection(onDownload: _confirmAlbumDownload),
            ] else ...[
              // Où chercher : bibliothèque locale, YouTube Music ou
              // Bandcamp. À trois sources, les libellés portent seuls : une
              // icône de plus et « Bibliothèque » déborde de son segment sur
              // un téléphone étroit.
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 6, 20, 6),
                child: SegmentedButton<_Source>(
                  segments: const [
                    ButtonSegment(
                      value: _Source.library,
                      label: Text('Bibliothèque'),
                    ),
                    ButtonSegment(
                      value: _Source.youtube,
                      label: Text('YouTube'),
                    ),
                    ButtonSegment(
                      value: _Source.bandcamp,
                      label: Text('Bandcamp'),
                    ),
                  ],
                  style: SegmentedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    textStyle: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  selected: {_source},
                  showSelectedIcon: false,
                  onSelectionChanged: (s) => setState(() {
                    _source = s.first;
                    _kind = _Kind.all; // réinitialise le type au changement
                    // Quitte la discographie d'un artiste éventuel.
                    _ytArtist = null;
                    _bcArtist = null;
                  }),
                ),
              ),
              // Quoi chercher : puces de type (dépend de la source). Masquées
              // en mode discographie d'un artiste (le type est alors imposé).
              if (_ytArtist == null && _bcArtist == null)
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
              else if (_source == _Source.bandcamp)
                ...(_bcArtist != null
                    ? _bcArtistDiscography(_bcArtist!)
                    : _bcResults(query.trim()))
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
              albumInSubtitle: true,
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
    final header = _ArtistHeader(
      name: artist.name,
      thumbnail: artist.thumbnail,
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
              trailing: a.inLibrary
                  ? const InLibraryBadge()
                  : const Icon(Icons.download_outlined),
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
        rows.add(_PreviewSongRow(
          previewId: s.videoId,
          title: s.title,
          subtitle: [
            s.artist,
            if (s.album.isNotEmpty) s.album,
            if (s.duration.isNotEmpty) s.duration,
          ].join(' · '),
          thumbnail: s.thumbnail,
          inLibrary: s.inLibrary,
          onToggle: () => ref.read(previewPlayerProvider.notifier).toggle(s),
          onDownload: () => _confirmSongDownload(s),
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
          trailing: a.inLibrary
              ? const InLibraryBadge()
              : const Icon(Icons.download_outlined),
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

  // ─────────────── Résultats « Bandcamp » (idée #110) ───────────────

  /// Album (ou titre publié seul) Bandcamp : voir [downloadBandcampRelease].
  Future<void> _confirmBandcampDownload(BcRelease release) =>
      downloadBandcampRelease(context, ref, release);

  /// Titre Bandcamp trouvé seul : il porte déjà son lien et son album, rien
  /// à résoudre avant de demander confirmation.
  Future<void> _confirmBandcampSong(BcSong song) async {
    final messenger = ScaffoldMessenger.of(context);
    final album = song.album.isEmpty ? 'Singles' : song.album;
    final duplicate = await ref
        .read(ytDownloadsRepositoryProvider)
        .checkDuplicate(
          artist: song.artist,
          album: album,
          url: song.url,
          title: song.title,
        );
    if (!mounted) return;

    final ok = await showDownloadConfirm(
      context,
      title: song.title,
      subtitle: song.artist,
      details: [
        if (song.album.isNotEmpty) song.album,
        'Bandcamp',
      ].join(' · '),
      body: "Le serveur télécharge ce titre puis l'ajoute "
          'à la bibliothèque.',
      duplicate: duplicate,
    );
    if (!ok || !mounted) return;

    try {
      await ref.read(ytDownloadsRepositoryProvider).start(
            url: song.url,
            artistName: song.artist,
            albumName: album,
            title: song.title,
            force: duplicate != null,
          );
      ref.invalidate(ytQueueProvider);
      _notifyStarted(messenger, song.title);
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Échec du démarrage : $e')),
      );
    }
  }

  /// Artiste Bandcamp tapé : ouvre SA discographie (via son bandId).
  void _openBcArtist(BcArtist artist) {
    _debounce?.cancel();
    _controller.text = artist.name;
    setState(() {
      _source = _Source.bandcamp;
      _kind = _Kind.albums;
      _bcArtist = artist;
    });
  }

  /// Discographie de l'artiste Bandcamp choisi, avec un en-tête permettant de
  /// revenir à la recherche.
  List<Widget> _bcArtistDiscography(BcArtist artist) {
    final albumsAsync = ref.watch(bcArtistDiscographyProvider(artist.bandId));
    final header = _ArtistHeader(
      name: artist.name,
      thumbnail: artist.thumbnail,
      onBack: () => setState(() => _bcArtist = null),
    );
    return albumsAsync.when(
      loading: () => [header, const _LoadingRow()],
      error: (e, _) => [header, _MessageRow('Erreur : $e')],
      data: (albums) {
        if (albums.isEmpty) {
          return [
            header,
            const _MessageRow('Aucune sortie trouvée pour cet artiste'),
          ];
        }
        return [
          header,
          for (final a in albums) _bcReleaseRow(a, withArtist: false),
        ];
      },
    );
  }

  List<Widget> _bcResults(String query) {
    if (query.length < 2) {
      return const [_MessageRow('Requête trop courte')];
    }
    final albumsAsync = ref.watch(bcAlbumSearchProvider(query));
    final songsAsync = ref.watch(bcSongSearchProvider(query));
    final artistsAsync = ref.watch(bcArtistSearchProvider(query));
    final limit = ref.watch(searchBandcampLimitProvider);
    final headers = _kind == _Kind.all;

    // Valeurs déjà connues : conservées pendant un « Charger plus ».
    final songs = _showSongs
        ? (songsAsync.value ?? const <BcSong>[])
        : const <BcSong>[];
    final albums = _showAlbums
        ? (albumsAsync.value ?? const <BcRelease>[])
        : const <BcRelease>[];
    final artists = _showArtists
        ? (artistsAsync.value ?? const <BcArtist>[])
        : const <BcArtist>[];

    final loading = (_showSongs && songsAsync.isLoading) ||
        (_showAlbums && albumsAsync.isLoading) ||
        (_showArtists && artistsAsync.isLoading);
    final hasAnyData = (_showSongs && songsAsync.hasValue) ||
        (_showAlbums && albumsAsync.hasValue) ||
        (_showArtists && artistsAsync.hasValue);

    if (!hasAnyData && loading) {
      return const [_LoadingRow()];
    }

    final rows = <Widget>[];

    if (_showArtists && artistsAsync.hasError && artists.isEmpty) {
      rows.add(_MessageRow('Artistes : erreur — ${artistsAsync.error}'));
    }
    if (_showSongs && songsAsync.hasError && songs.isEmpty) {
      rows.add(_MessageRow('Titres : erreur — ${songsAsync.error}'));
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
          // Deux groupes du même nom se distinguent par leur ville : Bandcamp
          // l'affiche partout, et c'est souvent le seul indice.
          subtitle: [
            a.isLabel ? 'Label' : 'Artiste',
            if (a.location.isNotEmpty) a.location,
          ].join(' · '),
          trailing: const Icon(Icons.chevron_right, color: Color(0xFFB6BAC1)),
          onTap: () => _openBcArtist(a),
        ));
      }
    }

    if (songs.isNotEmpty) {
      if (headers) rows.add(const _SectionHeader('Titres'));
      for (final s in songs) {
        rows.add(_PreviewSongRow(
          previewId: s.previewId,
          title: s.title,
          subtitle: [
            s.artist,
            if (s.album.isNotEmpty) s.album,
          ].join(' · '),
          thumbnail: s.thumbnail,
          inLibrary: s.inLibrary,
          onToggle: () =>
              ref.read(previewPlayerProvider.notifier).toggleBandcamp(s),
          onDownload: () => _confirmBandcampSong(s),
        ));
      }
    }

    if (albums.isNotEmpty) {
      if (headers) rows.add(const _SectionHeader('Albums'));
      for (final a in albums) {
        rows.add(_bcReleaseRow(a));
      }
    }

    if (rows.isEmpty && !loading) {
      return const [_MessageRow('Aucun résultat sur Bandcamp')];
    }

    final canLoadMore = limit < 50 &&
        ((_showSongs && songs.length >= limit) ||
            (_showAlbums && albums.length >= limit) ||
            (_showArtists && artists.length >= limit));
    if (loading) {
      rows.add(const _LoadingRow());
    } else if (canLoadMore) {
      rows.add(_LoadMoreButton(
        onPressed: () =>
            ref.read(searchBandcampLimitProvider.notifier).more(),
      ));
    }
    return rows;
  }

  /// Rangée d'une sortie Bandcamp (album ou titre publié seul).
  Widget _bcReleaseRow(BcRelease release, {bool withArtist = true}) =>
      _ResultRow(
        artwork: Artwork(
          url: release.thumbnail.isEmpty ? null : release.thumbnail,
          size: 46,
          borderRadius: 12,
        ),
        title: release.title,
        subtitle: [
          if (withArtist && release.artist.isNotEmpty) release.artist,
          if (release.year.isNotEmpty) release.year,
          release.isTrack ? 'Titre' : 'Album',
        ].join(' · '),
        trailing: release.inLibrary
            ? const InLibraryBadge()
            : const Icon(Icons.download_outlined),
        onTap: () => _confirmBandcampDownload(release),
      );
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

/// Rangée d'un titre trouvé en ligne (YouTube ou Bandcamp) : pré-écoute avant
/// téléchargement. Un tap sur la rangée (ou la pochette) lance / met en pause
/// la pré-écoute; le bouton de droite lance le téléchargement. Le titre en
/// cours affiche une barre de progression et une pochette « lecture / pause ».
///
/// La pré-écoute part dans le lecteur principal (idée #59) : le mini-lecteur
/// s'ouvre dessus, la notification l'annonce et l'écran éteint ne la coupe plus.
/// Ce qui s'affiche ici n'est que l'écho de ce que joue ce lecteur.
class _PreviewSongRow extends ConsumerWidget {
  const _PreviewSongRow({
    required this.previewId,
    required this.title,
    required this.subtitle,
    required this.thumbnail,
    required this.inLibrary,
    required this.onToggle,
    required this.onDownload,
  });

  /// Identité du titre auprès du lecteur de pré-écoute (identifiant YouTube,
  /// ou `bc:<id>` pour Bandcamp).
  final String previewId;
  final String title;
  final String subtitle;
  final String thumbnail;
  final bool inLibrary;
  final VoidCallback onToggle;
  final VoidCallback onDownload;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final preview = ref.watch(previewPlayerProvider);
    final active = preview.isActive(previewId);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onToggle,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
          child: Row(
            children: [
              _PreviewArtwork(
                url: thumbnail.isEmpty ? null : thumbnail,
                active: active,
                playing: active && preview.playing,
                loading: active && preview.loading,
              ),
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
                    if (active) ...[
                      const SizedBox(height: 6),
                      _PreviewProgress(preview: preview, color: scheme.primary),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 4),
              if (inLibrary) const InLibraryBadge(),
              IconButton(
                tooltip: 'Télécharger',
                icon: const Icon(Icons.download_outlined),
                onPressed: onDownload,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Pochette d'un titre YouTube avec voile + icône de lecture/pause (ou
/// indicateur de chargement) signalant la pré-écoute d'un simple tap.
class _PreviewArtwork extends StatelessWidget {
  const _PreviewArtwork({
    required this.url,
    required this.active,
    required this.playing,
    required this.loading,
  });

  final String? url;
  final bool active;
  final bool playing;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 46,
      height: 46,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Artwork(url: url, size: 46, borderRadius: 12, icon: Icons.music_note),
          DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: Colors.black.withValues(alpha: active ? 0.44 : 0.30),
            ),
            child: Center(
              child: loading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Icon(
                      playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                      color: Colors.white,
                      size: 26,
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Fine barre de progression de la pré-écoute en cours.
class _PreviewProgress extends StatelessWidget {
  const _PreviewProgress({required this.preview, required this.color});

  final PreviewState preview;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final dur = preview.duration;
    final value = (dur != null && dur.inMilliseconds > 0)
        ? (preview.position.inMilliseconds / dur.inMilliseconds)
            .clamp(0.0, 1.0)
        : null;
    return ClipRRect(
      borderRadius: BorderRadius.circular(3),
      child: LinearProgressIndicator(
        value: preview.loading ? null : value,
        minHeight: 3,
        color: color,
        backgroundColor: color.withValues(alpha: 0.15),
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

/// Découverte : les nouvelles sorties de YouTube Music, ALBUMS seulement (le
/// serveur écarte singles et EP). Affichée dans l'onglet Recherche quand le
/// champ est vide; un tap propose le téléchargement, comme un résultat.
///
/// YouTube sert la même page mondiale à tout le monde (le pays n'y change
/// rien) : c'est le serveur qui la reclasse, tes artistes en tête et le bruit
/// à la fin. Les sorties d'un artiste déjà écouté le disent sous leur titre.
class _NewReleasesSection extends ConsumerWidget {
  const _NewReleasesSection({required this.onDownload});

  final ValueChanged<YtAlbum> onDownload;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final releases = ref.watch(ytNewReleasesProvider);
    final limit = ref.watch(newReleasesLimitProvider);
    // Valeurs déjà connues : conservées pendant un « Charger plus ».
    final albums = releases.value ?? const <YtAlbum>[];
    // Section secondaire : si YouTube ne répond pas, on n'encombre pas l'écran.
    if (albums.isEmpty && releases.hasError) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionTitle(
          'Nouveautés',
          padding: EdgeInsets.fromLTRB(20, 18, 20, 2),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, 6),
          child: Text(
            'Nouveaux albums sur YouTube Music, tes artistes en premier',
            style: TextStyle(fontSize: 12.5, color: Color(0xFF8A8F98)),
          ),
        ),
        for (final a in albums)
          _ResultRow(
            artwork: Artwork(
              url: a.thumbnail.isEmpty ? null : a.thumbnail,
              size: 46,
              borderRadius: 12,
            ),
            title: a.title,
            subtitle: a.knownArtist && !a.inLibrary
                ? '${a.artist} · Tu écoutes déjà cet artiste'
                : a.artist,
            trailing: a.inLibrary
                ? const InLibraryBadge()
                : const Icon(Icons.download_outlined),
            onTap: () => onDownload(a),
          ),
        if (releases.isLoading)
          const _LoadingRow()
        else if (albums.length >= limit && limit < 60)
          _LoadMoreButton(
            onPressed: () => ref.read(newReleasesLimitProvider.notifier).more(),
          ),
      ],
    );
  }
}

/// En-tête de la discographie d'un artiste en ligne : sa photo, son nom, et
/// une flèche pour revenir aux résultats de recherche.
class _ArtistHeader extends StatelessWidget {
  const _ArtistHeader({
    required this.name,
    required this.thumbnail,
    required this.onBack,
  });

  final String name;
  final String thumbnail;
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
            url: thumbnail.isEmpty ? null : thumbnail,
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
                  name,
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
