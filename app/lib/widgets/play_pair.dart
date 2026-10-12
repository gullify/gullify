import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/song.dart';
import '../state/player.dart';
import 'glass_kit.dart';

/// « Tout lire » et l'aléatoire, côte à côte, au-dessus d'une collection.
///
/// Partout le même geste : le gros bouton lance la collection dans l'ordre,
/// la plaque de verre la lance mélangée. [titres] n'est appelé qu'au moment
/// du tap — une collection dont on n'a pas la liste sous la main (un genre,
/// une année) n'a pas à la charger pour afficher ses deux boutons.
class PaireDeLecture extends ConsumerStatefulWidget {
  const PaireDeLecture({
    super.key,
    required this.titres,
    this.label = 'Tout lire',
    this.aleatoire = 'Lecture aléatoire',
    this.vide = 'Aucun titre à jouer',
  });

  /// La liste à jouer, chargée au tap. [shuffle] dit lequel des deux boutons
  /// a été pressé : à la collection de décider si le hasard se fait côté
  /// serveur (un vivier de genre) ou sur place.
  final Future<List<Song>> Function({required bool shuffle}) titres;

  final String label;
  final String aleatoire;

  /// Ce qu'on dit quand la collection ne rend aucun titre — mieux vaut le dire
  /// que de lancer le vide.
  final String vide;

  @override
  ConsumerState<PaireDeLecture> createState() => _PaireDeLectureState();
}

class _PaireDeLectureState extends ConsumerState<PaireDeLecture> {
  bool _busy = false;

  Future<void> _play({required bool shuffle}) async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final songs = await widget.titres(shuffle: shuffle);
      if (songs.isEmpty) {
        messenger.showSnackBar(SnackBar(content: Text(widget.vide)));
        return;
      }
      await ref.read(playerActionsProvider).playSongs(songs);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Erreur : $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: AccentPlayButton(
            label: _busy ? 'Chargement…' : widget.label,
            onPressed: _busy ? null : () => _play(shuffle: false),
          ),
        ),
        const SizedBox(width: 12),
        GlassIconButton(
          icon: Icons.shuffle,
          tooltip: widget.aleatoire,
          size: 50,
          onPressed: _busy ? null : () => _play(shuffle: true),
        ),
      ],
    );
  }
}
