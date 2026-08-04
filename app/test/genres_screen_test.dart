// « Gérer les genres » ne faisait que renommer et supprimer : on ne pouvait
// ajouter un genre qu'en le tapant dans la fiche d'un artiste, et il
// disparaissait de la liste dès que plus personne ne le portait.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gullify/api/api_client.dart';
import 'package:gullify/api/library_repository.dart';
import 'package:gullify/screens/genres_screen.dart';
import 'package:gullify/state/library.dart';

const _taxonomy = ['Punk', 'Métal'];

class _FakeLibraryRepo extends Fake implements LibraryRepository {
  /// Les genres que la bibliothèque contient (get_genres).
  List<GenreCount> library = const [GenreCount('Punk', 4, albumCount: 9)];

  /// Ceux ajoutés à la main, portés ou non par un artiste.
  List<String> custom = const [];

  /// Le refus du serveur, quand il y en a un (doublon, nom vide).
  String? refusal;

  final added = <String>[];
  final deleted = <String>[];

  @override
  Future<List<GenreCount>> genres() async => library;

  @override
  Future<GenreTaxonomy> genreTaxonomy() async =>
      GenreTaxonomy(genres: [..._taxonomy, ...custom], custom: custom);

  @override
  Future<void> addGenre(String name) async {
    if (refusal != null) throw ApiException('add_genre', refusal!);
    added.add(name);
    custom = [...custom, name];
  }

  @override
  Future<void> deleteGenre(String genre) async {
    deleted.add(genre);
    custom = [...custom.where((g) => g != genre)];
    library = [...library.where((g) => g.name != genre)];
  }
}

Future<void> _pump(WidgetTester tester, _FakeLibraryRepo repo) async {
  tester.view.physicalSize = const Size(412, 892);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [libraryRepositoryProvider.overrideWithValue(repo)],
      child: const MaterialApp(home: GenresScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('un genre ajouté figure dans la liste, sans artiste',
      (tester) async {
    final repo = _FakeLibraryRepo()..custom = const ['Musique de fanfare'];
    await _pump(tester, repo);

    expect(find.text('Punk'), findsOneWidget);
    expect(find.text('4 artistes'), findsOneWidget);
    expect(find.text('Musique de fanfare'), findsOneWidget);
    expect(find.text('Aucun artiste'), findsOneWidget);
  });

  testWidgets('un genre ajouté déjà porté n\'apparaît qu\'une fois',
      (tester) async {
    final repo = _FakeLibraryRepo()
      ..library = const [GenreCount('Musique de fanfare', 2, albumCount: 3)]
      ..custom = const ['Musique de fanfare'];
    await _pump(tester, repo);

    expect(find.text('Musique de fanfare'), findsOneWidget);
    expect(find.text('2 artistes'), findsOneWidget);
    expect(find.text('Aucun artiste'), findsNothing);
  });

  testWidgets('« Ajouter » crée le genre et la liste le montre aussitôt',
      (tester) async {
    final repo = _FakeLibraryRepo();
    await _pump(tester, repo);

    await tester.tap(find.widgetWithText(FloatingActionButton, 'Ajouter'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '  Musique de fanfare  ');
    await tester.tap(find.widgetWithText(FilledButton, 'Ajouter'));
    await tester.pumpAndSettle();

    // Les espaces de trop ne font pas un autre genre.
    expect(repo.added, ['Musique de fanfare']);
    expect(find.text('Genre « Musique de fanfare » ajouté'), findsOneWidget);
    expect(find.widgetWithText(ListTile, 'Musique de fanfare'), findsOneWidget);
  });

  testWidgets('un nom vide n\'appelle même pas le serveur', (tester) async {
    final repo = _FakeLibraryRepo();
    await _pump(tester, repo);

    await tester.tap(find.widgetWithText(FloatingActionButton, 'Ajouter'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Ajouter'));
    await tester.pumpAndSettle();

    expect(repo.added, isEmpty);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('le refus du serveur se montre tel quel', (tester) async {
    final repo = _FakeLibraryRepo()
      ..refusal = '« Punk » est déjà dans la liste.';
    await _pump(tester, repo);

    await tester.tap(find.widgetWithText(FloatingActionButton, 'Ajouter'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'punk');
    await tester.tap(find.widgetWithText(FilledButton, 'Ajouter'));
    await tester.pumpAndSettle();

    expect(find.text('« Punk » est déjà dans la liste.'), findsOneWidget);
    expect(find.widgetWithText(ListTile, 'punk'), findsNothing);
  });

  testWidgets('supprimer un genre sans artiste dit qu\'il quitte la liste',
      (tester) async {
    final repo = _FakeLibraryRepo()..custom = const ['Musique de fanfare'];
    await _pump(tester, repo);

    await tester.tap(find.byIcon(Icons.delete_outline).last);
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Personne ne le porte'),
      findsOneWidget,
    );

    await tester.tap(find.widgetWithText(FilledButton, 'Supprimer'));
    await tester.pumpAndSettle();

    expect(repo.deleted, ['Musique de fanfare']);
    expect(find.text('Musique de fanfare'), findsNothing);
  });
}
