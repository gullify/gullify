import 'package:audio_service/audio_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/yt_downloads_repository.dart';
import '../audio/audio_handler.dart';
import 'player.dart';
import 'yt_downloads.dart';

/// État de la pré-écoute d'une chanson YouTube (avant téléchargement), tel que
/// l'affiche la rangée de la recherche. Ce n'est plus qu'une lecture du lecteur
/// principal : [videoId] est le titre YouTube qu'il joue, s'il en joue un.
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

/// Le titre YouTube en pré-écoute dans une fiche du lecteur principal, s'il
/// s'agit d'une pré-écoute.
String? previewVideoIdOf(MediaItem? item) =>
    item?.extras?[kPreviewVideoId] as String?;

/// Pré-écoute d'un titre YouTube : **le lecteur principal**, et rien d'autre
/// (idée #59).
///
/// Elle avait le sien, à l'écart, pour ne pas jeter la file en cours. On y
/// perdait tout le reste : le lecteur ne s'ouvrait pas, la notification ne
/// disait rien, l'écran éteint coupait le son (hors du service de premier plan,
/// Android suspend l'app), et un medley lancé dans la foulée se superposait —
/// il ne faisait taire que le lecteur principal, qui ne jouait pas. Une
/// pré-écoute est une écoute : elle passe par le lecteur principal comme une
/// chanson, et remplace la file comme une radio.
///
/// Ce qui reste ici n'est plus qu'un guichet : lancer le titre, et relire ce
/// que le lecteur principal en dit pour l'afficher dans la rangée.
final previewPlayerProvider =
    NotifierProvider<PreviewPlayer, PreviewState>(PreviewPlayer.new);

class PreviewPlayer extends Notifier<PreviewState> {
  /// Le dernier titre qui n'a pas pu se lancer. Le lecteur principal, lui, ne
  /// dit rien d'un flux injoignable — il reste sur sa fiche, à l'arrêt.
  String? _failed;

  @override
  PreviewState build() {
    final item = ref.watch(currentMediaItemProvider).value;
    final videoId = previewVideoIdOf(item);
    // Le lecteur principal joue autre chose (ou plus rien) : aucune rangée de
    // la recherche ne s'allume.
    if (videoId == null) return const PreviewState();

    final playback = ref.watch(playbackStateProvider).value;
    final processing = playback?.processingState;
    return PreviewState(
      videoId: videoId,
      playing: playback?.playing ?? false,
      loading: processing == AudioProcessingState.loading ||
          processing == AudioProcessingState.buffering,
      error: _failed == videoId,
      position: ref.watch(positionProvider).value ?? Duration.zero,
      duration: item?.duration,
    );
  }

  /// Vrai tant que le lecteur principal tient encore le titre. Un titre allé
  /// jusqu'au bout laisse sa fiche affichée mais le lecteur au repos : le
  /// reprendre demande de le relancer, pas de rappuyer sur « lecture ».
  bool get _held {
    final s = ref.read(playbackStateProvider).value?.processingState;
    return s == AudioProcessingState.ready ||
        s == AudioProcessingState.buffering ||
        s == AudioProcessingState.loading;
  }

  /// Bascule la pré-écoute du [song] : lance / met en pause / reprend.
  Future<void> toggle(YtSong song) async {
    if (song.videoId.isEmpty) return;
    final handler = ref.read(audioHandlerProvider);

    // Même titre, toujours chargé : simple pause / reprise du lecteur principal.
    if (state.videoId == song.videoId && !state.error && _held) {
      if (state.playing) {
        await handler.pause();
      } else {
        await handler.play();
      }
      return;
    }

    _failed = null;
    try {
      await handler.playPreview(
        videoId: song.videoId,
        url: ref.read(ytDownloadsRepositoryProvider).previewUrl(song.videoId),
        title: song.title,
        artist: song.artist,
        artwork: song.thumbnail.isEmpty ? null : song.thumbnail,
      );
    } catch (_) {
      _failed = song.videoId;
      state = state.copyWith(
        videoId: song.videoId,
        playing: false,
        loading: false,
        error: true,
      );
    }
  }
}
