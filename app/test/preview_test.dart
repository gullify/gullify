// La pré-écoute d'un titre YouTube n'a plus de lecteur à elle : elle passe par
// le lecteur principal, et la rangée de la recherche n'est plus que l'écho de
// ce qu'il joue (idée #59).
import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gullify/audio/audio_handler.dart';
import 'package:gullify/state/player.dart';
import 'package:gullify/state/preview.dart';

/// Une fiche de pré-écoute, telle que le handler la met dans la file.
MediaItem _preview(String videoId, {Duration? duration}) => MediaItem(
      id: 'https://exemple/preview/$videoId',
      title: 'Un titre',
      album: 'Pré-écoute YouTube',
      duration: duration,
      extras: {kPreviewVideoId: videoId},
    );

/// Une chanson de la bibliothèque : rien à voir avec une pré-écoute.
const _song = MediaItem(id: 'https://exemple/stream1', title: 'Une chanson');

PlaybackState _state({
  bool playing = false,
  AudioProcessingState processing = AudioProcessingState.ready,
}) =>
    PlaybackState(playing: playing, processingState: processing);

class _Bench {
  final item = StreamController<MediaItem?>.broadcast();
  final playback = StreamController<PlaybackState>.broadcast();
  final position = StreamController<Duration>.broadcast();

  ProviderContainer container() {
    final container = ProviderContainer(
      overrides: [
        currentMediaItemProvider.overrideWith((ref) => item.stream),
        playbackStateProvider.overrideWith((ref) => playback.stream),
        positionProvider.overrideWith((ref) => position.stream),
      ],
    );
    // Tout doit être écouté d'emblée : la pré-écoute ne regarde l'état du
    // lecteur que lorsqu'elle est active, et un flux qu'on n'écoute pas encore
    // perd ce qu'on lui donne.
    container.listen(currentMediaItemProvider, (_, _) {});
    container.listen(playbackStateProvider, (_, _) {});
    container.listen(positionProvider, (_, _) {});
    container.listen(previewPlayerProvider, (_, _) {});
    addTearDown(() {
      container.dispose();
      item.close();
      playback.close();
      position.close();
    });
    return container;
  }
}

/// Laisse les flux arriver jusqu'aux providers.
Future<void> _settle() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  test('rien ne joue : aucune rangée ne s\'allume', () async {
    final container = _Bench().container();
    expect(container.read(previewPlayerProvider).videoId, isNull);
  });

  test('le lecteur principal joue une pré-écoute : la rangée s\'allume',
      () async {
    final bench = _Bench();
    final container = bench.container();

    bench.item.add(_preview('abc', duration: const Duration(minutes: 3)));
    bench.playback.add(_state(playing: true));
    bench.position.add(const Duration(seconds: 12));
    await _settle();

    final preview = container.read(previewPlayerProvider);
    expect(preview.isActive('abc'), isTrue);
    expect(preview.isActive('xyz'), isFalse);
    expect(preview.playing, isTrue);
    expect(preview.loading, isFalse);
    expect(preview.position, const Duration(seconds: 12));
    expect(preview.duration, const Duration(minutes: 3));
  });

  test('le titre qui se charge fait tourner l\'indicateur', () async {
    final bench = _Bench();
    final container = bench.container();

    bench.item.add(_preview('abc'));
    bench.playback.add(_state(processing: AudioProcessingState.loading));
    await _settle();

    expect(container.read(previewPlayerProvider).loading, isTrue);
    expect(container.read(previewPlayerProvider).playing, isFalse);

    bench.playback.add(_state(processing: AudioProcessingState.buffering));
    await _settle();
    expect(container.read(previewPlayerProvider).loading, isTrue);
  });

  test('le lecteur principal passe à autre chose : la rangée s\'éteint',
      () async {
    final bench = _Bench();
    final container = bench.container();

    bench.item.add(_preview('abc'));
    bench.playback.add(_state(playing: true));
    await _settle();
    expect(container.read(previewPlayerProvider).isActive('abc'), isTrue);

    // Une chanson de la bibliothèque, jouée par le même lecteur : la pré-écoute
    // n'a plus rien à afficher — c'est elle qui vient d'être remplacée.
    bench.item.add(_song);
    await _settle();
    expect(container.read(previewPlayerProvider).videoId, isNull);
    expect(container.read(previewPlayerProvider).playing, isFalse);
  });

  test('la pause du lecteur principal met la pré-écoute en pause', () async {
    final bench = _Bench();
    final container = bench.container();

    bench.item.add(_preview('abc'));
    bench.playback.add(_state(playing: true));
    await _settle();
    expect(container.read(previewPlayerProvider).playing, isTrue);

    // Un medley qui démarre fait taire le lecteur principal : la pré-écoute
    // s'arrête avec lui, au lieu de jouer par-dessous (idée #59).
    bench.playback.add(_state(playing: false));
    await _settle();
    expect(container.read(previewPlayerProvider).playing, isFalse);
    expect(container.read(previewPlayerProvider).isActive('abc'), isTrue);
  });

  test('previewVideoIdOf ne reconnaît que les pré-écoutes', () {
    expect(previewVideoIdOf(_preview('abc')), 'abc');
    expect(previewVideoIdOf(_song), isNull);
    expect(previewVideoIdOf(null), isNull);
  });
}
