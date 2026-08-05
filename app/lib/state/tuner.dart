import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../audio/tuner.dart';

/// Le micro de l'accordeur. Remplaçable : les tests injectent une source de
/// fréquences de papier, sans appareil.
final pitchSourceProvider = Provider<PitchSource>((ref) {
  final source = MicPitchSource();
  ref.onDispose(source.dispose);
  return source;
});
