// Pièces jointes du carnet d'idées (idée #84) : une capture d'écran ou un
// fichier vaut mieux qu'un paragraphe. Le carnet les montre, permet d'en
// ajouter/retirer, et les envoie une fois l'idée créée côté serveur.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gullify/api/ideas_repository.dart';
import 'package:gullify/screens/ideas_screen.dart';
import 'package:gullify/state/ideas.dart';

class _FakeIdeasRepo extends Fake implements IdeasRepository {
  _FakeIdeasRepo(this.ideas);

  List<Idea> ideas;
  final List<String> added = [];
  final List<int> deletedFiles = [];
  final List<(int, String)> uploads = [];
  int nextId = 42;

  @override
  Future<List<Idea>> list() async => ideas;

  @override
  Future<int> add(String text) async {
    added.add(text);
    return nextId;
  }

  @override
  Future<IdeaAttachment> addFile(int ideaId, String filePath, String name) async {
    uploads.add((ideaId, name));
    return IdeaAttachment(
      id: 100 + uploads.length,
      name: name,
      mime: mimeForName(name),
      size: 1234,
      url: 'serve_idea_file.php?id=${100 + uploads.length}',
    );
  }

  @override
  Future<void> deleteFile(int fileId) async => deletedFiles.add(fileId);

  @override
  String fileUrl(IdeaAttachment attachment, {String? token}) =>
      'https://exemple.test/${attachment.url}';
}

Idea _idea({
  int id = 1,
  String text = 'Une idée',
  String status = 'todo',
  List<IdeaAttachment> attachments = const [],
}) =>
    Idea(id: id, text: text, status: status, attachments: attachments);

const _capture = IdeaAttachment(
  id: 7,
  name: 'capture.png',
  mime: 'image/png',
  size: 2048,
  url: 'serve_idea_file.php?id=7',
);

Future<void> _pump(
  WidgetTester tester,
  _FakeIdeasRepo repo, {
  List<PickedIdeaFile> picks = const [],
}) async {
  tester.view.physicalSize = const Size(412, 892);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ideasRepositoryProvider.overrideWithValue(repo),
        // Les octets d'une pièce jointe sortent de l'API v2 : le jeton part
        // en en-tête. Rien à authentifier dans un test.
        ideaFileHeadersProvider.overrideWithValue(const <String, String>{}),
      ],
      child: MaterialApp(
        // Ni galerie ni SAF sous test : le choix du fichier est simulé.
        home: IdeasScreen(filePicker: () async => picks),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  test('le type MIME se devine à partir du nom', () {
    expect(mimeForName('capture.PNG'), 'image/png');
    expect(mimeForName('photo.jpg'), 'image/jpeg');
    expect(mimeForName('journal.log'), 'text/plain');
    expect(mimeForName('archive.zip'), 'application/octet-stream');
    expect(mimeForName('sans_extension'), 'application/octet-stream');
  });

  test('une idée relit ses pièces jointes du JSON serveur', () {
    final idea = Idea.fromJson({
      'id': 3,
      'text': 'joindre des fichiers',
      'status': 'todo',
      'attachments': [
        {
          'id': 9,
          'name': 'maquette.png',
          'mime': 'image/png',
          'size': 1536 * 1024,
          'url': 'serve_idea_file.php?id=9',
        },
      ],
    });
    expect(idea.attachments, hasLength(1));
    expect(idea.attachments.single.isImage, isTrue);
    expect(idea.attachments.single.prettySize, '1,5 Mo');
  });

  testWidgets('une idée sans fichier propose d\'en joindre un',
      (tester) async {
    await _pump(tester, _FakeIdeasRepo([_idea()]));
    expect(find.text('Joindre un fichier'), findsOneWidget);
  });

  testWidgets('une idée avec fichiers les compte et les liste',
      (tester) async {
    await _pump(tester, _FakeIdeasRepo([_idea(attachments: const [_capture])]));

    expect(find.text('1 pièce jointe'), findsOneWidget);
    await tester.tap(find.text('1 pièce jointe'));
    await tester.pumpAndSettle();

    expect(find.text('Pièces jointes'), findsOneWidget);
    expect(find.text('capture.png'), findsOneWidget);
    expect(find.text('2 ko'), findsOneWidget);
  });

  testWidgets('retirer une pièce jointe la supprime côté serveur',
      (tester) async {
    final repo = _FakeIdeasRepo([_idea(attachments: const [_capture])]);
    await _pump(tester, repo);

    await tester.tap(find.text('1 pièce jointe'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();

    expect(repo.deletedFiles, [7]);
    expect(find.text('capture.png'), findsNothing);
    expect(find.text('Aucun fichier joint.'), findsOneWidget);
  });

  testWidgets('une idée faite garde ses fichiers mais n\'en accepte plus',
      (tester) async {
    await _pump(
      tester,
      _FakeIdeasRepo([_idea(status: 'done', attachments: const [_capture])]),
    );

    expect(find.text('1 pièce jointe'), findsOneWidget);
    await tester.tap(find.text('1 pièce jointe'));
    await tester.pumpAndSettle();

    expect(find.text('capture.png'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Joindre'), findsNothing);
    expect(find.byIcon(Icons.delete_outline), findsNothing);
  });

  testWidgets('ajouter une idée envoie ensuite ses pièces jointes',
      (tester) async {
    final repo = _FakeIdeasRepo([]);
    await _pump(
      tester,
      repo,
      picks: const [PickedIdeaFile('/tmp/capture.png', 'capture.png')],
    );

    await tester.enterText(find.byType(TextField), 'idée avec capture');
    await tester.tap(find.byIcon(Icons.attach_file));
    await tester.pumpAndSettle();
    // Le fichier attend dans le brouillon : l'idée n'existe pas encore.
    expect(find.widgetWithText(Chip, 'capture.png'), findsOneWidget);
    expect(repo.uploads, isEmpty);

    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();

    expect(repo.added, ['idée avec capture']);
    // …et il part sur l'idée qui vient d'être créée.
    expect(repo.uploads, [(42, 'capture.png')]);
    expect(find.widgetWithText(Chip, 'capture.png'), findsNothing);
  });

  testWidgets('joindre un fichier à une idée existante l\'envoie tout de suite',
      (tester) async {
    final repo = _FakeIdeasRepo([_idea(id: 5)]);
    await _pump(
      tester,
      repo,
      picks: const [PickedIdeaFile('/tmp/journal.log', 'journal.log')],
    );

    await tester.tap(find.text('Joindre un fichier'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Joindre'));
    await tester.pumpAndSettle();

    expect(repo.uploads, [(5, 'journal.log')]);
    expect(find.text('journal.log'), findsOneWidget);
  });
}
