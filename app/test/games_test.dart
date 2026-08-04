// Règles de placement du jeu « Chrono » : la seule logique de jeu qui peut
// silencieusement se tromper (et fausser une partie entière).
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gullify/models/game_source.dart';
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

  group('GameSource', () {
    test('toute la bibliothèque n\'ajoute aucun paramètre', () {
      expect(GameSource.all.isAll, isTrue);
      expect(GameSource.all.query, isEmpty);
      expect(GameSource.all.label, 'Toute la bibliothèque');
    });

    test('une sélection vide retombe sur « tout »', () {
      // Sans quoi le jeu n'aurait plus rien à tirer.
      const genres = GameSource(mode: GameSourceMode.genres);
      expect(genres.isAll, isTrue);
      expect(genres.query, isEmpty);
      const playlists = GameSource(mode: GameSourceMode.playlists);
      expect(playlists.isAll, isTrue);
    });

    test('le vivier part au serveur en un seul paramètre JSON', () {
      // Un nom de genre peut contenir une virgule : pas de liste séparée.
      const source = GameSource(
        mode: GameSourceMode.genres,
        genres: ['Rock, Pop', 'Jazz'],
      );
      final sent = jsonDecode(source.query['source']!) as Map<String, dynamic>;
      expect(sent['mode'], 'genres');
      expect(sent['genres'], ['Rock, Pop', 'Jazz']);
      expect(sent['playlists'], isEmpty);
    });

    test('les playlists ne partent que par leur identifiant', () {
      const source = GameSource(
        mode: GameSourceMode.playlists,
        playlists: [GameSourcePlaylist(id: 7, name: 'Focus')],
      );
      expect(source.toApi()['playlists'], [7]);
      expect(source.label, 'Focus');
    });

    test('le réglage stocké se relit à l\'identique, noms compris', () {
      const source = GameSource(
        mode: GameSourceMode.playlists,
        playlists: [
          GameSourcePlaylist(id: 7, name: 'Focus'),
          GameSourcePlaylist(id: 9, name: 'Route de nuit'),
        ],
      );
      expect(GameSource.decode(source.encode()), source);
      expect(GameSource.decode(source.encode()).label, '2 playlists');
    });

    test('un réglage illisible ne bloque jamais une partie', () {
      expect(GameSource.decode(null), GameSource.all);
      expect(GameSource.decode(''), GameSource.all);
      expect(GameSource.decode('{pas du json'), GameSource.all);
      expect(GameSource.decode('{"mode":"nawak"}'), GameSource.all);
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
