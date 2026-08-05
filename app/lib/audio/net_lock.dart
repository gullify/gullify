import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Verrou réseau (WifiLock HIGH_PERF + WakeLock partiel) tenu par le code natif
/// pendant la lecture. Sans lui, écran éteint la radio Wi-Fi passe en power-save
/// et le flux cale (« mise en tampon ») jusqu'au réveil — c'est le comportement
/// que just_audio n'active pas (aucun WAKE_MODE sur ExoPlayer). Chaque lecteur
/// de l'app en prend une [NetworkLockHold] pendant qu'il joue (voir
/// tuned_player.dart).
const _channel = MethodChannel('gullify/netlock');

/// Combien de lecteurs tiennent le verrou en ce moment. Le verrou natif est
/// unique pour toute l'app : sans ce compte, une pré-écoute qui se tait
/// relâcherait aussi celui du lecteur principal.
int _holders = 0;

@visibleForTesting
int get networkLockHolders => _holders;

@visibleForTesting
void resetNetworkLockForTest() => _holders = 0;

/// La prise d'un lecteur sur le verrou réseau. On lui dit l'état voulu (« je
/// joue » / « je ne joue plus ») autant de fois qu'on veut : elle ne fait le
/// voyage natif que quand le premier lecteur démarre et quand le dernier
/// s'arrête.
class NetworkLockHold {
  bool _held = false;

  bool get held => _held;

  void hold(bool on) {
    if (_held == on) return;
    _held = on;
    _holders += on ? 1 : -1;
    if (on && _holders == 1) {
      _set('acquire');
    } else if (!on && _holders == 0) {
      _set('release');
    }
  }
}

Future<void> _set(String method) async {
  if (kIsWeb || !Platform.isAndroid) return;
  try {
    await _channel.invokeMethod<void>(method);
  } catch (_) {
    // Un échec de verrou ne doit jamais casser la lecture.
  }
}
