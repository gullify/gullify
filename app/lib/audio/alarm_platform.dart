import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Le réveil, côté système (idée #81).
///
/// La programmation ne peut pas vivre dans Dart : l'app est fermée à 7 h du
/// matin. C'est une alarme exacte Android qui réveille le téléphone, puis
/// ouvre l'app — voir `GullifyAlarm.kt`. Ici, seulement le fil qui les relie.
///
/// Tout est protégé : sur un appareil sans le canal (tests, plateforme non
/// Android), chaque appel ne fait rien plutôt que de faire remonter une
/// MissingPluginException dans un écran de réglage.
const _channel = MethodChannel('gullify/alarm');

/// Le réveil n'existe que sur Android — nulle part ailleurs on ne peut
/// promettre qu'il sonnera l'app fermée.
bool get alarmSupported => !kIsWeb && Platform.isAndroid;

Future<T?> _call<T>(String method, [Map<String, dynamic>? args]) async {
  if (!alarmSupported) return null;
  try {
    return await _channel.invokeMethod<T>(method, args);
  } catch (_) {
    return null;
  }
}

/// Programme (ou retire) le réveil. Renvoie l'heure de la prochaine sonnerie.
Future<DateTime?> alarmConfigure({
  required bool enabled,
  required int hour,
  required int minute,
  required int daysMask,
}) async {
  final at = await _call<int>('configure', {
    'enabled': enabled,
    'hour': hour,
    'minute': minute,
    'days': daysMask,
  });
  return (at == null || at == 0)
      ? null
      : DateTime.fromMillisecondsSinceEpoch(at);
}

/// Pose une sonnerie à une heure précise : le rappel (« encore 9 minutes »)
/// et l'essai à une minute d'ici.
Future<void> alarmArmAt(DateTime at) =>
    _call<bool>('armAt', {'at': at.millisecondsSinceEpoch});

Future<void> alarmCancel() => _call<bool>('cancel');

Future<DateTime?> alarmNextRing() async {
  final at = await _call<int>('nextRing');
  return (at == null || at == 0)
      ? null
      : DateTime.fromMillisecondsSinceEpoch(at);
}

/// Une sonnerie qui a retenti et que l'app n'a pas encore reprise (elle était
/// fermée, ou la notification n'a été touchée que plus tard).
Future<DateTime?> alarmPendingRing() async {
  final at = await _call<int>('pendingRing');
  return (at == null || at == 0)
      ? null
      : DateTime.fromMillisecondsSinceEpoch(at);
}

/// « J'ai pris le relais » : coupe le filet audible et la notification.
Future<void> alarmHandled() => _call<bool>('handled');

/// L'alarme exacte est-elle permise ? Sans elle, Android a le droit de
/// décaler la sonnerie de plusieurs minutes.
Future<bool> alarmCanRingExactly() async =>
    await _call<bool>('canRingExactly') ?? false;

Future<void> alarmRequestExactPermission() =>
    _call<bool>('requestExactPermission');

/// Monte le volume média au niveau réglé (et retient celui d'avant).
Future<void> alarmSetVolume(int percent) =>
    _call<bool>('setMediaVolume', {'percent': percent});

/// Remet le volume média tel qu'il était avant la sonnerie.
Future<void> alarmRestoreVolume() => _call<bool>('restoreMediaVolume');

/// Vrai si l'app vient d'être ouverte PAR le réveil (démarrage à froid). Le
/// drapeau ne se lit qu'une fois.
Future<bool> alarmLaunchedApp() async =>
    await _call<bool>('launchedByAlarm') ?? false;

/// Prévenu quand le réveil sonne alors que l'app tournait déjà.
void alarmOnRing(void Function() onRing) {
  if (!alarmSupported) return;
  try {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'ring') onRing();
      return null;
    });
  } catch (_) {}
}
