// L'accordeur de guitare de la feuille des accords (idée #62) : le micro donne
// des blocs de son, YIN en tire la fréquence, et l'app la rapporte à la corde
// visée. Tout se teste ici sur des sons fabriqués, sans appareil.
import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gullify/audio/tuner.dart';
import 'package:gullify/state/tuner.dart';
import 'package:gullify/widgets/tuner_sheet.dart';

const _rate = 22050;

/// Une note tenue : la fondamentale et, en option, ses harmoniques — une corde
/// de guitare en a de plus fortes que sa fondamentale.
List<double> _tone(
  double hz, {
  int samples = 2048,
  List<double> harmonics = const [1],
  double amplitude = 0.3,
}) {
  final out = List<double>.filled(samples, 0);
  for (var i = 0; i < samples; i++) {
    var value = 0.0;
    for (var h = 0; h < harmonics.length; h++) {
      value += harmonics[h] * math.sin(2 * math.pi * hz * (h + 1) * i / _rate);
    }
    out[i] = value * amplitude;
  }
  return out;
}

/// Un micro de papier : on lui dicte les fréquences qu'il « entend ».
class _FakePitchSource implements PitchSource {
  _FakePitchSource({this.allowed = true, this.fails = false});

  final bool allowed;
  final bool fails;
  final StreamController<double?> controller =
      StreamController<double?>.broadcast();
  int stops = 0;

  @override
  Future<bool> ensurePermission() async => allowed;

  @override
  Future<Stream<double?>> start() async {
    if (fails) throw StateError('micro occupé');
    return controller.stream;
  }

  @override
  Future<void> stop() async {
    stops++;
  }

  @override
  Future<void> dispose() async {}
}

Future<_FakePitchSource> _open(
  WidgetTester tester, {
  _FakePitchSource? source,
  String? tuning,
}) async {
  final fake = source ?? _FakePitchSource();
  tester.view.physicalSize = const Size(412, 892);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [pitchSourceProvider.overrideWithValue(fake)],
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => showTunerSheet(context, tuning: tuning),
                child: const Text('ouvrir'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('ouvrir'));
  await tester.pumpAndSettle();
  return fake;
}

void main() {
  group('détection de la hauteur', () {
    test('trouve la fréquence d\'un son pur', () {
      for (final hz in [82.41, 110.0, 196.0, 329.63, 440.0]) {
        final found = detectPitch(_tone(hz), _rate);
        expect(found, isNotNull, reason: '$hz Hz doit être entendu');
        expect(
          centsBetween(found!, midiOfFrequency(hz)).abs(),
          lessThan(15),
          reason: '$hz Hz trouvé à ${found.toStringAsFixed(2)} Hz',
        );
      }
    });

    test('ne se trompe pas d\'octave sur une corde riche en harmoniques', () {
      // Mi grave d'une guitare : la fondamentale est plus faible que ses deux
      // premières harmoniques. Un simple pic spectral répondrait 164 Hz.
      final found = detectPitch(
        _tone(82.41, harmonics: [0.3, 1.0, 0.8, 0.5]),
        _rate,
      );
      expect(found, isNotNull);
      expect((found! - 82.41).abs(), lessThan(1.5));
    });

    test('rend null sur le silence et sur du bruit', () {
      expect(detectPitch(List<double>.filled(2048, 0), _rate), isNull);
      final noise = math.Random(7);
      final hiss = [
        for (var i = 0; i < 2048; i++) (noise.nextDouble() - 0.5) * 0.6,
      ];
      expect(detectPitch(hiss, _rate), isNull);
    });

    test('reste assez précis pour accorder (≈ 2 cents)', () {
      // Une corde 6 cents trop haute doit se lire comme telle, pas comme juste.
      final target = frequencyOfMidi(45) * math.pow(2, 6 / 1200);
      final found = detectPitch(_tone(target.toDouble()), _rate)!;
      expect(centsBetween(found, 45), closeTo(6, 2));
    });

    test('découpe le flux du micro en fenêtres qui se recouvrent', () {
      final windows = PitchWindows(windowSize: 8, hopSize: 4);
      // Les blocs du micro n'ont pas la taille d'une fenêtre : on attend.
      expect(windows.add(List<double>.filled(5, 1)), isEmpty);
      // 12 échantillons en réserve : deux fenêtres décalées d'un demi-pas.
      final frames = windows.add(List<double>.filled(7, 2));
      expect(frames.length, 2);
      expect(frames.every((f) => f.length == 8), isTrue);
      // Reste 4 échantillons : la fenêtre suivante n'a besoin que de 4 de plus.
      expect(windows.add(List<double>.filled(4, 3)).length, 1);

      // Retour d'arrière-plan : on repart du son récent, sans rattraper tout.
      final late = PitchWindows(windowSize: 8, hopSize: 4);
      expect(late.add(List<double>.filled(200, 1)).length, 1);
    });

    test('lit le PCM 16 bits du micro', () {
      final bytes = Uint8List(4)
        ..buffer.asByteData().setInt16(0, 16384, Endian.little)
        ..buffer.asByteData().setInt16(2, -16384, Endian.little);
      expect(pcm16ToSamples(bytes), [0.5, -0.5]);
    });
  });

  group('notes et accordages', () {
    test('nomme les notes', () {
      expect(frequencyOfMidi(69), 440);
      expect(noteName(40), 'E');
      expect(octaveOfMidi(40), 2);
      expect(frenchNoteName(45), 'La');
      expect(frenchNoteName(54), 'Fa♯');
      expect(midiOfFrequency(440), 69);
      expect(centsBetween(440, 69), closeTo(0, 0.001));
    });

    test('reconnaît l\'accordage annoncé par la grille', () {
      expect(tuningFromLabel('E A D G B E')?.name, 'Standard');
      expect(tuningFromLabel('D A D G B E')?.name, 'Drop D');
      expect(tuningFromLabel('Eb Ab Db Gb Bb Eb')?.name, 'Demi-ton plus bas');
      expect(tuningFromLabel('D A D G A D')?.name, 'DADGAD');
      // Rien d'exploitable : l'accordeur reste sur le standard.
      expect(tuningFromLabel('Accordage bizarre'), isNull);
      expect(tuningFromLabel('E A D G'), isNull);
      expect(tuningFromLabel(null), isNull);
    });

    test('désigne la corde la plus proche', () {
      final low = readingFor(frequencyOfMidi(40).toDouble(), standardTuning);
      expect(low.stringIndex, 0);
      expect(low.name, 'E');
      expect(low.inTune, isTrue);

      // Le mi aigu ne doit pas être pris pour le mi grave.
      expect(readingFor(329.63, standardTuning).stringIndex, 5);
      // Corde très détendue : encore rattachée à sa corde, mais fausse.
      final flat = readingFor(
        frequencyOfMidi(45) * math.pow(2, -40 / 1200).toDouble(),
        standardTuning,
      );
      expect(flat.stringIndex, 1);
      expect(flat.cents, closeTo(-40, 1));
      expect(flat.inTune, isFalse);
      // Une note qui n'est celle d'aucune corde ne désigne personne.
      expect(readingFor(1000, standardTuning).stringIndex, isNull);
    });

    test('suit l\'accordage choisi', () {
      final dropD = guitarTunings.firstWhere((t) => t.name == 'Drop D');
      expect(dropD.labels, 'D A D G B E');
      final reading = readingFor(frequencyOfMidi(38).toDouble(), dropD);
      expect(reading.stringIndex, 0);
      expect(reading.inTune, isTrue);
    });
  });

  group('lissage des mesures', () {
    test('une mesure aberrante ne fait pas sauter l\'aiguille', () {
      final tracker = PitchTracker();
      for (final hz in [110.0, 110.4, 109.8]) {
        tracker.add(hz);
      }
      // Harmonique captée au moment de l'attaque : hors de la note tenue, on
      // repart proprement plutôt que de mélanger deux hauteurs.
      expect(tracker.add(110.2), closeTo(110.2, 0.4));
      expect(tracker.add(110.1), closeTo(110.2, 0.4));
    });

    test('garde la note un instant après l\'extinction de la corde', () {
      final tracker = PitchTracker(window: 3, hold: 2);
      tracker.add(196.0);
      expect(tracker.add(null), closeTo(196, 0.01));
      expect(tracker.add(null), closeTo(196, 0.01));
      expect(tracker.add(null), isNull);
      expect(tracker.value, isNull);
    });

    test('change de corde sans traîner sur la précédente', () {
      final tracker = PitchTracker();
      tracker.add(110.0);
      tracker.add(110.2);
      // Une corde plus haute : la médiane ne doit pas retenir l'ancienne.
      expect(tracker.add(146.8), closeTo(146.8, 0.01));
    });
  });

  group('feuille de l\'accordeur', () {
    testWidgets('affiche la note entendue et allume sa corde', (tester) async {
      final source = await _open(tester);

      expect(find.text('Accordeur'), findsOneWidget);
      expect(find.text('Joue une corde à vide'), findsOneWidget);

      source.controller.add(frequencyOfMidi(45).toDouble());
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('A'), findsWidgets);
      expect(find.text('Juste !'), findsOneWidget);
      expect(find.textContaining('110.0 Hz'), findsOneWidget);
    });

    testWidgets('dit dans quel sens tourner la mécanique', (tester) async {
      final source = await _open(tester);

      source.controller.add(frequencyOfMidi(40) * math.pow(2, -30 / 1200));
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('Trop grave — tends la corde'), findsOneWidget);
      expect(find.text('-30 cents'), findsOneWidget);

      source.controller.add(frequencyOfMidi(64) * math.pow(2, 25 / 1200));
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('Trop aigu — détends la corde'), findsOneWidget);
      expect(find.text('+25 cents'), findsOneWidget);
    });

    testWidgets('part sur l\'accordage de la grille', (tester) async {
      await _open(tester, tuning: 'D A D G B E');

      // L'accordeur a suivi la grille : le chip « Drop D » est sélectionné, et
      // amené sous les yeux même s'il est loin dans la liste.
      expect(find.text('Drop D'), findsOneWidget);
      final chip = tester.widget<ChoiceChip>(
        find.ancestor(
          of: find.text('Drop D'),
          matching: find.byType(ChoiceChip),
        ),
      );
      expect(chip.selected, isTrue);
    });

    testWidgets('change d\'accordage à la demande', (tester) async {
      final source = await _open(tester);
      source.controller.add(frequencyOfMidi(38).toDouble());
      await tester.pump(const Duration(milliseconds: 200));
      // En standard, un ré grave n'est la corde de personne.
      expect(find.text('Aucune corde de cet accordage'), findsOneWidget);

      await tester.ensureVisible(find.text('Drop D'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Drop D'));
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('Juste !'), findsOneWidget);
    });

    testWidgets('sans micro, le dit et propose de réessayer', (tester) async {
      await _open(tester, source: _FakePitchSource(allowed: false));

      expect(
        find.text('Micro refusé — autorise-le dans les réglages'),
        findsOneWidget,
      );
      expect(find.text('Réessayer'), findsOneWidget);
    });

    testWidgets('micro occupé : message plutôt qu\'écran figé', (tester) async {
      await _open(tester, source: _FakePitchSource(fails: true));

      expect(find.text('Micro indisponible'), findsOneWidget);
    });

    testWidgets('referme le micro en quittant la feuille', (tester) async {
      final source = await _open(tester);
      expect(source.stops, 0);

      Navigator.of(tester.element(find.text('Accordeur'))).pop();
      await tester.pumpAndSettle();

      expect(source.stops, greaterThan(0));
    });
  });
}
