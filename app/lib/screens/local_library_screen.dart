import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/song.dart';
import '../state/auth.dart';
import '../state/local_library.dart';
import '../state/player.dart';
import '../widgets/adaptive_layout.dart';
import '../widgets/album_card.dart' show kArtShadow;
import '../widgets/alpha_grid.dart';
import '../widgets/artwork.dart';
import '../widgets/detail_hero.dart';
import '../widgets/glass_box.dart';
import '../widgets/glass_kit.dart';
import '../widgets/mascot_empty.dart';
import '../widgets/mini_player.dart';
import '../widgets/song_tile.dart';

/// Le mode « dossier local » (idée #114) : l'app sans serveur, sur un dossier
/// du téléphone. Trois vues — artistes, albums, titres —, un album et un
/// artiste qui s'ouvrent comme ailleurs, et le même lecteur.
///
/// Tout ce qui demande un serveur (favoris, playlists, radios, jeux, paroles,
/// statistiques, partage) est absent : ce n'est pas un repli du mode serveur,
/// c'est un mode à part, et il ne prétend pas en faire autant.

/// Demande un dossier et y installe le mode local. Renvoie `true` si un
/// dossier a été choisi.
///
/// Le parcours n'est PAS lancé ici : l'écran du dossier local s'en charge en
/// s'ouvrant — celui qui appelle (l'écran du serveur) disparaît dans
/// l'intervalle, et n'a plus de quoi attendre quoi que ce soit.
Future<bool> pickLocalFolder(BuildContext context, WidgetRef ref) async {
  String? path;
  try {
    path = await FilePicker.getDirectoryPath(
      dialogTitle: 'Dossier de musique',
    );
  } catch (_) {
    path = null;
  }
  if (path == null) return false;
  // Android rend « / » pour un dossier protégé, dont rien ne pourra être lu.
  if (path == '/' || path.isEmpty) {
    if (context.mounted) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(
          content: Text('Ce dossier n\'est pas accessible — essaie un dossier '
              'de la mémoire du téléphone, comme Music ou Download.'),
        ),
      );
    }
    return false;
  }
  // La vignette de reprise d'Android Auto désigne ce qu'on écoutait AVANT :
  // dans l'autre mode, ce titre n'a plus ni fichier ni flux.
  await ref.read(audioHandlerProvider).resume.forget();
  await ref.read(authProvider.notifier).useLocalFolder(path);
  return true;
}

enum _LocalView { artistes, albums, titres }

class LocalLibraryScreen extends ConsumerStatefulWidget {
  const LocalLibraryScreen({super.key});

  @override
  ConsumerState<LocalLibraryScreen> createState() => _LocalLibraryScreenState();
}

class _LocalLibraryScreenState extends ConsumerState<LocalLibraryScreen> {
  _LocalView _view = _LocalView.albums;

  @override
  void initState() {
    super.initState();
    // Dossier jamais parcouru (premier lancement, index effacé) : on s'y met
    // sans rien demander. Choisir un dossier PUIS devoir demander sa lecture
    // n'aurait aucun sens.
    WidgetsBinding.instance.addPostFrameCallback((_) => _ensureScanned());
  }

  void _ensureScanned() {
    if (!mounted) return;
    ref.read(localLibraryProvider.notifier).ensureScanned();
  }

  @override
  Widget build(BuildContext context) {
    // Changement de dossier en cours de route : le nouvel index arrive vide,
    // et demande lui aussi son parcours.
    ref.listen(localLibraryProvider, (_, next) {
      if (next.value?.scannedAt == null) _ensureScanned();
    });

    final local = ref.watch(localLibraryProvider);
    final scan = ref.watch(localScanProvider);

    return Scaffold(
      bottomNavigationBar: const SafeArea(top: false, child: MiniPlayer()),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _Header(folderName: local.value?.folderName),
            Expanded(
              child: switch ((local, scan)) {
                // Le parcours passe devant : c'est le seul moment où l'écran a
                // quelque chose à raconter.
                (_, final LocalScanProgress p) when p.error == null =>
                  _ScanProgressView(progress: p),
                (_, final LocalScanProgress p) => _ScanErrorView(error: p
                    .error!),
                (AsyncLoading(), _) =>
                  const Center(child: CircularProgressIndicator()),
                (AsyncError(:final error), _) =>
                  _ScanErrorView(error: '$error'),
                (AsyncData(value: final LocalLibrary lib), _) => lib.isEmpty
                    ? const _EmptyFolderView()
                    : _LibraryViews(
                        library: lib,
                        view: _view,
                        onViewChanged: (v) => setState(() => _view = v),
                      ),
                _ => const Center(child: CircularProgressIndicator()),
              },
            ),
          ],
        ),
      ),
    );
  }
}

// ───────────────────────────── En-tête ─────────────────────────────

class _Header extends ConsumerWidget {
  const _Header({required this.folderName});

  final String? folderName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Dossier local',
                  style: TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.6,
                    height: 1.02,
                  ),
                ),
                if (folderName != null)
                  Text(
                    folderName!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
              ],
            ),
          ),
          // La recherche, comme avec un serveur (idée #115) : au doigt, elle
          // cherche dans tout le dossier — titres, albums et artistes
          // ensemble — là où le filtre d'une vue ne voit que la sienne.
          GlassIconButton(
            icon: Icons.search,
            tooltip: 'Rechercher dans le dossier',
            size: 42,
            onPressed: () => context.push('/local/search'),
          ),
          const SizedBox(width: 8),
          GlassIconButton(
            icon: Icons.more_horiz,
            tooltip: 'Options du dossier',
            size: 42,
            onPressed: () => _showMenu(context, ref),
          ),
        ],
      ),
    );
  }

  Future<void> _showMenu(BuildContext context, WidgetRef ref) async {
    final scanning = ref.read(localScanProvider) != null;
    await showModalBottomSheet<void>(
      context: context,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.refresh),
              title: const Text('Reparcourir le dossier'),
              subtitle: const Text('À faire après avoir ajouté de la musique'),
              enabled: !scanning,
              onTap: () {
                Navigator.of(sheet).pop();
                ref.read(localLibraryProvider.notifier).rescan();
              },
            ),
            ListTile(
              leading: const Icon(Icons.folder_open),
              title: const Text('Changer de dossier'),
              onTap: () async {
                Navigator.of(sheet).pop();
                await pickLocalFolder(context, ref);
              },
            ),
            ListTile(
              leading: const Icon(Icons.dns_outlined),
              title: const Text('Se connecter à un serveur'),
              subtitle: const Text(
                'Bibliothèque partagée, favoris, playlists, radios…',
              ),
              onTap: () async {
                Navigator.of(sheet).pop();
                await ref.read(audioHandlerProvider).resume.forget();
                await ref.read(localLibraryProvider.notifier).forget();
                await ref.read(authProvider.notifier).leaveLocalFolder();
              },
            ),
            ListTile(
              leading: const Icon(Icons.tune),
              title: const Text('Égaliseur et fondus'),
              onTap: () {
                Navigator.of(sheet).pop();
                context.push('/settings/equalizer');
              },
            ),
            // Les titres descendus d'un serveur se jouent depuis leur fichier :
            // ils restent écoutables ici, et dans la voiture (idée #115).
            ListTile(
              leading: const Icon(Icons.download_done),
              title: const Text('Téléchargements'),
              subtitle: const Text(
                'Les titres déjà descendus sur le téléphone',
              ),
              onTap: () {
                Navigator.of(sheet).pop();
                context.push('/settings/downloads');
              },
            ),
            ListTile(
              leading: const Icon(Icons.directions_car_outlined),
              title: const Text('Journal Android Auto'),
              onTap: () {
                Navigator.of(sheet).pop();
                context.push('/settings/aa-diagnostic');
              },
            ),
          ],
        ),
      ),
    );
  }
}

// ──────────────────────── Parcours du dossier ────────────────────────

class _ScanProgressView extends StatelessWidget {
  const _ScanProgressView({required this.progress});

  final LocalScanProgress progress;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                progress.listing
                    ? 'Recherche des fichiers…'
                    : 'Lecture des étiquettes',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight
                    .w700),
              ),
              const SizedBox(height: 16),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: progress.fraction,
                  minHeight: 8,
                ),
              ),
              const SizedBox(height: 12),
              if (progress.total > 0)
                Text(
                  '${progress.done} / ${progress.total} fichiers',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              if (progress.current != null) ...[
                const SizedBox(height: 4),
                Text(
                  progress.current!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ScanErrorView extends ConsumerWidget {
  const _ScanErrorView({required this.error});

  final String error;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MascotEmpty(
      message: 'Dossier non lu',
      hint: error,
      action: Wrap(
        spacing: 12,
        alignment: WrapAlignment.center,
        children: [
          FilledButton(
            onPressed: () => ref.read(localLibraryProvider.notifier).rescan(),
            child: const Text('Réessayer'),
          ),
          OutlinedButton(
            onPressed: () => pickLocalFolder(context, ref),
            child: const Text('Changer de dossier'),
          ),
        ],
      ),
    );
  }
}

class _EmptyFolderView extends ConsumerWidget {
  const _EmptyFolderView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MascotEmpty(
      message: 'Rien à écouter ici',
      hint: 'Ce dossier ne contient aucun fichier audio que Gullify sache '
          'lire (MP3, FLAC, M4A, OGG, Opus, WAV).',
      action: FilledButton(
        onPressed: () => pickLocalFolder(context, ref),
        child: const Text('Choisir un autre dossier'),
      ),
    );
  }
}

// ───────────────────────── Les trois vues ─────────────────────────

class _LibraryViews extends StatelessWidget {
  const _LibraryViews({
    required this.library,
    required this.view,
    required this.onViewChanged,
  });

  final LocalLibrary library;
  final _LocalView view;
  final ValueChanged<_LocalView> onViewChanged;

  static const _labels = {
    _LocalView.artistes: 'Artistes',
    _LocalView.albums: 'Albums',
    _LocalView.titres: 'Titres',
  };

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: GlassBox(
            radius: 16,
            blur: false,
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Row(
                children: [
                  for (final v in _LocalView.values)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: _SegmentButton(
                          label: _labels[v]!,
                          selected: v == view,
                          onTap: () => onViewChanged(v),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        Expanded(
          child: switch (view) {
            _LocalView.artistes => _ArtistsView(library: library),
            _LocalView.albums => _AlbumsView(library: library),
            _LocalView.titres => _SongsView(library: library),
          },
        ),
      ],
    );
  }
}

class _SegmentButton extends StatelessWidget {
  const _SegmentButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
      height: 38,
      decoration: BoxDecoration(
        color: selected ? scheme.primary : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Center(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              label,
              maxLines: 1,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
                color: selected ? scheme.onPrimary : scheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ArtistsView extends StatelessWidget {
  const _ArtistsView({required this.library});

  final LocalLibrary library;

  @override
  Widget build(BuildContext context) {
    return AlphaGrid<LocalArtist>(
      items: library.artists,
      nameOf: (a) => a.artist.name,
      hintText: 'Filtrer les artistes…',
      trailing: _ShuffleAllButton(songs: library.songs),
      rowExtent: 72,
      itemBuilder: (context, artist) => _LocalArtistRow(artist: artist),
    );
  }
}

class _AlbumsView extends StatelessWidget {
  const _AlbumsView({required this.library});

  final LocalLibrary library;

  @override
  Widget build(BuildContext context) {
    return AlphaGrid<LocalAlbum>(
      items: library.albums,
      nameOf: (a) => a.album.name,
      hintText: 'Filtrer les albums…',
      trailing: _ShuffleAllButton(songs: library.songs),
      maxCrossAxisExtent: 200,
      childAspectRatio: 0.75,
      itemBuilder: (context, album) => _LocalAlbumCard(album: album),
    );
  }
}

class _SongsView extends ConsumerWidget {
  const _SongsView({required this.library});

  final LocalLibrary library;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentSongId =
        ref.watch(currentMediaItemProvider).value?.extras?['songId'] as int?;
    // Même ordre que celui de la liste (AlphaGrid trie par nom) : la file qui
    // part d'un titre doit être celle qu'on voit, pas celle du rangement par
    // artiste.
    final byTitle = [...library.songs]
      ..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    return AlphaGrid<Song>(
      items: byTitle,
      nameOf: (s) => s.title,
      hintText: 'Filtrer les titres…',
      trailing: _ShuffleAllButton(songs: library.songs),
      rowExtent: 72,
      itemBuilder: (context, song) => SongTile(
        song: song,
        isPlaying: song.id == currentSongId,
        albumInSubtitle: true,
        onTap: () => _playFrom(ref, byTitle, song),
        onLongPress: () => showLocalSongMenu(context, ref, song),
      ),
    );
  }
}

/// Lance la liste à partir d'un titre : la file entière, comme partout
/// ailleurs dans l'app — pas le seul titre touché.
void _playFrom(WidgetRef ref, List<Song> songs, Song song) {
  final index = songs.indexWhere((s) => s.id == song.id);
  ref.read(playerActionsProvider).playSongs(
        songs,
        startIndex: index < 0 ? 0 : index,
      );
}

/// Le menu d'un titre local : ni favoris, ni playlists, ni partage — rien de
/// tout cela n'existe sans serveur. Juste la file.
Future<void> showLocalSongMenu(
  BuildContext context,
  WidgetRef ref,
  Song song,
) async {
  final actions = ref.read(playerActionsProvider);
  await showModalBottomSheet<void>(
    context: context,
    builder: (sheet) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: Artwork(url: song.artworkUrl, size: 44),
            title: Text(song.title, maxLines: 1, overflow: TextOverflow
                .ellipsis),
            subtitle: song.artistName == null
                ? null
                : Text(
                    song.artistName!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.playlist_play),
            title: const Text('Lire ensuite'),
            onTap: () {
              Navigator.of(sheet).pop();
              actions.playNext(song);
            },
          ),
          ListTile(
            leading: const Icon(Icons.queue_music),
            title: const Text('Ajouter à la file'),
            onTap: () {
              Navigator.of(sheet).pop();
              actions.addToQueue(song);
            },
          ),
        ],
      ),
    ),
  );
}

class _ShuffleAllButton extends ConsumerWidget {
  const _ShuffleAllButton({required this.songs});

  final List<Song> songs;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return IconButton.filledTonal(
      tooltip: 'Lecture aléatoire du dossier',
      icon: const Icon(Icons.shuffle),
      onPressed: songs.isEmpty
          ? null
          : () => ref
              .read(playerActionsProvider)
              .playSongs(songs.toList()..shuffle()),
    );
  }
}

class _LocalAlbumCard extends StatelessWidget {
  const _LocalAlbumCard({required this.album});

  final LocalAlbum album;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () => context.push('/local/album/${album.album.id}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 1,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                boxShadow: const [kArtShadow],
              ),
              child: Artwork(url: album.album.artworkUrl, borderRadius: 20),
            ),
          ),
          const SizedBox(height: 9),
          Text(
            album.album.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
          ),
          Text(
            album.album.artistName ?? kUnknownArtist,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _LocalArtistRow extends StatelessWidget {
  const _LocalArtistRow({required this.artist});

  final LocalArtist artist;

  @override
  Widget build(BuildContext context) {
    final a = artist.artist;
    return ListTile(
      leading: ClipOval(
        child: Artwork(url: a.imageUrl, size: 48, icon: Icons.person),
      ),
      title: Text(
        a.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      subtitle: Text(
        '${a.albumCount} album${a.albumCount > 1 ? 's' : ''} · '
        '${a.songCount} titre${a.songCount > 1 ? 's' : ''}',
      ),
      onTap: () => context.push('/local/artist/${a.id}'),
    );
  }
}

// ─────────────────────── Recherche dans le dossier ───────────────────────

/// La recherche du mode local (idée #115) : un seul champ pour tout le
/// dossier — titres, albums et artistes à la fois —, là où le filtre d'une vue
/// ne voit que la sienne. Sans serveur, il n'y a ni YouTube ni Bandcamp
/// derrière : ce qui se cherche ici est ce qui est déjà sur le téléphone.
class LocalSearchScreen extends ConsumerStatefulWidget {
  const LocalSearchScreen({super.key});

  @override
  ConsumerState<LocalSearchScreen> createState() => _LocalSearchScreenState();
}

class _LocalSearchScreenState extends ConsumerState<LocalSearchScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final library = ref.watch(localLibraryProvider).value;
    final currentSongId =
        ref.watch(currentMediaItemProvider).value?.extras?['songId'] as int?;
    final songs = library?.search(_query) ?? const <Song>[];
    final albums = library?.searchAlbums(_query) ?? const <LocalAlbum>[];
    final artists = library?.searchArtists(_query) ?? const <LocalArtist>[];
    final nothing = songs.isEmpty && albums.isEmpty && artists.isEmpty;

    return Scaffold(
      appBar: AppBar(
        title: TextField(
          autofocus: true,
          textInputAction: TextInputAction.search,
          onChanged: (v) => setState(() => _query = v),
          decoration: const InputDecoration(
            hintText: 'Chercher dans le dossier…',
            prefixIcon: Icon(Icons.search),
            isDense: true,
          ),
        ),
      ),
      bottomNavigationBar: const SafeArea(top: false, child: MiniPlayer()),
      body: _query.trim().isEmpty
          ? const _SearchHint()
          : nothing
              ? const MascotEmpty(
                  message: 'Rien trouvé',
                  hint: 'Aucun titre, album ou artiste de ce dossier ne porte '
                      'ce nom. Chercher sur Bandcamp ou télécharger de la '
                      'musique, en revanche, demande un serveur : c\'est lui '
                      'qui va la chercher et la range.',
                )
              : ListView(
                  padding: const EdgeInsets.only(bottom: 24),
                  // Défiler referme le clavier : les résultats prennent alors
                  // tout l'écran.
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  children: [
                    if (artists.isNotEmpty) ...[
                      const _SearchSection(title: 'Artistes'),
                      for (final a in artists) _LocalArtistRow(artist: a),
                    ],
                    if (albums.isNotEmpty) ...[
                      const _SearchSection(title: 'Albums'),
                      for (final a in albums)
                        ListTile(
                          leading: Artwork(
                            url: a.album.artworkUrl,
                            size: 48,
                            borderRadius: 8,
                          ),
                          title: Text(
                            a.album.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style:
                                const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          subtitle: Text(
                            a.album.artistName ?? kUnknownArtist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onTap: () =>
                              context.push('/local/album/${a.album.id}'),
                        ),
                    ],
                    if (songs.isNotEmpty) ...[
                      const _SearchSection(title: 'Titres'),
                      for (final s in songs)
                        SongTile(
                          song: s,
                          isPlaying: s.id == currentSongId,
                          albumInSubtitle: true,
                          // La file, c'est ce qu'on voit : les résultats.
                          onTap: () => _playFrom(ref, songs, s),
                          onLongPress: () =>
                              showLocalSongMenu(context, ref, s),
                        ),
                    ],
                  ],
                ),
    );
  }
}

class _SearchHint extends StatelessWidget {
  const _SearchHint();

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            'Cherche un titre, un album ou un artiste du dossier.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      );
}

class _SearchSection extends StatelessWidget {
  const _SearchSection({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
        child: Text(
          title,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
        ),
      );
}

// ────────────────────────── Un album du dossier ──────────────────────────

class LocalAlbumScreen extends ConsumerWidget {
  const LocalAlbumScreen({super.key, required this.albumId});

  final int albumId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final album = ref.watch(localLibraryProvider).value?.albumById(albumId);
    final currentSongId =
        ref.watch(currentMediaItemProvider).value?.extras?['songId'] as int?;
    if (album == null) {
      return const Scaffold(
        body: Center(child: Text('Cet album n\'est plus dans le dossier.')),
      );
    }
    final songs = album.songs;
    return Scaffold(
      bottomNavigationBar: const SafeArea(top: false, child: MiniPlayer()),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          DetailHero(
            imageUrl: album.album.artworkUrl,
            onMenu: () => _menu(context, ref, songs),
            info: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  album.album.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.8,
                    height: 1.04,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    album.album.artistName ?? kUnknownArtist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    [
                      if (album.album.year != null) '${album.album.year}',
                      '${songs.length} titre${songs.length > 1 ? 's' : ''}',
                    ].join(' · '),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
          _PlayRow(songs: songs),
          for (final (i, song) in songs.indexed)
            SongTile(
              song: song,
              showArtwork: false,
              leadingNumber: song.trackNumber ?? i + 1,
              isPlaying: song.id == currentSongId,
              showTrackArtist: song.artistName != null &&
                  song.artistName != album.album.artistName,
              showArtist: false,
              showAlbum: false,
              onTap: () => ref
                  .read(playerActionsProvider)
                  .playSongs(songs, startIndex: i),
              onLongPress: () => showLocalSongMenu(context, ref, song),
            ),
        ],
      ),
    );
  }

  Future<void> _menu(
    BuildContext context,
    WidgetRef ref,
    List<Song> songs,
  ) async {
    final actions = ref.read(playerActionsProvider);
    await showModalBottomSheet<void>(
      context: context,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.queue_music),
              title: const Text('Ajouter l\'album à la file'),
              onTap: () {
                Navigator.of(sheet).pop();
                for (final s in songs) {
                  actions.addToQueue(s);
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}

// ───────────────────────── Un artiste du dossier ─────────────────────────

class LocalArtistScreen extends ConsumerWidget {
  const LocalArtistScreen({super.key, required this.artistId});

  final int artistId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final artist = ref.watch(localLibraryProvider).value?.artistById(artistId);
    if (artist == null) {
      return const Scaffold(
        body: Center(child: Text('Cet artiste n\'est plus dans le dossier.')),
      );
    }
    return Scaffold(
      bottomNavigationBar: const SafeArea(top: false, child: MiniPlayer()),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          DetailHero(
            imageUrl: artist.artist.imageUrl,
            icon: Icons.person,
            roundCover: true,
            onMenu: () {},
            info: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  artist.artist.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.8,
                    height: 1.04,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    '${artist.albums.length} album'
                    '${artist.albums.length > 1 ? 's' : ''} · '
                    '${artist.songs.length} titre'
                    '${artist.songs.length > 1 ? 's' : ''}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
          _PlayRow(songs: artist.songs),
          for (final album in artist.albums) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
              child: InkWell(
                onTap: () => context.push('/local/album/${album.album.id}'),
                child: Row(
                  children: [
                    Artwork(url: album.album.artworkUrl, size: 44),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        album.album.year == null
                            ? album.album.name
                            : '${album.album.name} · ${album.album.year}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 17,
                        ),
                      ),
                    ),
                    const Icon(Icons.chevron_right),
                  ],
                ),
              ),
            ),
            for (final (i, song) in album.songs.indexed)
              _LocalSongTile(
                song: song,
                number: song.trackNumber ?? i + 1,
                songs: album.songs,
                index: i,
              ),
          ],
        ],
      ),
    );
  }
}

class _LocalSongTile extends ConsumerWidget {
  const _LocalSongTile({
    required this.song,
    required this.number,
    required this.songs,
    required this.index,
  });

  final Song song;
  final int number;
  final List<Song> songs;
  final int index;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentSongId =
        ref.watch(currentMediaItemProvider).value?.extras?['songId'] as int?;
    return SongTile(
      song: song,
      showArtwork: false,
      leadingNumber: number,
      isPlaying: song.id == currentSongId,
      showArtist: false,
      showAlbum: false,
      onTap: () =>
          ref.read(playerActionsProvider).playSongs(songs, startIndex: index),
      onLongPress: () => showLocalSongMenu(context, ref, song),
    );
  }
}

class _PlayRow extends ConsumerWidget {
  const _PlayRow({required this.songs});

  final List<Song> songs;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final actions = ref.read(playerActionsProvider);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 6),
      child: Row(
        children: [
          PrimaryActionSlot(
            child: AccentPlayButton(
              onPressed: songs.isEmpty ? null : () => actions.playSongs(songs),
            ),
          ),
          const SizedBox(width: 12),
          GlassIconButton(
            icon: Icons.shuffle,
            tooltip: 'Lecture aléatoire',
            size: 50,
            onPressed: songs.isEmpty
                ? null
                : () => actions.playSongs(songs.toList()..shuffle()),
          ),
        ],
      ),
    );
  }
}
