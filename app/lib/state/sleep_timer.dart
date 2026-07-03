import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'player.dart';

/// Minuterie d'arrêt : met la lecture en pause à l'échéance, ou à la fin du
/// titre en cours (`endOfTrack`).
class SleepTimerState {
  const SleepTimerState({this.endsAt, this.endOfTrack = false});

  final DateTime? endsAt;
  final bool endOfTrack;

  bool get active => endsAt != null || endOfTrack;

  Duration? get remaining => endsAt?.difference(DateTime.now());
}

final sleepTimerProvider =
    NotifierProvider<SleepTimerNotifier, SleepTimerState>(
  SleepTimerNotifier.new,
);

class SleepTimerNotifier extends Notifier<SleepTimerState> {
  Timer? _timer;
  Timer? _tick;
  StreamSubscription<dynamic>? _trackSub;

  @override
  SleepTimerState build() {
    ref.onDispose(_cancelAll);
    return const SleepTimerState();
  }

  void start(Duration duration) {
    _cancelAll();
    state = SleepTimerState(endsAt: DateTime.now().add(duration));
    _timer = Timer(duration, _fire);
    // Rafraîchit l'affichage du temps restant.
    _tick = Timer.periodic(const Duration(seconds: 30), (_) {
      state = SleepTimerState(endsAt: state.endsAt);
    });
  }

  /// S'arrête à la fin du titre en cours (pause au changement de piste).
  void startEndOfTrack() {
    _cancelAll();
    state = const SleepTimerState(endOfTrack: true);
    final handler = ref.read(audioHandlerProvider);
    final startId = handler.mediaItem.value?.id;
    _trackSub = handler.mediaItem.listen((item) {
      if (item != null && item.id != startId) _fire();
    });
  }

  void cancel() {
    _cancelAll();
    state = const SleepTimerState();
  }

  void _fire() {
    ref.read(audioHandlerProvider).pause();
    cancel();
  }

  void _cancelAll() {
    _timer?.cancel();
    _tick?.cancel();
    _trackSub?.cancel();
    _timer = null;
    _tick = null;
    _trackSub = null;
  }
}
