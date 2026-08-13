import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/player.dart';
import '../theme.dart';

/// Le thème rétro Winamp est-il levé ? (idée #82)
bool isRetroSkin(BuildContext context) =>
    Theme.of(context).extension<GullifySurfaces>()?.retro ?? false;

/// Le lettrage de l'afficheur : chasse fixe, vert sur noir. `monospace` est
/// la famille générique d'Android — aucune police à embarquer pour retrouver
/// le grain des lecteurs de 1999.
TextStyle lcdTextStyle({
  double size = 13,
  FontWeight weight = FontWeight.w700,
  Color color = winampGreen,
}) => TextStyle(
  fontFamily: 'monospace',
  fontFamilyFallback: const ['Roboto Mono', 'Courier'],
  fontSize: size,
  fontWeight: weight,
  letterSpacing: 0.5,
  color: color,
  height: 1.2,
);

/// L'afficheur du lecteur, façon Winamp : le temps en gros chiffres verts, le
/// titre qui défile quand il est trop long, et les barres de l'analyseur.
///
/// N'apparaît que sous le thème rétro — partout ailleurs, le lecteur garde
/// son verre.
class RetroLcd extends ConsumerWidget {
  const RetroLcd({super.key, required this.title, this.artist, this.duration});

  final String title;
  final String? artist;
  final Duration? duration;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final position = ref.watch(positionProvider).value ?? Duration.zero;
    final playing = ref.watch(playbackStateProvider).value?.playing ?? false;
    final total = duration;
    final line = artist == null || artist!.isEmpty
        ? title
        : '$title  —  $artist';

    return Container(
      decoration: BoxDecoration(
        color: winampLcd,
        borderRadius: BorderRadius.circular(2),
        border: Border.all(color: const Color(0xFF12141A), width: 1.5),
      ),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            _clock(position, playing),
            style: lcdTextStyle(size: 26, weight: FontWeight.w800),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _Marquee(text: line, style: lcdTextStyle(size: 12.5)),
                const SizedBox(height: 3),
                Text(
                  total == null
                      ? 'STEREO'
                      : '${_mmss(total)}  ·  STEREO',
                  style: lcdTextStyle(
                    size: 9.5,
                    weight: FontWeight.w600,
                    color: winampGreen.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          _Analyser(playing: playing),
        ],
      ),
    );
  }

  /// Winamp faisait clignoter les deux points à l'arrêt : le temps est
  /// suspendu, et ça se voit sans lire.
  static String _clock(Duration position, bool playing) {
    final text = _mmss(position);
    return playing ? text : text.replaceFirst(':', ' ');
  }

  static String _mmss(Duration d) {
    final minutes = d.inMinutes.toString().padLeft(2, '0');
    final seconds = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}

/// Le titre qui défile — et seulement quand il dépasse, comme sur l'original.
class _Marquee extends StatefulWidget {
  const _Marquee({required this.text, required this.style});

  final String text;
  final TextStyle style;

  @override
  State<_Marquee> createState() => _MarqueeState();
}

class _MarqueeState extends State<_Marquee> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 12),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final painter = TextPainter(
          text: TextSpan(text: widget.text, style: widget.style),
          textDirection: TextDirection.ltr,
        )..layout();
        final width = painter.width;
        final text = Text(
          widget.text,
          maxLines: 1,
          softWrap: false,
          style: widget.style,
        );
        // Ça tient : pas de défilement, le titre se lit d'un coup d'œil.
        if (width <= constraints.maxWidth) {
          return SizedBox(height: painter.height, child: text);
        }
        // L'espace entre la fin du titre et son retour, comme sur l'original.
        const gap = 40.0;
        final span = width + gap;
        return ClipRect(
          child: SizedBox(
            height: painter.height,
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, _) => Transform.translate(
                offset: Offset(-span * _controller.value, 0),
                child: OverflowBox(
                  alignment: Alignment.centerLeft,
                  maxWidth: span * 2,
                  child: Row(
                    children: [
                      text,
                      const SizedBox(width: gap),
                      text,
                    ],
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

/// L'analyseur de spectre : quelques barres vertes qui sautent au son. Elles
/// ne mesurent rien (aucun accès au signal), elles vivent — exactement comme
/// le mini-analyseur que tout le monde regardait sans jamais s'en servir.
class _Analyser extends StatefulWidget {
  const _Analyser({required this.playing});

  final bool playing;

  @override
  State<_Analyser> createState() => _AnalyserState();
}

class _AnalyserState extends State<_Analyser>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  // Chaque barre a sa propre allure : sans ça, les cinq montent ensemble et
  // on voit un peigne, pas un spectre.
  static const _phases = [0.0, 0.35, 0.7, 0.15, 0.5];
  static const _tops = [0.9, 0.65, 1.0, 0.5, 0.8];

  @override
  void initState() {
    super.initState();
    if (widget.playing) _controller.repeat();
  }

  @override
  void didUpdateWidget(_Analyser old) {
    super.didUpdateWidget(old);
    if (widget.playing && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!widget.playing && _controller.isAnimating) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    builder: (context, _) => Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (var i = 0; i < _phases.length; i++) ...[
          Container(
            width: 3,
            height: 4 + 18 * _level(i),
            color: winampGreen,
          ),
          if (i < _phases.length - 1) const SizedBox(width: 2),
        ],
      ],
    ),
  );

  double _level(int i) {
    if (!widget.playing) return 0.12;
    final t = (_controller.value + _phases[i]) % 1.0;
    // Montée franche, descente lente : c'est le mouvement d'un vumètre.
    final shape = t < 0.3 ? t / 0.3 : 1 - (t - 0.3) / 0.7;
    return (shape * _tops[i]).clamp(0.08, 1.0);
  }
}
