// Le lecteur a un bouton « Accords guitare » à côté des paroles (idée #61) :
// le serveur renvoie une grille balisée [ch]…[/ch], l'app la colore, la
// transpose sans casser l'alignement et dessine les doigtés.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gullify/api/library_repository.dart';
import 'package:gullify/audio/tuner.dart';
import 'package:gullify/models/song_chords.dart';
import 'package:gullify/state/library.dart';
import 'package:gullify/state/tuner.dart';
import 'package:gullify/widgets/chords_sheet.dart';

/// Micro de papier : l'accordeur ouvert depuis la grille ne doit pas aller
/// chercher le vrai micro dans un test.
class _SilentPitchSource implements PitchSource {
  @override
  Future<bool> ensurePermission() async => true;

  @override
  Future<Stream<double?>> start() async => const Stream<double?>.empty();

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {}
}

class _FakeLibraryRepo extends Fake implements LibraryRepository {
  _FakeLibraryRepo(this.result);

  final ChordsResult result;
  final List<String> asked = [];

  @override
  Future<ChordsResult> chords(String filePath) async {
    asked.add(filePath);
    return result;
  }
}

const _grid = '''
[Intro]
[ch]Em7[/ch]   [ch]G[/ch]   [ch]Dsus4[/ch]

[Verse 1]
[ch]Em7[/ch]      [ch]G[/ch]
Today is gonna be the day''';

SongChords _chords({String content = _grid}) => SongChords(
      artist: 'Oasis',
      title: 'Wonderwall',
      content: content,
      url: 'https://tabs.ultimate-guitar.com/tab/oasis/wonderwall-chords-39144',
      capo: 2,
      tonality: 'F#m',
      tuning: 'E A D G B E',
      votes: 12528,
      shapes: const {
        'Em7': ChordShape(
          frets: [0, 0, 0, 0, 2, 0],
          fingers: [0, 0, 0, 0, 1, 0],
        ),
        'G': ChordShape(frets: [3, 0, 0, 0, 2, 3], fingers: [3, 0, 0, 0, 1, 2]),
      },
    );

/// Le texte d'une ligne, accords compris : ce que l'œil voit à l'écran.
String _flat(List<ChordToken> line) => line.map((t) => t.text).join();

/// Colonne où commence chaque accord de la ligne.
List<int> _chordOffsets(List<ChordToken> line) {
  final offsets = <int>[];
  var column = 0;
  for (final token in line) {
    if (token.isChord) offsets.add(column);
    column += token.text.length;
  }
  return offsets;
}

/// Vrai si un accord colle au morceau suivant : la grille devient illisible.
bool _glued(List<ChordToken> line) {
  for (var i = 0; i < line.length - 1; i++) {
    if (line[i].isChord && !line[i + 1].text.startsWith(' ')) return true;
  }
  return false;
}

Future<void> _open(WidgetTester tester, _FakeLibraryRepo repo) async {
  tester.view.physicalSize = const Size(412, 892);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        libraryRepositoryProvider.overrideWithValue(repo),
        pitchSourceProvider.overrideWithValue(_SilentPitchSource()),
      ],
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => showChordsSheet(context, 'a/b/song.mp3'),
                child: const Text('ouvrir'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('ouvrir'));
  await tester.pumpAndSettle();
}

void main() {
  group('lecture de la grille', () {
    test('sépare les accords du texte', () {
      final lines = parseChordLines(_grid);
      expect(lines.length, 6);
      expect(isSectionLine(lines[0]), isTrue);
      final chordsOfLine = lines[1].where((t) => t.isChord).map((t) => t.text);
      expect(chordsOfLine, ['Em7', 'G', 'Dsus4']);
      expect(lines[5].every((t) => !t.isChord), isTrue);
      expect(_flat(lines[5]), 'Today is gonna be the day');
    });

    test('liste les accords distincts dans l\'ordre', () {
      expect(distinctChords(parseChordLines(_grid)), ['Em7', 'G', 'Dsus4']);
    });

    test('une ligne de paroles n\'est pas une section', () {
      expect(isSectionLine(parseChordLines('Today is the day').single), isFalse);
    });
  });

  group('transposition', () {
    test('déplace la fondamentale et la basse', () {
      expect(transposeChord('G', 2), 'A');
      expect(transposeChord('Em7', 1), 'Fm7');
      expect(transposeChord('G/F#', 2), 'A/G#');
      expect(transposeChord('Dsus4', -2), 'Csus4');
    });

    test('boucle sur l\'octave et garde l\'écriture en bémols', () {
      expect(transposeChord('B', 1), 'C');
      expect(transposeChord('C', -1), 'B');
      expect(transposeChord('Bb', 2), 'C');
      expect(transposeChord('Ab', 1), 'A');
    });

    test('laisse le texte qui n\'est pas un accord', () {
      expect(transposeChord('x4', 2), 'x4');
      expect(transposeChord('Intro', 2), 'Intro');
    });

    test('garde les accords au-dessus des mêmes syllabes', () {
      final original = parseChordLines(
        '[ch]Em7[/ch]      [ch]G[/ch]    [ch]Dsus4[/ch]   fin',
      );
      for (final semitones in [1, -1, 5, -4]) {
        final moved = transposeLines(original, semitones);
        expect(
          _chordOffsets(moved.single),
          _chordOffsets(original.single),
          reason: 'colonnes conservées à $semitones demi-tons',
        );
        // Un séparateur reste toujours après un accord.
        expect(_glued(moved.single), isFalse);
      }
    });

    test('ne touche à rien à zéro demi-ton', () {
      final lines = parseChordLines(_grid);
      expect(transposeLines(lines, 0), same(lines));
    });
  });

  group('feuille du lecteur', () {
    testWidgets('affiche la grille, le capo et les doigtés', (tester) async {
      final repo = _FakeLibraryRepo(ChordsResult(chords: _chords()));
      await _open(tester, repo);

      expect(repo.asked, ['a/b/song.mp3']);
      expect(find.text('Wonderwall'), findsOneWidget);
      expect(find.text('Capo 2'), findsOneWidget);
      expect(find.text('Tonalité F#m'), findsOneWidget);
      // Un diagramme par accord connu du serveur.
      expect(find.byType(ChordDiagram), findsNWidgets(2));
      expect(find.text('Today is gonna be the day'), findsOneWidget);
    });

    testWidgets('le bouton + transpose la grille et la tonalité',
        (tester) async {
      await _open(tester, _FakeLibraryRepo(ChordsResult(chords: _chords())));

      await tester.tap(find.byTooltip('Transposer vers le haut'));
      await tester.pump();

      expect(find.text('+1'), findsOneWidget);
      expect(find.text('Tonalité Gm'), findsOneWidget);
      // Les doigtés restent ceux de la version d'origine : on l'annonce.
      expect(find.text('Doigtés (position d\'origine)'), findsOneWidget);
    });

    testWidgets('ouvre l\'accordeur réglé sur l\'accordage de la grille',
        (tester) async {
      await _open(tester, _FakeLibraryRepo(ChordsResult(chords: _chords())));

      await tester.tap(find.byTooltip('Accordeur'));
      await tester.pumpAndSettle();

      expect(find.text('Accordeur'), findsOneWidget);
      expect(find.text('Joue une corde à vide'), findsOneWidget);
      // « E A D G B E » : l'accordeur est parti sur le standard.
      final chip = tester.widget<ChoiceChip>(
        find.ancestor(
          of: find.text('Standard'),
          matching: find.byType(ChoiceChip),
        ),
      );
      expect(chip.selected, isTrue);
    });

    testWidgets('sans grille, propose la recherche', (tester) async {
      await _open(
        tester,
        _FakeLibraryRepo(
          const ChordsResult(searchUrl: 'https://www.ultimate-guitar.com/x'),
        ),
      );

      expect(find.text('Aucune grille trouvée pour ce titre'), findsOneWidget);
      expect(find.text('Chercher sur Ultimate-Guitar'), findsOneWidget);
    });
  });
}
