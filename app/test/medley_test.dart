// Un medley doit se promener : plusieurs albums, un extrait pris là où il y a
// de la musique, jamais l'intro ni le silence de la fin.
import 'package:flutter_test/flutter_test.dart';
import 'package:gullify/models/song.dart';
import 'package:gullify/state/genre_medley.dart';

Song _s(int id, {int? album, int duration = 240}) => Song(
      id: id,
      title: 'Titre $id',
      filePath: '/musique/$id.mp3',
      albumId: album,
      duration: duration,
    );

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
}
