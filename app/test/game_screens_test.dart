// Les quatre jeux se déroulent entièrement à l'écran (aucune page de
// détail) : ce test vérifie qu'ils s'ouvrent, expliquent leurs règles à la
// première partie, puis affichent leur plateau — et qu'aucune mise en page
// ne déborde sur un écran de téléphone.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gullify/api/library_repository.dart';
import 'package:gullify/models/album.dart';
import 'package:gullify/models/game_track.dart';
import 'package:gullify/models/song.dart';
import 'package:gullify/screens/games/blind_test_game_screen.dart';
import 'package:gullify/screens/games/chrono_game_screen.dart';
import 'package:gullify/screens/games/cover_game_screen.dart';
import 'package:gullify/screens/games/duel_game_screen.dart';
import 'package:gullify/screens/games/game_kit.dart';
import 'package:gullify/state/games.dart';
import 'package:gullify/state/library.dart';
import 'package:gullify/theme.dart';

Song _song(int i) => Song(
  id: i,
  title: 'Titre $i',
  filePath: '$i.mp3',
  duration: 180 + i,
  albumId: i,
  albumName: 'Album $i',
  artistId: i,
  artistName: 'Artiste $i',
);

final _tracks = [
  for (var i = 1; i <= 12; i++) GameTrack(song: _song(i), year: 1970 + i * 3),
];

final _albums = [
  for (var i = 1; i <= 12; i++)
    Album(
      id: i,
      name: 'Album $i',
      artistName: 'Artiste $i',
      year: 1970 + i * 3,
    ),
];

final _songs = [for (var i = 1; i <= 12; i++) _song(i)];

/// Le vrai dépôt exigerait un client HTTP authentifié ; seul l'URL de flux
/// est utilisée par les jeux.
class _FakeRepository extends Fake implements LibraryRepository {
  @override
  String streamUrl(Song song) => 'https://example.test/${song.id}.mp3';
}

Widget _wrap(Widget child) => ProviderScope(
  overrides: [
    libraryRepositoryProvider.overrideWithValue(_FakeRepository()),
    gamePoolProvider.overrideWith(
      (ref) async => GamePool(tracks: _tracks, albums: _albums),
    ),
    blindPoolProvider.overrideWith((ref) async => _songs),
  ],
  child: MaterialApp(
    theme: gullifyThemeFor(GullifyAccent.indigo, dark: false),
    home: child,
  ),
);

void main() {
  /// Ouvre un jeu : les règles s'affichent (première partie), on les valide,
  /// la partie démarre.
  Future<void> openGame(WidgetTester tester, Widget screen) async {
    tester.view.physicalSize = const Size(412, 892);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_wrap(screen));
    await tester.pump();
    // Le stockage sécurisé n'existe pas en test : les jeux attendent son
    // délai de garde (2 s) avant de décider d'afficher les règles.
    await tester.pump(const Duration(seconds: 3));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Le but'), findsOneWidget);
    await tester.tap(find.text('Compris, on joue !'));
    // Pas de pumpAndSettle : les barres d'égaliseur (et le chargeur) tournent
    // en boucle, la scène ne se stabilise jamais.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('Chrono ouvre ses règles puis pose la première carte', (
    tester,
  ) async {
    await openGame(tester, const ChronoGameScreen());
    expect(find.text('Extrait mystère'), findsOneWidget);
    // La frise démarre avec une carte révélée et ses trous de dépôt.
    expect(find.text('Où le places-tu ?'), findsOneWidget);
    expect(find.byIcon(Icons.add_rounded), findsNWidgets(2));

    // Trois manches jouées en plaçant tantôt avant, tantôt après : le tirage
    // étant aléatoire, cela traverse les deux révélations possibles (« Bien
    // vu ! » et « Raté — une vie en moins », la plus longue à afficher).
    for (var round = 0; round < 3; round++) {
      final gaps = find.byIcon(Icons.add_rounded);
      await tester.tap(round.isEven ? gaps.first : gaps.last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      final next = find.byIcon(Icons.arrow_forward_rounded);
      expect(next, findsOneWidget);
      await tester.tap(next);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      if (find.text('Extrait mystère').evaluate().isEmpty) {
        // Trois placements ratés : la partie s'arrête sur l'écran de score.
        expect(find.text('Rejouer'), findsOneWidget);
        break;
      }
    }
  });

  testWidgets('Blind test propose quatre réponses', (tester) async {
    await openGame(tester, const BlindTestGameScreen());
    expect(find.text('Quel est ce titre ?'), findsOneWidget);
    expect(find.byType(GameChoiceTile), findsNWidgets(4));
  });

  testWidgets('Pochette mystère affiche la pochette et les réponses', (
    tester,
  ) async {
    await openGame(tester, const CoverGameScreen());
    expect(find.text('Quel album se cache là-dessous ?'), findsOneWidget);
    expect(find.byType(GameChoiceTile), findsNWidgets(4));
  });

  testWidgets('Duel oppose deux albums', (tester) async {
    await openGame(tester, const DuelGameScreen());
    expect(find.text('Lequel est le plus ancien ?'), findsOneWidget);
    expect(find.text('VS'), findsOneWidget);
  });
}
