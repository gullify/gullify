import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Verrou réseau (WifiLock HIGH_PERF + WakeLock partiel) tenu par le code natif
/// pendant la lecture. Sans lui, écran éteint la radio Wi-Fi passe en power-save
/// et le flux cale (« mise en tampon ») jusqu'au réveil — c'est le comportement
/// que just_audio n'active pas (aucun WAKE_MODE sur ExoPlayer). On l'acquiert
/// sur ▶ et on le relâche sur ⏸/stop depuis l'AudioHandler.
const _channel = MethodChannel('gullify/netlock');

Future<void> acquireNetworkLock() => _set('acquire');
Future<void> releaseNetworkLock() => _set('release');

Future<void> _set(String method) async {
  if (kIsWeb || !Platform.isAndroid) return;
  try {
    await _channel.invokeMethod<void>(method);
  } catch (_) {
    // Un échec de verrou ne doit jamais casser la lecture.
  }
}
