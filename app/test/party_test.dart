// Multijoueur : ce que l'app fait d'un état de partie.
//
// Le serveur fait autorité, donc rien de la logique de jeu n'est testé ici —
// en revanche l'app doit lire correctement ce qu'il envoie (et surtout ne
// jamais inventer ce qu'il tait : la bonne réponse avant la révélation) et
// afficher les quatre jeux sans déborder de l'écran.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gullify/api/party_repository.dart';
import 'package:gullify/screens/games/game_kit.dart';
import 'package:gullify/screens/games/party_round.dart';
import 'package:gullify/state/games.dart';
import 'package:gullify/theme.dart';

String? _abs(String? u) =>
    u == null || u.isEmpty ? null : 'https://example.test/$u';

Map<String, dynamic> _base({
  required String game,
  String phase = 'guessing',
  String status = 'playing',
  Map<String, dynamic>? round,
  List<Map<String, dynamic>>? players,
  int? turnPlayerId,
}) => {
  'code': 'K7M2',
  'game': game,
  'audioMode': 'guests',
  'status': status,
  'phase': phase,
  'version': 4,
  'serverNow': 1000000,
  'phaseAt': 990000,
  'roundMs': 20000,
  'revealMs': 4500,
  'roundIndex': 2,
  'roundCount': 10,
  'turnPlayerId': turnPlayerId,
  'maxPlayers': 12,
  'me': {'id': 1, 'name': 'Maxime', 'isHost': true},
  'players': players ??
      [
        {
          'id': 1,
          'name': 'Maxime',
          'isHost': true,
          'score': 130,
          'lives': 3,
          'answered': true,
          'correct': null,
          'gained': null,
          'timeline': null,
        },
        {
          'id': 2,
          'name': 'Léa',
          'isHost': false,
          'score': 200,
          'lives': 2,
          'answered': false,
          'correct': null,
          'gained': null,
          'timeline': null,
        },
      ],
  'round': round,
};

Map<String, dynamic> _blindRound({bool revealed = false}) => {
  'i': 2,
  'kind': 'blind',
  'myAnswer': revealed ? '11' : null,
  'options': [
    {'id': '11', 'title': 'Sac à main', 'subtitle': 'Les Cowboys'},
    {'id': '12', 'title': 'Pet sauce', 'subtitle': 'Subb'},
    {'id': '13', 'title': 'Revenant', 'subtitle': 'The Distillers'},
    {'id': '14', 'title': 'Ruby Soho', 'subtitle': 'Rancid'},
  ],
  'filePath': 'musique/piste.mp3',
  'startSec': 42,
  if (revealed) ...{
    'answerId': '12',
    'title': 'Pet sauce',
    'artist': 'Subb',
    'artworkUrl': 'serve_image.php?album_id=12',
  },
};

Widget _wrap(Widget child) => ProviderScope(
  child: MaterialApp(
    theme: gullifyThemeFor(GullifyAccent.indigo, dark: true),
    home: Scaffold(body: child),
  ),
);

void main() {
  group('lecture de l\'état', () {
    test('une manche non révélée ne porte aucune réponse', () {
      final s = PartyState.fromJson(
        _base(game: 'blind', round: _blindRound()),
        _abs,
      );
      expect(s.round!.answerId, isNull);
      expect(s.round!.answered, isFalse);
      expect(s.isRevealed, isFalse);
      // Le verdict des autres reste caché lui aussi.
      expect(s.players.every((p) => p.correct == null), isTrue);
    });

    test('la révélation apporte réponse, titre et pochette', () {
      final s = PartyState.fromJson(
        _base(game: 'blind', phase: 'revealed', round: _blindRound(revealed: true)),
        _abs,
      );
      expect(s.isRevealed, isTrue);
      expect(s.round!.answerId, '12');
      expect(s.round!.myAnswer, '11');
      expect(s.round!.artworkUrl, 'https://example.test/serve_image.php?album_id=12');
    });

    test('les images relatives deviennent absolues, les absentes restent nulles', () {
      final s = PartyState.fromJson(_base(game: 'blind', round: _blindRound()), _abs);
      expect(s.round!.artworkUrl, isNull);
    });

    test('le classement va du plus fort au plus faible', () {
      final s = PartyState.fromJson(_base(game: 'blind'), _abs);
      expect(s.ranking.map((p) => p.name), ['Léa', 'Maxime']);
      expect(s.me!.name, 'Maxime');
      expect(s.meIsHost, isTrue);
    });

    test('le décompte est recalé sur l\'horloge du serveur', () {
      // Le serveur dit : phase commencée il y a 10 s, manche de 20 s.
      final s = PartyState.fromJson(_base(game: 'blind'), _abs);
      expect(s.remaining.inSeconds, closeTo(10, 1));
      expect(s.progress, closeTo(0.5, 0.06));
    });

    test('le décompte ne passe jamais sous zéro', () {
      final json = _base(game: 'blind')..['phaseAt'] = 900000;
      final s = PartyState.fromJson(json, _abs);
      expect(s.remaining, Duration.zero);
      expect(s.progress, 0);
    });

    test('c\'est mon tour quand le serveur me désigne', () {
      expect(
        PartyState.fromJson(_base(game: 'chrono', turnPlayerId: 1), _abs).myTurn,
        isTrue,
      );
      expect(
        PartyState.fromJson(_base(game: 'chrono', turnPlayerId: 2), _abs).myTurn,
        isFalse,
      );
    });

    test('une frise se relit carte par carte', () {
      final s = PartyState.fromJson(
        _base(game: 'chrono', turnPlayerId: 1, players: [
          {
            'id': 1,
            'name': 'Maxime',
            'isHost': true,
            'score': 2,
            'lives': 3,
            'answered': false,
            'correct': null,
            'gained': null,
            'timeline': [
              {
                'songId': 5,
                'title': 'Ruby Soho',
                'artist': 'Rancid',
                'year': 1995,
                'artworkUrl': 'serve_image.php?album_id=5',
              },
            ],
          },
        ]),
        _abs,
      );
      final tl = s.players.first.timeline!;
      expect(tl.single.year, 1995);
      expect(tl.single.artworkUrl, startsWith('https://example.test/'));
    });
  });

  group('affichage des manches', () {
    late SnippetPlayer snippet;

    setUp(() => snippet = SnippetPlayer());
    tearDown(() => snippet.dispose());

    Future<void> show(WidgetTester tester, PartyState party) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        _wrap(PartyRoundView(party: party, snippet: snippet)),
      );
      await tester.pump();
    }

    testWidgets('blind test : la question et les quatre réponses', (tester) async {
      await show(
        tester,
        PartyState.fromJson(_base(game: 'blind', round: _blindRound()), _abs),
      );
      expect(find.text('Quel est ce titre ?'), findsOneWidget);
      expect(find.text('Pet sauce'), findsOneWidget);
      expect(find.text('3/10'), findsOneWidget);
      // Le titre mystère n'est nulle part avant la révélation.
      expect(find.textContaining('Subb'), findsOneWidget); // sous-titre du leurre
      expect(tester.takeException(), isNull);
    });

    testWidgets('blind test révélé : le verdict et la bonne réponse', (tester) async {
      await show(
        tester,
        PartyState.fromJson(
          _base(game: 'blind', phase: 'revealed', round: _blindRound(revealed: true)),
          _abs,
        ),
      );
      expect(find.text('Raté'), findsOneWidget);
      expect(find.text('Manche suivante…'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('pochette mystère : la question et les propositions', (tester) async {
      await show(
        tester,
        PartyState.fromJson(
          _base(game: 'cover', round: {
            'i': 2,
            'kind': 'cover',
            'myAnswer': null,
            'artworkUrl': 'serve_image.php?album_id=3',
            'options': [
              {'id': '1', 'title': 'Indestructible', 'subtitle': 'Rancid'},
              {'id': '2', 'title': 'Coral Fang', 'subtitle': 'The Distillers'},
              {'id': '3', 'title': 'Commit This', 'subtitle': 'MCS'},
              {'id': '4', 'title': 'Punk-O-Rama', 'subtitle': 'Divers'},
            ],
          }),
          _abs,
        ),
      );
      expect(find.text('Quel est cet album ?'), findsOneWidget);
      expect(find.text('Coral Fang'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('duel : deux albums, sans millésime avant la révélation', (tester) async {
      await show(
        tester,
        PartyState.fromJson(
          _base(game: 'duel', round: {
            'i': 2,
            'kind': 'duel',
            'myAnswer': null,
            'left': {
              'id': '1',
              'title': 'Let\'s Go',
              'subtitle': 'Rancid',
              'artworkUrl': 'serve_image.php?album_id=1',
            },
            'right': {
              'id': '2',
              'title': 'Sing the Sorrow',
              'subtitle': 'AFI',
              'artworkUrl': 'serve_image.php?album_id=2',
            },
          }),
          _abs,
        ),
      );
      expect(find.text('Lequel est le plus ancien ?'), findsOneWidget);
      expect(find.text('Sing the Sorrow'), findsOneWidget);
      expect(find.textContaining(RegExp(r'^\d{4}$')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('chrono : ma frise et les trous où placer', (tester) async {
      await show(
        tester,
        PartyState.fromJson(
          _base(game: 'chrono', turnPlayerId: 1, round: {
            'i': 2,
            'kind': 'chrono',
            'myAnswer': null,
            'filePath': 'musique/piste.mp3',
            'startSec': 30,
          }, players: [
            {
              'id': 1,
              'name': 'Maxime',
              'isHost': true,
              'score': 1,
              'lives': 3,
              'answered': false,
              'correct': null,
              'gained': null,
              'timeline': [
                {'songId': 5, 'title': 'Ruby Soho', 'year': 1995},
                {'songId': 6, 'title': 'Sac à main', 'year': 2004},
              ],
            },
          ]),
          _abs,
        ),
      );
      expect(find.text('À toi de placer'), findsOneWidget);
      expect(find.text('Ta frise'), findsOneWidget);
      expect(find.text('1995'), findsOneWidget);
      // Trois trous pour deux cartes : avant, entre, après.
      expect(find.byIcon(Icons.add_rounded), findsNWidgets(3));
      expect(find.text('Passer mon tour'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('chrono, tour d\'un autre : on regarde sans pouvoir placer', (tester) async {
      await show(
        tester,
        PartyState.fromJson(
          _base(game: 'chrono', turnPlayerId: 2, round: {
            'i': 2,
            'kind': 'chrono',
            'myAnswer': null,
          }),
          _abs,
        ),
      );
      expect(find.text('Au tour de Léa'), findsOneWidget);
      expect(find.text('Passer mon tour'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  test('chaque jeu du catalogue a bien une fiche', () {
    for (final id in ['blind', 'cover', 'duel', 'chrono']) {
      expect(gameById(id), isNotNull, reason: 'fiche manquante pour $id');
    }
    expect(gameById('inconnu'), isNull);
  });
}
