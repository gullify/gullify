import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Sur quel genre d'appareil Gullify s'est ouvert.
///
/// Un seul APK sert le téléphone et le téléviseur : c'est ici qu'on décide
/// laquelle des deux interfaces montrer. La question se pose une fois, au
/// démarrage, avant le premier affichage — basculer d'interface en cours de
/// route ferait perdre l'écran en cours.

const _storage = FlutterSecureStorage();
const _channel = MethodChannel('gullify/device');
const _forceKey = 'tv_force_mode';

/// Ce que le forçage manuel peut valoir. `auto` laisse Android répondre ;
/// les deux autres servent à essayer l'interface TV sur un téléphone (et
/// l'inverse, si jamais un boîtier se déclarait mal).
enum TvForce { auto, tv, handheld }

TvForce _parseForce(String? raw) => switch (raw) {
  'tv' => TvForce.tv,
  'handheld' => TvForce.handheld,
  _ => TvForce.auto,
};

/// Ce qu'Android a répondu au démarrage. Surchargé depuis `main()` : le
/// routeur en a besoin avant de construire quoi que ce soit, et une valeur
/// qui arriverait après coup ferait clignoter l'app d'une interface à l'autre.
final tvDetectedProvider = Provider<bool>(
  (_) =>
      throw StateError('tvDetectedProvider doit être surchargé au démarrage'),
);

/// Le forçage manuel relu au démarrage (surchargé depuis `main()` lui aussi).
final tvForceInitialProvider = Provider<TvForce>((_) => TvForce.auto);

/// Interroge Android puis relit le forçage manuel. Appelé une seule fois, dans
/// `main()`. Ne lève jamais : sans réponse, on reste sur l'interface tactile.
Future<({bool detected, TvForce force})> detectTelevision() async {
  var detected = false;
  try {
    detected = await _channel.invokeMethod<bool>('isTelevision') ?? false;
  } catch (_) {
    // Plateforme sans le canal (tests, iOS, ancien APK) : téléphone.
  }
  var force = TvForce.auto;
  try {
    // Borné : le trousseau Android peut mettre un moment à s'initialiser au
    // tout premier lancement, et rien ne justifie de retarder l'affichage
    // pour un réglage d'essai.
    force = _parseForce(
      await _storage
          .read(key: _forceKey)
          .timeout(const Duration(milliseconds: 1500)),
    );
  } catch (_) {}
  return (detected: detected, force: force);
}

/// L'interface à servir : le forçage manuel s'il y en a un, sinon la réponse
/// d'Android.
class TvMode extends Notifier<bool> {
  late TvForce _force;

  @override
  bool build() {
    _force = ref.read(tvForceInitialProvider);
    return _resolve();
  }

  bool _resolve() => switch (_force) {
    TvForce.tv => true,
    TvForce.handheld => false,
    TvForce.auto => ref.read(tvDetectedProvider),
  };

  TvForce get force => _force;

  /// Vrai quand c'est Android qui a tranché, pas un réglage.
  bool get isAutomatic => _force == TvForce.auto;

  Future<void> setForce(TvForce force) async {
    if (force == _force) return;
    _force = force;
    state = _resolve();
    try {
      await _storage.write(
        key: _forceKey,
        value: force == TvForce.auto ? null : force.name,
      );
    } catch (_) {
      // Réglage d'essai : le perdre au prochain démarrage est sans gravité.
    }
  }
}

final tvModeProvider = NotifierProvider<TvMode, bool>(TvMode.new);
