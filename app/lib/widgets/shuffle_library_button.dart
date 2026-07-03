import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/library.dart';
import '../state/player.dart';

/// Lance toute la bibliothèque en aléatoire (échantillon mélangé serveur).
class ShuffleLibraryButton extends ConsumerStatefulWidget {
  const ShuffleLibraryButton({super.key});

  @override
  ConsumerState<ShuffleLibraryButton> createState() =>
      _ShuffleLibraryButtonState();
}

class _ShuffleLibraryButtonState extends ConsumerState<ShuffleLibraryButton> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    return IconButton.filledTonal(
      tooltip: 'Toute la bibliothèque en aléatoire',
      icon: _busy
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.shuffle),
      onPressed: _busy
          ? null
          : () async {
              setState(() => _busy = true);
              final messenger = ScaffoldMessenger.of(context);
              try {
                final songs = await ref
                    .read(libraryRepositoryProvider)
                    .randomSongs();
                if (songs.isEmpty) return;
                await ref.read(playerActionsProvider).playSongs(songs);
              } catch (e) {
                messenger.showSnackBar(
                  SnackBar(content: Text('Erreur : $e')),
                );
              } finally {
                if (mounted) setState(() => _busy = false);
              }
            },
    );
  }
}
