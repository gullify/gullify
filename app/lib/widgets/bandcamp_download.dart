import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../api/bandcamp_repository.dart';
import '../state/bandcamp.dart';
import '../state/yt_downloads.dart';
import 'download_confirm.dart';

/// Télécharge un album (ou un titre publié seul) Bandcamp dans la
/// bibliothèque : la sortie est d'abord résolue — la recherche n'en donne ni
/// l'année ni le nombre de pistes, et la discographie d'un artiste pas même le
/// lien —, le doublon vérifié, puis la confirmation demandée.
///
/// Partagé par la recherche (idée #110) et par « Découvrir sur Bandcamp »
/// (idée #111).
Future<void> downloadBandcampRelease(
  BuildContext context,
  WidgetRef ref,
  BcRelease release,
) async {
  final messenger = ScaffoldMessenger.of(context);
  // Le dialogue vit sur le navigateur RACINE : c'est lui qu'il faut refermer,
  // pas celui de l'onglet.
  final rootNavigator = Navigator.of(context, rootNavigator: true);
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const Center(child: CircularProgressIndicator()),
  );
  BcResolved resolved;
  try {
    resolved = await ref.read(bandcampRepositoryProvider).resolve(
          bandId: release.bandId,
          itemId: release.itemId,
          itemType: release.itemType,
          url: release.url,
        );
  } catch (e) {
    if (context.mounted) rootNavigator.pop();
    messenger.showSnackBar(
      SnackBar(content: Text("Impossible de lire cette sortie : $e")),
    );
    return;
  }
  // Un titre seul se juge sur son titre, un album sur son nom.
  final duplicate = await ref
      .read(ytDownloadsRepositoryProvider)
      .checkDuplicate(
        artist: resolved.artist,
        album: resolved.albumName,
        url: resolved.url,
        title: resolved.isTrack ? resolved.title : '',
      );
  if (!context.mounted) return;
  rootNavigator.pop();

  final ok = await showDownloadConfirm(
    context,
    title: resolved.title,
    subtitle: resolved.artist,
    details: [
      if (resolved.year.isNotEmpty) resolved.year,
      if (!resolved.isTrack)
        '${resolved.trackCount} piste'
            '${resolved.trackCount > 1 ? 's' : ''}',
      'Bandcamp',
    ].join(' · '),
    body: resolved.isTrack
        ? "Le serveur télécharge ce titre puis l'ajoute à la bibliothèque."
        : "Le serveur télécharge cet album puis l'ajoute "
            'à la bibliothèque.',
    duplicate: duplicate,
  );
  if (!ok || !context.mounted) return;

  try {
    await ref.read(ytDownloadsRepositoryProvider).start(
          url: resolved.url,
          artistName: resolved.artist,
          albumName: resolved.albumName,
          title: resolved.isTrack ? resolved.title : '',
          force: duplicate != null,
        );
    ref.invalidate(ytQueueProvider);
    messenger.showSnackBar(
      SnackBar(
        content: Text('Téléchargement démarré : ${resolved.title}'),
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
