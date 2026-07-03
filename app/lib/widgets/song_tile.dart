import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/song.dart';
import '../state/player.dart';
import 'artwork.dart';
import 'glass_kit.dart';

String formatDuration(int seconds) {
  final m = seconds ~/ 60;
  final s = seconds % 60;
  return '$m:${s.toString().padLeft(2, '0')}';
}

/// Rangée de chanson, style Liquid Glass Player : titre gras, pochette
/// arrondie, durée tabulaire; barres d'égaliseur animées sur la piste
/// en cours (sur la pochette, ou à la place du numéro).
class SongTile extends ConsumerWidget {
  const SongTile({
    super.key,
    required this.song,
    required this.onTap,
    this.onLongPress,
    this.showArtwork = true,
    this.leadingNumber,
    this.isPlaying = false,
    this.subtitle,
    this.trailing,
  });

  final Song song;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final bool showArtwork;
  final int? leadingNumber;
  final bool isPlaying;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    // Détecte la piste en cours même si l'appelant ne le précise pas.
    final currentId = ref
        .watch(currentMediaItemProvider)
        .value
        ?.extras?['songId'] as int?;
    final isCurrent = isPlaying || currentId == song.id;
    final playing = isCurrent &&
        (ref.watch(playbackStateProvider).value?.playing ?? false);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
          child: Row(
            children: [
              if (showArtwork)
                Stack(
                  children: [
                    Artwork(
                      url: song.artworkUrl,
                      size: 46,
                      borderRadius: 12,
                      icon: Icons.music_note,
                    ),
                    if (isCurrent)
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.35),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Center(
                            child: EqBars(
                              color: Colors.white,
                              playing: playing,
                            ),
                          ),
                        ),
                      ),
                  ],
                )
              else
                SizedBox(
                  width: 28,
                  child: Center(
                    child: isCurrent
                        ? EqBars(playing: playing)
                        : Text(
                            '${leadingNumber ?? ''}',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                  ),
                ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      song.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        color: isCurrent ? scheme.primary : null,
                      ),
                    ),
                    if ((subtitle ?? song.artistName) != null)
                      Text(
                        subtitle ?? song.artistName!,
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
              const SizedBox(width: 8),
              trailing ??
                  Text(
                    formatDuration(song.duration),
                    style: TextStyle(
                      fontSize: 12.5,
                      color: scheme.outline,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
            ],
          ),
        ),
      ),
    );
  }
}
