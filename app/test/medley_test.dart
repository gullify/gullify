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

/// Ce que le medley a fait entendre, tous lecteurs confondus : le medley en
/// tient deux, à tour de rôle, pour croiser les extraits sans couper le son.
class _Bench {
  final List<_FakeMedleyAudio> players = [];
  final List<String> urls = [];
  final List<Duration?> starts = [];

  MedleyAudio create() {
    final player = _FakeMedleyAudio(this);
    players.add(player);
    return player;
  }

  /// Le son qui sort de l'app : le plus fort des lecteurs en train de jouer.
  double get volume => players
      .where((p) => p.playing)
      .fold<double>(0, (loudest, p) => p.volume > loudest ? p.volume : loudest);

  bool get playing => players.any((p) => p.playing);
  int get playingCount => players.where((p) => p.playing).length;
}

/// Un lecteur qui se comporte comme just_audio là où ça compte : son [play]
/// ne rend la main qu'à l'arrêt du son. C'est ce qui gelait le medley.
class _FakeMedleyAudio implements MedleyAudio {
  _FakeMedleyAudio(this.bench);

  final _Bench bench;
  double volume = 1;
  bool playing = false;
  Completer<void>? _playing;

  @override
  Future<void> setVolume(double v) async => volume = v;

  @override
  Future<void> setUrl(String url, {Duration? initialPosition}) async {
    bench.urls.add(url);
    bench.starts.add(initialPosition);
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
  _FakeRepo({this.songsPerAlbum = 2});

  final int songsPerAlbum;

  @override
  Future<AlbumDetail> albumDetail(int id) async => AlbumDetail(
        album: Album(id: id, name: 'Album $id'),
        songs: [
          for (var i = 0; i < songsPerAlbum; i++) _s(id * 10 + i, album: id),
        ],
      );

  @override
  String streamUrl(Song song) => 'https://exemple/stream${song.id}';
}

const _twoAlbums = [
  Album(id: 1, name: 'Premier'),
  Album(id: 2, name: 'Dernier'),
];

ProviderContainer _container(
  _Bench bench, {
  _FakeRepo? repo,
  List<Album> albums = _twoAlbums,
}) {
  final container = ProviderContainer(
    overrides: [
      medleyAudioProvider.overrideWithValue(bench.create),
      libraryRepositoryProvider.overrideWithValue(repo ?? _FakeRepo()),
      // Le medley écoute le lecteur principal pour se taire s'il repart ;
      // ici il ne joue jamais. (audioHandlerProvider, lui, n'est pas fourni :
      // le medley encaisse déjà son absence.)
      playbackStateProvider.overrideWith((ref) => const Stream.empty()),
      // Deux artistes : on enchaîne de l'un à l'autre en rangeant par séries.
      for (final id in [1, 2])
        artistDetailProvider(id).overrideWith((ref) async => ArtistDetail(
              artist: Artist(
                id: id,
                name: 'Artiste $id',
                albumCount: albums.length,
              ),
              albums: albums,
              topTracks: const [],
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
        [1, 4, 6, 2, 5],
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

  // ── Toujours de quoi se faire une idée (idée #54) ───────────────────────
  group('albumPicks', () {
    test('commence par le milieu de l\'album', () {
      final songs = List.generate(9, (i) => _s(i));
      expect(albumPicks(songs).first.id, 4);
    });

    test('puis s\'étale sur tout le disque, sans doublon', () {
      final songs = List.generate(9, (i) => _s(i));
      final ids = albumPicks(songs).map((s) => s.id).toList();
      expect(ids.length, kMedleySongs);
      expect(ids.toSet().length, kMedleySongs);
      expect(ids.first, 4);
    });

    test('ne rend que ce que l\'album a', () {
      expect(albumPicks([_s(1), _s(2)]).map((s) => s.id).toList(), [2, 1]);
      expect(albumPicks(const []), isEmpty);
    });
  });

  group('medleyFromAlbums', () {
    test('tourne d\'un album à l\'autre tant qu\'il y en a', () {
      final albums = [
        [_s(1), _s(2), _s(3)],
        [_s(11), _s(12), _s(13)],
        [_s(21), _s(22), _s(23)],
      ];
      // Le milieu de chacun d'abord, puis le second tour.
      expect(
        medleyFromAlbums(albums).map((s) => s.id).toList(),
        [2, 12, 22, 1, 11],
      );
    });

    test('repasse dans le même disque quand l\'artiste n\'a qu\'un album', () {
      final only = [List.generate(12, (i) => _s(i))];
      expect(medleyFromAlbums(only).length, kMedleySongs);
    });

    test('se contente du peu qu\'il y a, sans jamais répéter', () {
      final ids = medleyFromAlbums([
        [_s(1), _s(2)],
        [_s(3)],
      ]).map((s) => s.id).toList();
      expect(ids.toSet().length, ids.length);
      expect(ids.length, 3);
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
      final bench = _Bench();
      final container = _container(bench);
      final medley = container.read(medleyPlayerProvider.notifier);

      unawaited(medley.toggle(1));
      await tester.pump();

      // Le premier extrait est lancé, en silence : le fondu commence.
      expect(bench.urls, ['https://exemple/stream11']);
      expect(bench.playing, isTrue);
      expect(bench.volume, 0);

      await tester.pump(kMedleyFadeIn + const Duration(milliseconds: 100));
      expect(bench.volume, 1);
      expect(container.read(medleyPlayerProvider).loading, isFalse);
      expect(container.read(medleyPlayerProvider).index, 1);

      // Puis l'extrait suivant vient tout seul, pris sur l'autre album.
      await tester.pump(kMedleyExcerpt);
      expect(bench.urls.length, 2);
      expect(bench.urls.last, 'https://exemple/stream21');
      expect(bench.volume, 1);
      expect(container.read(medleyPlayerProvider).index, 2);

      await medley.stop();
    });

    testWidgets('entre dans le vif de chaque titre', (tester) async {
      final bench = _Bench();
      final container = _container(bench);
      final medley = container.read(medleyPlayerProvider.notifier);

      unawaited(medley.toggle(1));
      await tester.pump();
      expect(bench.starts.single, medleyStart(240));

      await medley.stop();
      // Laisse expirer le pas de fondu en cours, qui se taira en voyant que
      // le medley n'est plus de son temps.
      await tester.pump(const Duration(milliseconds: 200));
    });

    testWidgets('un seul album donne quand même un medley entier',
        (tester) async {
      // Repro d'idée #54 : un artiste d'un seul album ne donnait qu'un extrait,
      // et le medley tournait en rond sur la même chanson.
      final bench = _Bench();
      final container = _container(
        bench,
        repo: _FakeRepo(songsPerAlbum: 12),
        albums: const [Album(id: 1, name: 'Unique')],
      );
      final medley = container.read(medleyPlayerProvider.notifier);

      unawaited(medley.toggle(1));
      await tester.pump();

      expect(container.read(medleyPlayerProvider).total, kMedleySongs);

      // Et ce sont bien cinq titres différents.
      final heard = <String>{bench.urls.single};
      for (var i = 1; i < kMedleySongs; i++) {
        await tester.pump(kMedleyExcerpt);
        heard.add(bench.urls.last);
      }
      expect(heard.length, kMedleySongs);

      await medley.stop();
      // Laisse expirer le pas de fondu en cours, qui se taira en voyant que le
      // medley n'est plus de son temps.
      await tester.pump(kMedleyFadeOut);
    });

    testWidgets('s\'arrête pour de bon quand on le ferme', (tester) async {
      final bench = _Bench();
      final container = _container(bench);
      final medley = container.read(medleyPlayerProvider.notifier);

      unawaited(medley.toggle(1));
      await tester.pump(kMedleyFadeIn + const Duration(milliseconds: 100));
      await medley.stop();

      expect(bench.playing, isFalse);
      expect(container.read(medleyPlayerProvider).active, isFalse);

      // Rien ne se rallume ensuite : les minuteries d'avant sont périmées.
      await tester.pump(kMedleyExcerpt * 2);
      expect(bench.urls.length, 1);
      expect(bench.playing, isFalse);
    });
  });

  // ── Un vrai fondu enchaîné (idée #55) ───────────────────────────────────
  // Repro du bug : avec un seul lecteur, le `setUrl` de l'extrait suivant
  // coupait le son, et le chargement se faisait en silence. On n'entendait pas
  // les fondus — seulement le blanc qu'ils laissaient entre chaque extrait.
  group('fondu enchaîné', () {
    testWidgets('ne laisse jamais de trou entre deux extraits', (tester) async {
      final bench = _Bench();
      final container = _container(bench);
      final medley = container.read(medleyPlayerProvider.notifier);

      unawaited(medley.toggle(1));
      await tester.pump();
      await tester.pump(kMedleyFadeIn + const Duration(milliseconds: 100));
      expect(bench.volume, 1);

      // On écoute tout du long, jusqu'au bout du passage à l'extrait suivant :
      // à aucun instant le son ne tombe.
      const pas = Duration(milliseconds: 200);
      for (var t = Duration.zero;
          t < kMedleyExcerpt + kMedleyFadeIn;
          t += pas) {
        await tester.pump(pas);
        expect(bench.playing, isTrue, reason: 'plus rien ne joue à $t');
        // Fondu à puissance constante : au milieu du croisement, les deux
        // extraits sont encore à ~0,71.
        expect(bench.volume, greaterThan(0.5), reason: 'trou à $t');
      }
      expect(bench.urls.length, greaterThanOrEqualTo(2));

      await medley.stop();
    });

    testWidgets('coupe l\'extrait sortant, une fois le fondu fini',
        (tester) async {
      final bench = _Bench();
      final container = _container(bench);
      final medley = container.read(medleyPlayerProvider.notifier);

      unawaited(medley.toggle(1));
      await tester.pump();

      // Pendant le croisement, les deux extraits sonnent ensemble…
      await tester.pump(kMedleyExcerpt + kMedleyFadeIn ~/ 2);
      expect(bench.playingCount, 2);

      // … et après, il n'en reste qu'un, à plein volume.
      await tester.pump(kMedleyFadeIn);
      expect(bench.playingCount, 1);
      expect(bench.volume, 1);

      await medley.stop();
    });

    testWidgets('laisse le temps de reconnaître un titre', (tester) async {
      // Idée #55 : dix-huit secondes, c'était trop court.
      expect(kMedleyExcerpt.inSeconds, greaterThanOrEqualTo(24));
      // Et il reste du plein volume entre les deux fondus.
      expect(kMedleyExcerpt, greaterThan(kMedleyFadeIn + kMedleyFadeOut));
    });
  });

  // ── Un medley par artiste (idée #56) ────────────────────────────────────
  // Le dialogue lance le medley tout seul et le coupe en se fermant. En
  // enchaînant sur l'artiste suivant, le dialogue précédent se défait *après*
  // que le suivant a lancé le sien : il ne doit couper que le sien.
  group('à qui appartient le medley', () {
    testWidgets('une fermeture ne coupe pas le medley d\'un autre artiste',
        (tester) async {
      final bench = _Bench();
      final container = _container(bench);
      final medley = container.read(medleyPlayerProvider.notifier);

      unawaited(medley.start(1));
      await tester.pump();
      expect(bench.playing, isTrue);

      // Le dialogue d'un autre artiste se ferme : rien ne bouge.
      await medley.stopFor(2);
      expect(bench.playing, isTrue);
      expect(container.read(medleyPlayerProvider).active, isTrue);

      // Le sien, en revanche, l'arrête.
      await medley.stopFor(1);
      expect(bench.playing, isFalse);
      expect(container.read(medleyPlayerProvider).active, isFalse);

      await tester.pump(const Duration(milliseconds: 200));
    });

    testWidgets('enchaîner passe la main à l\'artiste suivant', (tester) async {
      final bench = _Bench();
      final container = _container(bench);
      final medley = container.read(medleyPlayerProvider.notifier);

      unawaited(medley.start(1));
      await tester.pump();
      final entendus = bench.urls.length;

      // Le suivant prend l'antenne…
      unawaited(medley.start(2));
      await tester.pump();
      expect(bench.urls.length, entendus + 1);
      expect(bench.playing, isTrue);

      // … et la fermeture du dialogue précédent ne l'interrompt pas.
      await medley.stopFor(1);
      expect(bench.playing, isTrue);
      expect(container.read(medleyPlayerProvider).active, isTrue);

      await medley.stop();
      await tester.pump(const Duration(milliseconds: 200));
    });
  });
}
