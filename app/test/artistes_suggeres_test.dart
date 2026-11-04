// Accueil → Découvrir → « Artistes suggérés » : les artistes aimés dans tes
// goûts mais pas encore chez toi d'abord, puis les autres ; le cœur ajoute
// (ou retire) un artiste de tes goûts.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gullify/api/api_client.dart';
import 'package:gullify/api/library_repository.dart';
import 'package:gullify/api/pour_toi_repository.dart';
import 'package:gullify/screens/artistes_suggeres_screen.dart';
import 'package:gullify/state/pour_toi.dart';
import 'package:gullify/theme.dart';

class _Faux extends PourToiRepository {
  _Faux()
    : super(
        ApiClient(serverUrl: 'https://maison.test'),
        LibraryRepository(ApiClient(serverUrl: 'https://maison.test')),
      );

  final choix = <String, int>{};

  @override
  Future<List<ArtisteSuggere>> suggestions() async => const [
    ArtisteSuggere(
      bulle: Bulle(cle: 'beaudommage', nom: 'Beau Dommage', niveau: 2),
      groupe: 'gouts',
      raison: 'Tu l\'adores',
    ),
    ArtisteSuggere(
      bulle: Bulle(cle: 'harmonium', nom: 'Harmonium'),
      groupe: 'suggeres',
      raison: 'Proche de Beau Dommage',
    ),
  ];

  @override
  Future<void> choisir(Bulle b, int niveau, {String? parent}) async =>
      choix[b.cle] = niveau;
}

void main() {
  testWidgets('les aimés pas encore chez toi d\'abord, puis les suggérés', (
    tester,
  ) async {
    final faux = _Faux();
    final container = ProviderContainer(
      retry: (_, _) => null,
      overrides: [pourToiRepositoryProvider.overrideWithValue(faux)],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: gullifyThemeFor(GullifyAccent.indigo, dark: false),
          home: const ArtistesSuggeresScreen(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    final titreGouts = tester.getTopLeft(
      find.text('Dans tes goûts, pas encore chez toi'),
    );
    final titreAutres = tester.getTopLeft(find.text('Suggérés pour toi'));
    final beau = tester.getTopLeft(find.text('Beau Dommage'));
    final harmonium = tester.getTopLeft(find.text('Harmonium'));
    expect(titreGouts.dy < beau.dy, isTrue);
    expect(beau.dy < titreAutres.dy, isTrue);
    expect(titreAutres.dy < harmonium.dy, isTrue);
    expect(find.text('Proche de Beau Dommage'), findsOneWidget);

    // Le cœur d'Harmonium : il rejoint tes goûts.
    await tester.tap(find.byTooltip('J\'aime'));
    await tester.pump();
    expect(faux.choix['harmonium'], 1);
    expect(find.byTooltip('Retirer de tes goûts'), findsNWidgets(2));
  });
}
