import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/song.dart';
import '../state/favorites.dart';
import '../state/library.dart';
import '../state/offline.dart';
import '../state/player.dart';
import '../state/playlists.dart';
import 'artwork.dart';
import 'share_sheet.dart';

/// Bottom sheet with actions for a song (favorite, playlists, navigation).
Future<void> showSongMenu(BuildContext context, Song song) {
  return showModalBottomSheet(
    context: context,
    useRootNavigator: true,
    builder: (context) => Consumer(
      builder: (context, ref, _) {
        final isFavorite =
            ref.watch(favoriteIdsProvider).value?.contains(song.id) ?? false;
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Artwork(
                  url: song.artworkUrl,
                  size: 44,
                  icon: Icons.music_note,
                ),
                title: Text(song.title, maxLines: 1),
                subtitle:
                    song.artistName != null ? Text(song.artistName!) : null,
              ),
              const Divider(height: 1),
              ListTile(
                leading: Icon(
                  isFavorite ? Icons.favorite : Icons.favorite_border,
                  color: isFavorite
                      ? Theme.of(context).colorScheme.primary
                      : null,
                ),
                title: Text(
                  isFavorite ? 'Retirer des favoris' : 'Ajouter aux favoris',
                ),
                onTap: () {
                  ref.read(favoriteIdsProvider.notifier).toggle(song.id);
                  Navigator.pop(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.playlist_play),
                title: const Text('Jouer ensuite'),
                onTap: () {
                  ref.read(playerActionsProvider).playNext(song);
                  Navigator.pop(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.queue),
                title: const Text('Ajouter à la file'),
                onTap: () {
                  ref.read(playerActionsProvider).addToQueue(song);
                  Navigator.pop(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.playlist_add),
                title: const Text('Ajouter à une playlist'),
                onTap: () {
                  Navigator.pop(context);
                  _showPlaylistPicker(context, song);
                },
              ),
              ListTile(
                leading: const Icon(Icons.ios_share_rounded),
                title: const Text('Partager'),
                subtitle: const Text('Lien d\'écoute valable 24 h'),
                onTap: () {
                  Navigator.pop(context);
                  showShareSheet(context, ShareTarget.song(song));
                },
              ),
              if (offlineSupported)
                Builder(builder: (context) {
                  final downloaded = ref
                          .watch(offlineProvider)
                          .value
                          ?.containsKey(song.id) ??
                      false;
                  return ListTile(
                    leading: Icon(
                      downloaded
                          ? Icons.download_done
                          : Icons.download_outlined,
                    ),
                    title: Text(
                      downloaded
                          ? 'Retirer le téléchargement'
                          : 'Télécharger',
                    ),
                    onTap: () async {
                      Navigator.pop(context);
                      final offline = ref.read(offlineProvider.notifier);
                      final messenger = ScaffoldMessenger.of(context);
                      try {
                        if (downloaded) {
                          await offline.remove(song.id);
                        } else {
                          await offline.download(song);
                          messenger.showSnackBar(
                            const SnackBar(content: Text('Titre téléchargé')),
                          );
                        }
                      } catch (_) {
                        messenger.showSnackBar(
                          const SnackBar(content: Text('Échec du téléchargement')),
                        );
                      }
                    },
                  );
                }),
              if (song.albumId != null)
                ListTile(
                  leading: const Icon(Icons.album_outlined),
                  title: const Text("Aller à l'album"),
                  onTap: () {
                    Navigator.pop(context);
                    context.push('/album/${song.albumId}');
                  },
                ),
              if (song.artistId != null)
                ListTile(
                  leading: const Icon(Icons.person_outline),
                  title: const Text("Aller à l'artiste"),
                  onTap: () {
                    Navigator.pop(context);
                    context.push('/artist/${song.artistId}');
                  },
                ),
              const Divider(height: 1),
              ListTile(
                leading: Icon(Icons.delete_outline,
                    color: Theme.of(context).colorScheme.error),
                title: Text(
                  'Supprimer définitivement',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
                onTap: () async {
                  final messenger = ScaffoldMessenger.of(context);
                  Navigator.pop(context);
                  final ok = await confirmDelete(
                    context,
                    'Supprimer « ${song.title} » ?',
                    'Le fichier et ses données seront effacés du serveur. '
                        'Action irréversible.',
                  );
                  if (ok != true) return;
                  try {
                    await ref
                        .read(libraryRepositoryProvider)
                        .deleteSongs([song.id]);
                    invalidateLibrary(ref);
                    messenger.showSnackBar(
                      SnackBar(content: Text('« ${song.title} » supprimé')),
                    );
                  } catch (e) {
                    messenger.showSnackBar(
                      SnackBar(content: Text('Échec : $e')),
                    );
                  }
                },
              ),
            ],
          ),
        );
      },
    ),
  );
}

/// Confirmation destructive réutilisable (rouge).
Future<bool?> confirmDelete(
  BuildContext context,
  String title,
  String message,
) =>
    showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );

/// Rafraîchit les listes après une suppression.
void invalidateLibrary(WidgetRef ref) {
  ref.invalidate(artistsProvider);
  ref.invalidate(albumsProvider);
  ref.invalidate(recentAlbumsProvider);
  ref.invalidate(popularSongsProvider);
  ref.invalidate(untaggedArtistsProvider);
  ref.invalidate(allFavoritesProvider);
  ref.invalidate(favoriteIdsProvider);
}

Future<void> _showPlaylistPicker(BuildContext context, Song song) {
  return showModalBottomSheet(
    context: context,
    useRootNavigator: true,
    builder: (context) => Consumer(
      builder: (context, ref, _) {
        final playlists = ref.watch(playlistsProvider);
        final actions = ref.read(playlistActionsProvider);

        Future<void> addTo(int playlistId) async {
          await actions.addSong(playlistId, song.id);
          if (context.mounted) {
            Navigator.pop(context);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Ajouté à la playlist')),
            );
          }
        }

        return SafeArea(
          child: playlists.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => Padding(
              padding: const EdgeInsets.all(32),
              child: Text('Erreur: $e'),
            ),
            data: (list) => ListView(
              shrinkWrap: true,
              children: [
                ListTile(
                  leading: const Icon(Icons.add),
                  title: const Text('Nouvelle playlist'),
                  onTap: () async {
                    final name = await promptPlaylistName(context);
                    if (name == null || name.isEmpty) return;
                    final id = await actions.create(name);
                    await addTo(id);
                  },
                ),
                for (final p in list)
                  ListTile(
                    leading: const Icon(Icons.queue_music),
                    title: Text(p.name),
                    subtitle: Text('${p.songCount} titre'
                        '${p.songCount > 1 ? 's' : ''}'),
                    onTap: () => addTo(p.id),
                  ),
              ],
            ),
          ),
        );
      },
    ),
  );
}

Future<String?> promptPlaylistName(
  BuildContext context, {
  String? initial,
}) async {
  final controller = TextEditingController(text: initial);
  final name = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(initial == null ? 'Nouvelle playlist' : 'Renommer'),
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: const InputDecoration(hintText: 'Nom de la playlist'),
        onSubmitted: (v) => Navigator.pop(context, v.trim()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, controller.text.trim()),
          child: const Text('OK'),
        ),
      ],
    ),
  );
  return (name == null || name.isEmpty) ? null : name;
}
