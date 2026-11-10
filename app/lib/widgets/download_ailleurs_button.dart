import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../audio/audio_handler.dart';
import '../state/yt_downloads.dart';
import 'download_confirm.dart';

/// Ce qu'il faut pour télécharger le titre d'ailleurs que joue le lecteur
/// (YouTube Music ou Bandcamp, lancé de la recherche ou par la lecture
/// automatique), `null` pour un titre de la bibliothèque, une radio…
class AilleursDownload {
  const AilleursDownload({
    required this.key,
    required this.url,
    required this.album,
    required this.source,
  });

  /// `yt:<id>` ou `bc:<id>`.
  final String key;

  /// La page du titre, celle que le serveur télécharge.
  final String url;

  /// L'album où le ranger (« Singles » quand la source n'en nomme pas).
  final String album;

  /// « YouTube Music » ou « Bandcamp », pour la fenêtre de confirmation.
  final String source;

  static AilleursDownload? of(MediaItem item) {
    final extras = item.extras;
    final key = ailleursKeyOf(extras);
    if (key == null) return null;
    final String url;
    if (key.startsWith('yt:')) {
      url = 'https://music.youtube.com/watch?v=${key.substring(3)}';
    } else {
      final page = extras?['bcUrl'];
      if (page is! String || page.isEmpty) return null;
      url = page;
    }
    final album = extras?[kSourceAlbum];
    return AilleursDownload(
      key: key,
      url: url,
      album: album is String && album.trim().isNotEmpty ? album : 'Singles',
      source: key.startsWith('yt:') ? 'YouTube Music' : 'Bandcamp',
    );
  }
}

/// Les titres d'ailleurs dont on a lancé le téléchargement pendant la séance :
/// le bouton du lecteur le dit au lieu de le reproposer.
final ailleursTelechargesProvider =
    NotifierProvider<_AilleursTelecharges, Set<String>>(
      _AilleursTelecharges.new,
    );

class _AilleursTelecharges extends Notifier<Set<String>> {
  @override
  Set<String> build() => const {};

  void ajouter(String key) => state = {...state, key};
}

/// « Je l'aime, je le garde » : sur un titre qui n'est pas dans la
/// bibliothèque, le lecteur propose de le télécharger — même file, même
/// fenêtre de confirmation que la recherche. Invisible pour tout le reste.
class DownloadAilleursButton extends ConsumerWidget {
  const DownloadAilleursButton({super.key, required this.item});

  final MediaItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dl = AilleursDownload.of(item);
    if (dl == null) return const SizedBox.shrink();
    final lance = ref.watch(ailleursTelechargesProvider).contains(dl.key);
    return IconButton(
      icon: Icon(
        lance ? Icons.download_done_rounded : Icons.download_rounded,
        color: lance ? Theme.of(context).colorScheme.primary : null,
      ),
      tooltip: lance
          ? 'Téléchargement lancé'
          : 'Télécharger dans ma bibliothèque',
      onPressed: lance
          ? () => context.push('/yt-downloads')
          : () => _telecharger(context, ref, dl),
    );
  }

  Future<void> _telecharger(
    BuildContext context,
    WidgetRef ref,
    AilleursDownload dl,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final repo = ref.read(ytDownloadsRepositoryProvider);
    final artist = item.artist ?? '';
    final duplicate = await repo.checkDuplicate(
      artist: artist,
      album: dl.album,
      url: dl.url,
      title: item.title,
    );
    if (!context.mounted) return;
    final ok = await showDownloadConfirm(
      context,
      title: item.title,
      subtitle: artist,
      details: [if (dl.album != 'Singles') dl.album, dl.source].join(' · '),
      body: "Le serveur télécharge ce titre puis l'ajoute à la bibliothèque.",
      duplicate: duplicate,
    );
    if (!ok || !context.mounted) return;
    try {
      await repo.start(
        url: dl.url,
        artistName: artist,
        albumName: dl.album,
        title: item.title,
        force: duplicate != null,
      );
      ref.read(ailleursTelechargesProvider.notifier).ajouter(dl.key);
      ref.invalidate(ytQueueProvider);
      messenger.showSnackBar(
        SnackBar(
          content: Text('Téléchargement démarré : ${item.title}'),
          action: SnackBarAction(
            label: 'Suivre',
            onPressed: () {
              if (context.mounted) context.push('/yt-downloads');
            },
          ),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Échec du démarrage : $e')),
      );
    }
  }
}
