// Égaliseur : lecture des bandes renvoyées par le canal natif et rendu de
// l'écran de réglage (Paramètres → Égaliseur).
//
// Régression idée #47 : l'égaliseur passait par l'AudioPipeline de just_audio,
// qui lit les bandes AVANT qu'ExoPlayer (media3 1.9) n'ait généré sa session
// audio. L'effet natif n'existait pas encore, l'exception remontait pendant
// l'activation du lecteur et le rendait définitivement inutilisable : plus
// aucune chanson ne démarrait. L'égaliseur vit désormais hors du lecteur —
// tant qu'aucune session n'existe, l'écran le dit au lieu de tout casser.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gullify/audio/equalizer.dart';
import 'package:gullify/screens/equalizer_screen.dart';
import 'package:gullify/state/player.dart';
import 'package:gullify/theme.dart';

/// Réponse type du canal natif (5 bandes, ±15 dB), telle que la construit
/// MainActivity.bindEqualizer.
const _payload = <Object?, Object?>{
  'minDecibels': -15.0,
  'maxDecibels': 15.0,
  'bands': [
    {'index': 0, 'centerFrequency': 60.0, 'gain': 0.0},
    {'index': 1, 'centerFrequency': 230.0, 'gain': 3.0},
    {'index': 2, 'centerFrequency': 910.0, 'gain': 0.0},
    {'index': 3, 'centerFrequency': 3600.0, 'gain': -2.5},
    {'index': 4, 'centerFrequency': 14000.0, 'gain': 0.0},
  ],
};

Widget _wrap(GullifyEqualizer eq) => ProviderScope(
      overrides: [equalizerProvider.overrideWithValue(eq)],
      child: MaterialApp(
        theme: gullifyThemeFor(GullifyAccent.indigo, dark: false),
        home: const EqualizerScreen(),
      ),
    );

void main() {
  test('les bandes du canal natif se relisent telles quelles', () {
    final params = EqualizerParameters.fromMap(_payload);

    expect(params.minDecibels, -15.0);
    expect(params.maxDecibels, 15.0);
    expect(params.bands.length, 5);
    expect(params.bands[1].centerFrequency, 230.0);
    expect(params.bands[3].gain, -2.5);
  });

  test('modifier une bande ne touche pas les autres', () {
    final params = EqualizerParameters.fromMap(_payload).withBandGain(3, 6.0);

    expect(params.bands[3].gain, 6.0);
    expect(params.bands[1].gain, 3.0);
  });

  testWidgets('sans session audio, l\'écran invite à lancer une chanson',
      (tester) async {
    await tester.pumpWidget(_wrap(GullifyEqualizer()));

    // Sur cette plateforme de test l'égaliseur n'existe pas : l'écran doit le
    // dire calmement, jamais lever d'exception.
    expect(find.byType(Slider), findsNothing);
    expect(find.textContaining('non disponible'), findsOneWidget);
  });

  testWidgets('avec des bandes, un curseur par bande et l\'interrupteur',
      (tester) async {
    final eq = GullifyEqualizer()
      ..debugAttach(EqualizerParameters.fromMap(_payload), enabled: true);
    await tester.pumpWidget(_wrap(eq));

    expect(find.byType(Slider), findsNWidgets(5));
    expect(find.text('5 bandes'), findsOneWidget);
    expect(find.text('+3.0'), findsOneWidget);
    expect(find.text('-2.5'), findsOneWidget);
    expect(tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        isTrue);
  });

  testWidgets('un preset répartit la courbe sur les bandes réelles',
      (tester) async {
    final eq = GullifyEqualizer()
      ..debugAttach(EqualizerParameters.fromMap(_payload));
    await tester.pumpWidget(_wrap(eq));

    await tester.tap(find.text('Basses +'));
    await tester.pumpAndSettle();

    final gains = [for (final b in eq.parameters!.bands) b.gain];
    // Courbe « Basses + » : grave poussé, aigus laissés à plat.
    expect(gains.first, greaterThan(gains.last));
    expect(gains.first, closeTo(6.0, 0.01));
    expect(gains.last, closeTo(0.0, 0.01));
  });
}
