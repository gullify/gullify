import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../state/player.dart';
import '../theme.dart';
import 'artwork.dart';

class MiniPlayer extends ConsumerWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final item = ref.watch(currentMediaItemProvider).value;
    if (item == null) return const SizedBox.shrink();

    final playing = ref.watch(playbackStateProvider).value?.playing ?? false;
    final actions = ref.read(playerActionsProvider);
    final scheme = Theme.of(context).colorScheme;

    // Carte flottante, détachée de la barre de navigation. En thème
    // « verre » elle a son propre flou; sinon une surface pleine arrondie.
    final surfaces = Theme.of(context).extension<GullifySurfaces>();
    final frosted = surfaces?.frosted ?? false;

    Widget card = Material(
      color: frosted
          ? (surfaces?.barColor ?? Colors.transparent)
          : scheme.surfaceContainerHighest,
      // Swipe horizontal : gauche = suivant, droite = précédent.
      child: GestureDetector(
        onHorizontalDragEnd: (details) {
          final v = details.primaryVelocity ?? 0;
          if (v < -300) {
            actions.next();
          } else if (v > 300) {
            actions.previous();
          }
        },
        child: InkWell(
          onTap: () => context.push('/now-playing'),
          child: SizedBox(
              height: 64,
              child: Row(
                children: [
                  const SizedBox(width: 8),
                  Artwork(
                    url: item.artUri?.toString(),
                    size: 48,
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
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        if (item.artist != null)
                          Text(
                            item.artist!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.skip_previous),
                    onPressed: actions.previous,
                  ),
                  IconButton(
                    iconSize: 36,
                    icon: Icon(
                      playing
                          ? Icons.pause_circle_filled
                          : Icons.play_circle_fill,
                      color: scheme.primary,
                    ),
                    onPressed: actions.togglePlayPause,
                  ),
                  IconButton(
                    icon: const Icon(Icons.skip_next),
                    onPressed: actions.next,
                  ),
                  const SizedBox(width: 4),
                ],
              ),
            ),
        ),
      ),
    );

    card = ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: frosted
          ? BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0x26FFFFFF)),
                ),
                child: card,
              ),
            )
          : card,
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
      child: SafeArea(top: false, child: card),
    );
  }
}
