import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../audio/alarm_platform.dart';
import '../models/alarm.dart';
import 'library.dart';
import 'player.dart';

const _storage = FlutterSecureStorage();
const _key = 'alarm_config';

/// Ce que le réveil a besoin de savoir de lui-même.
class AlarmState {
  const AlarmState({
    this.config = AlarmConfig.off,
    this.next,
    this.ringing = false,
    this.snoozedUntil,
    this.exactAllowed = true,
    this.fellBackToTone = false,
  });

  final AlarmConfig config;

  /// La prochaine sonnerie posée (celle du système quand il sait la dire).
  final DateTime? next;

  /// Le réveil sonne en ce moment.
  final bool ringing;

  /// Rappel demandé : l'heure à laquelle il revient.
  final DateTime? snoozedUntil;

  /// L'alarme exacte est permise. Sans elle, Android a le droit de décaler la
  /// sonnerie — l'écran de réglage le dit et propose d'aller la permettre.
  final bool exactAllowed;

  /// La sonnerie a remplacé la musique (serveur injoignable au réveil).
  final bool fellBackToTone;

  AlarmState copyWith({
    AlarmConfig? config,
    DateTime? next,
    bool clearNext = false,
    bool? ringing,
    DateTime? snoozedUntil,
    bool clearSnooze = false,
    bool? exactAllowed,
    bool? fellBackToTone,
  }) => AlarmState(
    config: config ?? this.config,
    next: clearNext ? null : (next ?? this.next),
    ringing: ringing ?? this.ringing,
    snoozedUntil: clearSnooze ? null : (snoozedUntil ?? this.snoozedUntil),
    exactAllowed: exactAllowed ?? this.exactAllowed,
    fellBackToTone: fellBackToTone ?? this.fellBackToTone,
  );
}

/// Le réveil matinal (idée #81).
///
/// Le déclenchement ne vient pas d'ici — une app fermée ne compte pas les
/// minutes. C'est une alarme exacte Android qui réveille le téléphone et
/// ouvre l'app ([alarm_platform.dart]) ; ce contrôleur choisit alors la
/// musique, monte le volume et pose le rappel. Il garde tout de même sa
/// propre minuterie : app ouverte, elle rattrape une alarme système qui
/// n'aurait pas parlé.
class AlarmController extends Notifier<AlarmState> {
  Timer? _watch;
  Timer? _autoStop;
  DateTime? _lastRing;

  /// Au-delà, une sonnerie que personne n'arrête s'arrête d'elle-même : un
  /// téléphone oublié sur la table de nuit ne joue pas jusqu'au soir.
  static const _maxRing = Duration(minutes: 45);

  /// Ce qu'on accepte de rattraper : une sonnerie d'il y a une demi-heure
  /// mérite encore d'être jouée, celle d'hier soir non.
  static const _catchUp = Duration(minutes: 30);

  @override
  AlarmState build() {
    ref.onDispose(() {
      _watch?.cancel();
      _autoStop?.cancel();
    });
    _restore();
    alarmOnRing(() => unawaited(ring()));
    // Minuterie de secours : tant que l'app tourne, elle sonne à l'heure même
    // si l'alarme système s'est perdue (permission retirée, constructeur
    // fantaisiste). Elle ne coûte qu'un réveil par demi-minute.
    _watch = Timer.periodic(const Duration(seconds: 30), (_) => _check());
    return const AlarmState();
  }

  Future<void> _restore() async {
    AlarmConfig config = AlarmConfig.off;
    try {
      config = AlarmConfig.decode(await _storage.read(key: _key));
    } catch (_) {
      // Stockage muet (tests, plateforme sans plugin) : pas de réveil.
    }
    state = state.copyWith(config: config, next: config.nextRing(DateTime.now()));
    // Repose l'alarme à chaque démarrage : une mise à jour de l'app, un
    // effacement des réglages système ou un redémarrage raté l'auraient
    // laissée sans alarme, et un réveil muet ne se remarque qu'au réveil.
    await _program();
    await checkPending();
  }

  /// Enregistre le réglage et le porte au système.
  Future<void> set(AlarmConfig config) async {
    state = state.copyWith(config: config, clearSnooze: true);
    try {
      await _storage.write(key: _key, value: config.encode());
    } catch (_) {}
    await _program();
  }

  Future<void> _program() async {
    final config = state.config;
    final next = await alarmConfigure(
      enabled: config.enabled,
      hour: config.hour,
      minute: config.minute,
      daysMask: config.daysMask,
    );
    state = state.copyWith(
      next: next ?? config.nextRing(DateTime.now()),
      clearNext: !config.enabled,
      exactAllowed: await alarmCanRingExactly(),
    );
  }

  /// Rouvre le réglage système de l'alarme exacte (Android 12+).
  Future<void> askExactPermission() async {
    await alarmRequestExactPermission();
    state = state.copyWith(exactAllowed: await alarmCanRingExactly());
  }

  /// Une sonnerie a retenti pendant que l'app était fermée (ou la
  /// notification n'a été touchée que plus tard) : on la rattrape.
  Future<void> checkPending() async {
    if (state.ringing) return;
    final fired = await alarmPendingRing();
    if (fired == null) return;
    if (DateTime.now().difference(fired) > _catchUp) {
      // Trop vieille : on ne réveille pas quelqu'un à midi pour l'alarme de 7 h.
      await alarmHandled();
      return;
    }
    await ring();
  }

  /// Fait sonner le réveil, tout de suite.
  Future<void> ring() async {
    final now = DateTime.now();
    // Deux chemins peuvent mener ici en même temps (l'alarme système et la
    // minuterie de secours) : une seule sonnerie.
    if (state.ringing) return;
    if (_lastRing != null && now.difference(_lastRing!) < const Duration(minutes: 5)) {
      return;
    }
    _lastRing = now;
    state = state.copyWith(
      ringing: true,
      clearSnooze: true,
      fellBackToTone: false,
    );
    // Le filet audible du natif n'a plus lieu d'être : c'est l'app qui joue.
    await alarmHandled();
    final config = state.config;
    await alarmSetVolume(config.volumePercent);

    final handler = ref.read(audioHandlerProvider);
    var played = false;
    if (config.sound == AlarmSound.music) {
      try {
        final songs = await ref
            .read(libraryRepositoryProvider)
            .randomSongs(limit: 60, source: config.source)
            .timeout(const Duration(seconds: 25));
        if (songs.isNotEmpty) {
          await handler.playSongs(songs);
          played = true;
        }
      } catch (_) {
        // Serveur injoignable, session perdue, vivier vide : on ne rate pas un
        // réveil pour si peu — la sonnerie embarquée prend le relais.
      }
    }
    if (!played) {
      await handler.playAlarmTone();
      if (config.sound == AlarmSound.music) {
        state = state.copyWith(fellBackToTone: true);
      }
    }
    unawaited(handler.startWakeFade(Duration(minutes: config.riseMinutes)));

    _autoStop?.cancel();
    _autoStop = Timer(_maxRing, () => unawaited(stop()));
    await _refreshNext();
  }

  /// Arrête la sonnerie et rend le volume d'avant.
  Future<void> stop() async {
    _autoStop?.cancel();
    if (state.ringing) await ref.read(audioHandlerProvider).pause();
    await alarmRestoreVolume();
    await alarmHandled();
    state = state.copyWith(ringing: false);
    await _refreshNext();
  }

  /// Garde la musique : le réveil s'efface, la lecture continue au volume où
  /// elle en est.
  Future<void> keepPlaying() async {
    _autoStop?.cancel();
    await alarmHandled();
    state = state.copyWith(ringing: false);
    await _refreshNext();
  }

  /// « Encore quelques minutes » : silence, et on repose l'alarme.
  Future<void> snooze() async {
    _autoStop?.cancel();
    if (state.ringing) await ref.read(audioHandlerProvider).pause();
    await alarmRestoreVolume();
    final at = DateTime.now().add(Duration(minutes: state.config.snoozeMinutes));
    await alarmArmAt(at);
    _lastRing = null;
    state = state.copyWith(ringing: false, snoozedUntil: at, next: at);
  }

  /// Essai : le réveil sonne dans une minute, écran éteint si on veut. C'est
  /// la seule façon de vérifier, sur son propre téléphone, que la sonnerie
  /// traverse bien la veille et l'écran verrouillé.
  Future<DateTime> testInAMinute() async {
    final at = DateTime.now().add(const Duration(minutes: 1));
    await alarmArmAt(at);
    _lastRing = null;
    state = state.copyWith(next: at);
    return at;
  }

  Future<void> _refreshNext() async {
    final next = await alarmNextRing() ?? state.config.nextRing(DateTime.now());
    state = state.copyWith(
      next: next,
      clearNext: !state.config.enabled && state.snoozedUntil == null,
      exactAllowed: await alarmCanRingExactly(),
    );
  }

  /// Filet de l'app ouverte : l'heure est passée et rien n'a sonné.
  void _check() {
    if (state.ringing) return;
    final due = state.snoozedUntil ?? state.next;
    if (due == null) return;
    final now = DateTime.now();
    if (now.isBefore(due)) return;
    if (now.difference(due) > _catchUp) {
      // Sonnerie manquée depuis trop longtemps (téléphone éteint, app en
      // sommeil) : on passe à la suivante sans réveiller personne.
      unawaited(_refreshNext());
      return;
    }
    unawaited(ring());
  }
}

final alarmProvider = NotifierProvider<AlarmController, AlarmState>(
  AlarmController.new,
);
