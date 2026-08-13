// Le réveil matinal (idée #81). Ce qu'un test peut vérifier d'un réveil :
// l'heure qu'il vise, les jours qu'il respecte, et le fait que son réglage
// survive au stockage. Le reste (l'alarme Android, l'ouverture de l'app à
// 7 h) ne se vérifie que sur le téléphone.
import 'package:flutter_test/flutter_test.dart';
import 'package:gullify/audio/fade.dart';
import 'package:gullify/models/alarm.dart';
import 'package:gullify/models/game_source.dart';

void main() {
  group('prochaine sonnerie', () {
    const alarm = AlarmConfig(enabled: true, hour: 7, minute: 0);

    test('aujourd\'hui si l\'heure n\'est pas passée', () {
      final next = alarm.nextRing(DateTime(2026, 8, 13, 6, 30));
      expect(next, DateTime(2026, 8, 13, 7, 0));
    });

    test('demain si l\'heure est passée', () {
      final next = alarm.nextRing(DateTime(2026, 8, 13, 7, 1));
      expect(next, DateTime(2026, 8, 14, 7, 0));
    });

    test('à la minute pile, c\'est pour demain (elle vient de sonner)', () {
      final next = alarm.nextRing(DateTime(2026, 8, 13, 7, 0));
      expect(next, DateTime(2026, 8, 14, 7, 0));
    });

    test('éteint : pas de sonnerie', () {
      expect(
        const AlarmConfig(hour: 7).nextRing(DateTime(2026, 8, 13, 6)),
        isNull,
      );
    });

    test('saute les jours non cochés', () {
      // Jeudi 13 août 2026 ; réveil le lundi et le vendredi seulement.
      const week = AlarmConfig(enabled: true, hour: 7, days: {1, 5});
      expect(
        week.nextRing(DateTime(2026, 8, 13, 8)),
        DateTime(2026, 8, 14, 7, 0),
      );
      // Vendredi soir : la prochaine est le lundi.
      expect(
        week.nextRing(DateTime(2026, 8, 14, 22)),
        DateTime(2026, 8, 17, 7, 0),
      );
    });

    test('un seul jour coché : la semaine d\'après', () {
      const sunday = AlarmConfig(enabled: true, hour: 9, days: {7});
      expect(
        sunday.nextRing(DateTime(2026, 8, 16, 10)), // dimanche, 10 h
        DateTime(2026, 8, 23, 9, 0),
      );
    });

    test('la semaine complète vaut « tous les jours »', () {
      const full = AlarmConfig(enabled: true, hour: 7, days: {1, 2, 3, 4, 5, 6, 7});
      expect(full.everyDay, isTrue);
      expect(full.daysMask, 0);
      expect(full.daysLabel, 'Tous les jours');
    });
  });

  group('masque des jours', () {
    test('lundi = bit 0, dimanche = bit 6', () {
      expect(const AlarmConfig(days: {1}).daysMask, 1);
      expect(const AlarmConfig(days: {7}).daysMask, 64);
      expect(const AlarmConfig(days: {1, 5}).daysMask, 1 | 16);
    });

    test('rien de coché = tous les jours', () {
      expect(const AlarmConfig().daysMask, 0);
    });
  });

  group('réglage mémorisé', () {
    test('fait l\'aller-retour', () {
      const config = AlarmConfig(
        enabled: true,
        hour: 6,
        minute: 45,
        days: {1, 2, 3, 4, 5},
        source: GameSource(
          mode: GameSourceMode.playlists,
          playlists: [GameSourcePlaylist(id: 3, name: 'Matin')],
        ),
        sound: AlarmSound.music,
        riseMinutes: 8,
        volumePercent: 40,
        snoozeMinutes: 12,
      );
      expect(AlarmConfig.decode(config.encode()), config);
    });

    test('réglage illisible : réveil éteint, pas de sonnerie surprise', () {
      expect(AlarmConfig.decode('pas du json'), AlarmConfig.off);
      expect(AlarmConfig.decode(null).enabled, isFalse);
      expect(AlarmConfig.decode('{}').enabled, isFalse);
    });

    test('valeurs aberrantes ramenées dans les bornes', () {
      final wild = AlarmConfig.decode(
        '{"enabled":true,"hour":99,"minute":-5,"rise":600,"volume":0,'
        '"snooze":999,"days":[0,3,42]}',
      );
      expect(wild.hour, 23);
      expect(wild.minute, 0);
      expect(wild.riseMinutes, AlarmConfig.maxRiseMinutes);
      expect(wild.volumePercent, 10);
      expect(wild.snoozeMinutes, 30);
      expect(wild.days, {3});
    });
  });

  group('montée du volume', () {
    test('part de zéro, finit à plein, sans marche audible', () {
      final ramp = fadeRamp(
        from: 0,
        to: 1,
        over: const Duration(minutes: 5),
        tick: const Duration(seconds: 2),
      );
      expect(ramp.length, 150);
      expect(ramp.first, closeTo(1 / 150, 0.0001));
      expect(ramp.last, 1.0);
      // Strictement croissante : le réveil ne redescend jamais.
      for (var i = 1; i < ramp.length; i++) {
        expect(ramp[i], greaterThan(ramp[i - 1]));
      }
    });

    test('le pas large ne change rien au fondu du lecteur', () {
      expect(
        fadeRamp(from: 0, to: 1, over: const Duration(seconds: 1)).length,
        25,
      );
    });
  });

  group('temps restant', () {
    test('s\'écrit comme on le dit', () {
      expect(formatUntilRing(const Duration(minutes: 45)), 'dans 45 min');
      expect(formatUntilRing(const Duration(hours: 7)), 'dans 7 h');
      expect(
        formatUntilRing(const Duration(hours: 7, minutes: 20)),
        'dans 7 h 20',
      );
      expect(formatUntilRing(const Duration(seconds: 30)),
          'dans moins d\'une minute');
    });
  });

  group('résumé du réglage', () {
    test('les jours ouvrés et le week-end ont leur mot', () {
      expect(
        const AlarmConfig(days: {1, 2, 3, 4, 5}).daysLabel,
        'Du lundi au vendredi',
      );
      expect(const AlarmConfig(days: {6, 7}).daysLabel, 'Le week-end');
      expect(const AlarmConfig(days: {2, 4}).daysLabel, 'Mar, Jeu');
    });

    test('l\'heure est écrite sur deux chiffres', () {
      expect(const AlarmConfig(hour: 7, minute: 5).timeLabel, '07:05');
    });

    test('la sonnerie l\'emporte sur le vivier dans le résumé', () {
      expect(const AlarmConfig(sound: AlarmSound.buzz).soundLabel, 'Sonnerie');
      expect(
        const AlarmConfig().soundLabel,
        'Toute la bibliothèque',
      );
    });
  });
}
