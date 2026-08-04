import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// L'égaliseur système n'existe que sur Android.
bool get equalizerSupported => !kIsWeb && Platform.isAndroid;

const _channel = MethodChannel('gullify/equalizer');
const _storage = FlutterSecureStorage();
const _kEnabled = 'gullify_eq_enabled';
const _kGains = 'gullify_eq_gains';

/// Une bande de l'égaliseur : leur nombre et leurs fréquences sont imposés par
/// l'appareil, on ne fait que les lire.
@immutable
class EqualizerBand {
  const EqualizerBand({
    required this.index,
    required this.centerFrequency,
    required this.gain,
  });

  final int index;

  /// Fréquence centrale, en Hz.
  final double centerFrequency;

  /// Gain appliqué, en dB.
  final double gain;

  EqualizerBand withGain(double value) =>
      EqualizerBand(index: index, centerFrequency: centerFrequency, gain: value);
}

@immutable
class EqualizerParameters {
  const EqualizerParameters({
    required this.minDecibels,
    required this.maxDecibels,
    required this.bands,
  });

  factory EqualizerParameters.fromMap(Map<Object?, Object?> map) {
    final rawBands = (map['bands'] as List<Object?>? ?? const []);
    return EqualizerParameters(
      minDecibels: (map['minDecibels'] as num).toDouble(),
      maxDecibels: (map['maxDecibels'] as num).toDouble(),
      bands: [
        for (final raw in rawBands.cast<Map<Object?, Object?>>())
          EqualizerBand(
            index: (raw['index'] as num).toInt(),
            centerFrequency: (raw['centerFrequency'] as num).toDouble(),
            gain: (raw['gain'] as num).toDouble(),
          ),
      ],
    );
  }

  final double minDecibels;
  final double maxDecibels;
  final List<EqualizerBand> bands;

  EqualizerParameters withBandGain(int index, double gain) =>
      EqualizerParameters(
        minDecibels: minDecibels,
        maxDecibels: maxDecibels,
        bands: [
          for (final band in bands)
            band.index == index ? band.withGain(gain) : band,
        ],
      );
}

/// Égaliseur système piloté par nos soins (canal `gullify/equalizer`), hors du
/// lecteur.
///
/// just_audio sait poser un `AndroidEqualizer` dans son `AudioPipeline`, mais
/// il lit les bandes au moment où il ACTIVE le lecteur. Or depuis media3 1.9
/// (tiré par video_player pour l'onglet Vidéos, et qui l'emporte sur le 1.4 de
/// just_audio) ExoPlayer ne génère plus l'identifiant de session audio dans son
/// constructeur mais en tâche de fond : à cet instant just_audio ne voit pas de
/// session, ne crée donc aucun effet, et sa lecture des bandes explose
/// (« Equalizer.getNumberOfBands() on a null object reference »). Cette
/// exception survenait pendant l'activation du lecteur et l'empoisonnait
/// définitivement : plus AUCUNE chanson ne démarrait (idée #47).
///
/// On attache donc l'effet nous-mêmes, une fois la session réellement connue
/// (elle arrive au démarrage de la lecture), et en dehors du pipeline : un
/// égaliseur indisponible ne peut plus couper le son.
class GullifyEqualizer extends ChangeNotifier {
  EqualizerParameters? _parameters;
  bool _enabled = false;
  bool _unavailable = false;
  bool _loaded = false;
  int? _sessionId;
  List<double> _savedGains = const [];

  /// Bandes de l'appareil, connues seulement une fois l'effet attaché.
  EqualizerParameters? get parameters => _parameters;

  bool get enabled => _enabled;

  /// L'appareil a refusé l'effet : aucun réglage possible.
  bool get unavailable => _unavailable;

  /// Aucune session audio pour l'instant : Android ne donne les bandes qu'une
  /// fois la lecture démarrée.
  bool get waitingForPlayback => _parameters == null && !_unavailable;

  /// Relit les réglages mémorisés (au démarrage de l'app).
  Future<void> loadSaved() async {
    if (_loaded) return;
    _loaded = true;
    try {
      _enabled = await _storage.read(key: _kEnabled) == '1';
      final raw = await _storage.read(key: _kGains);
      if (raw != null) {
        _savedGains = [
          for (final gain in jsonDecode(raw) as List<dynamic>)
            (gain as num).toDouble(),
        ];
      }
    } catch (_) {
      // Réglages illisibles : on repart d'un égaliseur neutre.
    }
    notifyListeners();
  }

  /// Attache l'effet à la session audio du lecteur et y rejoue les réglages
  /// mémorisés. Appelé à chaque nouvelle session (une session = un effet).
  Future<void> attachSession(int sessionId) async {
    if (!equalizerSupported || sessionId == 0 || sessionId == _sessionId) {
      return;
    }
    await loadSaved();
    try {
      final map = await _channel.invokeMapMethod<Object?, Object?>('bind', {
        'sessionId': sessionId,
        'enabled': _enabled,
        'gains': _savedGains,
      });
      if (map == null) return;
      _sessionId = sessionId;
      _parameters = EqualizerParameters.fromMap(map);
      _unavailable = false;
    } catch (_) {
      // Effet refusé (appareil sans égaliseur, session déjà prise…) : la
      // lecture continue, seul l'écran de réglage le signalera.
      _unavailable = true;
    }
    notifyListeners();
  }

  /// Bandes injectées sans passer par le canal natif (tests d'écran).
  @visibleForTesting
  void debugAttach(EqualizerParameters params, {bool enabled = false}) {
    _parameters = params;
    _enabled = enabled;
    _loaded = true;
    notifyListeners();
  }

  Future<void> setEnabled(bool value) async {
    _enabled = value;
    notifyListeners();
    try {
      await _channel.invokeMethod<void>('setEnabled', {'enabled': value});
    } catch (_) {
      // Rien à faire : le réglage reste mémorisé pour la prochaine session.
    }
    await save();
  }

  Future<void> setBandGain(int index, double gain) async {
    final params = _parameters;
    if (params == null) return;
    final clamped = gain.clamp(params.minDecibels, params.maxDecibels);
    _parameters = params.withBandGain(index, clamped);
    notifyListeners();
    try {
      await _channel.invokeMethod<void>('setBandGain', {
        'index': index,
        'gain': clamped,
      });
    } catch (_) {
      // Idem : réglage conservé côté app, réappliqué à la prochaine session.
    }
  }

  /// Mémorise les réglages courants (relâchement d'un curseur, preset choisi).
  Future<void> save() async {
    final params = _parameters;
    try {
      await _storage.write(key: _kEnabled, value: _enabled ? '1' : '0');
      if (params != null) {
        _savedGains = [for (final band in params.bands) band.gain];
        await _storage.write(key: _kGains, value: jsonEncode(_savedGains));
      }
    } catch (_) {
      // Un échec d'écriture ne doit jamais remonter à l'interface.
    }
  }
}
