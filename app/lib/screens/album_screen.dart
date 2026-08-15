import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../api/api_client.dart';
import '../api/library_repository.dart';
import '../models/album.dart';
import '../models/song.dart';
import '../state/library.dart';
import '../state/offline.dart';
import '../state/player.dart';
import '../widgets/artwork.dart';
import '../widgets/glass_kit.dart';
import '../widgets/image_choice_dialog.dart';
import 'shell_screen.dart';
import '../widgets/share_sheet.dart';
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
            _AlbumHeader(
              album: d.album,
              songCount: d.songs.length,
              onMenu: () => _albumMenu(context, ref, d.album),
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
                // Compilation : affiche « Interprète — Titre », sauf pour les
                // pistes sans interprète propre (elles héritent alors de
                // l'artiste de l'album — inutile de le répéter).
                showTrackArtist: song.artistName != null &&
                    song.artistName != d.album.artistName,
                // L'entête donne déjà l'artiste de l'album.
                showArtist: false,
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

/// Menu d'un album : partage éphémère, jaquette, suppression définitive
/// (fichiers + base).
void _albumMenu(BuildContext context, WidgetRef ref, Album album) {
  showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.ios_share_rounded),
            title: const Text("Partager l'album"),
            subtitle: const Text('Lien d\'écoute valable 24 h'),
            onTap: () {
              Navigator.pop(sheetContext);
              showShareSheet(context, ShareTarget.album(album));
            },
          ),
          ListTile(
            leading: const Icon(Icons.image_outlined),
            title: const Text('Changer la jaquette'),
            subtitle: const Text('Proposition, lien ou image du téléphone'),
            onTap: () {
              Navigator.pop(sheetContext);
              _albumCoverDialog(context, album);
            },
          ),
          ListTile(
            leading: const Icon(Icons.drive_file_rename_outline),
            title: const Text("Corriger l'artiste ou le titre"),
            subtitle: const Text('Range l\'album chez le bon artiste'),
            onTap: () {
              Navigator.pop(sheetContext);
              _albumNamesDialog(context, ref, album);
            },
          ),
          const Divider(height: 1),
          ListTile(
            leading: Icon(Icons.delete_outline,
                color: Theme.of(sheetContext).colorScheme.error),
            title: Text(
              "Supprimer l'album",
              style:
                  TextStyle(color: Theme.of(sheetContext).colorScheme.error),
            ),
            subtitle: const Text('Tous ses titres'),
            onTap: () async {
              final messenger = ScaffoldMessenger.of(context);
              Navigator.pop(sheetContext);
              final ok = await confirmDelete(
                context,
                'Supprimer « ${album.name} » ?',
                'Tous les titres de cet album seront effacés du serveur. '
                    'Action irréversible.',
              );
              if (ok != true) return;
              try {
                await ref.read(libraryRepositoryProvider).deleteAlbum(album.id);
                invalidateLibrary(ref);
                if (context.mounted) {
                  context.pop();
                  messenger.showSnackBar(
                    SnackBar(content: Text('« ${album.name} » supprimé')),
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

/// Dialogue « Changer la jaquette » (idée #93), et ce qu'il faut faire
/// après : la fiche et les listes reprennent l'URL neuve — elle porte la date
/// de la jaquette, sans quoi le cache d'images de l'app continuerait
/// d'afficher l'ancienne et le changement n'aurait l'air de rien.
///
/// La jaquette choisie est rangée côté serveur dans le cache, servi avant le
/// `folder.jpg` du dossier et avant la pochette des tags : aucun fichier de
/// musique n'est touché, et « Jaquette automatique » rend la main à ce que le
/// serveur trouve tout seul.
Future<void> _albumCoverDialog(BuildContext context, Album album) async {
  final messenger = ScaffoldMessenger.of(context);
  final container = ProviderScope.containerOf(context, listen: false);
  final repo = container.read(libraryRepositoryProvider);

  // « artiste titre » : le titre seul ramène les albums homonymes de toute la
  // planète, et il y en a beaucoup.
  final query = [album.artistName ?? '', album.name]
      .where((s) => s.isNotEmpty)
      .join(' ');

  final done = await showDialog<String>(
    context: context,
    builder: (_) => ImageChoiceDialog(
      title: 'Jaquette de « ${album.name} »',
      searchLabel: 'Chercher un album',
      initialQuery: query,
      emptyMessage: 'Aucune jaquette trouvée sous ce nom.',
      doneMessage: 'Jaquette mise à jour',
      resetLabel: 'Jaquette automatique',
      resetMessage: 'Jaquette automatique rétablie',
      onSearch: (q) async => [
        for (final c in await repo.albumCoverCandidates(album.id, query: q))
          ImageCandidate(
            thumbnail: c.thumbnail,
            label: c.title,
            sublabel: c.artist,
            source: c.source,
          ),
      ],
      onUrl: (url) => repo.setAlbumCoverFromUrl(album.id, url),
      onFile: (path) => repo.uploadAlbumCover(album.id, path),
      onReset: () => repo.resetAlbumCover(album.id),
    ),
  );
  if (done == null) return; // Refermé sans rien changer.

  container.invalidate(albumDetailProvider(album.id));
  container.invalidate(albumsProvider);
  container.invalidate(recentAlbumsProvider);
  if (album.artistId != null) {
    container.invalidate(artistDetailProvider(album.artistId!));
  }
  messenger.showSnackBar(SnackBar(content: Text(done)));
}

/// Corriger l'artiste ou le titre d'un album (idée #94), et ce qu'il faut
/// faire après : un album qui a rejoint son homonyme n'existe plus sous son
/// ancien identifiant — rester sur sa fiche n'afficherait qu'une erreur.
///
/// Le serveur fait le reste : l'album passe sous l'artiste ainsi nommé (celui
/// qui existe déjà de préférence), l'artiste laissé vide s'en va, et les tags
/// des fichiers sont récrits pour que le prochain scan ne ramène pas l'erreur.
Future<void> _albumNamesDialog(
  BuildContext context,
  WidgetRef ref,
  Album album,
) async {
  final messenger = ScaffoldMessenger.of(context);
  final repo = ref.read(libraryRepositoryProvider);
  final oldArtistId = album.artistId;

  final done = await showDialog<AlbumEdit>(
    context: context,
    builder: (_) => _AlbumNamesDialog(
      artist: album.artistName ?? '',
      album: album.name,
      onSave: (artist, name) =>
          repo.editAlbum(album.id, artist: artist, album: name),
    ),
  );
  if (done == null || !done.changed) return; // Refermé sans rien changer.

  invalidateLibrary(ref);
  ref.invalidate(albumDetailProvider(album.id));
  ref.invalidate(albumDetailProvider(done.albumId));
  if (oldArtistId != null) ref.invalidate(artistDetailProvider(oldArtistId));
  ref.invalidate(artistDetailProvider(done.artistId));

  messenger.showSnackBar(SnackBar(content: Text(done.summary)));
  if (done.albumId != album.id && context.mounted) {
    context.pushReplacement('/album/${done.albumId}');
  }
}

/// Les deux noms qui rangent un album : son artiste et son titre. Ils sont
/// donnés remplis — on vient ici pour corriger une faute, pas pour tout
/// ressaisir — et « Enregistrer » ne s'allume qu'une fois quelque chose changé.
class _AlbumNamesDialog extends StatefulWidget {
  const _AlbumNamesDialog({
    required this.artist,
    required this.album,
    required this.onSave,
  });

  final String artist;
  final String album;
  final Future<AlbumEdit> Function(String artist, String album) onSave;

  @override
  State<_AlbumNamesDialog> createState() => _AlbumNamesDialogState();
}

class _AlbumNamesDialogState extends State<_AlbumNamesDialog> {
  late final _artistCtrl = TextEditingController(text: widget.artist);
  late final _albumCtrl = TextEditingController(text: widget.album);

  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _artistCtrl.dispose();
    _albumCtrl.dispose();
    super.dispose();
  }

  /// Un champ vidé garde son nom d'avant : on ne corrige jamais qu'un des deux.
  String get _artist =>
      _artistCtrl.text.trim().isEmpty ? widget.artist : _artistCtrl.text.trim();
  String get _album =>
      _albumCtrl.text.trim().isEmpty ? widget.album : _albumCtrl.text.trim();

  bool get _dirty => _artist != widget.artist || _album != widget.album;

  /// Enregistre, puis referme en rendant ce qui a été fait. Un échec reste
  /// dans le dialogue : rien n'a changé, autant pouvoir réessayer sans tout
  /// ressaisir.
  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await widget.onSave(_artist, _album);
      if (mounted) Navigator.pop(context, result);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e is ApiException ? e.message : '$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      titlePadding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
      contentPadding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
      title: const Text(
        "Corriger l'artiste ou le titre",
        style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
      ),
      content: SizedBox(
        width: 380,
        child: _busy
            ? const Padding(
                padding: EdgeInsets.symmetric(vertical: 28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 12),
                    Text('Correction des fichiers…'),
                  ],
                ),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: _artistCtrl,
                    style: const TextStyle(fontSize: 14),
                    textInputAction: TextInputAction.next,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      isDense: true,
                      labelText: 'Artiste',
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _albumCtrl,
                    style: const TextStyle(fontSize: 14),
                    textInputAction: TextInputAction.done,
                    onChanged: (_) => setState(() {}),
                    onSubmitted: (_) => _dirty ? _save() : null,
                    decoration: const InputDecoration(
                      isDense: true,
                      labelText: "Titre de l'album",
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    "L'album va rejoindre l'artiste ainsi nommé, et se réunir "
                    'avec l\'album du même titre s\'il y en a un. Les tags des '
                    'fichiers sont corrigés au passage ; ils restent dans leur '
                    'dossier.',
                    style: TextStyle(
                      fontSize: 12.5,
                      height: 1.35,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _error!,
                      style: TextStyle(fontSize: 13, color: scheme.error),
                    ),
                  ],
                ],
              ),
      ),
      actions: _busy
          ? const []
          : [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Annuler'),
              ),
              FilledButton(
                onPressed: _dirty ? _save : null,
                child: const Text('Enregistrer'),
              ),
            ],
    );
  }
}

/// En-tête d'album immersif : pochette floutée plein cadre qui se dissout
/// dans le fond de l'app, pochette nette + titre + artiste en surimpression.
class _AlbumHeader extends StatelessWidget {
  const _AlbumHeader({
    required this.album,
    required this.songCount,
    required this.onMenu,
  });

  final Album album;
  final int songCount;
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
