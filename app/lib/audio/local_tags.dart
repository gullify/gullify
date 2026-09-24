import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Lecture des étiquettes d'un fichier audio — en Dart pur (idée #114).
///
/// Le mode « dossier local » n'a pas de serveur pour ranger la musique : c'est
/// l'app qui doit lire elle-même le titre, l'interprète, l'album, la pochette
/// et la durée dans les fichiers. Plutôt qu'un greffon natif (une dépendance
/// de plus à compiler pour chaque plateforme, et un binaire à faire confiance),
/// les quatre familles de fichiers que joue Android sont analysées ici :
///
///   · MP3      → ID3v2 (2.2/2.3/2.4) puis ID3v1, durée par en-tête Xing/VBRI
///                ou, à défaut, par débit constant ;
///   · FLAC     → STREAMINFO (durée exacte), VORBIS_COMMENT, PICTURE ;
///   · Ogg/Opus → en-tête de commentaires, durée par le dernier granule ;
///   · MP4/M4A  → atomes `moov/mvhd` (durée) et `moov/udta/meta/ilst` (tags) ;
///   · WAV      → `fmt `/`data` pour la durée, `LIST/INFO` pour les tags.
///
/// Rien n'est jamais exigé : un fichier sans étiquette lisible repart avec des
/// champs nuls, et le scan retombe alors sur les noms de dossier et de fichier.
/// Une erreur de lecture ne fait pas échouer le scan — voir [readAudioTags].

/// Source d'octets à accès direct. Le fichier n'est jamais chargé en entier :
/// une pochette de 3 Mo au milieu d'une bibliothèque de 5000 titres tiendrait
/// difficilement en mémoire.
abstract class ByteSource {
  /// Taille totale, en octets.
  int get length;

  /// Lit au plus [count] octets à partir de [offset]. Peut renvoyer moins
  /// (fin de fichier) — jamais `null`.
  Future<Uint8List> read(int offset, int count);

  Future<void> close();
}

class FileByteSource implements ByteSource {
  FileByteSource._(this._file, this.length);

  static Future<FileByteSource> open(File file) async {
    final length = await file.length();
    return FileByteSource._(await file.open(), length);
  }

  final RandomAccessFile _file;

  @override
  final int length;

  @override
  Future<Uint8List> read(int offset, int count) async {
    if (offset >= length || count <= 0) return Uint8List(0);
    final want = count.clamp(0, length - offset);
    await _file.setPosition(offset);
    return _file.read(want);
  }

  @override
  Future<void> close() => _file.close();
}

/// Source en mémoire — utilisée par les tests, qui fabriquent des fichiers
/// minimaux octet par octet.
class MemoryByteSource implements ByteSource {
  MemoryByteSource(this.bytes);

  final Uint8List bytes;

  @override
  int get length => bytes.length;

  @override
  Future<Uint8List> read(int offset, int count) async {
    if (offset >= bytes.length || count <= 0) return Uint8List(0);
    final end = (offset + count).clamp(0, bytes.length);
    return Uint8List.sublistView(bytes, offset, end);
  }

  @override
  Future<void> close() async {}
}

/// Une pochette trouvée dans un fichier.
class EmbeddedPicture {
  const EmbeddedPicture(this.bytes, this.mime);

  final Uint8List bytes;
  final String mime;

  /// Extension de fichier à donner à l'image extraite.
  String get extension => switch (mime.toLowerCase()) {
        'image/png' => 'png',
        'image/webp' => 'webp',
        _ => 'jpg',
      };
}

/// Ce qu'un fichier audio a su dire de lui-même. Tout est optionnel.
class AudioTags {
  const AudioTags({
    this.title,
    this.artist,
    this.albumArtist,
    this.album,
    this.genre,
    this.trackNumber,
    this.discNumber,
    this.year,
    this.duration,
    this.picture,
  });

  final String? title;
  final String? artist;
  final String? albumArtist;
  final String? album;
  final String? genre;
  final int? trackNumber;
  final int? discNumber;
  final int? year;

  /// Durée, quand elle a pu être calculée sans décoder l'audio.
  final Duration? duration;

  final EmbeddedPicture? picture;

  AudioTags merge(AudioTags other) => AudioTags(
        title: title ?? other.title,
        artist: artist ?? other.artist,
        albumArtist: albumArtist ?? other.albumArtist,
        album: album ?? other.album,
        genre: genre ?? other.genre,
        trackNumber: trackNumber ?? other.trackNumber,
        discNumber: discNumber ?? other.discNumber,
        year: year ?? other.year,
        duration: duration ?? other.duration,
        picture: picture ?? other.picture,
      );
}

/// Les extensions que le lecteur d'Android sait jouer et que l'on range donc
/// dans une bibliothèque locale. Le WMA n'y est pas : ExoPlayer ne le décode
/// pas, l'afficher ne donnerait que des pistes muettes.
const kLocalAudioExtensions = {
  'mp3',
  'flac',
  'm4a',
  'm4b',
  'mp4',
  'aac',
  'ogg',
  'oga',
  'opus',
  'wav',
};

/// Lit les étiquettes de [source], en choisissant l'analyseur d'après
/// [extension] (sans point, en minuscules) puis d'après la signature du
/// fichier. Ne lève jamais : un fichier illisible ou abîmé repart vide.
Future<AudioTags> readAudioTags(
  ByteSource source, {
  required String extension,
  bool withPicture = true,
}) async {
  try {
    final magic = await source.read(0, 12);
    // La signature l'emporte sur l'extension : un « .m4a » qui commence par
    // « ID3 » est un MP3 mal nommé, et bien des « .mp3 » renferment du FLAC.
    if (_startsWith(magic, 'fLaC')) {
      return _readFlac(source, withPicture: withPicture);
    }
    if (_startsWith(magic, 'OggS')) {
      return _readOgg(source, withPicture: withPicture);
    }
    if (_startsWith(magic, 'RIFF')) return _readRiff(source);
    if (magic.length >= 8 && _startsWith(magic, 'ftyp', from: 4)) {
      return _readMp4(source, withPicture: withPicture);
    }
    return switch (extension) {
      'flac' => _readFlac(source, withPicture: withPicture),
      'ogg' || 'oga' || 'opus' => _readOgg(source, withPicture: withPicture),
      'wav' => _readRiff(source),
      'm4a' || 'm4b' || 'mp4' || 'aac' =>
        _readMp4(source, withPicture: withPicture),
      _ => _readMp3(source, withPicture: withPicture),
    };
  } catch (_) {
    // Une étiquette abîmée ne doit pas interrompre le rangement d'une
    // bibliothèque entière : le titre repart sur son nom de fichier.
    return const AudioTags();
  }
}

bool _startsWith(Uint8List bytes, String ascii, {int from = 0}) {
  if (bytes.length < from + ascii.length) return false;
  for (var i = 0; i < ascii.length; i++) {
    if (bytes[from + i] != ascii.codeUnitAt(i)) return false;
  }
  return true;
}

int _be32(Uint8List b, int o) =>
    (b[o] << 24) | (b[o + 1] << 16) | (b[o + 2] << 8) | b[o + 3];

int _be24(Uint8List b, int o) => (b[o] << 16) | (b[o + 1] << 8) | b[o + 2];

int _be16(Uint8List b, int o) => (b[o] << 8) | b[o + 1];

int _le16(Uint8List b, int o) => b[o] | (b[o + 1] << 8);

int _le32(Uint8List b, int o) =>
    b[o] | (b[o + 1] << 8) | (b[o + 2] << 16) | (b[o + 3] << 24);

/// Entier « syncsafe » d'ID3v2 : sept bits utiles par octet, pour qu'aucune
/// taille ne puisse ressembler à une synchro audio.
int _syncsafe32(Uint8List b, int o) =>
    ((b[o] & 0x7f) << 21) | ((b[o + 1] & 0x7f) << 14) |
    ((b[o + 2] & 0x7f) << 7) | (b[o + 3] & 0x7f);

/// « 3/12 » → 3. Un numéro de piste s'écrit aussi bien seul qu'avec le total.
int? parseTrackNumber(String? raw) {
  if (raw == null) return null;
  final slash = raw.indexOf('/');
  final head = (slash >= 0 ? raw.substring(0, slash) : raw).trim();
  final n = int.tryParse(head);
  return (n != null && n > 0) ? n : null;
}

/// « 1987-03-02 », « 1987 », « 03/1987 » → 1987. Les quatre chiffres d'une
/// année plausible, où qu'ils soient dans la chaîne.
int? parseYear(String? raw) {
  if (raw == null) return null;
  final m = RegExp(r'(1[0-9]{3}|20[0-9]{2})').firstMatch(raw);
  if (m == null) return null;
  return int.tryParse(m.group(1)!);
}

String? _clean(String? s) {
  if (s == null) return null;
  // Les étiquettes se terminent souvent par des octets nuls de bourrage.
  final t = s.replaceAll('\u0000', '').trim();
  return t.isEmpty ? null : t;
}

// ══════════════════════════════════ MP3 / ID3 ══════════════════════════════

Future<AudioTags> _readMp3(ByteSource source, {bool withPicture = true}) async {
  final header = await source.read(0, 10);
  var audioStart = 0;
  var tags = const AudioTags();
  if (_startsWith(header, 'ID3') && header.length == 10) {
    final size = _syncsafe32(header, 6);
    audioStart = 10 + size;
    final body = await source.read(10, size);
    tags = _parseId3v2(body, header[3], header[5], withPicture: withPicture);
  }
  // ID3v1 en fin de fichier : elle ne sert qu'à combler ce que l'ID3v2 n'a
  // pas dit (beaucoup de fichiers portent les deux).
  if (tags.title == null || tags.artist == null || tags.album == null) {
    final v1 = await _parseId3v1(source);
    if (v1 != null) tags = tags.merge(v1);
  }
  final duration = await _mp3Duration(source, audioStart);
  return duration == null ? tags : tags.merge(AudioTags(duration: duration));
}

/// Corps d'une étiquette ID3v2 (l'en-tête de 10 octets déjà retiré).
AudioTags _parseId3v2(
  Uint8List body,
  int major,
  int flags, {
  bool withPicture = true,
}) {
  // Désynchronisation globale (rare, ID3v2.3) : les 0xFF 0x00 insérés pour
  // qu'aucune étiquette ne ressemble à de l'audio sont retirés avant tout.
  var data = (flags & 0x80) != 0 ? _deunsynchronise(body) : body;

  var pos = 0;
  // En-tête étendu : sa taille se compte différemment d'une version à l'autre.
  if ((flags & 0x40) != 0 && data.length >= 4) {
    pos += major >= 4 ? _syncsafe32(data, 0) : _be32(data, 0) + 4;
  }

  final idLength = major <= 2 ? 3 : 4;
  final sizeLength = major <= 2 ? 3 : 4;
  final frameHeader = major <= 2 ? 6 : 10;

  String? title, artist, albumArtist, album, genre, track, disc, year;
  int? lengthMs;
  EmbeddedPicture? picture;

  while (pos + frameHeader <= data.length) {
    final id = String.fromCharCodes(data, pos, pos + idLength);
    // Bourrage de fin d'étiquette : des octets nuls jusqu'au début de l'audio.
    if (id.codeUnitAt(0) == 0) break;
    final size = switch (sizeLength) {
      3 => _be24(data, pos + idLength),
      // ID3v2.4 annonce ses tailles en syncsafe… sauf les encodeurs qui s'en
      // dispensent. Une taille syncsafe qui déborde de l'étiquette alors que
      // la lecture brute, elle, tient : c'est un tag mal formé, on le suit.
      _ => _frameSize(data, pos, major, frameHeader),
    };
    if (size <= 0) break;
    var start = pos + frameHeader;
    var end = start + size;
    if (end > data.length) break;
    var frame = Uint8List.sublistView(data, start, end);
    if (major >= 4) {
      final frameFlags = data[pos + 9];
      // Désynchronisation par trame (ID3v2.4).
      if ((frameFlags & 0x02) != 0) frame = _deunsynchronise(frame);
      // Indicateur de longueur de données : quatre octets syncsafe en tête.
      if ((frameFlags & 0x01) != 0 && frame.length > 4) {
        frame = Uint8List.sublistView(frame, 4);
      }
    }
    pos = end;

    switch (id) {
      case 'TIT2':
      case 'TT2':
        title ??= _id3Text(frame);
      case 'TPE1':
      case 'TP1':
        artist ??= _id3Text(frame);
      case 'TPE2':
      case 'TP2':
        albumArtist ??= _id3Text(frame);
      case 'TALB':
      case 'TAL':
        album ??= _id3Text(frame);
      case 'TCON':
      case 'TCO':
        genre ??= _id3Genre(_id3Text(frame));
      case 'TRCK':
      case 'TRK':
        track ??= _id3Text(frame);
      case 'TPOS':
      case 'TPA':
        disc ??= _id3Text(frame);
      case 'TDRC':
      case 'TYER':
      case 'TYE':
      case 'TDRL':
        year ??= _id3Text(frame);
      case 'TLEN':
        lengthMs ??= int.tryParse(_clean(_id3Text(frame)) ?? '');
      case 'APIC':
      case 'PIC':
        if (withPicture) picture ??= _id3Picture(frame, major);
    }
  }

  return AudioTags(
    title: _clean(title),
    artist: _clean(artist),
    albumArtist: _clean(albumArtist),
    album: _clean(album),
    genre: _clean(genre),
    trackNumber: parseTrackNumber(track),
    discNumber: parseTrackNumber(disc),
    year: parseYear(year),
    duration: (lengthMs != null && lengthMs > 0)
        ? Duration(milliseconds: lengthMs)
        : null,
    picture: picture,
  );
}

/// Taille d'une trame ID3v2.3/2.4. La 2.4 la veut syncsafe, mais des encodeurs
/// l'écrivent en entier brut : quand la lecture syncsafe mène hors de
/// l'étiquette et que la brute y reste, c'est la brute qui a raison.
int _frameSize(Uint8List data, int pos, int major, int frameHeader) {
  final raw = _be32(data, pos + 4);
  if (major < 4) return raw;
  final safe = _syncsafe32(data, pos + 4);
  if (safe == raw) return safe;
  final limit = data.length - pos - frameHeader;
  if (safe <= limit) return safe;
  return raw <= limit ? raw : safe;
}

Uint8List _deunsynchronise(Uint8List input) {
  final out = Uint8List(input.length);
  var n = 0;
  for (var i = 0; i < input.length; i++) {
    out[n++] = input[i];
    if (input[i] == 0xFF && i + 1 < input.length && input[i + 1] == 0x00) i++;
  }
  return Uint8List.sublistView(out, 0, n);
}

/// Contenu d'une trame texte : un octet d'encodage, puis la chaîne.
String? _id3Text(Uint8List frame) {
  if (frame.isEmpty) return null;
  return _decodeId3(frame[0], Uint8List.sublistView(frame, 1));
}

String? _decodeId3(int encoding, Uint8List bytes) {
  try {
    return switch (encoding) {
      0 => latin1.decode(bytes, allowInvalid: true),
      1 => _decodeUtf16(bytes),
      2 => _decodeUtf16(bytes, bigEndian: true),
      _ => utf8.decode(bytes, allowMalformed: true),
    };
  } catch (_) {
    return null;
  }
}

String _decodeUtf16(Uint8List bytes, {bool bigEndian = false}) {
  var data = bytes;
  var be = bigEndian;
  if (data.length >= 2) {
    if (data[0] == 0xFF && data[1] == 0xFE) {
      be = false;
      data = Uint8List.sublistView(data, 2);
    } else if (data[0] == 0xFE && data[1] == 0xFF) {
      be = true;
      data = Uint8List.sublistView(data, 2);
    }
  }
  final units = <int>[];
  for (var i = 0; i + 1 < data.length; i += 2) {
    units.add(be ? _be16(data, i) : _le16(data, i));
  }
  return String.fromCharCodes(units);
}

/// « (17) » ou « (17)Rock » : les genres numérotés d'ID3v1, que certains
/// encodeurs recopient tels quels dans TCON.
String? _id3Genre(String? raw) {
  final text = _clean(raw);
  if (text == null) return null;
  final m = RegExp(r'^\((\d+)\)(.*)$').firstMatch(text);
  if (m == null) return text;
  final rest = _clean(m.group(2));
  if (rest != null) return rest;
  final n = int.tryParse(m.group(1)!);
  return (n != null && n < _id3v1Genres.length) ? _id3v1Genres[n] : null;
}

EmbeddedPicture? _id3Picture(Uint8List frame, int major) {
  if (frame.length < 4) return null;
  final encoding = frame[0];
  var pos = 1;
  String mime;
  if (major <= 2) {
    // ID3v2.2 : trois lettres de format d'image (« JPG », « PNG »).
    final format = String.fromCharCodes(frame, 1, 4).toUpperCase();
    mime = format == 'PNG' ? 'image/png' : 'image/jpeg';
    pos = 4;
  } else {
    final end = _indexOfZero(frame, pos);
    if (end < 0) return null;
    mime = latin1.decode(
      Uint8List.sublistView(frame, pos, end),
      allowInvalid: true,
    );
    if (!mime.contains('/')) {
      mime = mime.toUpperCase() == 'PNG' ? 'image/png' : 'image/jpeg';
    }
    pos = end + 1;
  }
  if (pos >= frame.length) return null;
  pos++; // type d'image (pochette avant, dos, logo…)
  // Description, terminée par un ou deux octets nuls selon l'encodage.
  final wide = encoding == 1 || encoding == 2;
  pos = wide ? _indexOfDoubleZero(frame, pos) : _indexOfZero(frame, pos);
  if (pos < 0) return null;
  pos += wide ? 2 : 1;
  if (pos >= frame.length) return null;
  return EmbeddedPicture(Uint8List.sublistView(frame, pos), mime);
}

int _indexOfZero(Uint8List b, int from) {
  for (var i = from; i < b.length; i++) {
    if (b[i] == 0) return i;
  }
  return -1;
}

int _indexOfDoubleZero(Uint8List b, int from) {
  for (var i = from; i + 1 < b.length; i += 2) {
    if (b[i] == 0 && b[i + 1] == 0) return i;
  }
  return -1;
}

Future<AudioTags?> _parseId3v1(ByteSource source) async {
  if (source.length < 128) return null;
  final tag = await source.read(source.length - 128, 128);
  if (!_startsWith(tag, 'TAG') || tag.length < 128) return null;
  String field(int start, int end) => latin1
      .decode(Uint8List.sublistView(tag, start, end), allowInvalid: true);
  final genreIndex = tag[127];
  // ID3v1.1 : le dernier octet du commentaire porte le numéro de piste.
  final track = tag[125] == 0 && tag[126] != 0 ? tag[126] : null;
  return AudioTags(
    title: _clean(field(3, 33)),
    artist: _clean(field(33, 63)),
    album: _clean(field(63, 93)),
    year: parseYear(_clean(field(93, 97))),
    trackNumber: track,
    genre: genreIndex < _id3v1Genres.length ? _id3v1Genres[genreIndex] : null,
  );
}

// ─────────────────────────── Durée d'un MP3 ────────────────────────────────

/// Durée d'un MP3 : d'abord l'en-tête Xing/VBRI (nombre exact de trames), sinon
/// le débit de la première trame, supposé constant. Rien de tout cela ne
/// demande de décoder l'audio.
Future<Duration?> _mp3Duration(ByteSource source, int audioStart) async {
  // 8 Ko suffisent à trouver la première trame, même derrière quelques
  // octets de bourrage.
  final window = await source.read(audioStart, 8192);
  if (window.length < 4) return null;
  for (var i = 0; i + 4 <= window.length; i++) {
    if (window[i] != 0xFF || (window[i + 1] & 0xE0) != 0xE0) continue;
    final frame = _Mp3Frame.parse(window, i);
    if (frame == null) continue;
    final frames = _xingFrameCount(window, i, frame);
    if (frames != null && frames > 0) {
      final seconds = frames * frame.samplesPerFrame / frame.sampleRate;
      return Duration(milliseconds: (seconds * 1000).round());
    }
    // Débit constant : la taille de l'audio divisée par le débit. On retire
    // l'éventuelle étiquette ID3v1 de fin, qui n'est pas de l'audio.
    final tail = await source.read(source.length - 128, 3);
    final hasV1 = _startsWith(tail, 'TAG');
    final audioBytes = source.length - audioStart - i - (hasV1 ? 128 : 0);
    if (audioBytes <= 0 || frame.bitrate <= 0) return null;
    final seconds = audioBytes * 8 / frame.bitrate;
    return Duration(milliseconds: (seconds * 1000).round());
  }
  return null;
}

class _Mp3Frame {
  const _Mp3Frame({
    required this.bitrate,
    required this.sampleRate,
    required this.samplesPerFrame,
    required this.mpegVersion,
    required this.channels,
  });

  final int bitrate; // bits/s
  final int sampleRate;
  final int samplesPerFrame;
  final int mpegVersion; // 1, 2 ou 25 (MPEG 2.5)
  final int channels;

  static const _rates = {
    // [version][layer][index] en kbit/s. Layer I, II, III.
    1: [
      [0, 32, 64, 96, 128, 160, 192, 224, 256, 288, 320, 352, 384, 416, 448],
      [0, 32, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320, 384],
      [0, 32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320],
    ],
    2: [
      [0, 32, 48, 56, 64, 80, 96, 112, 128, 144, 160, 176, 192, 224, 256],
      [0, 8, 16, 24, 32, 40, 48, 56, 64, 80, 96, 112, 128, 144, 160],
      [0, 8, 16, 24, 32, 40, 48, 56, 64, 80, 96, 112, 128, 144, 160],
    ],
  };

  static const _sampleRates = {
    1: [44100, 48000, 32000],
    2: [22050, 24000, 16000],
    25: [11025, 12000, 8000],
  };

  static _Mp3Frame? parse(Uint8List b, int o) {
    if (o + 4 > b.length) return null;
    final versionBits = (b[o + 1] >> 3) & 0x03;
    final layerBits = (b[o + 1] >> 1) & 0x03;
    if (layerBits == 0) return null; // couche réservée
    final version = switch (versionBits) {
      3 => 1,
      2 => 2,
      0 => 25,
      _ => 0, // 1 = réservé
    };
    if (version == 0) return null;
    final layer = 4 - layerBits; // 1, 2 ou 3
    final rateIndex = (b[o + 2] >> 4) & 0x0F;
    final srIndex = (b[o + 2] >> 2) & 0x03;
    if (rateIndex == 0 || rateIndex == 0x0F || srIndex == 3) return null;
    final table = _rates[version == 1 ? 1 : 2]![layer - 1];
    final bitrate = table[rateIndex] * 1000;
    final sampleRate = _sampleRates[version]![srIndex];
    final samples = layer == 1 ? 384 : (layer == 3 && version != 1 ? 576 : 1152);
    final channelBits = (b[o + 3] >> 6) & 0x03;
    return _Mp3Frame(
      bitrate: bitrate,
      sampleRate: sampleRate,
      samplesPerFrame: samples,
      mpegVersion: version,
      channels: channelBits == 3 ? 1 : 2,
    );
  }
}

/// Nombre de trames annoncé par l'en-tête Xing, Info ou VBRI de la première
/// trame — le seul moyen de dater un MP3 à débit variable sans le décoder.
int? _xingFrameCount(Uint8List b, int frameStart, _Mp3Frame frame) {
  final sideInfo = frame.mpegVersion == 1
      ? (frame.channels == 1 ? 17 : 32)
      : (frame.channels == 1 ? 9 : 17);
  final xing = frameStart + 4 + sideInfo;
  if (xing + 12 <= b.length &&
      (_startsWith(b, 'Xing', from: xing) ||
          _startsWith(b, 'Info', from: xing))) {
    final flags = _be32(b, xing + 4);
    if ((flags & 0x01) != 0) return _be32(b, xing + 8);
    return null;
  }
  // VBRI (encodeur Fraunhofer) : toujours 32 octets après l'en-tête.
  final vbri = frameStart + 4 + 32;
  if (vbri + 26 <= b.length && _startsWith(b, 'VBRI', from: vbri)) {
    return _be32(b, vbri + 14);
  }
  return null;
}

// ═════════════════════════════════════ FLAC ════════════════════════════════

Future<AudioTags> _readFlac(
  ByteSource source, {
  bool withPicture = true,
}) async {
  var tags = const AudioTags();
  var pos = 4; // « fLaC »
  var last = false;
  // Un FLAC peut aussi porter une étiquette ID3v2 en tête (ajoutée par un
  // lecteur) : la signature est alors décalée.
  final head = await source.read(0, 10);
  if (_startsWith(head, 'ID3') && head.length == 10) {
    final id3 = _syncsafe32(head, 6);
    tags = _parseId3v2(
      await source.read(10, id3),
      head[3],
      head[5],
      withPicture: withPicture,
    );
    pos = 10 + id3 + 4;
  }
  while (!last && pos + 4 <= source.length) {
    final header = await source.read(pos, 4);
    if (header.length < 4) break;
    last = (header[0] & 0x80) != 0;
    final type = header[0] & 0x7f;
    final size = _be24(header, 1);
    final body = pos + 4;
    pos = body + size;
    switch (type) {
      case 0: // STREAMINFO : la durée exacte, en échantillons.
        final info = await source.read(body, size < 18 ? size : 18);
        if (info.length >= 18) {
          final rate = (info[10] << 12) | (info[11] << 4) | (info[12] >> 4);
          // 36 bits d'échantillons : 4 bits de poids fort dans l'octet 13.
          final samples = ((info[13] & 0x0F) * 4294967296) +
              (_be32(info, 14) & 0xFFFFFFFF);
          if (rate > 0 && samples > 0) {
            tags = tags.merge(AudioTags(
              duration: Duration(milliseconds: (samples * 1000 / rate).round()),
            ));
          }
        }
      case 4: // VORBIS_COMMENT
        tags = tags.merge(
          _parseVorbisComment(
            await source.read(body, size),
            withPicture: withPicture,
          ),
        );
      case 6: // PICTURE
        if (withPicture && tags.picture == null) {
          final picture = _parseFlacPicture(await source.read(body, size));
          if (picture != null) tags = tags.merge(AudioTags(picture: picture));
        }
    }
    if (size <= 0) break;
  }
  return tags;
}

/// Bloc PICTURE de FLAC (aussi utilisé, en base64, par
/// METADATA_BLOCK_PICTURE dans les commentaires Vorbis).
EmbeddedPicture? _parseFlacPicture(Uint8List b) {
  if (b.length < 32) return null;
  var pos = 4; // type d'image
  final mimeLength = _be32(b, pos);
  pos += 4;
  if (pos + mimeLength > b.length) return null;
  final mime = latin1.decode(
    Uint8List.sublistView(b, pos, pos + mimeLength),
    allowInvalid: true,
  );
  pos += mimeLength;
  if (pos + 4 > b.length) return null;
  final descLength = _be32(b, pos);
  pos += 4 + descLength;
  // largeur, hauteur, profondeur, couleurs indexées, taille des données
  pos += 16;
  if (pos + 4 > b.length) return null;
  final dataLength = _be32(b, pos);
  pos += 4;
  if (pos >= b.length) return null;
  final end = (pos + dataLength).clamp(pos, b.length);
  return EmbeddedPicture(Uint8List.sublistView(b, pos, end), mime);
}

/// Commentaires Vorbis : un vendeur, puis des « CLÉ=valeur » en UTF-8.
AudioTags _parseVorbisComment(Uint8List b, {bool withPicture = true}) {
  if (b.length < 8) return const AudioTags();
  var pos = 0;
  final vendorLength = _le32(b, pos);
  pos += 4 + vendorLength;
  if (pos + 4 > b.length) return const AudioTags();
  final count = _le32(b, pos);
  pos += 4;
  final fields = <String, String>{};
  EmbeddedPicture? picture;
  for (var i = 0; i < count && pos + 4 <= b.length; i++) {
    final length = _le32(b, pos);
    pos += 4;
    if (length < 0 || pos + length > b.length) break;
    final entry = utf8.decode(
      Uint8List.sublistView(b, pos, pos + length),
      allowMalformed: true,
    );
    pos += length;
    final eq = entry.indexOf('=');
    if (eq <= 0) continue;
    final key = entry.substring(0, eq).toUpperCase();
    final value = entry.substring(eq + 1);
    if (key == 'METADATA_BLOCK_PICTURE') {
      if (withPicture && picture == null) {
        try {
          picture = _parseFlacPicture(base64Decode(value));
        } catch (_) {
          // Pochette illisible : le titre s'affichera sans.
        }
      }
      continue;
    }
    fields.putIfAbsent(key, () => value);
  }
  return AudioTags(
    title: _clean(fields['TITLE']),
    artist: _clean(fields['ARTIST']),
    albumArtist: _clean(fields['ALBUMARTIST'] ?? fields['ALBUM ARTIST']),
    album: _clean(fields['ALBUM']),
    genre: _clean(fields['GENRE']),
    trackNumber: parseTrackNumber(fields['TRACKNUMBER']),
    discNumber: parseTrackNumber(fields['DISCNUMBER']),
    year: parseYear(fields['DATE'] ?? fields['YEAR']),
    picture: picture,
  );
}

// ═════════════════════════════════ Ogg / Opus ══════════════════════════════

Future<AudioTags> _readOgg(ByteSource source, {bool withPicture = true}) async {
  // Les en-têtes tiennent dans les premières pages ; une pochette embarquée
  // peut en occuper plusieurs, d'où la fenêtre généreuse.
  final head = await source.read(0, 512 * 1024);
  var tags = const AudioTags();
  var rate = 0;
  var pageStart = 0;
  final packet = BytesBuilder(copy: false);
  while (pageStart + 27 <= head.length &&
      _startsWith(head, 'OggS', from: pageStart)) {
    final segments = head[pageStart + 26];
    if (pageStart + 27 + segments > head.length) break;
    var payload = 0;
    for (var i = 0; i < segments; i++) {
      payload += head[pageStart + 27 + i];
    }
    final start = pageStart + 27 + segments;
    final end = start + payload;
    if (end > head.length) break;
    packet.add(Uint8List.sublistView(head, start, end));
    final lastLacing = segments > 0 ? head[start - 1] : 0;
    pageStart = end;
    // Un paquet qui remplit son dernier segment (255 octets) continue sur la
    // page suivante : une pochette embarquée en occupe plusieurs.
    if (lastLacing == 255) continue;
    final data = packet.takeBytes();
    if (_startsWith(data, 'OpusHead')) {
      // Le débit interne d'Opus est toujours de 48 kHz côté granule.
      rate = 48000;
    } else if (data.length > 7 && _startsWith(data, 'vorbis', from: 1)) {
      if (data[0] == 1 && data.length >= 16) {
        rate = _le32(data, 12);
      } else if (data[0] == 3) {
        tags = tags.merge(
          _parseVorbisComment(
            Uint8List.sublistView(data, 7),
            withPicture: withPicture,
          ),
        );
        break;
      }
    } else if (_startsWith(data, 'OpusTags')) {
      tags = tags.merge(
        _parseVorbisComment(
          Uint8List.sublistView(data, 8),
          withPicture: withPicture,
        ),
      );
      break;
    }
  }
  final duration = rate > 0 ? await _oggDuration(source, rate) : null;
  return duration == null ? tags : tags.merge(AudioTags(duration: duration));
}

/// Durée d'un flux Ogg : la position de granule de sa dernière page, c'est-à-
/// dire le nombre d'échantillons écoulés à la fin du fichier.
Future<Duration?> _oggDuration(ByteSource source, int rate) async {
  const window = 65536;
  final start = source.length > window ? source.length - window : 0;
  final tail = await source.read(start, window);
  for (var i = tail.length - 27; i >= 0; i--) {
    if (!_startsWith(tail, 'OggS', from: i)) continue;
    // Granule sur 64 bits, petit-boutiste. Les 32 bits de poids fort suffisent
    // à écarter le -1 des pages sans granule.
    final low = _le32(tail, i + 6) & 0xFFFFFFFF;
    final high = _le32(tail, i + 10) & 0xFFFFFFFF;
    if (low == 0xFFFFFFFF && high == 0xFFFFFFFF) continue;
    final granule = high * 4294967296 + low;
    if (granule <= 0) continue;
    return Duration(milliseconds: (granule * 1000 / rate).round());
  }
  return null;
}

// ══════════════════════════════════ MP4 / M4A ══════════════════════════════

Future<AudioTags> _readMp4(ByteSource source, {bool withPicture = true}) async {
  final moov = await _findAtom(source, 'moov', 0, source.length);
  if (moov == null) return const AudioTags();
  var tags = const AudioTags();

  final mvhd = await _findAtom(source, 'mvhd', moov.start, moov.end);
  if (mvhd != null) {
    final b = await source.read(mvhd.start, 32);
    if (b.length >= 24) {
      final version = b[0];
      // v0 : timescale et durée sur 32 bits ; v1 : sur 64 bits.
      final timescale = version == 1 ? _be32(b, 20) : _be32(b, 12);
      final duration = version == 1
          ? (_be32(b, 24) * 4294967296 + _be32(b, 28))
          : _be32(b, 16);
      if (timescale > 0 && duration > 0) {
        tags = tags.merge(AudioTags(
          duration: Duration(milliseconds: (duration * 1000 / timescale)
              .round()),
        ));
      }
    }
  }

  final udta = await _findAtom(source, 'udta', moov.start, moov.end);
  if (udta == null) return tags;
  final meta = await _findAtom(source, 'meta', udta.start, udta.end);
  if (meta == null) return tags;
  // `meta` porte quatre octets de version/drapeaux avant ses enfants.
  final ilst = await _findAtom(source, 'ilst', meta.start + 4, meta.end);
  if (ilst == null) return tags;
  return tags.merge(
    await _parseIlst(source, ilst.start, ilst.end, withPicture: withPicture),
  );
}

class _Atom {
  const _Atom(this.start, this.end);

  /// Premier octet du contenu (l'en-tête est déjà passé).
  final int start;

  /// Premier octet après le contenu.
  final int end;
}

/// Cherche l'atome [name] parmi les enfants directs de l'intervalle donné.
Future<_Atom?> _findAtom(
  ByteSource source,
  String name,
  int from,
  int to,
) async {
  var pos = from;
  while (pos + 8 <= to) {
    final header = await source.read(pos, 16);
    if (header.length < 8) return null;
    var size = _be32(header, 0);
    var headerSize = 8;
    if (size == 1) {
      // Taille étendue sur 64 bits.
      if (header.length < 16) return null;
      size = _be32(header, 8) * 4294967296 + _be32(header, 12);
      headerSize = 16;
    } else if (size == 0) {
      size = to - pos; // « jusqu'à la fin »
    }
    if (size < headerSize) return null;
    final type = String.fromCharCodes(header, 4, 8);
    final end = pos + size > to ? to : pos + size;
    if (type == name) return _Atom(pos + headerSize, end);
    pos += size;
  }
  return null;
}

/// La liste d'étiquettes d'un MP4 : chaque enfant porte son nom (« ©nam »,
/// « trkn », « covr »…) et un atome `data` où gît la valeur.
Future<AudioTags> _parseIlst(
  ByteSource source,
  int from,
  int to, {
  bool withPicture = true,
}) async {
  String? title, artist, albumArtist, album, genre, year;
  int? track, disc;
  EmbeddedPicture? picture;

  var pos = from;
  while (pos + 8 <= to) {
    final header = await source.read(pos, 8);
    if (header.length < 8) break;
    final size = _be32(header, 0);
    if (size < 8) break;
    final name = String.fromCharCodes(header, 4, 8);
    final end = pos + size > to ? to : pos + size;
    final data = await _findAtom(source, 'data', pos + 8, end);
    if (data != null && data.end > data.start + 8) {
      // `data` : 4 octets de type, 4 de « locale », puis la valeur.
      final type = _be32(await source.read(data.start, 4), 0) & 0xFFFFFF;
      final value = await source.read(data.start + 8, data.end - data.start - 8);
      String text() => utf8.decode(value, allowMalformed: true);
      switch (name) {
        case '©nam':
          title ??= text();
        case '©ART':
          artist ??= text();
        case 'aART':
          albumArtist ??= text();
        case '©alb':
          album ??= text();
        case '©gen':
          genre ??= text();
        case 'gnre':
          // Genre numéroté, comme ID3v1 (l'index commence à 1).
          if (value.length >= 2) {
            final n = _be16(value, 0) - 1;
            if (n >= 0 && n < _id3v1Genres.length) genre ??= _id3v1Genres[n];
          }
        case '©day':
          year ??= text();
        case 'trkn':
          if (value.length >= 4) track ??= _be16(value, 2);
        case 'disk':
          if (value.length >= 4) disc ??= _be16(value, 2);
        case 'covr':
          if (withPicture && picture == null && value.isNotEmpty) {
            picture = EmbeddedPicture(
              value,
              type == 14 ? 'image/png' : 'image/jpeg',
            );
          }
      }
    }
    pos += size;
  }

  return AudioTags(
    title: _clean(title),
    artist: _clean(artist),
    albumArtist: _clean(albumArtist),
    album: _clean(album),
    genre: _clean(genre),
    trackNumber: (track != null && track > 0) ? track : null,
    discNumber: (disc != null && disc > 0) ? disc : null,
    year: parseYear(year),
    picture: picture,
  );
}

// ══════════════════════════════════ WAV / RIFF ═════════════════════════════

Future<AudioTags> _readRiff(ByteSource source) async {
  var pos = 12; // « RIFF » + taille + « WAVE »
  var byteRate = 0;
  var dataSize = 0;
  String? title, artist, album, genre, year, track;
  while (pos + 8 <= source.length) {
    final header = await source.read(pos, 8);
    if (header.length < 8) break;
    final id = String.fromCharCodes(header, 0, 4);
    final size = _le32(header, 4);
    if (size < 0) break;
    final body = pos + 8;
    switch (id) {
      case 'fmt ':
        final fmt = await source.read(body, size < 16 ? size : 16);
        if (fmt.length >= 16) byteRate = _le32(fmt, 8);
      case 'data':
        dataSize = size;
      case 'LIST':
        final list = await source.read(body, size.clamp(0, 64 * 1024));
        if (_startsWith(list, 'INFO')) {
          final info = _parseRiffInfo(list);
          title ??= info['INAM'];
          artist ??= info['IART'];
          album ??= info['IPRD'];
          genre ??= info['IGNR'];
          year ??= info['ICRD'];
          track ??= info['ITRK'];
        }
    }
    // Les morceaux RIFF sont alignés sur deux octets.
    pos = body + size + (size.isOdd ? 1 : 0);
  }
  return AudioTags(
    title: _clean(title),
    artist: _clean(artist),
    album: _clean(album),
    genre: _clean(genre),
    trackNumber: parseTrackNumber(track),
    year: parseYear(year),
    duration: (byteRate > 0 && dataSize > 0)
        ? Duration(milliseconds: (dataSize * 1000 / byteRate).round())
        : null,
  );
}

Map<String, String> _parseRiffInfo(Uint8List list) {
  final out = <String, String>{};
  var pos = 4;
  while (pos + 8 <= list.length) {
    final id = String.fromCharCodes(list, pos, pos + 4);
    final size = _le32(list, pos + 4);
    final body = pos + 8;
    if (size < 0 || body + size > list.length) break;
    out.putIfAbsent(
      id,
      () => latin1.decode(
        Uint8List.sublistView(list, body, body + size),
        allowInvalid: true,
      ),
    );
    pos = body + size + (size.isOdd ? 1 : 0);
  }
  return out;
}

/// Les genres numérotés d'ID3v1 — encore écrits par bien des encodeurs, aussi
/// bien dans TCON que dans l'atome `gnre` des MP4.
const _id3v1Genres = <String>[
  'Blues', 'Classic Rock', 'Country', 'Dance', 'Disco', 'Funk', 'Grunge',
  'Hip-Hop', 'Jazz', 'Metal', 'New Age', 'Oldies', 'Other', 'Pop', 'R&B',
  'Rap', 'Reggae', 'Rock', 'Techno', 'Industrial', 'Alternative', 'Ska',
  'Death Metal', 'Pranks', 'Soundtrack', 'Euro-Techno', 'Ambient', 'Trip-Hop',
  'Vocal', 'Jazz+Funk', 'Fusion', 'Trance', 'Classical', 'Instrumental',
  'Acid', 'House', 'Game', 'Sound Clip', 'Gospel', 'Noise', 'Alt. Rock',
  'Bass', 'Soul', 'Punk', 'Space', 'Meditative', 'Instrumental Pop',
  'Instrumental Rock', 'Ethnic', 'Gothic', 'Darkwave', 'Techno-Industrial',
  'Electronic', 'Pop-Folk', 'Eurodance', 'Dream', 'Southern Rock', 'Comedy',
  'Cult', 'Gangsta Rap', 'Top 40', 'Christian Rap', 'Pop/Funk', 'Jungle',
  'Native American', 'Cabaret', 'New Wave', 'Psychedelic', 'Rave',
  'Showtunes', 'Trailer', 'Lo-Fi', 'Tribal', 'Acid Punk', 'Acid Jazz',
  'Polka', 'Retro', 'Musical', 'Rock & Roll', 'Hard Rock', 'Folk',
  'Folk/Rock', 'National Folk', 'Swing', 'Fast-Fusion', 'Bebop', 'Latin',
  'Revival', 'Celtic', 'Bluegrass', 'Avantgarde', 'Gothic Rock',
  'Progressive Rock', 'Psychedelic Rock', 'Symphonic Rock', 'Slow Rock',
  'Big Band', 'Chorus', 'Easy Listening', 'Acoustic', 'Humour', 'Speech',
  'Chanson', 'Opera', 'Chamber Music', 'Sonata', 'Symphony', 'Booty Bass',
  'Primus', 'Porn Groove', 'Satire', 'Slow Jam', 'Club', 'Tango', 'Samba',
  'Folklore', 'Ballad', 'Power Ballad', 'Rhythmic Soul', 'Freestyle', 'Duet',
  'Punk Rock', 'Drum Solo', 'A Cappella', 'Euro-House', 'Dance Hall',
];
