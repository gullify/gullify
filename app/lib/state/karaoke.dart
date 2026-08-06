import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/library_repository.dart';
import 'library.dart';
import 'player.dart';

/// Mode karaoké (idée #63) : le serveur rend une version « voix atténuée » du
/// titre (annulation du centre du mixage — voir src/Karaoke.php), et le
/// lecteur bascule dessus sans perdre sa place.
///
/// Le rendu se fait en tâche de fond côté serveur : on le demande, puis on
/// redemande jusqu'à ce qu'il soit prêt. Tant qu'il ne l'est pas, on ne
/// bascule pas — mieux vaut attendre deux secondes que d'entendre la version
/// d'origine en croyant le mode actif.
enum KaraokePhase { off, preparing, on, unavailable }

class KaraokeStateInfo {
  const KaraokeStateInfo({this.phase = KaraokePhase.off, this.reason});

  final KaraokePhase phase;

  /// Pourquoi c'est indisponible, quand ça l'est (voir [KaraokeStatus]).
  final String? reason;

  bool get busy => phase == KaraokePhase.preparing;
  bool get active => phase == KaraokePhase.on;
}

/// Combien de temps on attend un rendu avant d'abandonner : ffmpeg tourne à
/// ~90× le temps réel, un titre est prêt en quelques secondes, mais le
/// serveur peut avoir d'autres rendus en file.
const _prepareTimeout = Duration(seconds: 90);
const _pollInterval = Duration(milliseconds: 1200);

final karaokeProvider = NotifierProvider<KaraokeNotifier, KaraokeStateInfo>(
  KaraokeNotifier.new,
);

class KaraokeNotifier extends Notifier<KaraokeStateInfo> {
  bool _cancelled = false;

  @override
  KaraokeStateInfo build() {
    // Un changement de titre ne coupe pas le mode (on chante l'album entier),
    // mais une préparation en cours ne concerne plus le bon morceau.
    ref.onDispose(() => _cancelled = true);
    return const KaraokeStateInfo();
  }

  /// Active le mode pour le titre en cours ([filePath]), ou le coupe.
  Future<void> toggle(String? filePath) async {
    if (state.active) {
      await off();
      return;
    }
    if (state.busy || filePath == null) return;
    await on(filePath);
  }

  Future<void> off() async {
    _cancelled = true;
    state = const KaraokeStateInfo();
    await ref.read(audioHandlerProvider).setKaraoke(false);
  }

  Future<void> on(String filePath) async {
    _cancelled = false;
    state = const KaraokeStateInfo(phase: KaraokePhase.preparing);

    final repo = ref.read(libraryRepositoryProvider);
    final deadline = DateTime.now().add(_prepareTimeout);
    while (!_cancelled) {
      KaraokeStatus status;
      try {
        status = await repo.prepareKaraoke(filePath);
      } catch (_) {
        state = const KaraokeStateInfo(
          phase: KaraokePhase.unavailable,
          reason: 'network',
        );
        return;
      }
      if (_cancelled) return;

      switch (status.state) {
        case KaraokeState.ready:
          await ref.read(audioHandlerProvider).setKaraoke(true);
          if (_cancelled) return;
          state = const KaraokeStateInfo(phase: KaraokePhase.on);
          return;
        case KaraokeState.unavailable:
          state = KaraokeStateInfo(
            phase: KaraokePhase.unavailable,
            reason: status.reason,
          );
          return;
        case KaraokeState.rendering:
          if (DateTime.now().isAfter(deadline)) {
            state = const KaraokeStateInfo(
              phase: KaraokePhase.unavailable,
              reason: 'timeout',
            );
            return;
          }
          await Future<void>.delayed(_pollInterval);
      }
    }
  }

  /// Message à montrer quand le karaoké n'est pas possible.
  static String explain(String? reason) => switch (reason) {
        'mono' => 'Ce titre est mixé trop au centre : il n\'y a pas de voix à '
            'retirer sans effacer le reste.',
        'source' => 'Ce titre n\'est pas sur le serveur : pas de version '
            'karaoké possible.',
        'network' => 'Serveur injoignable : réessaie dans un instant.',
        'timeout' => 'Le serveur met trop de temps à préparer ce titre. '
            'Réessaie dans un instant.',
        _ => 'Impossible de préparer la version karaoké de ce titre.',
      };
}
