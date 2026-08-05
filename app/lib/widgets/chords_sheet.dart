import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/song_chords.dart';
import '../state/library.dart';

/// Feuille « Accords » du lecteur : la grille guitare du titre en cours,
/// transposable, avec défilement automatique et diagrammes de doigté.
void showChordsSheet(BuildContext context, String? filePath) {
  showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    builder: (context) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      builder: (context, controller) => filePath == null
          ? const Center(child: Text('Accords indisponibles'))
          : Consumer(
              builder: (context, ref, _) {
                final chords = ref.watch(chordsProvider(filePath));
                return chords.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (e, _) => _Empty(
                    message: 'Accords indisponibles pour le moment',
                    detail: '$e',
                  ),
                  data: (result) => result.chords == null
                      ? _Empty(
                          message: 'Aucune grille trouvée pour ce titre',
                          searchUrl: result.searchUrl,
                        )
                      : _ChordsView(
                          chords: result.chords!,
                          controller: controller,
                        ),
                );
              },
            ),
    ),
  );
}

/// Petite icône « accords » dessinée à la main : le manche vu de face, avec
/// ses trois doigts posés. Material n'a pas d'icône de guitare.
class ChordsIcon extends StatelessWidget {
  const ChordsIcon({super.key, this.size = 24});

  final double size;

  @override
  Widget build(BuildContext context) => CustomPaint(
        size: Size.square(size),
        painter: _ChordsIconPainter(
          IconTheme.of(context).color ?? Theme.of(context).colorScheme.onSurface,
        ),
      );
}

class _ChordsIconPainter extends CustomPainter {
  const _ChordsIconPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final left = s * 0.18;
    final right = s * 0.82;
    final top = s * 0.22;
    final bottom = s * 0.86;
    final line = Paint()
      ..color = color
      ..strokeWidth = s * 0.055
      ..strokeCap = StrokeCap.round;

    // Sillet (trait épais) puis cordes et frettes.
    canvas.drawLine(
      Offset(left, top),
      Offset(right, top),
      Paint()
        ..color = color
        ..strokeWidth = s * 0.11
        ..strokeCap = StrokeCap.round,
    );
    for (var i = 0; i < 4; i++) {
      final x = left + (right - left) * i / 3;
      canvas.drawLine(Offset(x, top), Offset(x, bottom), line);
    }
    for (var i = 1; i <= 2; i++) {
      final y = top + (bottom - top) * i / 3;
      canvas.drawLine(Offset(left, y), Offset(right, y), line);
    }

    final dot = Paint()..color = color;
    final columns = [0, 1, 2];
    final rows = [1, 2, 1];
    for (var i = 0; i < columns.length; i++) {
      canvas.drawCircle(
        Offset(
          left + (right - left) * columns[i] / 3,
          top + (bottom - top) * (rows[i] - 0.5) / 3,
        ),
        s * 0.11,
        dot,
      );
    }
  }

  @override
  bool shouldRepaint(_ChordsIconPainter old) => old.color != color;
}

class _Empty extends StatelessWidget {
  const _Empty({required this.message, this.detail, this.searchUrl});

  final String message;
  final String? detail;
  final String? searchUrl;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ChordsIcon(size: 44),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
            if (detail != null) ...[
              const SizedBox(height: 8),
              Text(
                detail!,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
            ],
            if (searchUrl != null) ...[
              const SizedBox(height: 16),
              TextButton.icon(
                onPressed: () => launchUrl(
                  Uri.parse(searchUrl!),
                  mode: LaunchMode.externalApplication,
                ),
                icon: const Icon(Icons.search, size: 18),
                label: const Text('Chercher sur Ultimate-Guitar'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ChordsView extends StatefulWidget {
  const _ChordsView({required this.chords, required this.controller});

  final SongChords chords;
  final ScrollController controller;

  @override
  State<_ChordsView> createState() => _ChordsViewState();
}

class _ChordsViewState extends State<_ChordsView> {
  /// Vitesses de défilement automatique, en pixels par seconde.
  static const _speeds = [10.0, 18.0, 30.0, 48.0];

  late final List<List<ChordToken>> _lines = parseChordLines(
    widget.chords.content,
  );
  late final List<String> _chordNames = distinctChords(_lines);

  int _transpose = 0;
  int _speedIndex = 1;
  Timer? _scroller;

  @override
  void dispose() {
    _scroller?.cancel();
    super.dispose();
  }

  void _toggleScroll() {
    if (_scroller != null) {
      _scroller!.cancel();
      setState(() => _scroller = null);
      return;
    }
    const tick = Duration(milliseconds: 40);
    setState(() {
      _scroller = Timer.periodic(tick, (timer) {
        final controller = widget.controller;
        if (!controller.hasClients) return;
        final max = controller.position.maxScrollExtent;
        final next = controller.offset + _speeds[_speedIndex] * tick.inMilliseconds / 1000;
        if (next >= max) {
          controller.jumpTo(max);
          timer.cancel();
          if (mounted) setState(() => _scroller = null);
          return;
        }
        controller.jumpTo(next);
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final chords = widget.chords;
    final lines = transposeLines(_lines, _transpose);

    return Column(
      children: [
        _Header(chords: chords, transpose: _transpose),
        _Toolbar(
          transpose: _transpose,
          onTranspose: (delta) => setState(() {
            _transpose = ((_transpose + delta + 6) % 12) - 6;
          }),
          scrolling: _scroller != null,
          onToggleScroll: _toggleScroll,
          speed: _speedIndex + 1,
          onSpeed: () => setState(() {
            _speedIndex = (_speedIndex + 1) % _speeds.length;
          }),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView(
            controller: widget.controller,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
            children: [
              if (_chordNames.isNotEmpty) ...[
                _ShapesRow(
                  names: _chordNames,
                  shapes: chords.shapes,
                  transpose: _transpose,
                ),
                const SizedBox(height: 16),
              ],
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final line in lines) _ChordLine(tokens: line),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Center(
                child: TextButton.icon(
                  onPressed: chords.url.isEmpty
                      ? null
                      : () => launchUrl(
                            Uri.parse(chords.url),
                            mode: LaunchMode.externalApplication,
                          ),
                  icon: const Icon(Icons.open_in_new, size: 16),
                  label: Text(
                    'Grille d\'Ultimate-Guitar'
                    '${chords.votes != null ? ' · ${chords.votes} avis' : ''}',
                    style: TextStyle(
                      fontSize: 12,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.chords, required this.transpose});

  final SongChords chords;
  final int transpose;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tonality = chords.tonality;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            chords.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.3,
            ),
          ),
          Text(
            chords.artist,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (chords.capo != null)
                _Pill(icon: Icons.horizontal_rule, label: 'Capo ${chords.capo}'),
              if (tonality != null && tonality.isNotEmpty)
                _Pill(
                  icon: Icons.piano,
                  label: 'Tonalité ${transposeChord(tonality, transpose)}',
                ),
              if (chords.tuning != null)
                _Pill(icon: Icons.tune, label: chords.tuning!),
            ],
          ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: scheme.onSurfaceVariant),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.transpose,
    required this.onTranspose,
    required this.scrolling,
    required this.onToggleScroll,
    required this.speed,
    required this.onSpeed,
  });

  final int transpose;
  final ValueChanged<int> onTranspose;
  final bool scrolling;
  final VoidCallback onToggleScroll;
  final int speed;
  final VoidCallback onSpeed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Transposer vers le bas',
            icon: const Icon(Icons.remove),
            onPressed: () => onTranspose(-1),
          ),
          SizedBox(
            width: 44,
            child: Text(
              transpose == 0
                  ? '0'
                  : '${transpose > 0 ? '+' : ''}$transpose',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: transpose == 0 ? scheme.onSurfaceVariant : scheme.primary,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Transposer vers le haut',
            icon: const Icon(Icons.add),
            onPressed: () => onTranspose(1),
          ),
          const Spacer(),
          if (scrolling)
            TextButton(
              onPressed: onSpeed,
              child: Text('×$speed'),
            ),
          IconButton(
            tooltip: scrolling
                ? 'Arrêter le défilement'
                : 'Défilement automatique',
            icon: Icon(
              scrolling ? Icons.pause_circle_outline : Icons.play_circle_outline,
              color: scrolling ? scheme.primary : null,
            ),
            onPressed: onToggleScroll,
          ),
        ],
      ),
    );
  }
}

/// Une ligne de la grille : accords en couleur accent, paroles en monospace
/// pour que les accords restent au-dessus de la bonne syllabe.
class _ChordLine extends StatelessWidget {
  const _ChordLine({required this.tokens});

  final List<ChordToken> tokens;

  static const _style = TextStyle(
    fontSize: 13,
    height: 1.5,
    fontFamily: 'monospace',
    fontFamilyFallback: ['Courier'],
  );

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (isSectionLine(tokens)) {
      return Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 2),
        child: Text(
          tokens.first.text.trim(),
          style: _style.copyWith(
            fontWeight: FontWeight.w800,
            color: scheme.onSurfaceVariant,
          ),
        ),
      );
    }
    return Text.rich(
      TextSpan(
        children: [
          for (final token in tokens)
            TextSpan(
              text: token.text,
              style: token.isChord
                  ? _style.copyWith(
                      color: scheme.primary,
                      fontWeight: FontWeight.w800,
                    )
                  : _style,
            ),
        ],
      ),
      style: _style,
    );
  }
}

/// Bandeau des doigtés. Les diagrammes viennent de la grille d'origine :
/// transposée, la position ne correspond plus, on le dit plutôt que de mentir.
class _ShapesRow extends StatelessWidget {
  const _ShapesRow({
    required this.names,
    required this.shapes,
    required this.transpose,
  });

  final List<String> names;
  final Map<String, ChordShape> shapes;
  final int transpose;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final known = names.where(shapes.containsKey).toList();
    if (known.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          transpose == 0 ? 'Doigtés' : 'Doigtés (position d\'origine)',
          style: TextStyle(
            fontSize: 11,
            letterSpacing: 1.2,
            fontWeight: FontWeight.w800,
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 108,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: known.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (context, i) => ChordDiagram(
              name: known[i],
              shape: shapes[known[i]]!,
            ),
          ),
        ),
      ],
    );
  }
}

/// Diagramme d'accord : six cordes, quatre cases, points de doigté.
class ChordDiagram extends StatelessWidget {
  const ChordDiagram({super.key, required this.name, required this.shape});

  final String name;
  final ChordShape shape;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          name,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w800,
            color: scheme.primary,
          ),
        ),
        const SizedBox(height: 4),
        CustomPaint(
          size: const Size(58, 82),
          painter: _ChordDiagramPainter(
            shape: shape,
            line: scheme.onSurface.withValues(alpha: 0.45),
            dot: scheme.primary,
            label: scheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _ChordDiagramPainter extends CustomPainter {
  const _ChordDiagramPainter({
    required this.shape,
    required this.line,
    required this.dot,
    required this.label,
  });

  final ChordShape shape;
  final Color line;
  final Color dot;
  final Color label;

  static const _fretCount = 4;

  /// Première case affichée : 1 pour les accords ouverts, sinon la plus basse
  /// case jouée (les accords barrés se lisent alors « 5fr », « 7fr »…).
  int get _firstFret {
    final played = shape.frets.where((f) => f > 0);
    if (played.isEmpty) return 1;
    final max = played.reduce((a, b) => a > b ? a : b);
    if (max <= _fretCount) return 1;
    return played.reduce((a, b) => a < b ? a : b);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final first = _firstFret;
    final top = 12.0;
    final left = 6.0;
    final right = size.width - 6;
    final bottom = size.height - 4;
    final stringGap = (right - left) / 5;
    final fretGap = (bottom - top) / _fretCount;

    final stroke = Paint()
      ..color = line
      ..strokeWidth = 1;

    for (var i = 0; i < 6; i++) {
      final x = left + stringGap * i;
      canvas.drawLine(Offset(x, top), Offset(x, bottom), stroke);
    }
    for (var i = 0; i <= _fretCount; i++) {
      final y = top + fretGap * i;
      canvas.drawLine(
        Offset(left, y),
        Offset(right, y),
        i == 0 && first == 1
            ? (Paint()
              ..color = line
              ..strokeWidth = 3)
            : stroke,
      );
    }

    if (first > 1) _text(canvas, '${first}fr', Offset(right + 1, top - 2), 8);

    // Les cases arrivent de la corde aiguë : la 1re case du tableau est le mi
    // aigu, dessiné à droite.
    for (var i = 0; i < 6; i++) {
      final x = right - stringGap * i;
      final fret = shape.frets[i];
      if (fret < 0) {
        _text(canvas, '×', Offset(x - 3, top - 11), 9);
      } else if (fret == 0) {
        canvas.drawCircle(
          Offset(x, top - 6),
          2.6,
          Paint()
            ..color = line
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1,
        );
      } else {
        final row = fret - first;
        if (row < 0 || row >= _fretCount) continue;
        canvas.drawCircle(
          Offset(x, top + fretGap * (row + 0.5)),
          fretGap * 0.3,
          Paint()..color = dot,
        );
      }
    }
  }

  void _text(Canvas canvas, String value, Offset at, double size) {
    TextPainter(
      text: TextSpan(
        text: value,
        style: TextStyle(fontSize: size, color: label),
      ),
      textDirection: TextDirection.ltr,
    )
      ..layout()
      ..paint(canvas, at);
  }

  @override
  bool shouldRepaint(_ChordDiagramPainter old) =>
      old.shape != shape || old.dot != dot;
}
