import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

import '../api/library_repository.dart';
import '../models/album.dart';
import '../models/song.dart';
import 'library.dart';
import 'player.dart';

/// Durée d'un extrait, et les fondus qui l'ouvrent et le ferment. Un medley
/// n'est pas une écoute : il donne la couleur d'un artiste le temps de choisir
/// son genre, sans jamais couper net.
const kMedleyExcerpt = Duration(seconds: 18);
const kMedleyFadeIn = Duration(milliseconds: 1500);
const kMedleyFadeOut = Duration(milliseconds: 2000);

/// Étale un choix sur toute une liste plutôt que d'en prendre la tête : sur
/// une discographie, les quatre premiers albums se ressemblent souvent, alors
/// que le premier, un du milieu et le dernier racontent l'artiste.
List<T> spreadPick<T>(List<T> items, int max) {
  if (max <= 0 || items.isEmpty) return const [];
  if (items.length <= max) return List<T>.of(items);
  return [
    for (var i = 0; i < max; i++) items[(i * items.length) ~/ max],
  ];
}

/// Un medley se promène : une chanson par album, en tournant, plutôt que
/// cinq titres du même disque.
List<Song> pickMedleySongs(List<Song> songs, {int max = 4}) {
  final byAlbum = <int, List<Song>>{};
  for (final s in songs) {
    byAlbum.putIfAbsent(s.albumId ?? 0, () => []).add(s);
  }
  final picked = <Song>[];
  var round = 0;
  while (picked.length < max) {
    var addedThisRound = false;
    for (final album in byAlbum.values) {
      if (picked.length >= max) break;
      if (round < album.length) {
        picked.add(album[round]);
        addedThisRound = true;
      }
    }
    if (!addedThisRound) break;
    round++;
  }
  return picked;
}

/// Où commencer un extrait : ni l'intro, ni le fondu final. Un titre trop
/// court se joue depuis le début — mieux vaut ça que le silence de la fin.
Duration medleyStart(int durationSeconds) {
  if (durationSeconds <= kMedleyExcerpt.inSeconds + 10) return Duration.zero;
  final wanted = (durationSeconds * 0.28).round().clamp(20, 90);
  final latest = durationSeconds - kMedleyExcerpt.inSeconds - 2;
  return Duration(seconds: wanted > latest ? latest : wanted);
}

/// État du medley : de quoi afficher ce qui joue, et rien de plus.
class MedleyState {
  const MedleyState({
    this.loading = false,
    this.current,
    this.index = 0,
    this.total = 0,
    this.error = false,
  });

  final bool loading;
  final Song? current;

  /// Rang de l'extrait en cours (1-based), 0 quand rien ne joue.
  final int index;
  final int total;
  final bool error;

  bool get active => loading || current != null;
}

/// Lecteur de medley : un [AudioPlayer] just_audio dédié, comme la pré-écoute
/// YouTube — le lecteur principal garde sa file et sa notification, on ne fait
/// que l'interrompre le temps de choisir.
final medleyPlayerProvider =
    NotifierProvider<MedleyPlayer, MedleyState>(MedleyPlayer.new);

class MedleyPlayer extends Notifier<MedleyState> {
  AudioPlayer? _player;
  Timer? _next;
  List<Song> _queue = const [];

  /// Génération courante : chaque start/stop l'incrémente, et tout ce qui
  /// dormait (fondu en cours, minuterie) se tait en constatant qu'il n'est
  /// plus de son temps.
  int _gen = 0;

  @override
  MedleyState build() {
    ref.onDispose(_dispose);
    // Si la musique repart pour de bon, le medley s'efface : jamais deux sons.
    ref.listen(playbackStateProvider, (_, next) {
      if ((next.value?.playing ?? false) && state.active) stop();
    });
    return const MedleyState();
  }

  /// Rassemble de quoi faire un medley : une chanson prise au milieu de
  /// quelques albums étalés sur la discographie, et à défaut les titres les
  /// plus joués de l'artiste.
  Future<List<Song>> _gather(int artistId) async {
    final repo = ref.read(libraryRepositoryProvider);
    final detail = await ref.read(artistDetailProvider(artistId).future);

    final albums = spreadPick<Album>(detail.albums, 4);
    final details = await Future.wait([
      for (final a in albums)
        repo.albumDetail(a.id).then<AlbumDetail?>((d) => d).catchError((_) => null),
    ]);

    final songs = <Song>[
      for (final d in details)
        if (d != null && d.songs.isNotEmpty) d.songs[d.songs.length ~/ 2],
    ];
    if (songs.isNotEmpty) return songs;
    return pickMedleySongs(detail.topTracks);
  }

  /// Lance le medley d'un artiste (ou l'arrête s'il tourne déjà).
  Future<void> toggle(int artistId) async {
    if (state.active) return stop();

    final gen = ++_gen;
    state = const MedleyState(loading: true);

    // Le lecteur principal se tait : on écoute pour choisir, pas pour écouter.
    try {
      await ref.read(audioHandlerProvider).pause();
    } catch (_) {}

    List<Song> songs;
    try {
      songs = await _gather(artistId);
    } catch (_) {
      songs = const [];
    }
    if (gen != _gen) return;
    if (songs.isEmpty) {
      state = const MedleyState(error: true);
      return;
    }

    _queue = songs;
    await _playAt(0, gen);
  }

  Future<void> _playAt(int i, int gen) async {
    if (gen != _gen || _queue.isEmpty) return;
    // Le medley tourne en boucle : on choisit un genre quand on est prêt, pas
    // quand la musique s'arrête.
    final index = i % _queue.length;
    final song = _queue[index];
    final player = _ensurePlayer();

    state = MedleyState(
      loading: true,
      current: song,
      index: index + 1,
      total: _queue.length,
    );

    try {
      await player.setVolume(0);
      await player.setUrl(
        ref.read(libraryRepositoryProvider).streamUrl(song),
        initialPosition: medleyStart(song.duration),
      );
      if (gen != _gen) return;
      await player.play();
    } catch (_) {
      if (gen != _gen) return;
      // Un titre illisible ne doit pas tuer le medley : on passe au suivant.
      _next = Timer(const Duration(milliseconds: 200), () => _playAt(i + 1, gen));
      return;
    }
    if (gen != _gen) return;

    state = MedleyState(
      current: song,
      index: index + 1,
      total: _queue.length,
    );

    await _fade(player, 0, 1, kMedleyFadeIn, gen);
    if (gen != _gen) return;

    final untilFadeOut = kMedleyExcerpt - kMedleyFadeIn - kMedleyFadeOut;
    _next = Timer(untilFadeOut.isNegative ? Duration.zero : untilFadeOut, () async {
      if (gen != _gen) return;
      await _fade(player, 1, 0, kMedleyFadeOut, gen);
      if (gen != _gen) return;
      await _playAt(i + 1, gen);
    });
  }

  /// Fondu à la main : just_audio ne monte pas le son tout seul, et un extrait
  /// qui commence à plein volume au milieu d'un couplet fait sursauter.
  Future<void> _fade(
    AudioPlayer player,
    double from,
    double to,
    Duration duration,
    int gen,
  ) async {
    const steps = 15;
    final step = Duration(microseconds: duration.inMicroseconds ~/ steps);
    for (var i = 1; i <= steps; i++) {
      await Future<void>.delayed(step);
      if (gen != _gen) return;
      try {
        await player.setVolume(from + (to - from) * i / steps);
      } catch (_) {
        return;
      }
    }
  }

  AudioPlayer _ensurePlayer() => _player ??= AudioPlayer();

  /// Arrête le medley et remet l'état à zéro. Appelé à la fermeture du
  /// dialogue, donc parfois après que le provider lui-même a disparu (fin de
  /// l'écran, d'où le garde-fou) — le son, lui, doit se taire dans tous les
  /// cas.
  Future<void> stop() async {
    _gen++;
    _next?.cancel();
    _next = null;
    _queue = const [];
    if (ref.mounted) state = const MedleyState();
    try {
      await _player?.stop();
    } catch (_) {}
  }

  void _dispose() {
    _gen++;
    _next?.cancel();
    _player?.dispose();
    _player = null;
  }
}
