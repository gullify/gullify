/// Grille d'accords guitare d'un titre (bouton « Accords » du lecteur).
/// Le serveur renvoie le texte tel quel, accords balisés `[ch]…[/ch]`.
library;

/// Doigté d'un accord : une case par corde, de l'aiguë (mi) à la grave.
/// `-1` = corde étouffée, `0` = corde à vide, sinon la case (absolue).
class ChordShape {
  const ChordShape({required this.frets, required this.fingers});

  final List<int> frets;
  final List<int> fingers;

  static ChordShape? fromJson(Map<String, dynamic> json) {
    final frets = (json['frets'] as List<dynamic>? ?? [])
        .map((e) => (e as num).toInt())
        .toList();
    if (frets.length != 6) return null;
    final fingers = (json['fingers'] as List<dynamic>? ?? [])
        .map((e) => (e as num).toInt())
        .toList();
    return ChordShape(
      frets: frets,
      fingers: fingers.length == 6 ? fingers : List.filled(6, 0),
    );
  }
}

class SongChords {
  const SongChords({
    required this.artist,
    required this.title,
    required this.content,
    required this.url,
    this.capo,
    this.tonality,
    this.tuning,
    this.rating,
    this.votes,
    this.shapes = const {},
  });

  final String artist;
  final String title;
  final String content;
  final String url;
  final int? capo;
  final String? tonality;
  final String? tuning;
  final double? rating;
  final int? votes;
  final Map<String, ChordShape> shapes;

  static SongChords? fromJson(Map<String, dynamic> json) {
    final content = json['content'] as String?;
    if (content == null || content.trim().isEmpty) return null;
    final shapes = <String, ChordShape>{};
    (json['shapes'] as Map<String, dynamic>? ?? {}).forEach((name, value) {
      if (value is Map<String, dynamic>) {
        final shape = ChordShape.fromJson(value);
        if (shape != null) shapes[name] = shape;
      }
    });
    return SongChords(
      artist: json['artist'] as String? ?? '',
      title: json['title'] as String? ?? '',
      content: content,
      url: json['url'] as String? ?? '',
      capo: (json['capo'] as num?)?.toInt(),
      tonality: json['tonality'] as String?,
      tuning: json['tuning'] as String?,
      rating: (json['rating'] as num?)?.toDouble(),
      votes: (json['votes'] as num?)?.toInt(),
      shapes: shapes,
    );
  }
}

/// Réponse de `chords.php` : la grille si elle existe, et toujours l'adresse
/// de recherche pour aller voir soi-même quand on n'a rien trouvé.
class ChordsResult {
  const ChordsResult({this.chords, this.searchUrl});

  final SongChords? chords;
  final String? searchUrl;
}

/// Un morceau de ligne : du texte simple, ou un accord.
class ChordToken {
  const ChordToken(this.text, {this.isChord = false});

  final String text;
  final bool isChord;
}

final _chordMarker = RegExp(r'\[ch\](.*?)\[/ch\]', dotAll: true);

/// Découpe la grille en lignes de morceaux, accords repérés par `[ch]…[/ch]`.
List<List<ChordToken>> parseChordLines(String content) => [
      for (final line in content.split('\n')) _parseLine(line),
    ];

List<ChordToken> _parseLine(String line) {
  final tokens = <ChordToken>[];
  var index = 0;
  for (final m in _chordMarker.allMatches(line)) {
    if (m.start > index) {
      tokens.add(ChordToken(line.substring(index, m.start)));
    }
    tokens.add(ChordToken(m.group(1)!, isChord: true));
    index = m.end;
  }
  if (index < line.length) tokens.add(ChordToken(line.substring(index)));
  return tokens;
}

/// Accords distincts de la grille, dans l'ordre d'apparition.
List<String> distinctChords(List<List<ChordToken>> lines) {
  final names = <String>{};
  for (final line in lines) {
    for (final token in line) {
      if (token.isChord && token.text.trim().isNotEmpty) {
        names.add(token.text.trim());
      }
    }
  }
  return names.toList();
}

/// Une ligne de section (« [Intro] », « [Verse 1] ») : un titre, pas des paroles.
bool isSectionLine(List<ChordToken> tokens) {
  if (tokens.length != 1 || tokens.first.isChord) return false;
  final text = tokens.first.text.trim();
  return text.length > 2 && text.startsWith('[') && text.endsWith(']');
}

const _sharpNotes = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'];
const _flatNotes = ['C', 'Db', 'D', 'Eb', 'E', 'F', 'Gb', 'G', 'Ab', 'A', 'Bb', 'B'];

int? _noteIndex(String note) {
  final sharp = _sharpNotes.indexOf(note);
  if (sharp >= 0) return sharp;
  final flat = _flatNotes.indexOf(note);
  return flat >= 0 ? flat : null;
}

final _chordPattern = RegExp(r'^([A-G][#b]?)([^/]*)(?:/([A-G][#b]?))?$');

/// Transpose un nom d'accord (« G/F# » → « A/G# »). Rend le nom inchangé si
/// ce n'est pas un accord reconnaissable — la grille contient aussi du texte.
String transposeChord(String chord, int semitones) {
  if (semitones == 0) return chord;
  final m = _chordPattern.firstMatch(chord.trim());
  if (m == null) return chord;
  final root = _noteIndex(m.group(1)!);
  if (root == null) return chord;
  // On garde l'écriture d'origine : une grille en bémols le reste.
  final scale = chord.contains('b') ? _flatNotes : _sharpNotes;
  String shift(int index) => scale[((index + semitones) % 12 + 12) % 12];

  final bassNote = m.group(3) != null ? _noteIndex(m.group(3)!) : null;
  final buffer = StringBuffer(shift(root))..write(m.group(2) ?? '');
  if (bassNote != null) buffer.write('/${shift(bassNote)}');
  return buffer.toString();
}

/// Transpose une grille entière en gardant l'alignement : un accord qui
/// s'allonge grignote l'espace qui le suit, un accord qui raccourcit le rend.
List<List<ChordToken>> transposeLines(
  List<List<ChordToken>> lines,
  int semitones,
) {
  if (semitones == 0) return lines;
  return [
    for (final line in lines) _transposeLine(line, semitones),
  ];
}

/// Transpose une ligne puis rattrape la largeur sur le texte qui suit chaque
/// accord : un accord qui s'allonge grignote un espace, un accord qui
/// raccourcit en rend un, pour que les colonnes restent au-dessus des paroles.
List<ChordToken> _transposeLine(List<ChordToken> line, int semitones) {
  final out = <ChordToken>[];
  for (var i = 0; i < line.length; i++) {
    final token = line[i];
    if (!token.isChord) {
      out.add(token);
      continue;
    }
    final moved = transposeChord(token.text, semitones);
    out.add(ChordToken(moved, isChord: true));

    final delta = moved.length - token.text.length;
    final next = i + 1 < line.length ? line[i + 1] : null;
    if (delta == 0 || next == null || next.isChord) continue;

    if (delta > 0) {
      // Ne mange que des espaces, et jamais le dernier : sans séparateur,
      // l'accord se collerait au mot suivant.
      final spaces = next.text.length - next.text.trimLeft().length;
      final eat = delta.clamp(0, spaces > 1 ? spaces - 1 : 0);
      if (eat == 0) continue;
      out.add(ChordToken(next.text.substring(eat)));
    } else {
      out.add(ChordToken(' ' * -delta + next.text));
    }
    i++; // le morceau de texte suivant vient d'être réécrit
  }
  return out;
}
