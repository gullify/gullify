import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/favorites.dart';
import '../state/player.dart';
import 'artwork.dart';
import 'glass_box.dart';
import 'song_tile.dart' show formatDuration;

/// La barre de lecture d'une tablette ou d'un grand écran : en bas de la
/// fenêtre, sur toute sa largeur, sous la navigation et le contenu.
///
/// C'est le mini-lecteur du téléphone, qui a enfin la place de tout montrer :
/// à gauche le titre en cours, au centre les commandes et la progression qu'on
/// fait glisser, à droite le favori et l'accès au lecteur complet. Sur un
/// grand écran on lance, on saute et on se place dans un titre sans ouvrir
/// quoi que ce soit.
///
/// Elle reste là quand le lecteur est ouvert : les commandes ne changent
/// jamais de place. Le lecteur ouvert, lui, montre la pochette et ce qui suit
/// (voir `NowPlayingScreen`).
///
/// Elle vit au-dessus du navigateur (voir `main.dart`) : ni infobulle ni feuille
/// ne peuvent s'y ouvrir. Ce qui demande un écran — paroles, file — passe par
/// le lecteur, via [onToggleExpanded].
class PlayerBar extends ConsumerWidget {
  const PlayerBar({
    super.key,
    required this.onToggleExpanded,
    this.expanded = false,
  });

  /// Ouvre le lecteur, ou le réduit s'il est déjà ouvert.
  final VoidCallback onToggleExpanded;

  /// Le lecteur est-il ouvert ?
  final bool expanded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final item = ref.watch(currentMediaItemProvider).value;
    // Rien en lecture : pas de barre vide qui mange la fenêtre.
    if (item == null) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;
    final state = ref.watch(playbackStateProvider).value;
    final playing = state?.playing ?? false;
    final actions = ref.read(playerActionsProvider);

    return Material(
      type: MaterialType.transparency,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: GlassBox(
            radius: 22,
            // Hors du shell : ni flou en direct (voir GlassBox — certains GPU
            // le peignent en plein écran), ni ombre, qui n'a nulle part où
            // tomber au bord de la fenêtre.
            blur: false,
            shadow: false,
            child: SizedBox(
              height: 84,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: _NowPlaying(item: item, onOpen: onToggleExpanded),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      flex: 4,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              _BarButton(
                                icon: Icons.shuffle_rounded,
                                label: 'Aléatoire',
                                active:
                                    state?.shuffleMode ==
                                    AudioServiceShuffleMode.all,
                                onPressed: actions.toggleShuffle,
                              ),
                              _BarButton(
                                icon: Icons.skip_previous_rounded,
                                label: 'Précédent',
                                size: 28,
                                onPressed: actions.previous,
                              ),
                              const SizedBox(width: 6),
                              Semantics(
                                button: true,
                                label: playing ? 'Pause' : 'Lecture',
                                child: IconButton.filled(
                                  onPressed: actions.togglePlayPause,
                                  style: IconButton.styleFrom(
                                    backgroundColor: scheme.primary,
                                    foregroundColor: Colors.white,
                                    fixedSize: const Size(42, 42),
                                  ),
                                  icon: Icon(
                                    playing
                                        ? Icons.pause_rounded
                                        : Icons.play_arrow_rounded,
                                    size: 26,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              _BarButton(
                                icon: Icons.skip_next_rounded,
                                label: 'Suivant',
                                size: 28,
                                onPressed: actions.next,
                              ),
                              _BarButton(
                                icon:
                                    state?.repeatMode ==
                                        AudioServiceRepeatMode.one
                                    ? Icons.repeat_one_rounded
                                    : Icons.repeat_rounded,
                                label: 'Répéter',
                                active:
                                    (state?.repeatMode ??
                                        AudioServiceRepeatMode.none) !=
                                    AudioServiceRepeatMode.none,
                                onPressed: actions.cycleRepeat,
                              ),
                            ],
                          ),
                          _Progress(item: item),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      flex: 3,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          _Favorite(item: item),
                          _BarButton(
                            icon: expanded
                                ? Icons.close_fullscreen_rounded
                                : Icons.open_in_full_rounded,
                            label: expanded
                                ? 'Réduire le lecteur'
                                : 'Ouvrir le lecteur',
                            active: expanded,
                            onPressed: onToggleExpanded,
                          ),
                        ],
                      ),
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

class _NowPlaying extends StatelessWidget {
  const _NowPlaying({required this.item, required this.onOpen});

  final MediaItem item;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onOpen,
        child: Row(
          children: [
            Artwork(
              url: item.artUri?.toString(),
              size: 56,
              borderRadius: 12,
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
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
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
    );
  }
}

/// La progression, qu'on fait glisser pour se placer dans le titre. Une radio
/// en direct n'a pas de durée : elle le dit, sans barre.
class _Progress extends ConsumerWidget {
  const _Progress({required this.item});

  final MediaItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final total = item.duration ?? Duration.zero;
    final muted = TextStyle(
      fontSize: 11.5,
      color: scheme.onSurfaceVariant,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    if (total == Duration.zero) {
      return Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text('EN DIRECT', style: muted.copyWith(letterSpacing: 1)),
      );
    }

    final position = ref.watch(positionProvider).value ?? Duration.zero;
    final value = (position.inMilliseconds / total.inMilliseconds).clamp(
      0.0,
      1.0,
    );

    return Row(
      children: [
        SizedBox(
          width: 52,
          child: Text(
            formatDuration(position.inSeconds),
            textAlign: TextAlign.right,
            maxLines: 1,
            softWrap: false,
            style: muted,
          ),
        ),
        Expanded(
          child: _SeekBar(
            value: value,
            onSeek: (v) => ref
                .read(playerActionsProvider)
                .seek(
                  Duration(milliseconds: (v * total.inMilliseconds).round()),
                ),
          ),
        ),
        SizedBox(
          width: 52,
          child: Text(
            formatDuration(total.inSeconds),
            maxLines: 1,
            softWrap: false,
            style: muted,
          ),
        ),
      ],
    );
  }
}

class _Favorite extends ConsumerWidget {
  const _Favorite({required this.item});

  final MediaItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final songId = item.extras?['songId'] as int?;
    // Une radio, un extrait : rien à mettre en favori.
    if (songId == null) return const SizedBox.shrink();
    final liked =
        ref.watch(favoriteIdsProvider).value?.contains(songId) ?? false;
    return _BarButton(
      icon: liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
      label: liked ? 'Retirer des favoris' : 'Ajouter aux favoris',
      active: liked,
      onPressed: () => ref.read(favoriteIdsProvider.notifier).toggle(songId),
    );
  }
}

/// Un bouton de la barre. Sans infobulle — il n'y a pas d'`Overlay` à cet
/// étage — mais avec son nom pour les lecteurs d'écran.
class _BarButton extends StatelessWidget {
  const _BarButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.active = false,
    this.size = 22,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final bool active;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: IconButton(
        onPressed: onPressed,
        icon: Icon(icon, size: size),
        color: active ? scheme.primary : scheme.onSurfaceVariant,
      ),
    );
  }
}

/// La progression, qu'on clique ou fait glisser pour se placer dans le titre.
///
/// Pas un `Slider` : le sien construit un `OverlayPortal` pour sa bulle de
/// valeur, qui exige un `Overlay` au-dessus de lui. La barre de lecture vit
/// au-dessus du navigateur, où il n'y en a pas — et en production Flutter
/// remplaçait le curseur par un rectangle gris.
class _SeekBar extends StatefulWidget {
  const _SeekBar({required this.value, required this.onSeek});

  /// Position, entre 0 et 1.
  final double value;
  final ValueChanged<double> onSeek;

  @override
  State<_SeekBar> createState() => _SeekBarState();
}

class _SeekBarState extends State<_SeekBar> {
  /// Pendant un glissement, la position suit la souris sans attendre le
  /// lecteur : on ne cherche dans le titre qu'au lâcher.
  double? _drag;
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        double at(double dx) => width <= 0 ? 0 : (dx / width).clamp(0.0, 1.0);
        final value = (_drag ?? widget.value).clamp(0.0, 1.0);
        final active = _hover || _drag != null;

        return Semantics(
          label: 'Progression dans le titre',
          slider: true,
          value: '${(value * 100).round()} %',
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            onEnter: (_) => setState(() => _hover = true),
            onExit: (_) => setState(() => _hover = false),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: (d) => widget.onSeek(at(d.localPosition.dx)),
              onHorizontalDragStart: (d) =>
                  setState(() => _drag = at(d.localPosition.dx)),
              onHorizontalDragUpdate: (d) =>
                  setState(() => _drag = at(d.localPosition.dx)),
              onHorizontalDragEnd: (_) {
                final target = _drag;
                setState(() => _drag = null);
                if (target != null) widget.onSeek(target);
              },
              child: SizedBox(
                height: 22,
                child: CustomPaint(
                  painter: _SeekPainter(
                    value: value,
                    track: scheme.outlineVariant,
                    fill: scheme.primary,
                    // Le bouton ne grossit qu'au survol : au repos, la barre
                    // reste une ligne discrète.
                    thumbRadius: active ? 6 : 4,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SeekPainter extends CustomPainter {
  const _SeekPainter({
    required this.value,
    required this.track,
    required this.fill,
    required this.thumbRadius,
  });

  final double value;
  final Color track;
  final Color fill;
  final double thumbRadius;

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height / 2;
    final paint = Paint()
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    final x = size.width * value;
    canvas.drawLine(Offset(0, y), Offset(size.width, y), paint..color = track);
    canvas.drawLine(Offset(0, y), Offset(x, y), paint..color = fill);
    canvas.drawCircle(Offset(x, y), thumbRadius, Paint()..color = fill);
  }

  @override
  bool shouldRepaint(_SeekPainter old) =>
      old.value != value ||
      old.track != track ||
      old.fill != fill ||
      old.thumbRadius != thumbRadius;
}
