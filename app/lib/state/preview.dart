import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../api/yt_downloads_repository.dart';
import '../audio/tuned_player.dart';
import 'player.dart';
import 'yt_downloads.dart';

/// État de la pré-écoute d'une chanson YouTube (avant téléchargement).
/// Un seul titre est en pré-écoute à la fois; [videoId] null = rien.
class PreviewState {
  const PreviewState({
    this.videoId,
    this.playing = false,
    this.loading = false,
    this.error = false,
    this.position = Duration.zero,
    this.duration,
  });

  final String? videoId;
  final bool playing;
  final bool loading;
  final bool error;
  final Duration position;
  final Duration? duration;

  bool isActive(String id) => videoId == id;

  PreviewState copyWith({
    String? videoId,
    bool? playing,
    bool? loading,
    bool? error,
    Duration? position,
    Duration? duration,
  }) =>
      PreviewState(
        videoId: videoId ?? this.videoId,
        playing: playing ?? this.playing,
        loading: loading ?? this.loading,
        error: error ?? this.error,
        position: position ?? this.position,
        duration: duration ?? this.duration,
      );
}

/// Lecteur de pré-écoute : un lecteur emprunté à la réserve commune, distinct du
/// lecteur principal (audio_service) pour ne pas jeter la file en cours — mais
/// réglé comme lui (tuned_player.dart). Il est rendu dès qu'on arrête la
/// pré-écoute. Lancer une pré-écoute met le lecteur principal en pause pour
/// éviter deux sons simultanés.
final previewPlayerProvider =
    NotifierProvider<PreviewPlayer, PreviewState>(PreviewPlayer.new);

class PreviewPlayer extends Notifier<PreviewState> {
  PlayerLease? _lease;
  final List<StreamSubscription<dynamic>> _subs = [];

  // La pré-écoute joue hors du foreground service : sans ça, Android suspend le
  // process et coupe le son dès que le téléphone tombe en veille. Le verrou
  // réseau du lecteur (tuned_player.dart) garde la Wi-Fi et le CPU actifs, mais
  // seul le service de premier plan protège du gel de l'app — on maintient donc
  // l'appareil éveillé tant que la pré-écoute joue, et on relâche à la pause.
  bool _awake = false;
  Future<void> _keepAwake(bool on) async {
    if (_awake == on) return;
    _awake = on;
    try {
      await WakelockPlus.toggle(enable: on);
    } catch (_) {}
  }

  @override
  PreviewState build() {
    ref.onDispose(_dispose);
    // Si le lecteur principal se (re)met à jouer, on coupe la pré-écoute :
    // jamais deux sons en même temps.
    ref.listen(playbackStateProvider, (_, next) {
      final playing = next.value?.playing ?? false;
      if (playing && state.videoId != null) stop();
    });
    return const PreviewState();
  }

  /// Le lecteur de la pré-écoute en cours, emprunté à la réserve au premier
  /// besoin. Ses écoutes vont et viennent avec lui : rendu, il repart faire du
  /// son ailleurs et ne doit plus rien nous dire.
  PlayerLease _ensureLease() {
    final existing = _lease;
    if (existing != null) return existing;
    final lease = leaseGullifyPlayer(use: PlayerUse.streaming);
    final p = lease.player;
    _subs.add(p.playerStateStream.listen((s) {
      final atEnd = s.processingState == ProcessingState.completed;
      final playing = s.playing && !atEnd;
      state = state.copyWith(
        playing: playing,
        loading: s.processingState == ProcessingState.loading ||
            s.processingState == ProcessingState.buffering,
      );
      _keepAwake(playing);
      if (atEnd) {
        // Fin du titre : on revient au début, prêt à ré-écouter.
        p.pause();
        p.seek(Duration.zero);
      }
    }));
    _subs.add(p.positionStream.listen((pos) {
      if (state.videoId != null) state = state.copyWith(position: pos);
    }));
    _subs.add(p.durationStream.listen((d) {
      state = state.copyWith(duration: d);
    }));
    _lease = lease;
    return lease;
  }

  /// Bascule la pré-écoute du [song] : lance / met en pause / reprend.
  Future<void> toggle(YtSong song) async {
    if (song.videoId.isEmpty) return;
    final lease = _ensureLease();
    final p = lease.player;

    // Même titre : simple pause / reprise.
    if (state.videoId == song.videoId) {
      if (p.playing) {
        await p.pause();
      } else {
        await p.play();
      }
      return;
    }

    // Nouveau titre : on coupe le lecteur principal pour éviter deux sons.
    try {
      await ref.read(audioHandlerProvider).pause();
    } catch (_) {}
    // Le lecteur principal qui se tait peut avoir arrêté la pré-écoute en
    // chemin : le lecteur est alors rendu, et ce n'est plus à nous d'y toucher.
    if (!identical(_lease, lease)) return;

    state = PreviewState(videoId: song.videoId, loading: true);
    final url = ref.read(ytDownloadsRepositoryProvider).previewUrl(song.videoId);
    try {
      await p.setUrl(url);
      if (!identical(_lease, lease)) return;
      await p.play();
    } catch (_) {
      state = PreviewState(videoId: song.videoId, error: true);
    }
  }

  /// Arrête toute pré-écoute et remet l'état à zéro. Le lecteur retourne à la
  /// réserve : rien ne sert d'en garder un allumé entre deux écoutes, et la
  /// prochaine pré-écoute en réempruntera un (idée #58).
  Future<void> stop() async {
    await _keepAwake(false);
    final lease = _lease;
    _lease = null;
    await _dropSubs();
    await lease?.give();
    state = const PreviewState();
  }

  Future<void> _dropSubs() async {
    final subs = List.of(_subs);
    _subs.clear();
    for (final s in subs) {
      await s.cancel();
    }
  }

  void _dispose() {
    _keepAwake(false);
    final lease = _lease;
    _lease = null;
    _dropSubs();
    lease?.give();
  }
}
