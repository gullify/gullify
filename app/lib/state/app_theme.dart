import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../theme.dart';

const _storage = FlutterSecureStorage();
const _kThemeStyle = 'theme_style';

/// Style visuel choisi par l'utilisateur, persisté entre les sessions.
/// Défaut : Audiophile (l'identité sombre historique de Gullify).
final themeStyleProvider = NotifierProvider<ThemeStyleNotifier, GullifyStyle>(
  ThemeStyleNotifier.new,
);

class ThemeStyleNotifier extends Notifier<GullifyStyle> {
  @override
  GullifyStyle build() {
    _restore();
    return GullifyStyle.audiophile;
  }

  Future<void> _restore() async {
    try {
      final raw = await _storage.read(key: _kThemeStyle);
      if (raw == null) return;
      state = GullifyStyle.values.firstWhere(
        (s) => s.name == raw,
        orElse: () => GullifyStyle.audiophile,
      );
    } catch (_) {
      // Meilleur effort : on garde le défaut.
    }
  }

  Future<void> set(GullifyStyle style) async {
    state = style;
    await _storage.write(key: _kThemeStyle, value: style.name);
  }
}
