import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../audio/tuner.dart';
import '../state/player.dart';
import '../state/tuner.dart';

/// Accordeur de guitare (idée #62), ouvert depuis la feuille des accords.
///
/// La musique se met en pause le temps de l'accordage : le micro entendrait le
/// haut-parleur avant la corde.
Future<void> showTunerSheet(BuildContext context, {String? tuning}) {
  final container = ProviderScope.containerOf(context, listen: false);
  final paused = _pauseMusic(container);
  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    builder: (context) => _TunerSheet(tuning: tuning, pausedMusic: paused),
  ).whenComplete(() {
    if (paused) _resumeMusic(container);
  });
}

/// Met la lecture en pause, et dit si c'est bien nous qui l'avons fait (rien à
/// reprendre si elle était déjà arrêtée). Sans lecteur — dans un test, sur un
/// écran ouvert avant l'audio — on ne touche à rien.
bool _pauseMusic(ProviderContainer container) {
  try {
    if (container.read(playbackStateProvider).value?.playing != true) {
      return false;
    }
    unawaited(container.read(playerActionsProvider).togglePlayPause());
    return true;
  } catch (_) {
    return false;
  }
}

void _resumeMusic(ProviderContainer container) {
  try {
    if (container.read(playbackStateProvider).value?.playing == true) return;
    unawaited(container.read(playerActionsProvider).togglePlayPause());
  } catch (_) {}
}

class _TunerSheet extends ConsumerStatefulWidget {
  const _TunerSheet({required this.tuning, required this.pausedMusic});

  /// L'accordage annoncé par la grille d'accords (« E A D G B E »), s'il y en a.
  final String? tuning;

  /// La musique a été mise en pause pour nous.
  final bool pausedMusic;

  @override
  ConsumerState<_TunerSheet> createState() => _TunerSheetState();
}

class _TunerSheetState extends ConsumerState<_TunerSheet> {
  late GuitarTuning _tuning =
      tuningFromLabel(widget.tuning) ?? standardTuning;

  final PitchTracker _tracker = PitchTracker();
  late final PitchSource _source = ref.read(pitchSourceProvider);
  StreamSubscription<double?>? _sub;
  TunerReading? _reading;
  bool _listening = false;
  String? _problem;

  @override
  void initState() {
    super.initState();
    _listen();
  }

  @override
  void dispose() {
    _sub?.cancel();
    // La source vit dans un provider (partagé, remplaçable en test) : on la
    // referme plutôt que de la laisser tenir le micro après la fermeture.
    unawaited(_source.stop());
    _keepScreenOn(false);
    super.dispose();
  }

  /// Accorder, c'est fixer l'écran sans le toucher : sans ça il s'éteint au
  /// milieu, et le micro avec.
  void _keepScreenOn(bool on) {
    unawaited(WakelockPlus.toggle(enable: on).catchError((Object _) {}));
  }

  Future<void> _listen() async {
    setState(() => _problem = null);
    final source = _source;

    if (!await source.ensurePermission()) {
      if (mounted) {
        setState(() => _problem = 'Micro refusé — autorise-le dans les réglages');
      }
      return;
    }

    Stream<double?> stream;
    try {
      stream = await source.start();
    } catch (_) {
      if (mounted) setState(() => _problem = 'Micro indisponible');
      return;
    }
    if (!mounted) {
      await source.stop();
      return;
    }

    setState(() => _listening = true);
    _keepScreenOn(true);
    _sub = stream.listen(
      (hz) {
        final held = _tracker.add(hz);
        if (!mounted) return;
        setState(() {
          _reading = held == null ? null : readingFor(held, _tuning);
        });
      },
      onError: (_) {
        if (mounted) {
          setState(() {
            _listening = false;
            _problem = 'Micro interrompu';
          });
        }
      },
    );
  }

  void _setTuning(GuitarTuning tuning) {
    setState(() {
      _tuning = tuning;
      final hz = _tracker.value;
      _reading = hz == null ? null : readingFor(hz, tuning);
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final reading = _reading;
    final insets = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: insets),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: scheme.onSurfaceVariant.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                'Accordeur',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                widget.pausedMusic
                    ? 'Lecture en pause le temps d\'accorder'
                    : 'Joue une corde, le micro écoute',
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 8),
              if (_problem != null)
                _Problem(message: _problem!, onRetry: _listen)
              else
                _Gauge(reading: reading, listening: _listening),
              const SizedBox(height: 12),
              _Strings(
                tuning: _tuning,
                reading: reading,
              ),
              const SizedBox(height: 16),
              _TuningPicker(tuning: _tuning, onChanged: _setTuning),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}

class _Problem extends StatelessWidget {
  const _Problem({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 28, 32, 12),
      child: Column(
        children: [
          Icon(Icons.mic_off, size: 36, color: scheme.onSurfaceVariant),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          TextButton(onPressed: onRetry, child: const Text('Réessayer')),
        ],
      ),
    );
  }
}

/// Le cadran : la note au centre, l'aiguille sur l'écart en cents.
class _Gauge extends StatelessWidget {
  const _Gauge({required this.reading, required this.listening});

  final TunerReading? reading;
  final bool listening;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final reading = this.reading;
    // Vert seulement quand c'est une corde de l'accordage qui est juste : une
    // note tombée pile mais étrangère à l'accordage n'est pas une bonne
    // nouvelle.
    final tuned = reading != null && reading.stringIndex != null && reading.inTune;
    final accent = tuned ? const Color(0xFF10B981) : scheme.primary;

    return Column(
      children: [
        SizedBox(
          width: 260,
          height: 148,
          child: Stack(
            alignment: Alignment.bottomCenter,
            children: [
              TweenAnimationBuilder<double>(
                // L'aiguille glisse au lieu de sauter d'une mesure à l'autre.
                duration: const Duration(milliseconds: 140),
                curve: Curves.easeOut,
                tween: Tween(
                  end: (reading?.cents ?? 0).clamp(-50.0, 50.0),
                ),
                builder: (context, cents, _) => CustomPaint(
                  size: const Size(260, 148),
                  painter: _GaugePainter(
                    cents: cents,
                    active: reading != null,
                    needle: accent,
                    dial: scheme.onSurface.withValues(alpha: 0.18),
                    tick: scheme.onSurfaceVariant,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      reading == null ? '—' : reading.name,
                      style: TextStyle(
                        fontSize: 46,
                        height: 1,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -1,
                        color: reading == null ? scheme.onSurfaceVariant : accent,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      reading == null
                          ? (listening ? 'À l\'écoute…' : 'Micro éteint')
                          : '${frenchNoteName(reading.midi)} '
                              '${reading.octave} · '
                              '${reading.frequency.toStringAsFixed(1)} Hz',
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Text(
          switch (reading) {
            null => 'Joue une corde à vide',
            final r when r.stringIndex == null =>
              'Aucune corde de cet accordage',
            final r when r.inTune => 'Juste !',
            final r when r.cents < 0 => 'Trop grave — tends la corde',
            _ => 'Trop aigu — détends la corde',
          },
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: tuned ? const Color(0xFF10B981) : scheme.onSurface,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          reading == null
              ? ''
              : '${reading.cents > 0 ? '+' : ''}'
                  '${reading.cents.round()} cents',
          style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

class _GaugePainter extends CustomPainter {
  const _GaugePainter({
    required this.cents,
    required this.active,
    required this.needle,
    required this.dial,
    required this.tick,
  });

  final double cents;
  final bool active;
  final Color needle;
  final Color dial;
  final Color tick;

  /// Ouverture du cadran : ±50 cents occupent ±60°.
  static const _sweep = math.pi / 3;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height - 8);
    final radius = size.height - 24;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2 - _sweep,
      _sweep * 2,
      false,
      Paint()
        ..color = dial
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round,
    );

    // Graduations tous les 10 cents, la médiane plus marquée : c'est elle qu'on
    // vise.
    for (var value = -50; value <= 50; value += 10) {
      final angle = -math.pi / 2 + _sweep * value / 50;
      final middle = value == 0;
      final inner = radius - (middle ? 16 : 9);
      final direction = Offset(math.cos(angle), math.sin(angle));
      canvas.drawLine(
        center + direction * inner,
        center + direction * radius,
        Paint()
          ..color = middle ? tick : tick.withValues(alpha: 0.5)
          ..strokeWidth = middle ? 3 : 1.5
          ..strokeCap = StrokeCap.round,
      );
    }

    if (!active) return;

    final angle = -math.pi / 2 + _sweep * cents.clamp(-50, 50) / 50;
    final direction = Offset(math.cos(angle), math.sin(angle));
    canvas.drawLine(
      center + direction * 18,
      center + direction * (radius - 4),
      Paint()
        ..color = needle
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(center, 6, Paint()..color = needle);
  }

  @override
  bool shouldRepaint(_GaugePainter old) =>
      old.cents != cents || old.active != active || old.needle != needle;
}

/// Les six cordes de l'accordage : celle qu'on entend s'allume, et passe au
/// vert quand elle est juste.
class _Strings extends StatelessWidget {
  const _Strings({required this.tuning, required this.reading});

  final GuitarTuning tuning;
  final TunerReading? reading;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < tuning.midi.length; i++)
            Builder(
              builder: (context) {
                final active = reading?.stringIndex == i;
                final tuned = active && reading!.inTune;
                final color = tuned
                    ? const Color(0xFF10B981)
                    : (active ? scheme.primary : scheme.onSurfaceVariant);
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        width: 44,
                        height: 44,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: active
                              ? color.withValues(alpha: 0.16)
                              : scheme.surfaceContainerHighest
                                  .withValues(alpha: 0.6),
                          border: Border.all(
                            color: active
                                ? color
                                : scheme.outlineVariant.withValues(alpha: 0.6),
                            width: active ? 2 : 1,
                          ),
                        ),
                        child: Text(
                          noteName(tuning.midi[i]),
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: active ? color : scheme.onSurface,
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        // La 6e corde est la plus grave : elle est à gauche.
                        '${tuning.midi.length - i}',
                        style: TextStyle(
                          fontSize: 10,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}

class _TuningPicker extends StatefulWidget {
  const _TuningPicker({required this.tuning, required this.onChanged});

  final GuitarTuning tuning;
  final ValueChanged<GuitarTuning> onChanged;

  @override
  State<_TuningPicker> createState() => _TuningPickerState();
}

class _TuningPickerState extends State<_TuningPicker> {
  final GlobalKey _selected = GlobalKey();

  @override
  void initState() {
    super.initState();
    // La grille peut demander un accordage rare, tout au bout de la liste :
    // on l'amène sous les yeux plutôt que de laisser croire au standard.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final context = _selected.currentContext;
      if (context != null) Scrollable.ensureVisible(context, alignment: 0.5);
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 40,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            for (final option in guitarTunings)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Builder(
                  builder: (context) {
                    final selected = option.name == widget.tuning.name;
                    return ChoiceChip(
                      key: selected ? _selected : null,
                      selected: selected,
                      onSelected: (_) => widget.onChanged(option),
                      label: Text(option.name),
                      labelStyle: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: selected ? scheme.onPrimary : scheme.onSurface,
                      ),
                      selectedColor: scheme.primary,
                      showCheckmark: false,
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
