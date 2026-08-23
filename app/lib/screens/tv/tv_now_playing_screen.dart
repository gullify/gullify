import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/library.dart';
import '../../state/player.dart';
import 'tv_kit.dart';

/// L'écran de lecture, plein cadre.
///
/// C'est ici que le verre translucide prend enfin son sens : sur un téléphone
/// la surface est trop petite pour qu'on voie le flou, sur un téléviseur la
/// pochette floutée occupe le salon. Le panneau de commandes flotte dessus.
class TvNowPlayingScreen extends ConsumerStatefulWidget {
  const TvNowPlayingScreen({super.key});

  @override
  ConsumerState<TvNowPlayingScreen> createState() => _TvNowPlayingScreenState();
}

class _TvNowPlayingScreenState extends ConsumerState<TvNowPlayingScreen> {
  /// Chemin du morceau dont on lit les paroles (nul = panneau fermé).
  String? _lyricsFor;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final item = ref.watch(currentMediaItemProvider).value;
    final playback = ref.watch(playbackStateProvider).value;
    final queue = ref.watch(queueProvider).value ?? const <MediaItem>[];
    final playing = playback?.playing ?? false;

    if (item == null) {
      return const TvScaffold(
        child: TvEmpty(
          message: 'Rien en lecture',
          hint: 'Choisis un album, une radio ou un titre pour commencer.',
          icon: Icons.play_circle_outline_rounded,
        ),
      );
    }

    final art = item.artUri?.toString();
    final index = queue.indexWhere((q) => q.id == item.id);
    final upNext = index >= 0 && index + 1 < queue.length
        ? queue.sublist(index + 1).take(6).toList()
        : const <MediaItem>[];

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Le fond, c'est la pochette : floutée, saturée, voilée.
          if (art != null) _Backdrop(url: art) else const SizedBox.shrink(),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [
                    scheme.surface.withValues(alpha: 0.94),
                    scheme.surface.withValues(alpha: 0.72),
                    scheme.surface.withValues(alpha: 0.9),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              tvSafeH,
              tvSafeV + 22,
              tvSafeH,
              tvSafeV,
            ),
            child: Column(
              children: [
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      TvArtwork(url: art, size: 440, borderRadius: 32),
                      const SizedBox(width: 70),
                      Expanded(
                        child: _Details(
                          item: item,
                          playing: playing,
                          hasQueue: queue.length > 1,
                          onLyrics: () => setState(
                            () => _lyricsFor =
                                item.extras?['filePath'] as String?,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (upNext.isNotEmpty)
                  _UpNext(items: upNext, total: queue.length - index - 1),
              ],
            ),
          ),
          if (_lyricsFor != null)
            _LyricsPanel(
              filePath: _lyricsFor!,
              onClose: () => setState(() => _lyricsFor = null),
            ),
        ],
      ),
    );
  }
}

/// Les paroles, plein écran.
///
/// Pas une feuille glissante comme sur téléphone : on ne fait pas glisser une
/// télécommande. Le panneau prend l'écran, se fait défiler avec haut et bas,
/// et se referme avec « Retour » ou son bouton.
class _LyricsPanel extends ConsumerStatefulWidget {
  const _LyricsPanel({required this.filePath, required this.onClose});

  final String filePath;
  final VoidCallback onClose;

  @override
  ConsumerState<_LyricsPanel> createState() => _LyricsPanelState();
}

class _LyricsPanelState extends ConsumerState<_LyricsPanel> {
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _scrollBy(double delta) {
    if (!_scroll.hasClients) return;
    _scroll.animateTo(
      (_scroll.offset + delta).clamp(0.0, _scroll.position.maxScrollExtent),
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final lyrics = ref.watch(lyricsProvider(widget.filePath));

    return Positioned.fill(
      child: ColoredBox(
        color: const Color(0xF0070810),
        child: FocusScope(
          autofocus: true,
          child: Focus(
            onKeyEvent: (node, event) {
              if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
                return KeyEventResult.ignored;
              }
              if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
                _scrollBy(140);
                return KeyEventResult.handled;
              }
              if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
                _scrollBy(-140);
                return KeyEventResult.handled;
              }
              return KeyEventResult.ignored;
            },
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                tvSafeH,
                tvSafeV,
                tvSafeH,
                tvSafeV,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.lyrics_outlined,
                        size: 32,
                        color: scheme.primary,
                      ),
                      const SizedBox(width: 14),
                      const Expanded(child: TvTitle('Paroles', size: 40)),
                      TvPill(
                        label: 'Fermer',
                        icon: Icons.close_rounded,
                        accent: false,
                        compact: true,
                        autofocus: true,
                        onPressed: widget.onClose,
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Expanded(
                    child: lyrics.when(
                      loading: () =>
                          const Center(child: CircularProgressIndicator()),
                      error: (e, _) => TvEmpty(
                        message: 'Paroles introuvables',
                        hint: '$e',
                        icon: Icons.lyrics_outlined,
                      ),
                      data: (text) => (text == null || text.trim().isEmpty)
                          ? const TvEmpty(
                              message: 'Pas de paroles pour ce titre',
                              hint:
                                  'Le serveur n\'en a trouvé nulle part. '
                                  'Certains titres n\'en ont tout simplement '
                                  'pas.',
                              icon: Icons.lyrics_outlined,
                            )
                          : Center(
                              child: SizedBox(
                                width: 1100,
                                child: ListView(
                                  controller: _scroll,
                                  children: [
                                    Text(
                                      text.trim(),
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        fontSize: 30,
                                        height: 1.6,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 60),
                                  ],
                                ),
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  const TvKeyHints(
                    hints: [('↑ ↓', 'Faire défiler'), ('Retour', 'Fermer')],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Backdrop extends StatelessWidget {
  const _Backdrop({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) => Transform.scale(
    scale: 1.3,
    child: ImageFiltered(
      imageFilter: ImageFilter.blur(
        sigmaX: 70,
        sigmaY: 70,
        tileMode: TileMode.decal,
      ),
      child: Opacity(opacity: 0.5, child: TvArtwork(url: url, borderRadius: 0)),
    ),
  );
}

class _Details extends ConsumerWidget {
  const _Details({
    required this.item,
    required this.playing,
    required this.hasQueue,
    required this.onLyrics,
  });

  final MediaItem item;
  final bool playing;
  final bool hasQueue;
  final VoidCallback onLyrics;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final actions = ref.read(playerActionsProvider);
    final live = item.duration == null || item.duration == Duration.zero;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          (live ? 'Radio en direct' : 'En lecture').toUpperCase(),
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            letterSpacing: 3,
            color: scheme.primary,
          ),
        ),
        const SizedBox(height: 14),
        Text(
          item.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 72,
            fontWeight: FontWeight.w800,
            letterSpacing: -2.4,
            height: 1.02,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          item.artist ?? '',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 34, color: scheme.onSurfaceVariant),
        ),
        if (item.album != null && item.album!.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            item.album!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 25,
              color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
            ),
          ),
        ],
        const SizedBox(height: 46),
        if (!live) _Scrubber(item: item),
        const SizedBox(height: 34),
        Row(
          children: [
            TvPill(
              label: '',
              icon: Icons.skip_previous_rounded,
              accent: false,
              onPressed: actions.previous,
            ),
            const SizedBox(width: 18),
            TvPill(
              label: playing ? 'Pause' : 'Lecture',
              icon: playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
              autofocus: true,
              onPressed: actions.togglePlayPause,
            ),
            const SizedBox(width: 18),
            TvPill(
              label: '',
              icon: Icons.skip_next_rounded,
              accent: false,
              onPressed: actions.next,
            ),
            if (hasQueue) ...[
              const SizedBox(width: 18),
              TvPill(
                label: '',
                icon: Icons.shuffle_rounded,
                accent: false,
                onPressed: actions.toggleShuffle,
              ),
            ],
            // Une radio n'a pas de paroles à chercher : le bouton ne sert
            // qu'aux morceaux de la bibliothèque.
            if (!live) ...[
              const SizedBox(width: 18),
              TvPill(
                label: 'Paroles',
                icon: Icons.lyrics_outlined,
                accent: false,
                onPressed: onLyrics,
              ),
            ],
          ],
        ),
        const SizedBox(height: 28),
        TvKeyHints(
          hints: const [
            ('OK', 'Lecture / pause'),
            ('← →', 'Avancer de 10 s'),
            ('Retour', 'Revenir'),
          ],
        ),
      ],
    );
  }
}

/// La barre de progression, en forme d'onde — reprise du mobile.
///
/// Focalisable : quand elle est visée, gauche et droite ne déplacent plus le
/// focus mais avancent dans le morceau. C'est le seul endroit de l'app TV où
/// la croix directionnelle change de rôle, et le bandeau des touches le dit.
class _Scrubber extends ConsumerWidget {
  const _Scrubber({required this.item});

  final MediaItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final position = ref.watch(positionProvider).value ?? Duration.zero;
    final total = item.duration ?? Duration.zero;
    final ratio = total.inMilliseconds == 0
        ? 0.0
        : (position.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0);

    void seekBy(int seconds) {
      final target = position + Duration(seconds: seconds);
      ref
          .read(playerActionsProvider)
          .seek(
            target < Duration.zero
                ? Duration.zero
                : (target > total ? total : target),
          );
    }

    return Focus(
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
          return KeyEventResult.ignored;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
          seekBy(-10);
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
          seekBy(10);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Builder(
        builder: (context) {
          final focused = Focus.of(context).hasFocus;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: focused ? tvFocusBorder(scheme.primary) : null,
                  boxShadow: focused
                      ? tvFocusGlow(scheme.primary, spread: 4)
                      : null,
                ),
                child: SizedBox(
                  height: 74,
                  child: CustomPaint(
                    painter: _WavePainter(
                      seed: item.id.hashCode,
                      ratio: ratio,
                      played: scheme.primary,
                      rest: scheme.onSurface.withValues(alpha: 0.22),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _hms(position),
                    style: TextStyle(
                      fontSize: 24,
                      color: scheme.onSurfaceVariant,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  Text(
                    '−${_hms(total - position)}',
                    style: TextStyle(
                      fontSize: 24,
                      color: scheme.onSurfaceVariant,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Onde décorative, mais stable : la même pour un même morceau, d'une
/// écoute à l'autre. Une onde qui changerait à chaque image donnerait
/// l'impression que la lecture saute.
class _WavePainter extends CustomPainter {
  const _WavePainter({
    required this.seed,
    required this.ratio,
    required this.played,
    required this.rest,
  });

  final int seed;
  final double ratio;
  final Color played;
  final Color rest;

  @override
  void paint(Canvas canvas, Size size) {
    const gap = 4.0;
    const width = 6.0;
    final count = (size.width / (width + gap)).floor();
    final head = (count * ratio).round();
    final random = math.Random(seed);

    for (var i = 0; i < count; i++) {
      final h =
          size.height *
          (0.16 +
              0.84 *
                  (0.35 * (1 + math.sin(i * 0.7)) / 2 +
                      0.35 * (1 + math.sin(i * 0.23)) / 2 +
                      0.3 * random.nextDouble()));
      final x = i * (width + gap);
      final y = (size.height - h) / 2;
      final paint = Paint()
        ..color = i == head ? Colors.white : (i < head ? played : rest);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, y, width, h),
          const Radius.circular(3),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_WavePainter old) =>
      old.ratio != ratio || old.seed != seed;
}

class _UpNext extends StatelessWidget {
  const _UpNext({required this.items, required this.total});

  final List<MediaItem> items;
  final int total;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          'À SUIVRE',
          style: TextStyle(
            fontSize: 23,
            fontWeight: FontWeight.w700,
            letterSpacing: 2.4,
            color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
          ),
        ),
        const SizedBox(width: 24),
        for (var i = 0; i < items.length; i++) ...[
          Opacity(
            opacity: 1 - i * 0.14,
            child: TvArtwork(
              url: items[i].artUri?.toString(),
              size: 74,
              borderRadius: 14,
            ),
          ),
          const SizedBox(width: 16),
        ],
        if (total > items.length)
          Text(
            '+ ${total - items.length} titres',
            style: TextStyle(
              fontSize: 23,
              color: scheme.onSurfaceVariant.withValues(alpha: 0.6),
            ),
          ),
      ],
    );
  }
}

String _hms(Duration d) {
  final total = d.inSeconds < 0 ? 0 : d.inSeconds;
  final h = total ~/ 3600;
  final m = (total % 3600) ~/ 60;
  final s = total % 60;
  final mm = h > 0 ? m.toString().padLeft(2, '0') : '$m';
  return h > 0
      ? '$h:$mm:${s.toString().padLeft(2, '0')}'
      : '$mm:${s.toString().padLeft(2, '0')}';
}
