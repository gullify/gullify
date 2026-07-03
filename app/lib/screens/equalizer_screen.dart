import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

import '../state/equalizer.dart';
import '../state/player.dart';

/// Courbes de presets définies sur 5 fréquences pivots (Hz) et interpolées
/// (en échelle log) sur les bandes réelles de l'appareil — leur nombre est
/// imposé par Android.
const _presetFreqs = [60.0, 230.0, 910.0, 3600.0, 14000.0];

const _presets = <String, List<double>>{
  'Plat': [0, 0, 0, 0, 0],
  'Rock': [5, 3, -1, 3, 5],
  'Pop': [-1, 2, 5, 1, -2],
  'Jazz': [4, 2, -2, 2, 5],
  'Classique': [5, 3, -2, 4, 4],
  'Dance': [6, 0, 2, 4, 1],
  'Basses +': [6, 4, 1, 0, 0],
  'Aigus +': [0, 0, 1, 4, 6],
  'Vocal': [-2, 1, 5, 3, -1],
};

double _interpolate(double hz, List<double> curve) {
  final x = math.log(hz);
  final xs = [for (final f in _presetFreqs) math.log(f)];
  if (x <= xs.first) return curve.first;
  if (x >= xs.last) return curve.last;
  for (var i = 0; i < xs.length - 1; i++) {
    if (x <= xs[i + 1]) {
      final t = (x - xs[i]) / (xs[i + 1] - xs[i]);
      return curve[i] + (curve[i + 1] - curve[i]) * t;
    }
  }
  return curve.last;
}

class EqualizerScreen extends ConsumerStatefulWidget {
  const EqualizerScreen({super.key});

  @override
  ConsumerState<EqualizerScreen> createState() => _EqualizerScreenState();
}

class _EqualizerScreenState extends ConsumerState<EqualizerScreen> {
  String? _activePreset;

  Future<void> _applyPreset(
    AndroidEqualizerParameters params,
    String name,
  ) async {
    final curve = _presets[name]!;
    for (final band in params.bands) {
      await band.setGain(
        _interpolate(band.centerFrequency, curve)
            .clamp(params.minDecibels, params.maxDecibels),
      );
    }
    setState(() => _activePreset = name);
    final eq = ref.read(audioHandlerProvider).equalizer;
    await saveEqualizer(
      enabled: eq.enabled,
      gains: [for (final b in params.bands) b.gain],
    );
  }

  @override
  Widget build(BuildContext context) {
    final eq = ref.watch(audioHandlerProvider).equalizer;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Égaliseur')),
      body: FutureBuilder<AndroidEqualizerParameters>(
        future: eq.parameters,
        builder: (context, snap) {
          final params = snap.data;
          if (snap.hasError) {
            return const Center(
              child: Text('Égaliseur non disponible sur cet appareil'),
            );
          }
          if (params == null) {
            return const Center(child: CircularProgressIndicator());
          }
          return Column(
            children: [
              StreamBuilder<bool>(
                stream: eq.enabledStream,
                builder: (context, enabledSnap) {
                  final enabled = enabledSnap.data ?? false;
                  return SwitchListTile(
                    title: const Text("Activer l'égaliseur"),
                    subtitle: Text(
                      '${params.bands.length} bandes',
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                    value: enabled,
                    onChanged: (v) async {
                      await eq.setEnabled(v);
                      await saveEqualizer(
                        enabled: v,
                        gains: [for (final b in params.bands) b.gain],
                      );
                    },
                  );
                },
              ),
              SizedBox(
                height: 48,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  children: [
                    for (final name in _presets.keys)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: ChoiceChip(
                          label: Text(name),
                          selected: _activePreset == name,
                          onSelected: (_) => _applyPreset(params, name),
                        ),
                      ),
                  ],
                ),
              ),
              const Divider(height: 16),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(4, 8, 12, 16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Échelle dB
                      Column(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          for (final label in [
                            '+${params.maxDecibels.round()}',
                            '0',
                            '${params.minDecibels.round()}',
                          ])
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 24,
                              ),
                              child: Text(
                                label,
                                style: TextStyle(
                                  fontSize: 10,
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                        ],
                      ),
                      for (final band in params.bands)
                        Expanded(
                          child: _BandSlider(
                            band: band,
                            min: params.minDecibels,
                            max: params.maxDecibels,
                            onChanged: () {
                              // Réglage manuel : plus aucun preset actif.
                              if (_activePreset != null) {
                                setState(() => _activePreset = null);
                              }
                              saveEqualizer(
                                enabled: eq.enabled,
                                gains: [
                                  for (final b in params.bands) b.gain,
                                ],
                              );
                            },
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _BandSlider extends StatelessWidget {
  const _BandSlider({
    required this.band,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final AndroidEqualizerBand band;
  final double min;
  final double max;
  final VoidCallback onChanged;

  String _freqLabel(double hz) => hz >= 1000
      ? '${(hz / 1000).toStringAsFixed(hz >= 10000 ? 0 : 1)} kHz'
      : '${hz.toStringAsFixed(0)} Hz';

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return StreamBuilder<double>(
      stream: band.gainStream,
      builder: (context, snap) {
        final gain = snap.data ?? band.gain;
        return Column(
          children: [
            Text(
              '${gain >= 0 ? '+' : ''}${gain.toStringAsFixed(1)}',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: gain.abs() > 0.05 ? scheme.primary : scheme.outline,
              ),
            ),
            Expanded(
              child: RotatedBox(
                quarterTurns: -1,
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 3,
                    activeTrackColor: scheme.primary,
                    inactiveTrackColor: scheme.surfaceContainerHighest,
                    thumbShape: const RoundSliderThumbShape(
                      enabledThumbRadius: 8,
                    ),
                  ),
                  child: Slider(
                    value: gain.clamp(min, max),
                    min: min,
                    max: max,
                    onChanged: (v) => band.setGain(v),
                    onChangeEnd: (_) => onChanged(),
                  ),
                ),
              ),
            ),
            Text(
              _freqLabel(band.centerFrequency),
              style: TextStyle(
                fontSize: 10,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        );
      },
    );
  }
}
