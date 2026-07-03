import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../state/player.dart';
import 'artwork.dart';
import 'glass_box.dart';

/// Mini-lecteur flottant, style Liquid Glass Player : carte de verre avec
/// barre de progression fine sur le bord supérieur, bouton lecture rond
/// plein en couleur accent. Swipe horizontal = piste suivante/précédente.
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

    final total = item.duration?.inMilliseconds ?? 0;
    final progress = total > 0
        ? (position.inMilliseconds / total).clamp(0.0, 1.0)
        : 0.0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 9),
      child: SafeArea(
        top: false,
        child: GestureDetector(
          onHorizontalDragEnd: (details) {
            final v = details.primaryVelocity ?? 0;
            if (v < -300) {
              actions.next();
            } else if (v > 300) {
              actions.previous();
            }
          },
          child: GlassBox(
            radius: 20,
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
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      item.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
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
