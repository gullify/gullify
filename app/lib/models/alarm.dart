import 'dart:convert';

import 'game_source.dart';

/// Ce que le réveil fait entendre.
enum AlarmSound {
  /// De la musique de la bibliothèque, choisie dans le vivier réglé.
  music,

  /// Une sonnerie, embarquée dans l'app : elle sonne sans réseau et sans
  /// serveur — le filet de celui qui a besoin d'être debout à 6 h.
  buzz,
}

/// Le réveil matinal (idée #81).
///
/// Une heure, des jours, un vivier musical, et une montée progressive : la
/// musique entre à volume nul et met [riseMinutes] à atteindre le volume
/// réglé. Le calcul de la prochaine sonnerie vit ici, à part de l'écran et du
/// natif : c'est la seule chose du réveil qu'un test puisse vérifier.
class AlarmConfig {
  const AlarmConfig({
    this.enabled = false,
    this.hour = 7,
    this.minute = 0,
    this.days = const {},
    this.source = GameSource.all,
    this.sound = AlarmSound.music,
    this.riseMinutes = 5,
    this.volumePercent = 65,
    this.snoozeMinutes = 9,
  });

  static const AlarmConfig off = AlarmConfig();

  /// Montée la plus longue proposée. Au-delà, la première moitié du réveil ne
  /// s'entend pas et on se rendort.
  static const int maxRiseMinutes = 20;

  final bool enabled;
  final int hour;
  final int minute;

  /// Jours de la semaine (1 = lundi … 7 = dimanche, comme DateTime.weekday).
  /// Vide : tous les jours.
  final Set<int> days;

  /// Où le réveil pioche sa musique — le même réglage que les jeux (idée #39).
  final GameSource source;

  final AlarmSound sound;

  /// Durée de la montée en volume, en minutes. Zéro : plein volume tout de
  /// suite (pour qui préfère être arraché du lit).
  final int riseMinutes;

  /// Volume média visé, en pourcentage du maximum de l'appareil.
  final int volumePercent;

  final int snoozeMinutes;

  bool get everyDay => days.isEmpty || days.length == 7;

  /// Masque des jours attendu par le natif : bit 0 = lundi … bit 6 = dimanche,
  /// et zéro pour « tous les jours ».
  int get daysMask {
    if (everyDay) return 0;
    var mask = 0;
    for (final d in days) {
      if (d >= 1 && d <= 7) mask |= 1 << (d - 1);
    }
    return mask;
  }

  /// La prochaine sonnerie après [from], ou `null` si le réveil est éteint.
  ///
  /// Passe par DateTime jour par jour plutôt que par une addition de durées :
  /// aux changements d'heure, un jour ne fait pas 24 h et le réveil doit
  /// quand même tomber à 7 h.
  DateTime? nextRing(DateTime from) {
    if (!enabled) return null;
    for (var i = 0; i <= 7; i++) {
      final day = DateTime(from.year, from.month, from.day + i, hour, minute);
      if (!day.isAfter(from)) continue;
      if (everyDay || days.contains(day.weekday)) return day;
    }
    return null;
  }

  /// Le réglage des jours, en une ligne.
  String get daysLabel {
    if (everyDay) return 'Tous les jours';
    const names = ['Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam', 'Dim'];
    final sorted = days.toList()..sort();
    if (sorted.length == 5 && sorted.every((d) => d <= 5)) {
      return 'Du lundi au vendredi';
    }
    if (sorted.length == 2 && sorted.first == 6 && sorted.last == 7) {
      return 'Le week-end';
    }
    return [for (final d in sorted) names[d - 1]].join(', ');
  }

  /// L'heure telle qu'elle s'affiche : « 07:05 ».
  String get timeLabel =>
      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

  String get soundLabel => switch (sound) {
    AlarmSound.music => source.label,
    AlarmSound.buzz => 'Sonnerie',
  };

  AlarmConfig copyWith({
    bool? enabled,
    int? hour,
    int? minute,
    Set<int>? days,
    GameSource? source,
    AlarmSound? sound,
    int? riseMinutes,
    int? volumePercent,
    int? snoozeMinutes,
  }) => AlarmConfig(
    enabled: enabled ?? this.enabled,
    hour: hour ?? this.hour,
    minute: minute ?? this.minute,
    days: days ?? this.days,
    source: source ?? this.source,
    sound: sound ?? this.sound,
    riseMinutes: riseMinutes ?? this.riseMinutes,
    volumePercent: volumePercent ?? this.volumePercent,
    snoozeMinutes: snoozeMinutes ?? this.snoozeMinutes,
  );

  String encode() => jsonEncode({
    'enabled': enabled,
    'hour': hour,
    'minute': minute,
    'days': days.toList()..sort(),
    'source': source.encode(),
    'sound': sound.name,
    'rise': riseMinutes,
    'volume': volumePercent,
    'snooze': snoozeMinutes,
  });

  /// Relit un réglage stocké. Toute valeur douteuse retombe sur le défaut :
  /// un réglage illisible ne doit jamais empêcher l'app de démarrer — mais il
  /// ne doit pas non plus allumer un réveil que personne n'a demandé.
  static AlarmConfig decode(String? raw) {
    if (raw == null || raw.isEmpty) return off;
    try {
      final json = jsonDecode(raw);
      if (json is! Map) return off;
      return AlarmConfig(
        enabled: json['enabled'] == true,
        hour: ((json['hour'] as num?)?.toInt() ?? 7).clamp(0, 23),
        minute: ((json['minute'] as num?)?.toInt() ?? 0).clamp(0, 59),
        days: {
          for (final d in json['days'] as List<dynamic>? ?? [])
            if (d is num && d >= 1 && d <= 7) d.toInt(),
        },
        source: GameSource.decode(json['source'] as String?),
        sound: AlarmSound.values.firstWhere(
          (s) => s.name == json['sound'],
          orElse: () => AlarmSound.music,
        ),
        riseMinutes: ((json['rise'] as num?)?.toInt() ?? 5)
            .clamp(0, maxRiseMinutes),
        volumePercent: ((json['volume'] as num?)?.toInt() ?? 65).clamp(10, 100),
        snoozeMinutes: ((json['snooze'] as num?)?.toInt() ?? 9).clamp(1, 30),
      );
    } catch (_) {
      return off;
    }
  }

  @override
  bool operator ==(Object other) =>
      other is AlarmConfig &&
      other.enabled == enabled &&
      other.hour == hour &&
      other.minute == minute &&
      other.days.length == days.length &&
      other.days.containsAll(days) &&
      other.source == source &&
      other.sound == sound &&
      other.riseMinutes == riseMinutes &&
      other.volumePercent == volumePercent &&
      other.snoozeMinutes == snoozeMinutes;

  @override
  int get hashCode => Object.hash(
    enabled,
    hour,
    minute,
    Object.hashAll(days.toList()..sort()),
    source,
    sound,
    riseMinutes,
    volumePercent,
    snoozeMinutes,
  );
}

/// Le temps qu'il reste avant la sonnerie, écrit comme on le dit : « dans
/// 7 h 20 », « dans 45 min ».
String formatUntilRing(Duration left) {
  if (left.isNegative) return 'maintenant';
  final hours = left.inHours;
  final minutes = left.inMinutes % 60;
  if (hours == 0 && minutes == 0) return 'dans moins d\'une minute';
  if (hours == 0) return 'dans $minutes min';
  if (minutes == 0) return 'dans $hours h';
  return 'dans $hours h $minutes';
}
