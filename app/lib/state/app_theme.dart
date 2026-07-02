import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

const _storage = FlutterSecureStorage();
const _kThemeMode = 'theme_mode';

/// Mode de thème choisi par l'utilisateur, persisté entre les sessions.
/// Défaut : sombre (l'identité « audiophile » historique de Gullify).
final themeModeProvider = NotifierProvider<ThemeModeNotifier, ThemeMode>(
  ThemeModeNotifier.new,
);

class ThemeModeNotifier extends Notifier<ThemeMode> {
  @override
  ThemeMode build() {
    _restore();
    return ThemeMode.dark;
  }

  Future<void> _restore() async {
    final raw = await _storage.read(key: _kThemeMode);
    if (raw == null) return;
    state = ThemeMode.values.firstWhere(
      (m) => m.name == raw,
      orElse: () => ThemeMode.dark,
    );
  }

  Future<void> set(ThemeMode mode) async {
    state = mode;
    await _storage.write(key: _kThemeMode, value: mode.name);
  }
}
