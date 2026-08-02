import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/song.dart';
import '../state/player.dart';
import 'artwork.dart';
import 'glass_kit.dart';
import 'song_menu.dart';

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
    this.showTrackArtist = false,
    this.showArtist = true,
  });

  final Song song;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final bool showArtwork;
  final int? leadingNumber;
  final bool isPlaying;
  final String? subtitle;
  final Widget? trailing;

  /// Préfixe le titre par l'interprète (« Artiste — Titre ») : utile pour
  /// les compilations Various Artists où chaque piste a un artiste différent.
  final bool showTrackArtist;

  /// Ligne secondaire avec l'interprète. À couper là où il est déjà donné
  /// par le contexte (page album : l'entête l'affiche déjà).
  final bool showArtist;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    // Interprète en préfixe du titre : inutile de le répéter en dessous.
    final secondary =
        subtitle ?? (showArtist && !showTrackArtist ? song.artistName : null);
    // Détecte la piste en cours même si l'appelant ne le précise pas.
    final currentId =
        ref.watch(currentMediaItemProvider).value?.extras?['songId'] as int?;
    final isCurrent = isPlaying || currentId == song.id;
    final playing =
        isCurrent && (ref.watch(playbackStateProvider).value?.playing ?? false);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        // Menu par défaut sur appui long : chaque titre, partout, offre les
        // mêmes actions (favori, playlist, file, téléchargement, navigation).
        onLongPress: onLongPress ?? () => showSongMenu(context, song),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            // Sélection : la piste en cours reçoit un fond accent doux.
            color: isCurrent
                ? scheme.primary.withValues(alpha: 0.10)
                : Colors.transparent,
            // Séparateur discret entre les rangées (sauf la piste courante).
            border: Border(
              bottom: BorderSide(
                color: isCurrent
                    ? Colors.transparent
                    : scheme.outlineVariant.withValues(alpha: 0.5),
                width: 0.7,
              ),
            ),
          ),
          child: Padding(
            // Espacement confortable au doigt, uniforme dans toutes les
            // listes (accueil, bibliothèque, album…).
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
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
                        showTrackArtist && song.artistName != null
                            ? '${song.artistName} — ${song.title}'
                            : song.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                          color: isCurrent ? scheme.primary : null,
                        ),
                      ),
                      if (secondary != null)
                        Text(
                          secondary,
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
      ),
    );
  }
}
