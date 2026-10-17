// Choisir où est la musique, sur la MACHINE — pas dans le conteneur.
//
// Le serveur ne voit que ce que Docker lui a monté : lui demander « quels
// disques as-tu ? », c'est demander à quelqu'un qui n'a pas d'yeux. C'est le
// compagnon, dehors, qui regarde — et qui remonte la pile une fois le dossier
// choisi, parce qu'un conteneur ne se remonte pas lui-même.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gullify/api/api_client.dart';
import 'package:gullify/api/music_root_repository.dart';
import 'package:gullify/screens/admin/music_root_screen.dart';
import 'package:gullify/state/music_root.dart';
import 'package:gullify/theme.dart';

class _FakeClient extends Fake implements ApiClient {
  final List<String> vus = [];
  final List<Map<String, dynamic>> envoyes = [];
  bool refuse = false;

  @override
  Future<dynamic> get(String path, {Map<String, dynamic>? query}) async {
    final chemin = query?['chemin'] as String?;
    vus.add(chemin ?? '(départ)');
    if (chemin == null) {
      return {
        'chemin': '',
        'depart': true,
        'actuelle': '/media/music',
        'dossiers': [
          {'nom': 'music', 'chemin': '/media/music', 'musique': 50},
          {'nom': 'Sans titre', 'chemin': '/media/maxime/USB', 'musique': 0},
        ],
      };
    }
    if (chemin == '/media/music/beaucoup') {
      return {
        'chemin': chemin,
        'parent': '/media/music',
        'actuelle': '/media/music',
        'musique': 50,
        'tronque': true,
        'dossiers': [
          // Dans un dossier d'artistes, le compagnon ne sonde plus chacun :
          // « -1 » dit qu'il n'a pas regardé, ce qui n'est pas « rien ».
          {'nom': 'Un artiste', 'chemin': '\$chemin/Un artiste', 'musique': -1},
        ],
      };
    }
    return {
      'chemin': chemin,
      'parent': '/media',
      'actuelle': '/media/music',
      'musique': 12,
      'dossiers': [
        {'nom': 'Albums', 'chemin': '\$chemin/Albums', 'musique': 7},
        {'nom': 'beaucoup', 'chemin': '/media/music/beaucoup', 'musique': 0},
      ],
    };
  }

  @override
  Future<dynamic> post(
    String path, {
    Object? body,
    Map<String, dynamic>? form,
    Map<String, dynamic>? query,
  }) async {
    if (refuse) throw Exception('compagnon absent');
    envoyes.add(body as Map<String, dynamic>);
    return {'demande': 'racine'};
  }
}

Widget _app(Widget child, _FakeClient client) => ProviderScope(
      overrides: [
        musicRootRepositoryProvider
            .overrideWithValue(MusicRootRepository(client)),
      ],
      child: MaterialApp(
        theme: gullifyThemeFor(GullifyAccent.indigo, dark: false),
        home: child,
      ),
    );

void main() {
  test('ce que le compagnon raconte se relit sans perdre un champ', () async {
    final vue = await MusicRootRepository(_FakeClient()).parcourir();

    expect(vue.depart, isTrue);
    expect(vue.actuelle, '/media/music');
    expect(vue.dossiers.map((d) => d.nom), ['music', 'Sans titre']);
    // L'indice qui compte au moment de choisir : y a-t-il de la musique ?
    expect(vue.dossiers.first.aDeLaMusique, isTrue);
    expect(vue.dossiers.last.aDeLaMusique, isFalse);
  });

  testWidgets('l\'écran part des disques, puis descend', (tester) async {
    final client = _FakeClient();
    await tester.pumpWidget(_app(const MusicRootScreen(), client));
    await tester.pumpAndSettle();

    // Au départ : les disques de la machine, clé USB comprise.
    expect(find.text('Les disques de la machine'), findsOneWidget);
    expect(find.text('music'), findsOneWidget);
    expect(find.text('Sans titre'), findsOneWidget);
    // Rien à choisir ici : on ne monte pas « les disques ».
    expect(find.textContaining('Lire la musique ici'), findsNothing);

    await tester.tap(find.text('music'));
    await tester.pumpAndSettle();

    expect(client.vus, ['(départ)', '/media/music']);
    expect(find.text('Albums'), findsOneWidget);
    // Le dossier où l'on est fait un candidat : c'est souvent lui qu'on veut.
    expect(find.text('Lire la musique ici'), findsOneWidget);
    expect(find.text('Remonter'), findsOneWidget);
  });

  testWidgets('choisir un dossier demande confirmation et prévient du '
      'redémarrage', (tester) async {
    final client = _FakeClient();
    await tester.pumpWidget(_app(const MusicRootScreen(), client));
    await tester.pumpAndSettle();
    await tester.tap(find.text('music'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Lire la musique ici'));
    await tester.pumpAndSettle();

    // On ne remonte pas un serveur par surprise.
    expect(find.text('Lire la musique ici ?'), findsOneWidget);
    expect(find.textContaining('redémarrer'), findsOneWidget);
    expect(client.envoyes, isEmpty);

    await tester.tap(find.text('Changer'));
    await tester.pumpAndSettle();

    expect(client.envoyes.single, {'chemin': '/media/music'});
  });

  testWidgets('une liste écourtée le dit, et « pas regardé » n\'est pas '
      '« rien »', (tester) async {
    final client = _FakeClient();
    await tester.pumpWidget(_app(const MusicRootScreen(), client));
    await tester.pumpAndSettle();
    await tester.tap(find.text('music'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('beaucoup'));
    await tester.pumpAndSettle();

    expect(find.textContaining('la liste est écourtée'), findsOneWidget);
    // Un dossier non sondé n'annonce pas de la musique qu'on n'a pas cherchée.
    expect(find.textContaining('· de la musique'), findsNothing);
  });

  testWidgets('un refus du serveur se dit, et rien ne bouge', (tester) async {
    final client = _FakeClient()..refuse = true;
    await tester.pumpWidget(_app(const MusicRootScreen(), client));
    await tester.pumpAndSettle();
    await tester.tap(find.text('music'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lire la musique ici'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Changer'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Refusé'), findsOneWidget);
    expect(client.envoyes, isEmpty);
  });
}
