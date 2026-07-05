import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../theme.dart';

const _storage = FlutterSecureStorage();
const _kAccent = 'theme_accent';
const _kMode = 'theme_mode';

/// Couleur d'accent choisie (structure de verre inchangée). Défaut : indigo.
final accentColorProvider =
    NotifierProvider<AccentNotifier, GullifyAccent>(AccentNotifier.new);

class AccentNotifier extends Notifier<GullifyAccent> {
  @override
  GullifyAccent build() {
    _restore();
    return GullifyAccent.indigo;
  }

  Future<void> _restore() async {
    try {
      final raw = await _storage.read(key: _kAccent);
      if (raw == null) return;
      state = GullifyAccent.values.firstWhere(
        (a) => a.name == raw,
        orElse: () => GullifyAccent.indigo,
      );
    } catch (_) {}
  }

  Future<void> set(GullifyAccent accent) async {
    state = accent;
    await _storage.write(key: _kAccent, value: accent.name);
  }
}

/// Base claire / sombre / système. Défaut : système.
final themeModeProvider =
    NotifierProvider<ThemeModeNotifier, ThemeMode>(ThemeModeNotifier.new);

class ThemeModeNotifier extends Notifier<ThemeMode> {
  @override
  ThemeMode build() {
    _restore();
    return ThemeMode.system;
  }

  Future<void> _restore() async {
    try {
      final raw = await _storage.read(key: _kMode);
      if (raw == null) return;
      state = ThemeMode.values.firstWhere(
        (m) => m.name == raw,
        orElse: () => ThemeMode.system,
      );
    } catch (_) {}
  }

  Future<void> set(ThemeMode mode) async {
    state = mode;
    await _storage.write(key: _kMode, value: mode.name);
  }
}
