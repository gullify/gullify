import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../audio/audio_handler.dart';

export '../audio/audio_handler.dart' show equalizerSupported;

const _storage = FlutterSecureStorage();
const _kEnabled = 'gullify_eq_enabled';
const _kGains = 'gullify_eq_gains';

/// Re-apply the persisted equalizer settings (called once at startup).
Future<void> applySavedEqualizer(GullifyAudioHandler handler) async {
  if (!equalizerSupported) return;
  try {
    final eq = handler.equalizer;
    await eq.setEnabled(await _storage.read(key: _kEnabled) == '1');
    final raw = await _storage.read(key: _kGains);
    if (raw == null) return;
    final gains = (jsonDecode(raw) as List<dynamic>).cast<num>();
    final params = await eq.parameters;
    for (var i = 0; i < params.bands.length && i < gains.length; i++) {
      await params.bands[i].setGain(
        gains[i].toDouble().clamp(params.minDecibels, params.maxDecibels),
      );
    }
  } catch (_) {
    // EQ is best-effort; never block startup.
  }
}

Future<void> saveEqualizer({
  required bool enabled,
  required List<double> gains,
}) async {
  await _storage.write(key: _kEnabled, value: enabled ? '1' : '0');
  await _storage.write(key: _kGains, value: jsonEncode(gains));
}
