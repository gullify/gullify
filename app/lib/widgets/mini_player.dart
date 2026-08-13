import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../state/player.dart';
import 'artwork.dart';
import 'glass_box.dart';
import 'retro_lcd.dart';

/// Mini-lecteur flottant, style Liquid Glass Player : carte de verre avec
/// barre de progression fine sur le bord supérieur, bouton lecture rond
/// plein en couleur accent.
///
/// Gestes : horizontal = piste suivante/précédente ; vers le haut = ouvre le
/// lecteur complet ; vers le bas = ferme le lecteur (idée #66). La fermeture
/// coupe le son et fait disparaître la carte, mais reste annulable quelques
/// secondes — un balayage se déclenche parfois sans qu'on l'ait voulu.
///
/// Pas de SafeArea ici : dans le shell, la barre d'onglets en dessous
/// applique déjà l'inset gestuel (le doubler faisait flotter le
/// mini-lecteur trop haut). Les écrans de détail qui l'affichent seul en
/// bottomNavigationBar l'enveloppent : SafeArea(top: false, child: …).
/// Ferme le lecteur, puis laisse quelques secondes pour se raviser : la file
/// rouvre alors à la piste et à la seconde où elle s'était arrêtée.
Future<void> _close(BuildContext context, WidgetRef ref) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final actions = ref.read(playerActionsProvider);
  final closed = await actions.dismiss();
  if (closed.queue.isEmpty) return;
  messenger
    ?..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: const Text('Lecteur fermé'),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 6),
        action: SnackBarAction(
          label: 'Annuler',
          onPressed: () => actions.restoreQueue(
            closed.queue,
            index: closed.index,
            position: closed.position,
          ),
        ),
      ),
    );
}

class MiniPlayer extends ConsumerWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final item = ref.watch(currentMediaItemProvider).value;
    if (item == null) return const SizedBox.shrink();

    final playing = ref.watch(playbackStateProvider).value?.playing ?? false;
    final position = ref.watch(positionProvider).value ?? Duration.zero;
    final actions = ref.read(playerActionsProvider);
    final scheme = Theme.of(context).colorScheme;
    final retro = isRetroSkin(context);

    final total = item.duration?.inMilliseconds ?? 0;
    final progress = total > 0
        ? (position.inMilliseconds / total).clamp(0.0, 1.0)
        : 0.0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
      child: GestureDetector(
        onHorizontalDragEnd: (details) {
          final v = details.primaryVelocity ?? 0;
          if (v < -300) {
            actions.next();
          } else if (v > 300) {
            actions.previous();
          }
        },
        onVerticalDragEnd: (details) {
          final v = details.primaryVelocity ?? 0;
          // Seuil plus haut vers le bas que vers le haut : ouvrir ne coûte
          // rien, fermer coupe la musique.
          if (v < -300) {
            context.push('/now-playing');
          } else if (v > 500) {
            _close(context, ref);
          }
        },
        child: GlassBox(
          radius: 20,
          // Pas de flou : c'est ce filtre qui, sur certains GPU, se
          // peignait en plein écran sur les pages artiste/album.
          blur: false,
          child: SizedBox(
            height: 62,
            child: Stack(
              children: [
                // Progression : filet accent sur le bord supérieur.
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: progress,
                    child: Container(
                      height: 3,
                      decoration: BoxDecoration(
                        color: scheme.primary,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Row(
                    children: [
                      Expanded(
                        child: InkWell(
                          borderRadius: BorderRadius.circular(13),
                          onTap: () => context.push('/now-playing'),
                          child: Row(
                            children: [
                              Artwork(
                                url: item.artUri?.toString(),
                                size: 46,
                                borderRadius: 13,
                                icon: Icons.music_note,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  // min obligatoire : en bottomNavigationBar
                                  // (contrainte bornée), max étendait la
                                  // Column — et le mini-lecteur — à tout
                                  // l'écran (bug « lecteur plein écran »).
                                  mainAxisSize: MainAxisSize.min,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      item.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      // Rétro Winamp (idée #82) : le titre
                                      // passe en chasse fixe verte, comme sur
                                      // l'afficheur du lecteur complet.
                                      style: retro
                                          ? lcdTextStyle(size: 13.5)
                                          : const TextStyle(
                                              fontWeight: FontWeight.w700,
                                              fontSize: 14.5,
                                            ),
                                    ),
                                    if (item.artist != null)
                                      Text(
                                        item.artist!,
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
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Lecture/pause : rond plein accent, signature du style.
                      SizedBox(
                        width: 44,
                        height: 44,
                        child: IconButton.filled(
                          style: IconButton.styleFrom(
                            backgroundColor: scheme.primary,
                            foregroundColor: scheme.onPrimary,
                            shape: retro
                                ? RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(3),
                                  )
                                : null,
                          ),
                          icon: Icon(playing ? Icons.pause : Icons.play_arrow),
                          onPressed: actions.togglePlayPause,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.skip_next),
                        iconSize: 28,
                        onPressed: actions.next,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
