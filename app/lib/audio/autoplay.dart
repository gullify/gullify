import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

const _storage = FlutterSecureStorage();
const _kEnabled = 'autoplay_enabled';

/// Lecture automatique (Pour toi) : au bout de la file, la musique continue
/// avec des titres choisis par le serveur d'après ce qui vient de jouer, la
/// séance en cours et le profil de goûts — comme la lecture automatique de
/// Spotify ou le Flow de Deezer. Allumée par défaut ; Paramètres → Lecture.
class Autoplay extends ChangeNotifier {
  bool _enabled = true;
  bool _loaded = false;

  bool get enabled => _enabled;

  /// Combien de titres demander à la fois.
  static const batch = 10;

  /// Quand il ne reste que ce nombre de titres après celui qui joue, on
  /// demande la suite : elle est là bien avant la fin.
  static const remainingTrigger = 1;

  Future<void> loadSaved() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final v = await _storage.read(key: _kEnabled);
      if (v != null) _enabled = v == '1';
    } catch (_) {
      // Illisible : allumée, comme par défaut.
    }
    notifyListeners();
  }

  Future<void> setEnabled(bool value) async {
    _enabled = value;
    _loaded = true;
    notifyListeners();
    try {
      await _storage.write(key: _kEnabled, value: value ? '1' : '0');
    } catch (_) {
      // Un échec d'écriture ne doit jamais remonter à l'interface.
    }
  }
}
