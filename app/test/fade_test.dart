// Fondu du lecteur (idée #75) : la rampe de volume, le réglage mémorisé et
// l'écran qui les règle (Paramètres → Lecture → Fondu).
//
// Ce qui compte ici : une rampe finit TOUJOURS exactement sur sa cible. Un
// fondu qui s'arrête à 0,98 laisserait le lecteur légèrement sourd pour
// toujours, et un fondu de sortie qui s'arrête à 0,02 ferait siffler la pause.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gullify/audio/fade.dart';
import 'package:gullify/screens/fade_screen.dart';
import 'package:gullify/state/player.dart';
import 'package:gullify/theme.dart';

Widget _wrap(PlaybackFade fade) => ProviderScope(
      overrides: [playbackFadeProvider.overrideWithValue(fade)],
      child: MaterialApp(
        theme: gullifyThemeFor(GullifyAccent.indigo, dark: false),
        home: const FadeScreen(),
      ),
    );

void main() {
  test('la rampe monte de zéro à un, et finit pile sur la cible', () {
    final ramp = fadeRamp(from: 0, to: 1, over: const Duration(seconds: 1));

    expect(ramp.length, 25); // 1 s / 40 ms
    expect(ramp.last, 1.0);
    expect(ramp.first, lessThan(0.1));
    for (var i = 1; i < ramp.length; i++) {
      expect(ramp[i], greaterThan(ramp[i - 1]));
    }
  });

  test('la rampe de sortie descend jusqu\'au silence', () {
    final ramp = fadeRamp(from: 1, to: 0, over: const Duration(seconds: 2));

    expect(ramp.length, 50);
    expect(ramp.last, 0.0);
    for (var i = 1; i < ramp.length; i++) {
      expect(ramp[i], lessThan(ramp[i - 1]));
    }
  });

  test('sans durée, la rampe pose la cible d\'un coup', () {
    expect(fadeRamp(from: 1, to: 0, over: Duration.zero), [0.0]);
    // Plus court qu'un pas : inutile de découper.
    expect(
      fadeRamp(from: 0, to: 1, over: const Duration(milliseconds: 20)),
      [1.0],
    );
  });

  test('un fondu éteint ne dure rien, et ne fond pas les titres', () {
    final fade = PlaybackFade();

    expect(fade.duration, const Duration(milliseconds: 500));
    expect(fade.fadesTracks, isFalse);

    fade.setBetweenTracks(true);
    expect(fade.fadesTracks, isTrue);

    fade.setEnabled(false);
    expect(fade.duration, Duration.zero);
    // Éteint, le fondu entre les titres ne s'applique plus non plus : c'est
    // le même réglage de durée qui le porte.
    expect(fade.fadesTracks, isFalse);
  });

  test('la durée reste dans les bornes réglables', () {
    final fade = PlaybackFade()..setSeconds(42);
    expect(fade.seconds, kFadeMaxSeconds);

    fade.setSeconds(0);
    expect(fade.seconds, kFadeMinSeconds);
  });

  group('fondu de fin de piste', () {
    const fade = Duration(seconds: 3);
    const total = Duration(minutes: 3);

    TrackFade at(
      Duration position, {
      bool fadingOut = false,
      bool playing = true,
      bool live = false,
      Duration? length = total,
      Duration duration = fade,
    }) =>
        trackFadeAt(
          position: position,
          total: length,
          fade: duration,
          playing: playing,
          live: live,
          fadingOut: fadingOut,
        );

    test('la descente commence dans la dernière ligne droite', () {
      expect(at(const Duration(minutes: 2)), TrackFade.none);
      expect(at(total - const Duration(seconds: 4)), TrackFade.none);
      expect(at(total - const Duration(seconds: 2)), TrackFade.out);
      // Déjà entamée : on ne la relance pas à chaque battement de position.
      expect(
        at(total - const Duration(seconds: 1), fadingOut: true),
        TrackFade.none,
      );
    });

    test('le volume remonte au titre suivant', () {
      expect(at(Duration.zero, fadingOut: true), TrackFade.back);
    });

    test('le volume remonte sur un titre rejoué en boucle', () {
      // Répétition d'un seul titre : la position repart à zéro sans que la
      // piste change. Sans ce retour, elle se rejouerait muette.
      expect(at(const Duration(seconds: 1), fadingOut: true), TrackFade.back);
    });

    test('le volume remonte si on revient en arrière pendant le fondu', () {
      expect(at(const Duration(minutes: 1), fadingOut: true), TrackFade.back);
    });

    test('le volume remonte à la fin de la file', () {
      // Piste terminée : la position colle à la durée, il ne reste rien à
      // fondre — le lecteur doit retrouver son volume pour la prochaine fois.
      expect(at(total, fadingOut: true), TrackFade.back);
      expect(at(total), TrackFade.none);
    });

    test('le volume remonte si le réglage est éteint pendant le fondu', () {
      expect(
        at(total - const Duration(seconds: 1),
            fadingOut: true, duration: Duration.zero),
        TrackFade.back,
      );
    });

    test('une radio et un flux sans durée ne fondent jamais', () {
      expect(at(const Duration(hours: 2), live: true), TrackFade.none);
      expect(at(const Duration(hours: 2), length: null), TrackFade.none);
      expect(at(Duration.zero, length: Duration.zero), TrackFade.none);
    });

    test('en pause, aucune descente ne s\'amorce', () {
      expect(at(total - const Duration(seconds: 1), playing: false),
          TrackFade.none);
    });
  });

  test('la durée s\'écrit à la française', () {
    expect(formatFadeSeconds(0.5), '0,5 s');
    expect(formatFadeSeconds(2), '2 s');
    expect(formatFadeSeconds(8), '8 s');
  });

  testWidgets('l\'écran règle la durée et le fondu entre les titres',
      (tester) async {
    final fade = PlaybackFade();
    await tester.pumpWidget(_wrap(fade));

    expect(find.text('0,5 s'), findsOneWidget);
    expect(find.byType(Slider), findsOneWidget);

    // Le curseur glissé à fond : durée maximale, affichée telle quelle.
    await tester.drag(find.byType(Slider), const Offset(500, 0));
    await tester.pumpAndSettle();
    expect(fade.seconds, kFadeMaxSeconds);
    expect(find.text('8 s'), findsOneWidget);

    await tester.tap(find.text('Fondu entre les titres'));
    await tester.pumpAndSettle();
    expect(fade.betweenTracks, isTrue);
  });

  testWidgets('fondu éteint, les réglages de durée sont hors service',
      (tester) async {
    final fade = PlaybackFade();
    await tester.pumpWidget(_wrap(fade));

    await tester.tap(find.text('Fondu à la lecture et à la pause'));
    await tester.pumpAndSettle();

    expect(fade.enabled, isFalse);
    expect(tester.widget<Slider>(find.byType(Slider)).onChanged, isNull);
    final tracks = tester.widget<SwitchListTile>(
      find.widgetWithText(SwitchListTile, 'Fondu entre les titres'),
    );
    expect(tracks.onChanged, isNull);
  });
}
