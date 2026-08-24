import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/yt_downloads_repository.dart';
import '../../state/yt_downloads.dart';
import 'tv_kit.dart';

/// Confirmation avant de lancer un téléchargement depuis YouTube.
///
/// Le téléphone ouvre une feuille glissante ; ici c'est un panneau plein
/// écran, dont les deux boutons se visent à la croix. Le serveur est
/// interrogé d'abord : s'il a déjà ce disque — ou s'il est en train de le
/// prendre — on le dit avant, plutôt que de le laisser retélécharger.
class TvDownloadConfirm extends StatelessWidget {
  const TvDownloadConfirm({
    super.key,
    required this.title,
    required this.subtitle,
    required this.details,
    required this.onConfirm,
    required this.onCancel,
    this.duplicate,
    this.busy = false,
    this.error,
  });

  final String title;
  final String subtitle;
  final String details;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;
  final YtDuplicate? duplicate;
  final bool busy;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dup = duplicate;

    return SizedBox.expand(
      child: ColoredBox(
        color: const Color(0xD9070810),
        child: Center(
          child: SizedBox(
            width: 760,
            child: FocusScope(
              autofocus: true,
              child: TvGlass(
                padding: const EdgeInsets.fromLTRB(44, 38, 44, 34),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'TÉLÉCHARGER',
                      style: TextStyle(
                        fontSize: tvMinText,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 2.8,
                        color: scheme.primary,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 40,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -1,
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      [
                        subtitle,
                        details,
                      ].where((s) => s.isNotEmpty).join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 24,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 22),
                    Text(
                      'Le serveur le télécharge, puis l\'ajoute à ta '
                      'bibliothèque. Tu peux continuer à te servir de '
                      'Gullify pendant ce temps.',
                      style: TextStyle(
                        fontSize: 23,
                        height: 1.4,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    if (dup != null) ...[
                      const SizedBox(height: 18),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 14,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(
                            0xFFE3A94F,
                          ).withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: const Color(
                              0xFFE3A94F,
                            ).withValues(alpha: 0.5),
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.warning_amber_rounded,
                              color: Color(0xFFE3A94F),
                              size: 28,
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Text(
                                dup.message,
                                style: const TextStyle(
                                  fontSize: 22,
                                  height: 1.35,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    if (error != null) ...[
                      const SizedBox(height: 16),
                      Text(
                        error!,
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: scheme.error,
                        ),
                      ),
                    ],
                    const SizedBox(height: 28),
                    Wrap(
                      spacing: 16,
                      runSpacing: 12,
                      children: [
                        TvPill(
                          label: busy
                              ? 'Mise en file…'
                              : (dup != null
                                    ? 'Télécharger quand même'
                                    : 'Télécharger'),
                          icon: Icons.download_rounded,
                          autofocus: true,
                          compact: true,
                          onPressed: busy ? null : onConfirm,
                        ),
                        TvPill(
                          label: 'Annuler',
                          accent: false,
                          compact: true,
                          onPressed: busy ? null : onCancel,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Ce qu'on s'apprête à télécharger : un album, ou une chanson seule.
sealed class TvDownloadTarget {
  const TvDownloadTarget();
}

class TvAlbumTarget extends TvDownloadTarget {
  const TvAlbumTarget(this.album);

  final YtAlbum album;
}

class TvSongTarget extends TvDownloadTarget {
  const TvSongTarget(this.song);

  final YtSong song;
}

/// Nom d'album retenu pour une chanson seule : elles atterrissent toutes
/// dans « Singles », côté serveur comme dans la bibliothèque.
String tvSongAlbum(YtSong song) => song.album.isEmpty ? 'Singles' : song.album;

/// Lance le téléchargement et rend l'éventuelle erreur, en clair.
Future<String?> tvStartDownload(
  WidgetRef ref,
  TvDownloadTarget target, {
  required bool force,
}) async {
  try {
    switch (target) {
      case TvAlbumTarget(:final album):
        final resolved = await ref
            .read(ytDownloadsRepositoryProvider)
            .resolveAlbum(album.browseId);
        await ref.read(ytQueueProvider.notifier).start(resolved, force: force);
      case TvSongTarget(:final song):
        await ref
            .read(ytDownloadsRepositoryProvider)
            .start(
              url: song.watchUrl,
              artistName: song.artist,
              albumName: tvSongAlbum(song),
              title: song.title,
              force: force,
            );
        ref.invalidate(ytQueueProvider);
    }
    return null;
  } catch (e) {
    return 'Échec du démarrage : $e';
  }
}
