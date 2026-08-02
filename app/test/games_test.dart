// Règles de placement du jeu « Chrono » : la seule logique de jeu qui peut
// silencieusement se tromper (et fausser une partie entière).
import 'package:flutter_test/flutter_test.dart';
import 'package:gullify/state/games.dart';

void main() {
  group('chronoPlacementIsCorrect', () {
    test('frise vide : le seul trou est toujours bon', () {
      expect(chronoPlacementIsCorrect([], 0, 1994), isTrue);
    });

    test('une seule carte : avant si plus ancien, après si plus récent', () {
      expect(chronoPlacementIsCorrect([2000], 0, 1990), isTrue);
      expect(chronoPlacementIsCorrect([2000], 1, 1990), isFalse);
      expect(chronoPlacementIsCorrect([2000], 1, 2010), isTrue);
      expect(chronoPlacementIsCorrect([2000], 0, 2010), isFalse);
    });

    test('insertion au milieu', () {
      const timeline = [1980, 1995, 2012];
      expect(chronoPlacementIsCorrect(timeline, 0, 1975), isTrue);
      expect(chronoPlacementIsCorrect(timeline, 1, 1990), isTrue);
      expect(chronoPlacementIsCorrect(timeline, 2, 2000), isTrue);
      expect(chronoPlacementIsCorrect(timeline, 3, 2020), isTrue);
      // Le bon millésime, le mauvais trou.
      expect(chronoPlacementIsCorrect(timeline, 1, 2000), isFalse);
      expect(chronoPlacementIsCorrect(timeline, 3, 1990), isFalse);
    });

    test('année déjà présente : les deux trous voisins sont acceptés', () {
      const timeline = [1980, 1995, 2012];
      expect(chronoPlacementIsCorrect(timeline, 1, 1995), isTrue);
      expect(chronoPlacementIsCorrect(timeline, 2, 1995), isTrue);
      expect(chronoPlacementIsCorrect(timeline, 0, 1995), isFalse);
      expect(chronoPlacementIsCorrect(timeline, 3, 1995), isFalse);
    });
  });

  test('le catalogue des jeux est cohérent', () {
    expect(kGames, isNotEmpty);
    // Les identifiants servent de clés de stockage (records, règles lues) :
    // un doublon écraserait le score d'un autre jeu.
    expect(kGames.map((g) => g.id).toSet().length, kGames.length);
    expect(kGames.map((g) => g.route).toSet().length, kGames.length);
    for (final game in kGames) {
      expect(game.route, startsWith('/games/'));
      expect(game.rules, isNotEmpty);
      expect(game.goal, isNotEmpty);
    }
  });
}
