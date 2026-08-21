// Fondu du lecteur (idée #75) : la rampe de volume, le réglage mémorisé et
// l'écran qui les règle (Paramètres → Lecture → Fondu).
//
// Ce qui compte ici : une rampe finit TOUJOURS exactement sur sa cible. Un
// fondu qui s'arrête à 0,98 laisserait le lecteur légèrement sourd pour
// toujours, et un fondu de sortie qui s'arrête à 0,02 ferait siffler la pause.
import 'dart:math';

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

    test('les deux rampes du croisement se complètent', () {
      final montee = fadeRamp(
        from: 0,
        to: 1,
        over: const Duration(seconds: 1),
        curve: FadeCurve.crossing,
      );
      final descente = fadeRamp(
        from: 1,
        to: 0,
        over: const Duration(seconds: 1),
        curve: FadeCurve.crossing,
      );

      expect(montee.last, 1.0);
      expect(descente.last, 0.0);
      // La loi du croisement : à chaque instant, sortant^k + entrant^k = 1.
      for (var i = 0; i < montee.length; i++) {
        final somme = pow(montee[i], kCrossfadeLaw) + pow(descente[i], kCrossfadeLaw);
        expect(somme, closeTo(1, 0.001));
      }
      // Elle tient entre les deux extrêmes : au-dessus de deux droites, qui
      // creuseraient un vrai trou, et sous la puissance constante, qui laisse
      // le passage enfler (idée #101).
      final lineaire = fadeRamp(from: 0, to: 1, over: const Duration(seconds: 1));
      expect(montee[12], greaterThan(lineaire[12]));
      expect(montee[12], lessThan(sqrt(0.5)));
    });

    test('le milieu du croisement pèse un peu moins qu\'un titre seul', () {
      // Idée #101 : deux musiques différentes qui jouent ensemble ne
      // s'entendent pas comme une seule de même puissance — elles ajoutent
      // aussi leurs sonies. Le croisement descend donc d'un décibel et demi à
      // mi-parcours, sans jamais aller jusqu'au creux des deux droites (−3 dB).
      const over = Duration(seconds: 1);
      final montee =
          fadeRamp(from: 0, to: 1, over: over, curve: FadeCurve.crossing);
      final descente =
          fadeRamp(from: 1, to: 0, over: over, curve: FadeCurve.crossing);

      final milieu = montee.length ~/ 2 - 1;
      final puissance = montee[milieu] * montee[milieu] +
          descente[milieu] * descente[milieu];
      expect(10 * (log(puissance) / ln10), closeTo(-1.5, 0.2));
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

    test('le croisement ne sonne jamais plus fort qu\'un seul titre', () {
      // Idée #91 : le passage enflait, parce que le titre entrant montait
      // pendant que le sortant tenait encore son plein volume.
      final plan = crossfadePlan(
        fade: fade,
        total: total,
        next: const TrackEdges(lead: Duration(seconds: 2)),
      );
      expect(plan.hold, greaterThan(Duration.zero));

      // Les deux rampes telles que le lecteur les joue : même attente, même
      // durée, l'une vers 1 et l'autre vers 0 (voir _fadeIncoming et
      // _fadeOutgoing dans audio_handler.dart).
      final entrant = [
        // L'attente, à volume nul.
        for (var i = 0; i < plan.hold.inMicroseconds ~/ kFadeTick.inMicroseconds; i++)
          0.0,
        ...fadeRamp(from: 0, to: 1, over: plan.fall, curve: FadeCurve.crossing),
      ];
      final sortant = [
        // L'attente, à plein volume.
        for (var i = 0; i < plan.hold.inMicroseconds ~/ kFadeTick.inMicroseconds; i++)
          1.0,
        ...fadeRamp(from: 1, to: 0, over: plan.fall, curve: FadeCurve.crossing),
      ];

      expect(entrant.length, sortant.length);
      for (var i = 0; i < entrant.length; i++) {
        // Jamais plus d'un titre dans les oreilles : les deux puissances
        // réunies ne dépassent pas celle du titre sortant seul.
        final somme = entrant[i] * entrant[i] + sortant[i] * sortant[i];
        expect(somme, lessThanOrEqualTo(1.001));
        expect(somme, greaterThan(0.7));
      }
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

    test('un titre entrant plus fort croise au niveau du sortant', () {
      // Idée #101 : deux morceaux ne sont pas gravés au même volume. Un
      // entrant six décibels au-dessus fait enfler le passage, quelle que
      // soit la forme des rampes.
      final plan = crossfadePlan(
        fade: fade,
        total: total,
        current: const TrackEdges(level: -14),
        next: const TrackEdges(level: -8),
      );

      // Six décibels de trop, c'est la moitié de l'amplitude.
      expect(plan.gain, closeTo(0.501, 0.005));
      // La forme du croisement, elle, ne bouge pas.
      expect(plan.rise, fade);
      expect(plan.fall, fade);
    });

    test('un titre entrant plus discret remonte vers son niveau', () {
      // Idée #104 : l'idée #101 ne savait que retenir. Une file finissait donc
      // par s'enfoncer sans jamais revenir, puisque la remontée d'après-passage
      // — la seule chose qui rendait les décibels retenus — n'existe plus.
      final plan = crossfadePlan(
        fade: fade,
        total: total,
        current: const TrackEdges(level: -8),
        next: const TrackEdges(level: -14),
      );

      expect(plan.gain, closeTo(pow(10, 6 / 20).toDouble(), 0.005));
      // Rien ne sature pour autant : c'est le volume final qui est borné.
      expect(crossfadeTarget(gain: plan.gain, playing: 1), 1);
      expect(crossfadeTarget(gain: plan.gain, playing: 0.501), closeTo(1, 0.01));
    });

    test('le croisement se cale sur les morceaux, pas sur leurs bords', () {
      // Idée #104 : deux morceaux gravés au même niveau se croisent sans
      // correction, même si le sortant finit cinq décibels plus bas qu'il n'a
      // joué — c'est le cas le plus courant, et l'idée #102 y retenait
      // l'entrant de ces cinq décibels-là. Il fallait ensuite les lui rendre,
      // et cette restitution s'entendait en plein milieu du morceau.
      final plan = crossfadePlan(
        fade: fade,
        total: total,
        current: const TrackEdges(level: -12),
        next: const TrackEdges(level: -12),
      );

      expect(plan.gain, 1);
      // Le volume posé au croisement est celui qu'on gardera : à niveaux
      // égaux, c'est exactement celui du sortant.
      expect(crossfadeTarget(gain: plan.gain, playing: 0.8), closeTo(0.8, 1e-9));
    });

    test('la mise à niveau ne fait pas disparaître le titre entrant', () {
      // Un écart énorme (mesure douteuse, morceau très discret) : on retient
      // ce qu'on a le droit de retenir, pas plus — et dans l'autre sens non
      // plus, on ne pousse pas plus haut que permis.
      expect(
        crossfadeGain(outgoing: -30, incoming: -2),
        closeTo(pow(10, -kCrossfadeMatchMaxDb / 20).toDouble(), 0.001),
      );
      expect(
        crossfadeGain(outgoing: -2, incoming: -30),
        closeTo(pow(10, kCrossfadeMatchMaxDb / 20).toDouble(), 0.001),
      );
      // Sans mesure des deux côtés, aucune correction.
      expect(crossfadeGain(outgoing: null, incoming: -8), 1);
      expect(crossfadeGain(outgoing: -8, incoming: null), 1);
      expect(crossfadePlan(fade: fade, total: total).gain, 1);
    });

    test('le volume posé au croisement ne bouge plus ensuite', () {
      // Le cœur de l'idée #104. Le titre entrant joue au niveau exact du
      // sortant, et il le tient jusqu'à sa dernière note : plus de remontée
      // d'après-passage, donc plus de dérive de volume sous une musique
      // installée — c'est elle, et non le croisement, qui s'entendait comme
      // quelqu'un qui monte le son.
      const sortantDb = -12.0;
      for (final entrantDb in [-18.0, -14.0, -12.0, -10.0, -6.0]) {
        final gain = crossfadeGain(outgoing: sortantDb, incoming: entrantDb);
        for (final tenu in [0.55, 0.8, 1.0]) {
          final cible = crossfadeTarget(gain: gain, playing: tenu);
          // Ce que les deux titres font ENTENDRE, une fois le passage fini.
          final sortantSonne = sortantDb + 20 * log(tenu) / ln10;
          final entrantSonne = entrantDb + 20 * log(cible) / ln10;
          // Égalité parfaite tant que la correction tient dans ses bornes.
          final borne = cible >= 1 || cible <= kCrossfadeVolumeFloor;
          if (!borne) {
            expect(entrantSonne, closeTo(sortantSonne, 0.001));
          }
          expect(cible, lessThanOrEqualTo(1));
          expect(cible, greaterThanOrEqualTo(kCrossfadeVolumeFloor - 1e-9));
        }
      }
    });

    test('une série de croisements ne fait ni sombrer ni enfler le volume', () {
      // Le revers de la mise à niveau : sans plancher, une file de morceaux
      // gravés fort descendrait marche après marche jusqu'au silence.
      var volume = 1.0;
      for (var i = 0; i < 20; i++) {
        volume = crossfadeTarget(gain: 0.501, playing: volume);
      }
      expect(volume, closeTo(kCrossfadeVolumeFloor, 0.001));

      // Et la file se redresse dès qu'un morceau gravé bas passe : c'est ce
      // que l'idée #101, qui ne savait que retenir, ne pouvait pas faire.
      for (var i = 0; i < 20; i++) {
        volume = crossfadeTarget(gain: 1.995, playing: volume);
      }
      expect(volume, 1);

      // Volume du sortant inconnu ou aberrant : on s'en tient à la mesure.
      expect(crossfadeTarget(gain: 0.6, playing: 0), closeTo(0.6, 1e-9));
      expect(crossfadeTarget(gain: 0.6, playing: 3), closeTo(0.6, 1e-9));
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
