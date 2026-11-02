// « Tes artistes » : les bulles à la Spotify — un toucher aime, deux adorent,
// trois retirent ; aimer fait éclore des artistes proches ; la recherche
// trouve aussi des artistes hors de la bibliothèque.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:gullify/api/api_client.dart';
import 'package:gullify/api/library_repository.dart';
import 'package:gullify/api/pour_toi_repository.dart';
import 'package:gullify/screens/artistes_bulles_screen.dart';
import 'package:gullify/state/pour_toi.dart';
import 'package:gullify/theme.dart';

class _Faux extends PourToiRepository {
  _Faux()
    : super(
        ApiClient(serverUrl: 'https://maison.test'),
        LibraryRepository(ApiClient(serverUrl: 'https://maison.test')),
      );

  final choix = <String, int>{};
  int analyses = 0;
  final autourDe = <String>[];

  @override
  Future<List<Bulle>> bulles() async => const [
    Bulle(cle: 'nofx', nom: 'NOFX', artistId: 1),
    Bulle(cle: 'reset', nom: 'Reset', artistId: 2),
    Bulle(cle: 'sum41', nom: 'Sum 41'),
  ];

  @override
  Future<List<Bulle>> autour(Bulle b, Iterable<String> deja) async {
    autourDe.add(b.cle);
    return const [
      Bulle(cle: 'pennywise', nom: 'Pennywise', artistId: 3),
      Bulle(cle: 'reset', nom: 'Reset', artistId: 2), // déjà là : ignoré
    ];
  }

  @override
  Future<List<Bulle>> chercherArtiste(String texte) async => const [
    Bulle(cle: 'beaudommage', nom: 'Beau Dommage'),
  ];

  @override
  Future<void> choisir(Bulle b, int niveau) async => choix[b.cle] = niveau;

  @override
  Future<void> analyser() async => analyses++;
}

Future<_Faux> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(412, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final faux = _Faux();
  final container = ProviderContainer(
    retry: (_, _) => null,
    overrides: [pourToiRepositoryProvider.overrideWithValue(faux)],
  );
  addTearDown(container.dispose);
  final router = GoRouter(
    initialLocation: '/gouts/artistes',
    routes: [
      GoRoute(path: '/', builder: (_, _) => const Text('accueil')),
      GoRoute(path: '/gouts', builder: (_, _) => const Text('page goûts')),
      GoRoute(
        path: '/gouts/artistes',
        builder: (_, _) => const ArtistesBullesScreen(),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        theme: gullifyThemeFor(GullifyAccent.indigo, dark: false),
        routerConfig: router,
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
  return faux;
}

void main() {
  testWidgets('un toucher aime, deux adorent, trois retirent', (tester) async {
    final faux = await _pump(tester);
    final nofx = find.text('NOFX');

    await tester.tap(nofx);
    await tester.pump(const Duration(milliseconds: 400));
    expect(faux.choix['nofx'], 1);
    expect(find.bySemanticsLabel('NOFX, aimé'), findsOneWidget);

    await tester.tap(nofx);
    await tester.pump(const Duration(milliseconds: 400));
    expect(faux.choix['nofx'], 2);
    expect(find.bySemanticsLabel('NOFX, adoré'), findsOneWidget);

    await tester.tap(nofx);
    await tester.pump(const Duration(milliseconds: 400));
    expect(faux.choix['nofx'], 0);
    expect(find.bySemanticsLabel('NOFX, pas choisi'), findsOneWidget);
  });

  testWidgets('aimer fait éclore les proches, sans doublon', (tester) async {
    final faux = await _pump(tester);
    expect(find.text('Pennywise'), findsNothing);
    await tester.tap(find.text('NOFX'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    expect(faux.autourDe, ['nofx']);
    expect(find.text('Pennywise'), findsOneWidget);
    expect(find.text('Reset'), findsOneWidget);
    // Adorer ensuite ne refait pas éclore.
    await tester.tap(find.text('NOFX'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(faux.autourDe, ['nofx']);
  });

  testWidgets('un artiste hors bibliothèque se trouve et s\'ajoute', (
    tester,
  ) async {
    final faux = await _pump(tester);
    expect(find.text('pas dans ta biblio'), findsOneWidget); // Sum 41
    await tester.enterText(find.byType(TextField), 'beau');
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    expect(find.text('Beau Dommage'), findsOneWidget);
    await tester.tap(find.text('Beau Dommage'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(faux.choix['beaudommage'], 1);
    // De retour aux bulles : il y est, aimé, en tête.
    await tester.enterText(find.byType(TextField), '');
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.bySemanticsLabel('Beau Dommage, aimé'), findsOneWidget);
  });

  testWidgets(
    '« Terminé » recalcule le profil quand on a changé quelque chose',
    (tester) async {
      final faux = await _pump(tester);
      await tester.tap(find.text('Reset'));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text('Terminé'));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));
      expect(faux.analyses, 1);
    await tester.pumpAndSettle();
    expect(find.text('page goûts'), findsOneWidget);
    },
  );
}
