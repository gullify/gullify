import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

import '../state/equalizer.dart';
import '../state/player.dart';

class EqualizerScreen extends ConsumerWidget {
  const EqualizerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final eq = ref.watch(audioHandlerProvider).equalizer;

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
                    title: const Text('Activer l\'égaliseur'),
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
              const Divider(height: 1),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 16,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final band in params.bands)
                        Expanded(
                          child: _BandSlider(
                            band: band,
                            min: params.minDecibels,
                            max: params.maxDecibels,
                            onChanged: () => saveEqualizer(
                              enabled: eq.enabled,
                              gains: [for (final b in params.bands) b.gain],
                            ),
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

  String _freqLabel(double hz) =>
      hz >= 1000 ? '${(hz / 1000).toStringAsFixed(0)}k' : hz.toStringAsFixed(0);

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<double>(
      stream: band.gainStream,
      builder: (context, snap) {
        final gain = snap.data ?? band.gain;
        return Column(
          children: [
            Text(
              '${gain >= 0 ? '+' : ''}${gain.toStringAsFixed(1)}',
              style: const TextStyle(fontSize: 11),
            ),
            Expanded(
              child: RotatedBox(
                quarterTurns: -1,
                child: Slider(
                  value: gain.clamp(min, max),
                  min: min,
                  max: max,
                  onChanged: (v) => band.setGain(v),
                  onChangeEnd: (_) => onChanged(),
                ),
              ),
            ),
            Text(
              _freqLabel(band.centerFrequency),
              style: const TextStyle(fontSize: 11),
            ),
          ],
        );
      },
    );
  }
}
