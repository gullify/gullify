import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:record/record.dart';

/// Accordeur de guitare (idée #62) : le micro écoute la corde, l'algorithme YIN
/// en tire la fréquence, et on la compare à la corde la plus proche de
/// l'accordage choisi.
///
/// Tout ce qui décide (détection, note visée, lissage) est du calcul pur, sans
/// micro ni widget : c'est ce qui permet de le tester sur des sinus fabriqués.

// ──────────────────────────────────────────────────────────────── notes ──

const _noteNames = [
  'C',
  'C#',
  'D',
  'D#',
  'E',
  'F',
  'F#',
  'G',
  'G#',
  'A',
  'A#',
  'B',
];

const _frenchNames = {
  'C': 'Do',
  'D': 'Ré',
  'E': 'Mi',
  'F': 'Fa',
  'G': 'Sol',
  'A': 'La',
  'B': 'Si',
};

/// Fréquence d'une note MIDI (69 = La 440).
double frequencyOfMidi(num midi) =>
    440 * math.pow(2, (midi - 69) / 12).toDouble();

/// Nom anglais d'une note MIDI, en dièses — la notation des grilles d'accords.
String noteName(int midi) => _noteNames[midi % 12];

/// Nom français ('Mi', 'Sol♯') : le solfège de ceux qui n'ont pas appris les
/// lettres.
String frenchNoteName(int midi) {
  final name = noteName(midi);
  final base = _frenchNames[name[0]]!;
  return name.length > 1 ? '$base♯' : base;
}

/// Octave à l'anglaise (La 440 = A4).
int octaveOfMidi(int midi) => midi ~/ 12 - 1;

/// Écart en cents entre une fréquence et une note MIDI (100 cents = 1 demi-ton).
double centsBetween(double hz, num midi) =>
    1200 * math.log(hz / frequencyOfMidi(midi)) / math.ln2;

/// La note MIDI la plus proche d'une fréquence.
int midiOfFrequency(double hz) =>
    (69 + 12 * math.log(hz / 440) / math.ln2).round();

// ───────────────────────────────────────────────────────────── accordages ──

/// Un accordage : ses six cordes, de la plus grave (6e) à la plus aiguë (1re).
class GuitarTuning {
  const GuitarTuning(this.name, this.midi);

  final String name;
  final List<int> midi;

  /// Les cordes écrites comme sur les grilles : « E A D G B E ».
  String get labels => midi.map(noteName).join(' ');
}

/// L'accordage par défaut, celui de presque toutes les grilles.
const standardTuning = GuitarTuning('Standard', [40, 45, 50, 55, 59, 64]);

/// Les accordages proposés, du plus courant au plus rare.
const guitarTunings = [
  standardTuning,
  GuitarTuning('Demi-ton plus bas', [39, 44, 49, 54, 58, 63]),
  GuitarTuning('Ton plus bas', [38, 43, 48, 53, 57, 62]),
  GuitarTuning('Drop D', [38, 45, 50, 55, 59, 64]),
  GuitarTuning('Drop C', [36, 43, 48, 53, 57, 62]),
  GuitarTuning('DADGAD', [38, 45, 50, 55, 57, 62]),
  GuitarTuning('Open G', [38, 43, 50, 55, 59, 62]),
  GuitarTuning('Open D', [38, 45, 50, 54, 57, 62]),
];

/// Les classes de note d'un accordage écrit (« E A D G B E », « Eb Ab Db… »).
/// `null` si ce n'est pas une suite de six notes.
List<int>? parseTuningLabel(String label) {
  final tokens = label
      .split(RegExp(r'[\s,|/-]+'))
      .where((t) => t.isNotEmpty)
      .toList();
  if (tokens.length != 6) return null;

  final classes = <int>[];
  for (final token in tokens) {
    final match = RegExp(r'^([A-Ga-g])([#♯b♭]?)$').firstMatch(token);
    if (match == null) return null;
    final letter = _noteNames.indexOf(match.group(1)!.toUpperCase());
    final accidental = switch (match.group(2)) {
      '#' || '♯' => 1,
      'b' || '♭' => -1,
      _ => 0,
    };
    classes.add((letter + accidental + 12) % 12);
  }
  return classes;
}

/// L'accordage connu qui correspond à celui annoncé par la grille d'accords.
/// On ne compare que les classes de note : Ultimate-Guitar n'écrit pas les
/// octaves, et une guitare n'a de toute façon qu'une façon de les monter.
GuitarTuning? tuningFromLabel(String? label) {
  if (label == null) return null;
  final classes = parseTuningLabel(label);
  if (classes == null) return null;
  for (final tuning in guitarTunings) {
    var same = true;
    for (var i = 0; i < 6; i++) {
      if (tuning.midi[i] % 12 != classes[i]) {
        same = false;
        break;
      }
    }
    if (same) return tuning;
  }
  return null;
}

// ─────────────────────────────────────────────────────────────── lecture ──

/// Ce que l'accordeur affiche à un instant donné.
class TunerReading {
  const TunerReading({
    required this.frequency,
    required this.midi,
    required this.cents,
    required this.stringIndex,
  });

  /// La fréquence entendue, en hertz.
  final double frequency;

  /// La note visée : celle de la corde qu'on tend, ou à défaut la note la plus
  /// proche de ce qu'on entend.
  final int midi;

  /// L'écart à cette note, en cents (négatif = trop grave).
  final double cents;

  /// La corde visée dans l'accordage (0 = 6e corde, la plus grave), ou `null`
  /// si la note jouée n'est celle d'aucune corde.
  final int? stringIndex;

  /// La tolérance d'un accordeur d'appareil : au-delà, l'oreille entend battre.
  bool get inTune => cents.abs() <= 5;

  String get name => noteName(midi);
  int get octave => octaveOfMidi(midi);
}

/// Rapporte une fréquence à l'accordage.
///
/// La référence est la corde qu'on est en train de tendre — pas la note la plus
/// proche : une corde à un demi-ton du compte doit montrer qu'elle est basse,
/// pas se faire renommer. Au-delà d'un demi-ton et demi, c'est qu'on joue autre
/// chose : l'accordeur retombe alors en chromatique, sans désigner de corde.
TunerReading readingFor(double hz, GuitarTuning tuning) {
  var closest = 0;
  var best = double.infinity;
  for (var i = 0; i < tuning.midi.length; i++) {
    final distance = centsBetween(hz, tuning.midi[i]).abs();
    if (distance < best) {
      best = distance;
      closest = i;
    }
  }

  final onString = best <= 150;
  final midi = onString ? tuning.midi[closest] : midiOfFrequency(hz);
  return TunerReading(
    frequency: hz,
    midi: midi,
    cents: centsBetween(hz, midi),
    stringIndex: onString ? closest : null,
  );
}

// ───────────────────────────────────────────────────────────── détection ──

/// Cherche la hauteur d'un extrait de son par l'algorithme YIN.
///
/// Une corde de guitare a des harmoniques bien plus fortes que sa fondamentale :
/// une simple recherche du pic spectral se tromperait d'octave. YIN travaille
/// sur l'auto-différence du signal, ce qui donne la vraie période.
///
/// Rend `null` quand rien n'est joué (trop faible) ou quand le son n'est pas
/// assez périodique pour qu'on s'engage (voix, bruit, deux cordes ensemble).
double? detectPitch(
  List<double> samples,
  int sampleRate, {
  double minHz = 60,
  double maxHz = 1300,
  double threshold = 0.15,
  double minRms = 0.006,
}) {
  final size = samples.length;
  final tauMax = math.min(size ~/ 2, (sampleRate / minHz).ceil());
  final tauMin = math.max(2, (sampleRate / maxHz).floor());
  if (tauMax <= tauMin) return null;

  // Le continu du micro (offset de l'ampli) fausse l'auto-différence : on
  // centre le signal avant tout.
  var mean = 0.0;
  for (final value in samples) {
    mean += value;
  }
  mean /= size;

  final signal = Float64List(size);
  var energy = 0.0;
  for (var i = 0; i < size; i++) {
    final value = samples[i] - mean;
    signal[i] = value;
    energy += value * value;
  }
  if (math.sqrt(energy / size) < minRms) return null;

  final window = size - tauMax;
  if (window < tauMax) return null;

  final yin = Float64List(tauMax + 1);
  for (var tau = 1; tau <= tauMax; tau++) {
    var sum = 0.0;
    for (var i = 0; i < window; i++) {
      final delta = signal[i] - signal[i + tau];
      sum += delta * delta;
    }
    yin[tau] = sum;
  }

  // Normalisation cumulative : sans elle, tau = 0 gagnerait toujours.
  yin[0] = 1;
  var running = 0.0;
  for (var tau = 1; tau <= tauMax; tau++) {
    running += yin[tau];
    yin[tau] = running == 0 ? 1 : yin[tau] * tau / running;
  }

  // Le premier creux sous le seuil, pas le plus profond : c'est ce qui évite de
  // répondre une octave trop bas quand la période double marche aussi bien.
  var best = -1;
  for (var tau = tauMin; tau <= tauMax; tau++) {
    if (yin[tau] < threshold) {
      while (tau + 1 <= tauMax && yin[tau + 1] < yin[tau]) {
        tau++;
      }
      best = tau;
      break;
    }
  }
  if (best < 0) return null;

  // Interpolation parabolique : sans elle, la précision est celle d'un
  // échantillon (≈ 15 cents sur une corde aiguë), trop grossière pour accorder.
  var period = best.toDouble();
  if (best > tauMin && best < tauMax) {
    final before = yin[best - 1];
    final at = yin[best];
    final after = yin[best + 1];
    final divisor = 2 * (2 * at - after - before);
    if (divisor != 0) period += (after - before) / divisor;
  }
  if (period <= 0) return null;

  final hz = sampleRate / period;
  if (hz < minHz || hz > maxHz) return null;
  return hz;
}

/// Convertit un bloc PCM 16 bits (ce que rend le micro) en échantillons −1..1.
List<double> pcm16ToSamples(Uint8List bytes) {
  final view = ByteData.sublistView(bytes);
  final samples = Float64List(bytes.lengthInBytes ~/ 2);
  for (var i = 0; i < samples.length; i++) {
    samples[i] = view.getInt16(i * 2, Endian.little) / 32768;
  }
  return samples;
}

/// Découpe le flux du micro en fenêtres d'analyse.
///
/// Le micro livre de petits blocs de taille variable ; YIN, lui, veut toujours
/// la même longueur de son. Les fenêtres se recouvrent de moitié pour que
/// l'aiguille bouge deux fois plus souvent qu'elle n'aurait de fenêtres.
class PitchWindows {
  PitchWindows({this.windowSize = 2048, this.hopSize = 1024});

  final int windowSize;
  final int hopSize;

  final List<double> _buffer = [];

  /// Les fenêtres complétées par ce bloc d'échantillons.
  List<List<double>> add(List<double> samples) {
    _buffer.addAll(samples);
    // Gros retard accumulé (application revenue de l'arrière-plan) : on jette
    // le vieux son plutôt que d'afficher une note d'il y a dix secondes.
    if (_buffer.length > windowSize * 4) {
      _buffer.removeRange(0, _buffer.length - windowSize);
    }

    final frames = <List<double>>[];
    while (_buffer.length >= windowSize) {
      frames.add(_buffer.sublist(0, windowSize));
      _buffer.removeRange(0, hopSize);
    }
    return frames;
  }

  void clear() => _buffer.clear();
}

/// Lisse la suite des mesures.
///
/// Une mesure isolée peut sauter (harmonique captée au moment de l'attaque,
/// choc sur la table) : on affiche la médiane des dernières. Et quand la corde
/// s'éteint, l'aiguille reste un instant plutôt que de disparaître aussitôt —
/// on regarde souvent l'écran juste après avoir lâché la corde.
class PitchTracker {
  PitchTracker({this.window = 5, this.hold = 10});

  /// Nombre de mesures gardées pour la médiane.
  final int window;

  /// Nombre de mesures vides tolérées avant d'oublier la note.
  final int hold;

  final List<double> _recent = [];
  int _missed = 0;
  double? _value;

  /// La fréquence tenue à l'écran (`null` = rien à afficher).
  double? get value => _value;

  /// Ajoute une mesure (ou `null` s'il n'y avait rien à entendre) et rend la
  /// fréquence à afficher.
  double? add(double? hz) {
    if (hz == null) {
      _missed++;
      if (_missed > hold) {
        _recent.clear();
        _value = null;
      }
      return _value;
    }

    _missed = 0;
    // Changement franc de corde : la médiane des anciennes mesures retiendrait
    // l'aiguille sur la note précédente pendant une demi-seconde.
    if (_recent.isNotEmpty &&
        (1200 * math.log(hz / _recent.last) / math.ln2).abs() > 150) {
      _recent.clear();
    }
    _recent.add(hz);
    if (_recent.length > window) _recent.removeAt(0);

    final sorted = [..._recent]..sort();
    _value = sorted[sorted.length ~/ 2];
    return _value;
  }

  void reset() {
    _recent.clear();
    _missed = 0;
    _value = null;
  }
}

// ──────────────────────────────────────────────────────────────── micro ──

/// Le micro, vu par l'accordeur (les tests en fournissent un autre).
abstract class PitchSource {
  /// Demande l'autorisation si besoin. `false` = pas de micro.
  Future<bool> ensurePermission();

  /// Ouvre le micro. Chaque évènement est une fréquence entendue, ou `null`
  /// quand plus rien n'est joué.
  Future<Stream<double?>> start();

  Future<void> stop();

  Future<void> dispose();
}

/// Micro de l'appareil, en PCM brut.
///
/// Volontairement sans réduction de bruit, sans gain automatique et sans
/// annulation d'écho : ces traitements sont faits pour la parole, ils hachent
/// une corde qui s'éteint et déforment sa hauteur.
class MicPitchSource implements PitchSource {
  MicPitchSource();

  /// 22 050 Hz suffit largement (la corde la plus aiguë monte à ~1,3 kHz) et
  /// divise par deux le travail de YIN.
  static const sampleRate = 22050;

  /// ~93 ms de son par analyse : assez long pour deux périodes du mi grave,
  /// assez court pour que l'aiguille suive la main.
  static const windowSize = 2048;

  /// Une analyse tous les ~46 ms (les fenêtres se recouvrent de moitié).
  static const hopSize = 1024;

  static const _config = RecordConfig(
    encoder: AudioEncoder.pcm16bits,
    sampleRate: sampleRate,
    numChannels: 1,
    autoGain: false,
    echoCancel: false,
    noiseSuppress: false,
    androidConfig: AndroidRecordConfig(audioSource: AndroidAudioSource.mic),
  );

  final AudioRecorder _recorder = AudioRecorder();
  final PitchWindows _windows = PitchWindows(
    windowSize: windowSize,
    hopSize: hopSize,
  );
  StreamSubscription<Uint8List>? _sub;
  StreamController<double?>? _out;

  @override
  Future<bool> ensurePermission() async {
    try {
      return await _recorder.hasPermission();
    } catch (_) {
      return false;
    }
  }

  @override
  Future<Stream<double?>> start() async {
    await stop();
    final raw = await _recorder.startStream(_config);
    final out = _out = StreamController<double?>.broadcast();
    _windows.clear();
    _sub = raw.listen(
      (bytes) {
        for (final frame in _windows.add(pcm16ToSamples(bytes))) {
          if (!out.isClosed) out.add(detectPitch(frame, sampleRate));
        }
      },
      onError: (_) {
        if (!out.isClosed) out.addError(StateError('micro interrompu'));
      },
      cancelOnError: false,
    );
    return out.stream;
  }

  @override
  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
    try {
      await _recorder.stop();
    } catch (_) {}
    await _out?.close();
    _out = null;
    _windows.clear();
  }

  @override
  Future<void> dispose() async {
    await stop();
    try {
      await _recorder.dispose();
    } catch (_) {}
  }
}
