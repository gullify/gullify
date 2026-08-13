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

  group('fondu enchaîné', () {
    const fade = Duration(seconds: 4);
    const total = Duration(minutes: 3);

    Crossfade at(
      Duration position, {
      bool armed = false,
      bool running = false,
      bool playing = true,
      bool live = false,
      bool hasNext = true,
      Duration? length = total,
      Duration duration = fade,
    }) =>
        crossfadeAt(
          position: position,
          total: length,
          // Sans mesure des bords, le plan rend le croisement fixe de #76.
          span: crossfadePlan(fade: duration, total: length).trigger,
          playing: playing,
          live: live,
          hasNext: hasNext,
          armed: armed,
          running: running,
        );

    test('le titre suivant se prépare avant qu\'on en ait besoin', () {
      // Loin de la fin : rien à faire.
      expect(at(const Duration(minutes: 1)), Crossfade.none);
      // Le croisement dure 4 s, la préparation prend les 10 s d'avant.
      expect(at(total - const Duration(seconds: 13)), Crossfade.arm);
      // Déjà préparé : on ne recharge pas à chaque battement de position.
      expect(at(total - const Duration(seconds: 13), armed: true),
          Crossfade.none);
    });

    test('le croisement part dans la dernière ligne droite', () {
      expect(at(total - const Duration(seconds: 5)), Crossfade.arm);
      expect(at(total - const Duration(seconds: 3), armed: true),
          Crossfade.start);
      // Même sans préparation : mieux vaut un croisement en retard que pas de
      // croisement du tout.
      expect(at(total - const Duration(seconds: 3)), Crossfade.start);
    });

    test('un croisement en cours se pilote seul', () {
      expect(at(total - const Duration(seconds: 1), running: true),
          Crossfade.none);
    });

    test('le tampon préparé est rendu dès qu\'il ne sert plus', () {
      // Retour en arrière : la fin s'est éloignée.
      expect(at(const Duration(seconds: 10), armed: true), Crossfade.disarm);
      // Pause, réglage éteint, dernier titre de la file, radio : rien à croiser.
      expect(at(total - const Duration(seconds: 5),
          armed: true, playing: false), Crossfade.disarm);
      expect(
        at(total - const Duration(seconds: 5),
            armed: true, duration: Duration.zero),
        Crossfade.disarm,
      );
      expect(at(total - const Duration(seconds: 5),
          armed: true, hasNext: false), Crossfade.disarm);
      expect(at(total - const Duration(seconds: 5), armed: true, live: true),
          Crossfade.disarm);
      // Rien de préparé : rien à rendre.
      expect(at(const Duration(seconds: 10)), Crossfade.none);
    });

    test('le dernier titre de la file ne croise personne', () {
      expect(at(total - const Duration(seconds: 2), hasNext: false),
          Crossfade.none);
    });

    test('une radio et un flux sans durée ne se croisent jamais', () {
      expect(at(const Duration(hours: 2), live: true), Crossfade.none);
      expect(at(const Duration(hours: 2), length: null), Crossfade.none);
    });

    test('un titre court ne se fait pas croiser de bout en bout', () {
      // Un fondu de 4 s sur un titre de 9 s : le croisement se contente du
      // tiers, sinon on n'entendrait jamais le titre seul.
      expect(crossfadeSpan(fade, const Duration(seconds: 9)),
          const Duration(seconds: 3));
      expect(crossfadeSpan(fade, total), fade);
      expect(
        at(const Duration(seconds: 7), length: const Duration(seconds: 9)),
        Crossfade.start,
      );
      expect(
        at(const Duration(seconds: 5), length: const Duration(seconds: 9)),
        Crossfade.arm,
      );
    });

    test('la rampe à puissance constante garde le niveau au milieu', () {
      final montee = fadeRamp(
        from: 0,
        to: 1,
        over: const Duration(seconds: 1),
        constantPower: true,
      );
      final descente = fadeRamp(
        from: 1,
        to: 0,
        over: const Duration(seconds: 1),
        constantPower: true,
      );

      expect(montee.last, 1.0);
      expect(descente.last, 0.0);
      // Au milieu du croisement, les deux titres réunis pèsent leur volume
      // d'origine : c'est tout l'intérêt de la racine.
      for (var i = 0; i < montee.length; i++) {
        final somme = montee[i] * montee[i] + descente[i] * descente[i];
        expect(somme, closeTo(1, 0.001));
      }
      // Une rampe linéaire, elle, creuse : à mi-parcours, 0,5² + 0,5² = 0,5.
      final lineaire = fadeRamp(from: 0, to: 1, over: const Duration(seconds: 1));
      expect(montee[12], greaterThan(lineaire[12]));
    });
  });

  group('croisement intelligent (#79)', () {
    const fade = Duration(seconds: 4);
    const total = Duration(minutes: 3);

    test('sans mesure, on retombe sur le croisement à durée fixe', () {
      final plan = crossfadePlan(fade: fade, total: total);

      expect(plan.trigger, fade);
      expect(plan.rise, fade);
      expect(plan.fall, fade);
      expect(plan.hold, Duration.zero);
      // Réglage éteint, durée inconnue : aucun croisement.
      expect(crossfadePlan(fade: Duration.zero, total: total).idle, isTrue);
      expect(crossfadePlan(fade: fade, total: null).idle, isTrue);
    });

    test('le blanc de fin est sauté : le suivant part avant', () {
      final plan = crossfadePlan(
        fade: fade,
        total: total,
        current: const TrackEdges(tail: Duration(seconds: 5)),
      );

      // Le croisement part cinq secondes plus tôt, mais dure toujours autant :
      // ce sont bien les deux musiques qui se croisent, pas le silence.
      expect(plan.trigger, const Duration(seconds: 9));
      expect(plan.rise, fade);
      expect(plan.fall, fade);
    });

    test('un blanc de fin à rallonge ne fait pas disparaître le titre', () {
      final plan = crossfadePlan(
        fade: fade,
        total: total,
        current: const TrackEdges(tail: Duration(seconds: 30)),
      );

      expect(plan.trigger, fade + kSmartTailMax);
    });

    test('une longue descente naturelle se fait couvrir en entier', () {
      final plan = crossfadePlan(
        fade: fade,
        total: total,
        current: const TrackEdges(decay: Duration(seconds: 7)),
      );

      expect(plan.rise, const Duration(seconds: 7));
      expect(plan.fall, const Duration(seconds: 7));
      // Jamais plus du double de la durée réglée : le réglage reste le maître.
      final long = crossfadePlan(
        fade: fade,
        total: total,
        current: const TrackEdges(decay: Duration(seconds: 20)),
      );
      expect(long.rise, fade * kSmartStretch);
    });

    test('un titre qui s\'arrête net garde la durée réglée', () {
      final plan = crossfadePlan(
        fade: fade,
        total: total,
        current: const TrackEdges(decay: Duration(milliseconds: 500)),
      );

      expect(plan.rise, fade);
      expect(plan.fall, fade);
    });

    test('le titre entrant part en avance, le sortant tient son volume', () {
      final plan = crossfadePlan(
        fade: fade,
        total: total,
        next: const TrackEdges(lead: Duration(seconds: 2)),
      );

      expect(plan.trigger, const Duration(seconds: 6));
      expect(plan.rise, const Duration(seconds: 6));
      // La descente, elle, ne s'allonge pas : elle attend l'intro du suivant.
      expect(plan.fall, fade);
      expect(plan.hold, const Duration(seconds: 2));
      // Une intro interminable n'est pas couverte pour autant.
      final slow = crossfadePlan(
        fade: fade,
        total: total,
        next: const TrackEdges(lead: Duration(seconds: 30)),
      );
      expect(slow.hold, kSmartLeadMax);
    });

    test('un titre court n\'est jamais croisé de bout en bout', () {
      const court = Duration(seconds: 30);
      final plan = crossfadePlan(
        fade: fade,
        total: court,
        current: const TrackEdges(
          tail: Duration(seconds: 8),
          decay: Duration(seconds: 12),
        ),
        next: const TrackEdges(lead: Duration(seconds: 3)),
      );

      // Le tiers pour les deux musiques réunies, la moitié blanc compris.
      expect(plan.rise, lessThanOrEqualTo(court ~/ 3));
      expect(plan.trigger, lessThanOrEqualTo(court ~/ 2));
      expect(plan.rise, greaterThan(Duration.zero));
      expect(plan.fall, lessThanOrEqualTo(plan.rise));
    });

    test('le suivi d\'écoute sait de combien un titre peut partir tôt', () {
      final fade = PlaybackFade();

      expect(fade.crossfadeReach, Duration.zero);
      fade.setBetweenTracks(true);
      fade.setSmart(false);
      expect(fade.crossfadeReach, fade.duration);
      fade.setSmart(true);
      expect(
        fade.crossfadeReach,
        fade.duration * kSmartStretch + kSmartLeadMax + kSmartTailMax,
      );
      // Le croisement intelligent n'existe que là où il y a un croisement.
      fade.setBetweenTracks(false);
      expect(fade.measuresTracks, isFalse);
      expect(fade.crossfadeReach, Duration.zero);
    });
  });

  test('la durée s\'écrit à la française', () {
    expect(formatFadeSeconds(0.5), '0,5 s');
    expect(formatFadeSeconds(2), '2 s');
    expect(formatFadeSeconds(8), '8 s');
  });

  testWidgets('l\'écran règle la durée et le fondu enchaîné',
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

    await tester.tap(find.text('Fondu enchaîné'));
    await tester.pumpAndSettle();
    expect(fade.betweenTracks, isTrue);
  });

  testWidgets('le croisement intelligent attend qu\'il y ait un croisement',
      (tester) async {
    final fade = PlaybackFade();
    await tester.pumpWidget(_wrap(fade));

    SwitchListTile smart() => tester.widget<SwitchListTile>(
          find.widgetWithText(SwitchListTile, 'Croisement intelligent'),
        );

    // Fondu enchaîné éteint : rien à tailler, le réglage est hors service.
    expect(smart().onChanged, isNull);

    await tester.tap(find.text('Fondu enchaîné'));
    await tester.pumpAndSettle();
    expect(smart().onChanged, isNotNull);
    // Actif par défaut : c'est le passage qu'on veut entendre.
    expect(fade.smart, isTrue);

    await tester.tap(find.text('Croisement intelligent'));
    await tester.pumpAndSettle();
    expect(fade.smart, isFalse);
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
      find.widgetWithText(SwitchListTile, 'Fondu enchaîné'),
    );
    expect(tracks.onChanged, isNull);
  });
}
