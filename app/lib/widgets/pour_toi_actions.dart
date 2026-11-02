import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/song.dart';
import '../state/player.dart';
import '../state/pour_toi.dart';

/// Un titre de la bibliothèque du serveur (ni maison amie, ni dossier local) :
/// le seul qui ait une radio et qu'on puisse écarter.
bool pourToiPossible(Song song) => song.id > 0 && song.streamUrl == null;

/// « Radio de ce titre » : le titre, puis vingt-cinq titres qui lui
/// ressemblent ; la lecture automatique prend ensuite le relais, sans fin.
Future<void> startSongRadio(
  ScaffoldMessengerState messenger,
  WidgetRef ref,
  Song song,
) async {
  messenger.showSnackBar(
    SnackBar(
      content: Text('Radio de « ${song.title} »…'),
      duration: const Duration(seconds: 2),
    ),
  );
  try {
    final recos = await ref.read(pourToiRepositoryProvider).radio(song.id);
    if (recos.length <= 1) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Pas assez de titres proches pour une radio.'),
        ),
      );
      return;
    }
    await ref.read(playerActionsProvider).playRecos(recos);
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('Radio impossible : $e')));
  }
}

/// « Pas pour moi » : le titre (ou son artiste) ne revient plus dans les
/// mix, les découvertes ni la lecture automatique. Annulable tout de suite, et
/// plus tard depuis « Tes goûts ».
Future<void> rejectFromRecos(
  ScaffoldMessengerState messenger,
  WidgetRef ref, {
  required String type,
  required int id,
  required String label,
}) async {
  final repo = ref.read(pourToiRepositoryProvider);
  try {
    await repo.rejeter(type, id);
    ref.invalidate(pourToiAccueilProvider);
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          type == 'artist'
              ? '$label ne te sera plus proposé.'
              : '« $label » ne te sera plus proposé.',
        ),
        action: SnackBarAction(
          label: 'Annuler',
          onPressed: () async {
            await repo.retablir(type, id);
            ref.invalidate(pourToiAccueilProvider);
          },
        ),
      ),
    );
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('Échec : $e')));
  }
}
