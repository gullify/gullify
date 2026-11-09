import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

const _storage = FlutterSecureStorage();
const _kKey = 'player_keep_screen_on';

/// « Garder l'écran allumé » dans le lecteur (comme le mode cuisine de
/// GulliEATS) : le choix est retenu d'une ouverture à l'autre, et ne vaut que
/// tant que le lecteur est affiché.
final keepScreenOnProvider = NotifierProvider<KeepScreenOn, bool>(
  KeepScreenOn.new,
);

class KeepScreenOn extends Notifier<bool> {
  @override
  bool build() {
    unawaited(_load());
    return false;
  }

  Future<void> _load() async {
    try {
      final v = await _storage.read(key: _kKey);
      if (v == '1') state = true;
    } catch (_) {}
  }

  Future<void> toggle() async {
    state = !state;
    try {
      await _storage.write(key: _kKey, value: state ? '1' : '0');
    } catch (_) {}
  }
}

/// Vrai tant qu'un lecteur ouvert tient l'écran allumé. L'accordeur, qui
/// s'ouvre par-dessus le lecteur, le relit en se fermant pour ne pas éteindre
/// ce que le lecteur a demandé.
bool playerHoldsScreen = false;

void applyWakelock(bool on) {
  unawaited(WakelockPlus.toggle(enable: on).catchError((Object _) {}));
}

/// Posé dans le lecteur : allume ou relâche l'écran selon le réglage, et le
/// relâche toujours quand le lecteur se ferme.
class KeepScreenOnScope extends ConsumerStatefulWidget {
  const KeepScreenOnScope({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<KeepScreenOnScope> createState() => _KeepScreenOnScopeState();
}

class _KeepScreenOnScopeState extends ConsumerState<KeepScreenOnScope> {
  @override
  void initState() {
    super.initState();
    _apply(ref.read(keepScreenOnProvider));
  }

  void _apply(bool on) {
    playerHoldsScreen = on;
    applyWakelock(on);
  }

  @override
  void dispose() {
    if (playerHoldsScreen) _apply(false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<bool>(keepScreenOnProvider, (_, on) => _apply(on));
    return widget.child;
  }
}
