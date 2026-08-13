import 'dart:math' as math;

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/player.dart';
import '../theme.dart';
import 'retro_chrome.dart';

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

/// L'afficheur du lecteur, façon Winamp : le temps en chiffres à segments,
/// l'analyseur de spectre à sa gauche, les voyants à droite et le titre qui
/// défile en dessous.
///
/// N'apparaît que sous le thème rétro — partout ailleurs, le lecteur garde
/// son verre.
class RetroLcd extends ConsumerWidget {
  const RetroLcd({super.key, required this.item});

  final MediaItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final position = ref.watch(positionProvider).value ?? Duration.zero;
    final playing = ref.watch(playbackStateProvider).value?.playing ?? false;
    final queue = ref.watch(queueProvider).value ?? const <MediaItem>[];
    final index = queue.indexWhere((q) => q.id == item.id);
    final total = item.duration;

    final artist = item.artist;
    // Le format du marquee de 1999 : le rang dans la file, le titre, et la
    // durée entre parenthèses.
    final line = StringBuffer();
    if (index >= 0) line.write('${index + 1}. ');
    line.write(item.title);
    if (artist != null && artist.isNotEmpty) line.write('  —  $artist');
    if (total != null) line.write('  (${_mmss(total)})');

    return RetroBevel(
      sunken: true,
      fill: winampLcd,
      padding: const EdgeInsets.fromLTRB(8, 7, 8, 7),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _Analyser(playing: playing),
              const SizedBox(width: 10),
              SevenSegment(_clock(position, playing), height: 26),
              const Spacer(),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      _LcdBox(text: _format(item)),
                      const SizedBox(width: 4),
                      _LcdBox(
                        text: index >= 0
                            ? '${index + 1}/${queue.length}'
                            : '--',
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  // Les deux voyants sont toujours gravés, un seul s'allume :
                  // c'est comme ça qu'on lisait un lecteur avant les icônes.
                  Row(
                    children: [
                      _Indicator(label: 'MONO', lit: false),
                      const SizedBox(width: 5),
                      _Indicator(label: 'STEREO', lit: true),
                    ],
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 6),
          _Marquee(text: line.toString(), style: lcdTextStyle(size: 12.5)),
        ],
      ),
    );
  }

  /// Ce que le lecteur sait dire du fichier : son extension, comme les vieux
  /// afficheurs annonçaient « MP3 ». Rien d'inventé — faute de mieux, il ne
  /// promet rien.
  static String _format(MediaItem item) {
    if (item.extras?['radio'] == true) return 'NET';
    final path = item.extras?['filePath'] as String?;
    final dot = path?.lastIndexOf('.') ?? -1;
    if (path == null || dot < 0 || dot == path.length - 1) return '---';
    final ext = path.substring(dot + 1).toUpperCase();
    return ext.length > 5 ? ext.substring(0, 5) : ext;
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

/// Les chiffres de l'afficheur, dessinés segment par segment. C'est ce
/// découpage — et les segments éteints qu'on devine derrière — qui fait le
/// tube d'un lecteur de 1999 ; du texte vert en chasse fixe reste du texte
/// (idée #83).
class SevenSegment extends StatelessWidget {
  const SevenSegment(
    this.text, {
    super.key,
    this.height = 26,
    this.color = winampGreen,
  });

  /// Chiffres, « : » et espaces (deux points éteints).
  final String text;
  final double height;
  final Color color;

  static const _digitRatio = 0.56;
  static const _colonRatio = 0.28;
  static const _gapRatio = 0.09;

  static double _advance(String char, double height) =>
      (char == ':' || char == ' ' ? _colonRatio : _digitRatio) * height;

  double get width {
    var w = 0.0;
    for (var i = 0; i < text.length; i++) {
      w += _advance(text[i], height) + (i > 0 ? _gapRatio * height : 0);
    }
    return w;
  }

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: Size(width, height),
    painter: _SegmentPainter(text, color, height),
  );
}

class _SegmentPainter extends CustomPainter {
  const _SegmentPainter(this.text, this.color, this.height);

  final String text;
  final Color color;
  final double height;

  /// Quels segments s'allument, dans l'ordre a·b·c·d·e·f·g.
  static const _map = {
    '0': 'abcdef',
    '1': 'bc',
    '2': 'abdeg',
    '3': 'abcdg',
    '4': 'bcfg',
    '5': 'acdfg',
    '6': 'acdefg',
    '7': 'abc',
    '8': 'abcdefg',
    '9': 'abcdfg',
  };

  @override
  void paint(Canvas canvas, Size size) {
    final t = height * 0.12;
    final lit = Paint()..color = color;
    // Les segments éteints ne disparaissent pas : ils restent en filigrane,
    // comme le cristal d'un vrai afficheur.
    final off = Paint()..color = color.withValues(alpha: 0.10);

    var x = 0.0;
    for (var i = 0; i < text.length; i++) {
      final char = text[i];
      final advance = SevenSegment._advance(char, height);
      if (char == ':' || char == ' ') {
        final square = t * 0.9;
        final paint = char == ':' ? lit : off;
        final left = x + (advance - square) / 2;
        canvas
          ..drawRect(Rect.fromLTWH(left, height * 0.26, square, square), paint)
          ..drawRect(Rect.fromLTWH(left, height * 0.62, square, square), paint);
      } else {
        final on = _map[char] ?? '';
        for (final segment in 'abcdefg'.split('')) {
          _segment(canvas, segment, x, advance, t, on.contains(segment) ? lit : off);
        }
      }
      x += advance + SevenSegment._gapRatio * height;
    }
  }

  /// Un segment est un hexagone aplati : ce sont ses pointes qui font
  /// l'afficheur, un rectangle ferait un code-barres.
  void _segment(
    Canvas canvas,
    String name,
    double x,
    double w,
    double t,
    Paint paint,
  ) {
    final h = height;
    // Les segments se rejoignent par la pointe : les verticaux montent
    // jusque sous l'horizontal, leur biseau fait l'angle. Trop courts, le
    // chiffre s'ouvre et ne se lit plus.
    final vLength = h / 2 - t * 0.9;
    final path = switch (name) {
      'a' => _horizontal(x + t * 0.55, 0, w - t * 1.1, t),
      'g' => _horizontal(x + t * 0.55, (h - t) / 2, w - t * 1.1, t),
      'd' => _horizontal(x + t * 0.55, h - t, w - t * 1.1, t),
      'f' => _vertical(x, t * 0.55, vLength, t),
      'b' => _vertical(x + w - t, t * 0.55, vLength, t),
      'e' => _vertical(x, h / 2 + t * 0.35, vLength, t),
      _ => _vertical(x + w - t, h / 2 + t * 0.35, vLength, t),
    };
    canvas.drawPath(path, paint);
  }

  static Path _horizontal(double x, double y, double w, double t) => Path()
    ..moveTo(x + t / 2, y)
    ..lineTo(x + w - t / 2, y)
    ..lineTo(x + w, y + t / 2)
    ..lineTo(x + w - t / 2, y + t)
    ..lineTo(x + t / 2, y + t)
    ..lineTo(x, y + t / 2)
    ..close();

  static Path _vertical(double x, double y, double h, double t) => Path()
    ..moveTo(x, y + t / 2)
    ..lineTo(x + t / 2, y)
    ..lineTo(x + t, y + t / 2)
    ..lineTo(x + t, y + h - t / 2)
    ..lineTo(x + t / 2, y + h)
    ..lineTo(x, y + h - t / 2)
    ..close();

  @override
  bool shouldRepaint(_SegmentPainter oldDelegate) =>
      oldDelegate.text != text ||
      oldDelegate.color != color ||
      oldDelegate.height != height;
}

/// Un petit cadre creux avec deux ou trois caractères verts dedans : les
/// cases « kbps » et « kHz » du lecteur d'origine, ici le format du fichier
/// et le rang dans la file.
class _LcdBox extends StatelessWidget {
  const _LcdBox({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => RetroBevel(
    sunken: true,
    fill: const Color(0xFF0D1010),
    padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
    // Largeur plancher : les deux cases restent alignées, que le mot dedans
    // fasse « MP3 » ou « FLAC ».
    child: ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 26),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: lcdTextStyle(size: 8.5, weight: FontWeight.w600),
      ),
    ),
  );
}

/// Un voyant gravé : allumé en vert, éteint mais toujours lisible.
class _Indicator extends StatelessWidget {
  const _Indicator({required this.label, required this.lit});

  final String label;
  final bool lit;

  @override
  Widget build(BuildContext context) => Text(
    label,
    style: lcdTextStyle(
      size: 8,
      weight: FontWeight.w700,
      color: lit ? winampGreen : winampGreen.withValues(alpha: 0.22),
    ).copyWith(letterSpacing: 1),
  );
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
  // Créé ici et pas en `late final` : un titre assez court pour tenir ne
  // touchait jamais le champ, et c'est `dispose` qui finissait par le créer
  // — construire un ticker pendant qu'on démonte l'arbre lève une assertion.
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 12),
    );
  }

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
          if (_controller.isAnimating) _controller.stop();
          return SizedBox(
            width: double.infinity,
            height: painter.height,
            child: text,
          );
        }
        if (!_controller.isAnimating) _controller.repeat();
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

/// L'analyseur de spectre : des colonnes de petits blocs qui montent du vert
/// à l'ambre, coiffées d'un plot gris qui redescend doucement. Elles ne
/// mesurent rien (aucun accès au signal), elles vivent — exactement comme le
/// mini-analyseur que tout le monde regardait sans jamais s'en servir.
class _Analyser extends StatefulWidget {
  const _Analyser({required this.playing});

  final bool playing;

  static const bars = 12;
  static const columnWidth = 3.0;
  static const columnGap = 1.0;
  static const height = 26.0;

  @override
  State<_Analyser> createState() => _AnalyserState();
}

class _AnalyserState extends State<_Analyser>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
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
  Widget build(BuildContext context) => SizedBox(
    width:
        _Analyser.bars * (_Analyser.columnWidth + _Analyser.columnGap) -
        _Analyser.columnGap,
    height: _Analyser.height,
    child: CustomPaint(
      painter: _AnalyserPainter(
        phase: _controller,
        playing: widget.playing,
      ),
    ),
  );
}

class _AnalyserPainter extends CustomPainter {
  _AnalyserPainter({required this.phase, required this.playing})
    : super(repaint: phase);

  final Animation<double> phase;
  final bool playing;

  static const _blockHeight = 2.0;
  static const _blockGap = 1.0;

  /// Chaque colonne a sa propre allure : sans ça, les douze montent ensemble
  /// et on voit un peigne, pas un spectre.
  static double _offset(int i) => (i * 0.37 + (i % 3) * 0.11) % 1.0;
  static double _top(int i) => 0.45 + 0.55 * ((i * 7) % 5) / 4;

  double _level(int i, double t) {
    if (!playing) return 0.06;
    final u = (t + _offset(i)) % 1.0;
    // Montée franche, descente lente : c'est le mouvement d'un vumètre.
    final shape = u < 0.3 ? u / 0.3 : 1 - (u - 0.3) / 0.7;
    return (shape * _top(i)).clamp(0.05, 1.0);
  }

  /// Le plot de crête : le plus haut niveau des dernières fractions de
  /// seconde. Il retombe donc tout seul, en retard sur la colonne.
  double _peak(int i, double t) {
    var peak = 0.0;
    for (var k = 0; k < 6; k++) {
      peak = math.max(peak, _level(i, (t - k * 0.03 + 1) % 1.0));
    }
    return peak;
  }

  /// Vert en bas, jaune à mi-hauteur, ambre en haut.
  static Color _shade(double fraction) => fraction < 0.5
      ? Color.lerp(winampGreen, const Color(0xFFC8F000), fraction * 2)!
      : Color.lerp(
          const Color(0xFFC8F000),
          const Color(0xFFF0A000),
          (fraction - 0.5) * 2,
        )!;

  @override
  void paint(Canvas canvas, Size size) {
    final t = phase.value;
    final rows = ((size.height + _blockGap) / (_blockHeight + _blockGap))
        .floor();
    final columns =
        ((size.width + _Analyser.columnGap) /
                (_Analyser.columnWidth + _Analyser.columnGap))
            .floor();
    final cap = Paint()..color = const Color(0xFFB4BAC4);

    for (var i = 0; i < columns; i++) {
      final x = i * (_Analyser.columnWidth + _Analyser.columnGap);
      final level = _level(i, t);
      final peakRow = (_peak(i, t) * rows).round().clamp(0, rows - 1);
      final litRows = (level * rows).round();
      for (var r = 0; r < litRows; r++) {
        final y = size.height - (r + 1) * _blockHeight - r * _blockGap;
        canvas.drawRect(
          Rect.fromLTWH(x, y, _Analyser.columnWidth, _blockHeight),
          Paint()..color = _shade(rows <= 1 ? 0 : r / (rows - 1)),
        );
      }
      if (playing) {
        final y =
            size.height - (peakRow + 1) * _blockHeight - peakRow * _blockGap;
        canvas.drawRect(
          Rect.fromLTWH(x, y, _Analyser.columnWidth, 1),
          cap,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_AnalyserPainter oldDelegate) =>
      oldDelegate.playing != playing;
}
