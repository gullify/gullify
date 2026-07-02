import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/song.dart';
import '../state/favorites.dart';
import '../state/offline.dart';
import '../state/playlists.dart';
import 'artwork.dart';

/// Bottom sheet with actions for a song (favorite, playlists, navigation).
Future<void> showSongMenu(BuildContext context, Song song) {
  return showModalBottomSheet(
    context: context,
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
                leading: const Icon(Icons.playlist_add),
                title: const Text('Ajouter à une playlist'),
                onTap: () {
                  Navigator.pop(context);
                  _showPlaylistPicker(context, song);
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
            ],
          ),
        );
      },
    ),
  );
}

Future<void> _showPlaylistPicker(BuildContext context, Song song) {
  return showModalBottomSheet(
    context: context,
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
