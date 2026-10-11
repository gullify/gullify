// La boîte du développeur : tout le monde peut envoyer une idée, une seule
// personne les reçoit. L'app doit dire à qui écrit que ses mots quittent sa
// machine, et ne montrer la boîte qu'à celui à qui elle est.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gullify/api/ideas_inbox_repository.dart';
import 'package:gullify/api/ideas_repository.dart';
import 'package:gullify/screens/ideas_screen.dart';
import 'package:gullify/state/ideas.dart';

class _CarnetFactice extends Fake implements IdeasRepository {
  _CarnetFactice({this.relais});

  final String? relais;

  @override
  Future<Carnet> list() async => Carnet(idees: const [], relais: relais);
}

class _BoiteFactice extends Fake implements IdeasInboxRepository {
  final adoptees = <int>[];
  final rejetees = <int>[];

  @override
  Future<void> adopter(int id) async => adoptees.add(id);

  @override
  Future<void> rejeter(int id) async => rejetees.add(id);
}

IdeeRecue recue(int id, {String utilisateur = 'bob', String serveur = 'https://chez-eux.ca'}) =>
    IdeeRecue(
      id: id,
      serveur: serveur,
      utilisateur: utilisateur,
      texte: 'Idée numéro $id',
      recueLe: '2026-10-11 10:00:00',
    );

Future<void> ouvrir(
  WidgetTester tester, {
  String? relais,
  List<IdeeRecue> boite = const [],
  IdeasInboxRepository? depot,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ideasRepositoryProvider.overrideWithValue(_CarnetFactice(relais: relais)),
        ideaFileHeadersProvider.overrideWithValue(const <String, String>{}),
        ideasInboxProvider.overrideWith((ref) async => boite),
        if (depot != null) ideasInboxRepositoryProvider.overrideWithValue(depot),
      ],
      child: const MaterialApp(home: IdeasScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('où vont les idées, dit avant de les écrire', () {
    testWidgets('un serveur qui relaie le dit', (tester) async {
      await ouvrir(tester, relais: 'https://maxime.gullify.app');
      expect(find.textContaining('envoyées au développeur'), findsOneWidget);
    });

    testWidgets('un serveur qui garde tout ne dit rien', (tester) async {
      // Le carnet du développeur lui-même : ses idées ne voyagent pas.
      await ouvrir(tester, relais: null);
      expect(find.textContaining('envoyées au développeur'), findsNothing);
    });
  });

  group('la boîte ne se montre qu\'à qui elle est', () {
    testWidgets('vide, elle est invisible', (tester) async {
      await ouvrir(tester, boite: const []);
      expect(find.textContaining('Reçues des autres'), findsNothing);
    });

    testWidgets('elle compte ce qu\'elle contient et dit d\'où ça vient',
        (tester) async {
      await ouvrir(tester, boite: [recue(1), recue(2, utilisateur: 'alice')]);

      expect(find.text('Reçues des autres · 2'), findsOneWidget);
      expect(find.text('Idée numéro 1'), findsOneWidget);
      expect(find.text('bob · chez-eux.ca'), findsOneWidget);
      expect(find.text('alice · chez-eux.ca'), findsOneWidget);
    });

    testWidgets('au-delà de quatre, elle ne chasse pas le carnet',
        (tester) async {
      await ouvrir(tester, boite: [for (var i = 1; i <= 7; i++) recue(i)]);

      expect(find.text('Idée numéro 4'), findsOneWidget);
      expect(find.text('Idée numéro 5'), findsNothing);
      expect(find.text('et 3 autres'), findsOneWidget);
    });

    testWidgets('adopter verse l\'idée, écarter la laisse', (tester) async {
      final depot = _BoiteFactice();
      await ouvrir(tester, boite: [recue(42)], depot: depot);

      await tester.tap(find.text('Adopter'));
      await tester.pumpAndSettle();
      expect(depot.adoptees, [42]);
      expect(depot.rejetees, isEmpty);
    });
  });

  group('la provenance se lit', () {
    test('sans serveur ni nom, on le dit', () {
      expect(recue(1, utilisateur: '', serveur: '').provenance,
          'origine inconnue');
    });

    test("l'adresse se lit sans son protocole", () {
      expect(recue(1, serveur: 'https://chez-eux.ca/').provenance,
          'bob · chez-eux.ca');
    });

    test('un nom seul suffit', () {
      expect(recue(1, serveur: '').provenance, 'bob');
    });
  });
}
