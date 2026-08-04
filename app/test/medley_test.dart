// Un medley doit se promener : plusieurs albums, un extrait pris là où il y a
// de la musique, jamais l'intro ni le silence de la fin. Et surtout : il doit
// s'entendre.
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gullify/api/library_repository.dart';
import 'package:gullify/models/album.dart';
import 'package:gullify/models/artist.dart';
import 'package:gullify/models/song.dart';
import 'package:gullify/state/genre_medley.dart';
import 'package:gullify/state/library.dart';
import 'package:gullify/state/player.dart';

Song _s(int id, {int? album, int duration = 240}) => Song(
      id: id,
      title: 'Titre $id',
      filePath: '/musique/$id.mp3',
      albumId: album,
      duration: duration,
    );

/// Un lecteur qui se comporte comme just_audio là où ça compte : son [play]
/// ne rend la main qu'à l'arrêt du son. C'est ce qui gelait le medley.
class _FakeMedleyAudio implements MedleyAudio {
  final List<String> urls = [];
  final List<Duration?> starts = [];
  double volume = 1;
  bool playing = false;
  Completer<void>? _playing;

  @override
  Future<void> setVolume(double v) async => volume = v;

  @override
  Future<void> setUrl(String url, {Duration? initialPosition}) async {
    urls.add(url);
    starts.add(initialPosition);
  }

  @override
  Future<void> play() {
    playing = true;
    return (_playing = Completer<void>()).future;
  }

  @override
  Future<void> stop() async {
    playing = false;
    _playing?.complete();
    _playing = null;
  }

  @override
  Future<void> dispose() async => stop();
}

class _FakeRepo extends Fake implements LibraryRepository {
  @override
  Future<AlbumDetail> albumDetail(int id) async => AlbumDetail(
        album: Album(id: id, name: 'Album $id'),
        songs: [_s(id * 10, album: id), _s(id * 10 + 1, album: id)],
      );

  @override
  String streamUrl(Song song) => 'https://exemple/stream${song.id}';
}

ProviderContainer _container(_FakeMedleyAudio audio) {
  final container = ProviderContainer(
    overrides: [
      medleyAudioProvider.overrideWithValue(() => audio),
      libraryRepositoryProvider.overrideWithValue(_FakeRepo()),
      // Le medley écoute le lecteur principal pour se taire s'il repart ;
      // ici il ne joue jamais. (audioHandlerProvider, lui, n'est pas fourni :
      // le medley encaisse déjà son absence.)
      playbackStateProvider.overrideWith((ref) => const Stream.empty()),
      artistDetailProvider(1).overrideWith((ref) async => const ArtistDetail(
            artist: Artist(id: 1, name: 'Artiste Test', albumCount: 2),
            albums: [Album(id: 1, name: 'Premier'), Album(id: 2, name: 'Dernier')],
            topTracks: [],
          )),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  group('spreadPick', () {
    test('étale le choix sur toute la liste', () {
      final items = List<int>.generate(12, (i) => i);
      expect(spreadPick(items, 4), [0, 3, 6, 9]);
    });

    test('rend tout quand il y a moins d\'éléments que demandé', () {
      expect(spreadPick([1, 2], 4), [1, 2]);
    });

    test('ne rend rien d\'une liste vide, ni pour un maximum nul', () {
      expect(spreadPick(<int>[], 4), isEmpty);
      expect(spreadPick([1, 2, 3], 0), isEmpty);
    });
  });

  group('pickMedleySongs', () {
    test('tourne d\'un album à l\'autre plutôt que d\'épuiser le premier', () {
      final songs = [
        _s(1, album: 10), _s(2, album: 10), _s(3, album: 10),
        _s(4, album: 20), _s(5, album: 20),
        _s(6, album: 30),
      ];
      expect(
        pickMedleySongs(songs).map((s) => s.id).toList(),
        [1, 4, 6, 2],
      );
    });

    test('se contente d\'un seul album s\'il n\'y en a qu\'un', () {
      final songs = [_s(1, album: 10), _s(2, album: 10)];
      expect(pickMedleySongs(songs).map((s) => s.id).toList(), [1, 2]);
    });

    test('ne dépasse jamais le maximum demandé', () {
      final songs = List.generate(20, (i) => _s(i, album: i % 4));
      expect(pickMedleySongs(songs, max: 3).length, 3);
    });

    test('sans chanson, pas de medley', () {
      expect(pickMedleySongs(const []), isEmpty);
    });
  });

  group('medleyStart', () {
    test('entre dans le vif du sujet sur un titre normal', () {
      final start = medleyStart(240); // 4 min
      expect(start.inSeconds, 67);
    });

    test('laisse la place à l\'extrait entier avant la fin', () {
      final start = medleyStart(45);
      expect(start.inSeconds + kMedleyExcerpt.inSeconds, lessThanOrEqualTo(45));
    });

    test('part du début quand le titre est trop court pour se promener', () {
      expect(medleyStart(20), Duration.zero);
      expect(medleyStart(0), Duration.zero);
    });

    test('ne va pas chercher au-delà d\'une minute et demie', () {
      expect(medleyStart(900).inSeconds, 90);
    });
  });

  // ── Le medley s'entend (idée #52) ───────────────────────────────────────
  // Repro du bug : `play()` de just_audio ne se referme qu'à l'arrêt du son.
  // L'attendre bloquait tout après lui — le fondu ne montait jamais le volume,
  // l'extrait suivant n'était jamais armé : un medley muet, qui a pourtant
  // l'air de tourner.
  group('lecture', () {
    testWidgets('monte le son et enchaîne, sans attendre la fin du morceau',
        (tester) async {
      final audio = _FakeMedleyAudio();
      final container = _container(audio);
      final medley = container.read(medleyPlayerProvider.notifier);

      unawaited(medley.toggle(1));
      await tester.pump();

      // Le premier extrait est lancé, en silence : le fondu commence.
      expect(audio.urls, ['https://exemple/stream11']);
      expect(audio.playing, isTrue);
      expect(audio.volume, 0);

      await tester.pump(kMedleyFadeIn + const Duration(milliseconds: 100));
      expect(audio.volume, 1);
      expect(container.read(medleyPlayerProvider).loading, isFalse);
      expect(container.read(medleyPlayerProvider).index, 1);

      // Puis l'extrait suivant vient tout seul, pris sur l'autre album.
      await tester.pump(kMedleyExcerpt);
      expect(audio.urls.length, 2);
      expect(audio.urls.last, 'https://exemple/stream21');
      expect(audio.volume, 1);
      expect(container.read(medleyPlayerProvider).index, 2);

      await medley.stop();
    });

    testWidgets('entre dans le vif de chaque titre', (tester) async {
      final audio = _FakeMedleyAudio();
      final container = _container(audio);
      final medley = container.read(medleyPlayerProvider.notifier);

      unawaited(medley.toggle(1));
      await tester.pump();
      expect(audio.starts.single, medleyStart(240));

      await medley.stop();
      // Laisse expirer le pas de fondu en cours, qui se taira en voyant que
      // le medley n'est plus de son temps.
      await tester.pump(const Duration(milliseconds: 200));
    });

    testWidgets('s\'arrête pour de bon quand on le ferme', (tester) async {
      final audio = _FakeMedleyAudio();
      final container = _container(audio);
      final medley = container.read(medleyPlayerProvider.notifier);

      unawaited(medley.toggle(1));
      await tester.pump(kMedleyFadeIn + const Duration(milliseconds: 100));
      await medley.stop();

      expect(audio.playing, isFalse);
      expect(container.read(medleyPlayerProvider).active, isFalse);

      // Rien ne se rallume ensuite : les minuteries d'avant sont périmées.
      await tester.pump(kMedleyExcerpt * 2);
      expect(audio.urls.length, 1);
      expect(audio.playing, isFalse);
    });
  });
}
