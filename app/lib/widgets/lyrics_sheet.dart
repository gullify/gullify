import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/karaoke.dart';
import '../state/library.dart';
import '../state/player.dart';

/// Feuille « Paroles » du lecteur : le texte du titre en cours, défilant au
/// rythme de la lecture quand il est horodaté (format LRC).
void showLyricsSheet(BuildContext context, String? filePath) {
  showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    builder: (context) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      builder: (context, controller) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
            child: Row(
              children: [
                Text(
                  'Paroles',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                _KaraokeButton(filePath: filePath),
              ],
            ),
          ),
          Expanded(
            child: filePath == null
                ? const Center(child: Text('Paroles indisponibles'))
                : Consumer(
                    builder: (context, ref, _) {
                      final lyrics = ref.watch(lyricsProvider(filePath));
                      return lyrics.when(
                        loading: () =>
                            const Center(child: CircularProgressIndicator()),
                        error: (e, _) => Center(child: Text('Erreur: $e')),
                        data: (text) => text == null
                            ? const Center(child: Text('Aucunes paroles trouvées'))
                            : LyricsView(text: text, controller: controller),
                      );
                    },
                  ),
          ),
        ],
      ),
    ),
  );
}

/// Bouton « micro barré » des paroles (idée #63) : bascule le lecteur sur la
/// version voix atténuée du titre, préparée par le serveur. Il attend que le
/// rendu soit prêt avant de basculer — sinon on entendrait la version
/// d'origine en croyant le mode actif — et dit pourquoi quand un titre ne s'y
/// prête pas (mixage trop centré : il n'y a pas de voix à retirer sans
/// effacer le reste).
class _KaraokeButton extends ConsumerWidget {
  const _KaraokeButton({required this.filePath});

  final String? filePath;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final karaoke = ref.watch(karaokeProvider);
    final scheme = Theme.of(context).colorScheme;

    ref.listen(karaokeProvider, (previous, next) {
      if (next.phase == KaraokePhase.unavailable &&
          previous?.phase != KaraokePhase.unavailable) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(KaraokeNotifier.explain(next.reason))),
        );
      }
    });

    final accent = karaoke.active ? scheme.primary : null;
    return TextButton.icon(
      onPressed: filePath == null || karaoke.busy
          ? null
          : () => ref.read(karaokeProvider.notifier).toggle(filePath),
      icon: karaoke.busy
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(Icons.mic_off, color: accent),
      label: Text(
        karaoke.busy ? 'Préparation…' : 'Karaoké',
        style: TextStyle(
          color: accent,
          fontWeight: karaoke.active ? FontWeight.w700 : null,
        ),
      ),
    );
  }
}

/// Taille de la ligne chantée, et des autres.
const kLyricsCurrentFontSize = 18.0;
const kLyricsOtherFontSize = 15.0;
const kLyricsLineHeight = 1.3;

/// Une phrase peut s'étaler sur deux lignes avant qu'on ne rétrécisse.
const kLyricsMaxLines = 2;

const _kMinScale = 0.6;
const _kScaleStep = 0.05;
const _kMinLineExtent = 44.0;
const _kLinePadding = 10.0;
const _kLyricsHorizontalPadding = 24.0;
const _kLyricsVerticalPadding = 120.0;

/// Encombrement d'une phrase de paroles (idée #100) : une phrase trop longue
/// n'est plus tranchée par des « … ». Elle passe d'abord sur deux lignes, puis,
/// si ça ne suffit toujours pas, sa taille rétrécit jusqu'à [_kMinScale].
class LyricsLineFit {
  const LyricsLineFit({required this.scale, required this.extent});

  /// Facteur à appliquer à la taille de police de la ligne.
  final double scale;

  /// Hauteur à réserver pour la ligne dans la liste.
  final double extent;
}

/// Mesure toujours à la taille de la ligne *chantée* : la hauteur réservée ne
/// dépend donc pas de l'endroit où en est la lecture, et la liste ne sursaute
/// pas quand le surlignage avance.
LyricsLineFit fitLyricsLine(
  String text, {
  required double maxWidth,
  TextScaler textScaler = TextScaler.noScaling,
}) {
  if (maxWidth <= 0) {
    return const LyricsLineFit(scale: 1, extent: _kMinLineExtent);
  }
  final painter = TextPainter(
    textDirection: TextDirection.ltr,
    textAlign: TextAlign.center,
    textScaler: textScaler,
    maxLines: kLyricsMaxLines,
  );
  var scale = 1.0;
  while (true) {
    painter.text = TextSpan(
      text: text,
      style: TextStyle(
        fontSize: kLyricsCurrentFontSize * scale,
        height: kLyricsLineHeight,
      ),
    );
    painter.layout(maxWidth: maxWidth);
    if (!painter.didExceedMaxLines || scale <= _kMinScale) break;
    scale = math.max(_kMinScale, scale - _kScaleStep);
  }
  final height = painter.height;
  painter.dispose();
  return LyricsLineFit(
    scale: scale,
    extent: math.max(_kMinLineExtent, height + _kLinePadding),
  );
}

class _LrcLine {
  const _LrcLine(this.time, this.text);

  final Duration time;
  final String text;
}

/// Paroles : défilement synchronisé si le texte est au format LRC
/// (`[mm:ss.xx] ligne`), sinon affichage statique.
class LyricsView extends ConsumerStatefulWidget {
  const LyricsView({super.key, required this.text, required this.controller});

  final String text;
  final ScrollController controller;

  @override
  ConsumerState<LyricsView> createState() => _LyricsViewState();
}

class _LyricsViewState extends ConsumerState<LyricsView> {
  static final _lrcPattern = RegExp(r'\[(\d+):(\d+(?:\.\d+)?)\]\s*(.*)');

  late final List<_LrcLine> _lines = _parse(widget.text);
  int _lastIndex = -1;

  /// Encombrement de chaque phrase, et haut de chaque phrase dans la liste :
  /// recalculés dès que la largeur (rotation, redimensionnement de la feuille)
  /// ou la taille de police du système change.
  List<LyricsLineFit> _fits = const [];
  List<double> _tops = const [];
  double _fitsWidth = 0;
  TextScaler _fitsScaler = TextScaler.noScaling;

  List<_LrcLine> _parse(String text) {
    final lines = <_LrcLine>[];
    for (final raw in text.split('\n')) {
      final m = _lrcPattern.firstMatch(raw.trim());
      if (m == null) continue;
      final content = m.group(3)!.trim();
      if (content.isEmpty) continue;
      lines.add(
        _LrcLine(
          Duration(
            minutes: int.parse(m.group(1)!),
            milliseconds: (double.parse(m.group(2)!) * 1000).round(),
          ),
          content,
        ),
      );
    }
    lines.sort((a, b) => a.time.compareTo(b.time));
    return lines;
  }

  int _indexFor(Duration position) {
    var index = -1;
    for (var i = 0; i < _lines.length; i++) {
      if (_lines[i].time <= position) {
        index = i;
      } else {
        break;
      }
    }
    return index;
  }

  void _measure(double width, TextScaler scaler) {
    if (width <= 0) return;
    if (width == _fitsWidth && scaler == _fitsScaler && _fits.isNotEmpty) return;
    _fitsWidth = width;
    _fitsScaler = scaler;
    _fits = [
      for (final line in _lines)
        fitLyricsLine(line.text, maxWidth: width, textScaler: scaler),
    ];
    final tops = <double>[];
    var y = _kLyricsVerticalPadding;
    for (final fit in _fits) {
      tops.add(y);
      y += fit.extent;
    }
    _tops = tops;
    // Les hauteurs ont changé : le prochain rendu doit recaler le défilement.
    _lastIndex = -1;
  }

  double _extentAt(int index) =>
      index < _fits.length ? _fits[index].extent : _kMinLineExtent;

  @override
  Widget build(BuildContext context) {
    // Moins de 4 lignes horodatées : traite comme des paroles simples.
    if (_lines.length < 4) {
      return SingleChildScrollView(
        controller: widget.controller,
        padding: const EdgeInsets.all(24),
        child: Text(
          widget.text,
          style: const TextStyle(fontSize: 16, height: 1.6),
        ),
      );
    }

    final scheme = Theme.of(context).colorScheme;
    final scaler = MediaQuery.textScalerOf(context);
    final position = ref.watch(positionProvider).value ?? Duration.zero;
    final current = _indexFor(position);

    return LayoutBuilder(
      builder: (context, constraints) {
        _measure(constraints.maxWidth - _kLyricsHorizontalPadding * 2, scaler);

        if (current != _lastIndex &&
            current >= 0 &&
            current < _tops.length &&
            widget.controller.hasClients) {
          _lastIndex = current;
          final top = _tops[current];
          final extent = _extentAt(current);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!widget.controller.hasClients) return;
            final viewport = widget.controller.position.viewportDimension;
            final target = (top + extent / 2 - viewport / 2)
                .clamp(0.0, widget.controller.position.maxScrollExtent);
            widget.controller.animateTo(
              target,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut,
            );
          });
        }

        return ListView.builder(
          controller: widget.controller,
          itemExtentBuilder: (index, _) => _extentAt(index),
          padding: const EdgeInsets.symmetric(
            vertical: _kLyricsVerticalPadding,
            horizontal: _kLyricsHorizontalPadding,
          ),
          itemCount: _lines.length,
          itemBuilder: (context, i) {
            final isCurrent = i == current;
            final scale = i < _fits.length ? _fits[i].scale : 1.0;
            return InkWell(
              onTap: () => ref.read(playerActionsProvider).seek(_lines[i].time),
              child: Center(
                child: Text(
                  _lines[i].text,
                  maxLines: kLyricsMaxLines,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize:
                        (isCurrent
                            ? kLyricsCurrentFontSize
                            : kLyricsOtherFontSize) *
                        scale,
                    height: kLyricsLineHeight,
                    fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w400,
                    color: isCurrent ? scheme.primary : scheme.onSurfaceVariant,
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
