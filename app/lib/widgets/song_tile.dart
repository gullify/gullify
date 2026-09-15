import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/song.dart';
import '../state/player.dart';
import 'adaptive_layout.dart';
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
    this.showAlbum = true,
    this.albumInSubtitle = false,
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

  /// Colonne de l'album, sur grand écran. À couper là où tous les titres sont
  /// du même album (la page de l'album elle-même).
  final bool showAlbum;

  /// Au téléphone, ajoute l'album à la ligne secondaire (« Interprète ·
  /// Album ») — là où il n'est pas donné par le contexte, comme dans les
  /// résultats d'une recherche. Sur grand écran, il a de toute façon sa colonne.
  final bool albumInSubtitle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    // Interprète en préfixe du titre : inutile de le répéter en dessous.
    final artist = showArtist && !showTrackArtist ? song.artistName : null;
    final secondary =
        subtitle ??
        (albumInSubtitle
            ? [?artist, ?song.albumName].join(' · ').nullIfEmpty
            : artist);
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
            // Sur grand écran, une rangée de 1 600 px laissait un désert entre le
            // titre et sa durée. L'interprète et l'album y prennent chacun leur
            // colonne, comme dans la liste de titres d'un site de musique. Au
            // téléphone, rien ne change.
            child: LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= kWideLayoutBreakpoint;
                final artistColumn = wide && subtitle == null && artist != null;
                // Un sous-titre composé par l'appelant garde la main : lui ajouter
                // une colonne, c'était montrer l'album deux fois.
                final albumColumn =
                    wide &&
                    subtitle == null &&
                    showAlbum &&
                    song.albumName != null;
                // Sur grand écran, l'interprète et l'album ont leur colonne : la ligne
                // secondaire ne garde qu'un sous-titre imposé par l'appelant.
                final under = !wide
                    ? secondary
                    : subtitle ?? (artistColumn ? null : artist);
                final muted = TextStyle(
                  fontSize: 13.5,
                  color: scheme.onSurfaceVariant,
                );
                return Row(
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
                      flex: 5,
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
                          if (under != null)
                            Text(
                              under,
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
                    if (artistColumn) ...[
                      const SizedBox(width: 16),
                      Expanded(
                        flex: 3,
                        child: Text(
                          song.artistName!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: muted,
                        ),
                      ),
                    ],
                    if (albumColumn) ...[
                      const SizedBox(width: 16),
                      Expanded(
                        flex: 3,
                        child: Text(
                          song.albumName!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: muted,
                        ),
                      ),
                    ],
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
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

extension on String {
  String? get nullIfEmpty => isEmpty ? null : this;
}
