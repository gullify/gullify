import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:permission_handler/permission_handler.dart';

const _storage = FlutterSecureStorage();
const _kAsked = 'battery_opt_asked';

/// L'exemption d'optimisation de batterie est-elle accordée ?
/// Sans elle, Android coupe le réseau en sommeil profond → le flux s'arrête
/// écran éteint et ne reprend qu'au déverrouillage.
Future<bool> backgroundPlaybackOk() async {
  if (kIsWeb || !Platform.isAndroid) return true;
  return Permission.ignoreBatteryOptimizations.isGranted;
}

/// Ouvre la demande système d'exemption (+ notifications sur Android 13+).
Future<bool> requestBackgroundPlayback() async {
  if (kIsWeb || !Platform.isAndroid) return true;
  await Permission.notification.request();
  final status = await Permission.ignoreBatteryOptimizations.request();
  return status.isGranted;
}

/// Au premier lancement : explique puis demande, une seule fois.
/// (Reste réactivable depuis Paramètres → Lecture en arrière-plan.)
Future<void> maybePromptBackgroundPlayback(BuildContext context) async {
  if (kIsWeb || !Platform.isAndroid) return;
  if (await backgroundPlaybackOk()) return;
  String? asked;
  try {
    asked = await _storage.read(key: _kAsked);
  } catch (_) {
    return;
  }
  if (asked == '1' || !context.mounted) return;
  await _storage.write(key: _kAsked, value: '1');

  if (!context.mounted) return;
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Lecture écran éteint'),
      content: const Text(
        "Pour que la musique continue quand l'écran est éteint, "
        'Android doit exempter Gullify de l\'optimisation de batterie. '
        'Sans cela, le flux est coupé après quelques minutes de veille.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Plus tard'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Autoriser'),
        ),
      ],
    ),
  );
  if (ok == true) await requestBackgroundPlayback();
}
