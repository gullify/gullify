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

/// Combien d'extraits il faut pour se faire une idée. Un artiste d'un seul
/// album donnait un seul extrait, et le medley tournait en rond sur la même
/// chanson : on va alors chercher plusieurs titres du même disque (idée #54).
const kMedleySongs = 5;

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

/// Ce qu'on prend d'un album, dans l'ordre : le milieu d'abord (un album s'y
/// reconnaît mieux que par sa première piste), puis des titres étalés sur tout
/// le disque. De quoi tenir un medley entier quand l'artiste n'a qu'un album.
List<Song> albumPicks(List<Song> songs, {int max = kMedleySongs}) {
  if (songs.isEmpty || max <= 0) return const [];
  final middle = songs[songs.length ~/ 2];
  return [
    middle,
    for (final s in spreadPick(songs, max))
      if (s.id != middle.id) s,
  ].take(max).toList();
}

/// Un medley se promène d'un album à l'autre : un titre de chacun, en
/// tournant, plutôt que cinq titres du même disque. Quand les albums viennent
/// à manquer, on repasse les chercher — mieux vaut cinq extraits d'un seul
/// disque qu'un seul extrait en boucle.
List<Song> medleyFromAlbums(List<List<Song>> albums, {int max = kMedleySongs}) {
  final picks = [for (final a in albums) albumPicks(a, max: max)];
  final picked = <Song>[];
  for (var round = 0; picked.length < max; round++) {
    var addedThisRound = false;
    for (final album in picks) {
      if (picked.length >= max) break;
      if (round < album.length) {
        picked.add(album[round]);
        addedThisRound = true;
      }
    }
    if (!addedThisRound) break;
  }
  return picked;
}

/// Un medley se promène : une chanson par album, en tournant, plutôt que
/// cinq titres du même disque.
List<Song> pickMedleySongs(List<Song> songs, {int max = kMedleySongs}) {
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

/// Le peu qu'un medley demande à un lecteur audio. L'interface existe pour
/// pouvoir faire tourner un medley en test avec un lecteur qui se comporte
/// comme just_audio — dont [play] ne rend la main qu'à l'arrêt du son.
abstract class MedleyAudio {
  Future<void> setVolume(double volume);
  Future<void> setUrl(String url, {Duration? initialPosition});

  /// Comme just_audio : le Future ne se referme qu'à la fin de la lecture, à
  /// la pause ou à l'arrêt. Ne jamais l'attendre pour enchaîner.
  Future<void> play();
  Future<void> stop();
  Future<void> dispose();
}

class _JustAudioMedley implements MedleyAudio {
  final AudioPlayer _player = AudioPlayer();

  @override
  Future<void> setVolume(double volume) => _player.setVolume(volume);

  @override
  Future<void> setUrl(String url, {Duration? initialPosition}) =>
      _player.setUrl(url, initialPosition: initialPosition);

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> stop() => _player.stop();

  @override
  Future<void> dispose() => _player.dispose();
}

/// Fabrique du lecteur de medley, remplaçable en test.
final medleyAudioProvider =
    Provider<MedleyAudio Function()>((ref) => _JustAudioMedley.new);

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
  MedleyAudio? _player;
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

  /// Rassemble de quoi faire un medley : [kMedleySongs] extraits pris sur des
  /// albums étalés sur la discographie — et plusieurs titres du même disque
  /// quand l'artiste n'en a qu'un. Les titres les plus joués complètent, et
  /// prennent le relais s'il n'y a aucun album lisible.
  Future<List<Song>> _gather(int artistId) async {
    final repo = ref.read(libraryRepositoryProvider);
    final detail = await ref.read(artistDetailProvider(artistId).future);

    final albums = spreadPick<Album>(detail.albums, kMedleySongs);
    final details = await Future.wait([
      for (final a in albums)
        repo.albumDetail(a.id).then<AlbumDetail?>((d) => d).catchError((_) => null),
    ]);

    final songs = medleyFromAlbums([
      for (final d in details)
        if (d != null && d.songs.isNotEmpty) d.songs,
    ]);
    if (songs.length >= kMedleySongs) return songs;

    // Les albums n'ont pas suffi : on complète avec les titres les plus joués,
    // sans repasser deux fois par la même chanson.
    final chosen = {for (final s in songs) s.id};
    return [
      ...songs,
      for (final s in pickMedleySongs(detail.topTracks))
        if (chosen.add(s.id)) s,
    ].take(kMedleySongs).toList();
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
      // Surtout ne pas attendre : chez just_audio, le Future de play() ne se
      // referme qu'à l'arrêt du son. L'attendre gelait le medley sur son
      // premier extrait, volume à zéro — l'image d'un medley qui tourne, et
      // pas une note (idée #52).
      unawaited(player.play().catchError((Object _) {}));
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
    MedleyAudio player,
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

  MedleyAudio _ensurePlayer() => _player ??= ref.read(medleyAudioProvider)();

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
