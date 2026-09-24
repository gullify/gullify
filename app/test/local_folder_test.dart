// Mode « dossier local » (idée #114) : Gullify sans serveur, sur un dossier du
// téléphone.
//
// Ce qui compte ici : les étiquettes des fichiers sont lues correctement (c'est
// tout ce dont dispose l'app pour ranger la musique — il n'y a pas de serveur
// pour le faire), le dossier se range en artistes et albums, les titres portent
// des identifiants qui ne peuvent pas se confondre avec ceux d'un serveur, et
// la lecture part du fichier plutôt que du réseau.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gullify/audio/audio_handler.dart';
import 'package:gullify/audio/local_mode.dart';
import 'package:gullify/audio/local_tags.dart';
import 'package:gullify/models/song.dart';
import 'package:gullify/screens/local_library_screen.dart';
import 'package:gullify/state/auth.dart';
import 'package:gullify/state/local_library.dart';
import 'package:gullify/state/player.dart';
import 'package:gullify/theme.dart';

// ─────────────────────── Fabrique de fichiers audio ───────────────────────
// Des fichiers minimaux, montés octet par octet : c'est la seule façon de
// vérifier un analyseur d'étiquettes sans embarquer de vrais morceaux dans le
// dépôt.

List<int> _be32(int n) =>
    [(n >> 24) & 0xff, (n >> 16) & 0xff, (n >> 8) & 0xff, n & 0xff];

List<int> _be16(int n) => [(n >> 8) & 0xff, n & 0xff];

List<int> _le32(int n) =>
    [n & 0xff, (n >> 8) & 0xff, (n >> 16) & 0xff, (n >> 24) & 0xff];

List<int> _syncsafe(int n) =>
    [(n >> 21) & 0x7f, (n >> 14) & 0x7f, (n >> 7) & 0x7f, n & 0x7f];

/// Une trame audio MPEG1 couche III, 128 kbit/s, 44,1 kHz, stéréo — et le
/// silence qui suit. 16 000 octets à 128 kbit/s font exactement une seconde.
List<int> _mp3Audio({int bytes = 16000, List<int> afterHeader = const []}) => [
      0xFF, 0xFB, 0x90, 0x00,
      ...afterHeader,
      ...List.filled(bytes - 4 - afterHeader.length, 0),
    ];

/// L'en-tête Xing d'un fichier à débit variable : 32 octets d'information
/// latérale (MPEG1 stéréo), puis le nombre exact de trames.
List<int> _xing(int frames) => [
      ...List.filled(32, 0),
      ...ascii.encode('Xing'),
      ..._be32(0x01), // seul le nombre de trames est présent
      ..._be32(frames),
    ];

List<int> _id3TextFrame(String id, String text, {int encoding = 0}) {
  final payload = <int>[
    encoding,
    ...switch (encoding) {
      0 => latin1.encode(text),
      1 => [0xFF, 0xFE, ...text.codeUnits.expand((c) => [c & 0xff, c >> 8])],
      _ => utf8.encode(text),
    },
  ];
  return [...ascii.encode(id), ..._be32(payload.length), 0, 0, ...payload];
}

List<int> _id3PictureFrame(List<int> image, {String mime = 'image/jpeg'}) {
  final payload = <int>[
    0, // encodage de la description
    ...latin1.encode(mime), 0,
    3, // pochette avant
    ...latin1.encode('couverture'), 0,
    ...image,
  ];
  return [...ascii.encode('APIC'), ..._be32(payload.length), 0, 0, ...payload];
}

/// Un MP3 avec son étiquette ID3v2 et une seconde d'audio.
Uint8List _mp3({
  required List<int> frames,
  int major = 3,
  List<int>? audio,
  List<int>? id3v1,
}) =>
    Uint8List.fromList([
      ...ascii.encode('ID3'), major, 0, 0,
      ..._syncsafe(frames.length),
      ...frames,
      ...(audio ?? _mp3Audio()),
      ...?id3v1,
    ]);

/// Une étiquette ID3v1 de fin de fichier : 128 octets, à taille fixe.
List<int> _id3v1({
  String title = '',
  String artist = '',
  String album = '',
  String year = '',
  int track = 0,
  int genre = 17,
}) {
  List<int> field(String s, int size) {
    final bytes = latin1.encode(s).take(size).toList();
    return [...bytes, ...List.filled(size - bytes.length, 0)];
  }

  return [
    ...ascii.encode('TAG'),
    ...field(title, 30),
    ...field(artist, 30),
    ...field(album, 30),
    ...field(year, 4),
    ...field('', 28), 0, track, // commentaire + numéro de piste (ID3v1.1)
    genre,
  ];
}

List<int> _flacBlock(int type, List<int> body, {bool last = false}) => [
      (last ? 0x80 : 0) | type,
      (body.length >> 16) & 0xff,
      (body.length >> 8) & 0xff,
      body.length & 0xff,
      ...body,
    ];

/// STREAMINFO : 44,1 kHz et [samples] échantillons, le reste à zéro.
List<int> _streamInfo(int samples) => [
      ...List.filled(10, 0),
      // 20 bits de fréquence : 0x0AC44 = 44100.
      0x0A, 0xC4, 0x40,
      (samples >> 32) & 0x0F,
      ..._be32(samples & 0xFFFFFFFF),
      ...List.filled(16, 0), // signature MD5
    ];

List<int> _vorbisComment(List<String> fields) => [
      ..._le32(4), ...ascii.encode('test'),
      ..._le32(fields.length),
      for (final f in fields) ...[
        ..._le32(utf8.encode(f).length),
        ...utf8.encode(f),
      ],
    ];

List<int> _flacPicture(List<int> image, {String mime = 'image/png'}) => [
      ..._be32(3), // pochette avant
      ..._be32(mime.length), ...ascii.encode(mime),
      ..._be32(0), // description vide
      ...List.filled(16, 0), // largeur, hauteur, profondeur, couleurs
      ..._be32(image.length),
      ...image,
    ];

Uint8List _flac({
  required int samples,
  List<String> comments = const [],
  List<int>? picture,
}) =>
    Uint8List.fromList([
      ...ascii.encode('fLaC'),
      ..._flacBlock(0, _streamInfo(samples)),
      ..._flacBlock(4, _vorbisComment(comments), last: picture == null),
      if (picture != null) ..._flacBlock(6, _flacPicture(picture), last: true),
    ]);

// Le « © » des étiquettes MP4 est un octet latin1, pas de l'ASCII.
List<int> _atom(String type, List<int> body) =>
    [..._be32(body.length + 8), ...latin1.encode(type), ...body];

/// Une étiquette de liste MP4 : « ©nam », « trkn »… et son atome `data`.
List<int> _ilstEntry(String name, List<int> value, {int type = 1}) =>
    _atom(name, _atom('data', [..._be32(type), ..._be32(0), ...value]));

Uint8List _mp4({
  required int durationMs,
  List<int> entries = const [],
}) {
  // Échelle de mille : la durée s'écrit alors directement en millisecondes.
  final mvhd = _atom('mvhd', [
    0, 0, 0, 0, // version 0 + drapeaux
    ..._be32(0), ..._be32(0), // création, modification
    ..._be32(1000), ..._be32(durationMs),
    ...List.filled(80, 0),
  ]);
  final ilst = _atom('ilst', entries);
  final meta = _atom('meta', [0, 0, 0, 0, ...ilst]);
  final udta = _atom('udta', meta);
  return Uint8List.fromList([
    ..._atom('ftyp', ascii.encode('M4A isom')),
    ..._atom('moov', [...mvhd, ...udta]),
  ]);
}

Future<AudioTags> _read(Uint8List bytes, String extension) =>
    readAudioTags(MemoryByteSource(bytes), extension: extension);

// ───────────────────────────── Faux et décors ─────────────────────────────

class _FakeActions extends Fake implements PlayerActions {
  final List<({List<Song> songs, int index})> played = [];

  @override
  Future<void> playSongs(List<Song> songs, {int startIndex = 0}) async =>
      played.add((songs: songs, index: startIndex));
}

/// Une session en mode local, sans passer par le coffre du téléphone.
class _LocalAuth extends AuthController {
  _LocalAuth(this.folder);

  final String folder;

  @override
  AuthState build() =>
      AuthState(status: AuthStatus.local, localFolder: folder);
}

/// Une bibliothèque déjà rangée, sans parcours de disque.
class _ReadyLibrary extends LocalLibraryController {
  _ReadyLibrary(this.library);

  final LocalLibrary library;

  @override
  Future<LocalLibrary?> build() async => library;
}

/// Un lecteur en mode « dossier local », sans attendre ni coffre ni dossier.
GullifyAudioHandler _localHandler() {
  final handler = GullifyAudioHandler();
  addTearDown(handler.player.dispose);
  handler.localLibraryWait = Duration.zero;
  return handler;
}

/// Ce que le binder pose sur le lecteur : le dossier rangé en albums et en
/// artistes, exactement comme en marche réelle.
void _bind(GullifyAudioHandler handler, List<Song> songs) {
  // Les albums/artistes se déduisent des titres donnés, sans repasser par le
  // disque : un album par (interprète, album).
  final albums = <String, List<Song>>{};
  for (final s in songs) {
    (albums['${s.artistName ?? ''}\u0000${s.albumName ?? ''}'] ??= []).add(s);
  }
  var albumId = 0;
  final browsable = [
    for (final e in albums.entries)
      LocalBrowseAlbum(
        id: ++albumId,
        name: e.value.first.albumName ?? kUnknownAlbum,
        artist: e.value.first.artistName,
        songs: e.value,
      ),
  ];
  final byArtist = <String, List<LocalBrowseAlbum>>{};
  for (final a in browsable) {
    (byArtist[a.artist ?? kUnknownArtist] ??= []).add(a);
  }
  var artistId = 0;
  handler.setLocalLibrary(
    mode: true,
    songs: songs,
    paths: {for (final s in songs) s.id: s.filePath},
    albums: browsable,
    artists: [
      for (final e in byArtist.entries)
        LocalBrowseArtist(
          id: ++artistId,
          name: e.key,
          albums: e.value,
          songs: [for (final a in e.value) ...a.songs],
        ),
    ],
  );
}

LocalTrack _track(
  String title, {
  String? artist,
  String? albumArtist,
  String? album,
  int? track,
  int? disc,
  int? year,
  int duration = 200,
  String? artworkPath,
}) =>
    LocalTrack(
      path: '/musique/$title.mp3',
      title: title,
      artist: artist,
      albumArtist: albumArtist,
      album: album,
      trackNumber: track,
      discNumber: disc,
      year: year,
      duration: duration,
      artworkPath: artworkPath,
    );

Widget _app(Widget child) => MaterialApp(
      theme: gullifyThemeFor(GullifyAccent.indigo, dark: false),
      home: child,
    );

void main() {
  // ══════════════════════════ Les étiquettes ══════════════════════════

  group('étiquettes ID3', () {
    test('un MP3 ID3v2.3 rend tout ce qu\'il porte', () async {
      final tags = await _read(
        _mp3(frames: [
          ..._id3TextFrame('TIT2', 'Où va le monde', encoding: 1),
          ..._id3TextFrame('TPE1', 'Étienne'),
          ..._id3TextFrame('TPE2', 'Various Artists'),
          ..._id3TextFrame('TALB', 'Le grand album'),
          ..._id3TextFrame('TRCK', '3/12'),
          ..._id3TextFrame('TPOS', '2/2'),
          ..._id3TextFrame('TYER', '1987'),
          ..._id3TextFrame('TCON', '(17)'),
          ..._id3PictureFrame([1, 2, 3, 4]),
        ]),
        'mp3',
      );

      expect(tags.title, 'Où va le monde');
      expect(tags.artist, 'Étienne');
      expect(tags.albumArtist, 'Various Artists');
      expect(tags.album, 'Le grand album');
      expect(tags.trackNumber, 3);
      expect(tags.discNumber, 2);
      expect(tags.year, 1987);
      // Genre numéroté d'ID3v1, recopié tel quel par bien des encodeurs.
      expect(tags.genre, 'Rock');
      expect(tags.picture?.bytes, [1, 2, 3, 4]);
      expect(tags.picture?.extension, 'jpg');
      // 16 000 octets à 128 kbit/s : une seconde tout rond.
      expect(tags.duration, const Duration(seconds: 1));
    });

    test('ID3v2.4 : tailles syncsafe, UTF-8 et TDRC', () async {
      List<int> frame(String id, String text) {
        final payload = [3, ...utf8.encode(text)];
        return [
          ...ascii.encode(id),
          ..._syncsafe(payload.length),
          0, 0,
          ...payload,
        ];
      }

      final tags = await _read(
        _mp3(
          major: 4,
          frames: [
            ...frame('TIT2', 'Déjà vu'),
            ...frame('TPE1', 'Quelqu\'un'),
            ...frame('TDRC', '1994-03-02'),
          ],
        ),
        'mp3',
      );

      expect(tags.title, 'Déjà vu');
      expect(tags.artist, 'Quelqu\'un');
      expect(tags.year, 1994);
    });

    test('sans ID3v2, l\'étiquette de fin de fichier prend le relais',
        () async {
      final tags = await _read(
        Uint8List.fromList([
          ..._mp3Audio(),
          ..._id3v1(
            title: 'Vieux titre',
            artist: 'Vieux groupe',
            album: 'Vieil album',
            year: '1975',
            track: 7,
          ),
        ]),
        'mp3',
      );

      expect(tags.title, 'Vieux titre');
      expect(tags.artist, 'Vieux groupe');
      expect(tags.album, 'Vieil album');
      expect(tags.year, 1975);
      expect(tags.trackNumber, 7);
      // Les 128 octets de l'étiquette ne sont pas de l'audio : la durée reste
      // d'une seconde, pas plus.
      expect(tags.duration, const Duration(seconds: 1));
    });

    test('ID3v2 incomplet : l\'ID3v1 comble les trous, sans rien écraser',
        () async {
      final tags = await _read(
        _mp3(
          frames: _id3TextFrame('TIT2', 'Le bon titre'),
          id3v1: _id3v1(title: 'Le mauvais titre', artist: 'L\'interprète'),
        ),
        'mp3',
      );

      expect(tags.title, 'Le bon titre');
      expect(tags.artist, 'L\'interprète');
    });

    test('un débit variable se date par son en-tête Xing', () async {
      final tags = await _read(
        _mp3(
          frames: _id3TextFrame('TIT2', 'Variable'),
          audio: _mp3Audio(afterHeader: _xing(100)),
        ),
        'mp3',
      );

      // 100 trames de 1152 échantillons à 44,1 kHz.
      expect(tags.duration!.inMilliseconds, 2612);
    });

    test('un fichier illisible ne fait pas échouer la lecture', () async {
      final tags = await _read(Uint8List.fromList([0, 1, 2, 3]), 'mp3');
      expect(tags.title, isNull);
      expect(tags.duration, isNull);
    });
  });

  group('étiquettes FLAC, MP4 et Ogg', () {
    test('un FLAC donne sa durée exacte, ses champs et sa pochette', () async {
      final tags = await _read(
        _flac(
          samples: 44100 * 2,
          comments: [
            'TITLE=Le titre',
            'ARTIST=L\'artiste',
            'ALBUMARTIST=Le groupe',
            'ALBUM=L\'album',
            'TRACKNUMBER=4',
            'DATE=2001-05-06',
            'GENRE=Jazz',
          ],
          picture: [9, 8, 7],
        ),
        'flac',
      );

      expect(tags.duration, const Duration(seconds: 2));
      expect(tags.title, 'Le titre');
      expect(tags.artist, 'L\'artiste');
      expect(tags.albumArtist, 'Le groupe');
      expect(tags.album, 'L\'album');
      expect(tags.trackNumber, 4);
      expect(tags.year, 2001);
      expect(tags.genre, 'Jazz');
      expect(tags.picture?.bytes, [9, 8, 7]);
      expect(tags.picture?.extension, 'png');
    });

    test('la signature l\'emporte sur l\'extension', () async {
      // Un FLAC nommé « .mp3 » : c'est le contenu qui décide.
      final tags = await _read(
        _flac(samples: 44100, comments: ['TITLE=Mal nommé']),
        'mp3',
      );
      expect(tags.title, 'Mal nommé');
      expect(tags.duration, const Duration(seconds: 1));
    });

    test('un M4A rend sa durée et ses étiquettes', () async {
      final tags = await _read(
        _mp4(
          durationMs: 185500,
          entries: [
            ..._ilstEntry('©nam', utf8.encode('Un titre')),
            ..._ilstEntry('©ART', utf8.encode('Un interprète')),
            ..._ilstEntry('aART', utf8.encode('Un groupe')),
            ..._ilstEntry('©alb', utf8.encode('Un album')),
            ..._ilstEntry('©day', utf8.encode('2019')),
            ..._ilstEntry('trkn', [..._be16(0), ..._be16(5), 0, 0], type: 0),
            ..._ilstEntry('covr', [4, 2], type: 13),
          ],
        ),
        'm4a',
      );

      expect(tags.duration, const Duration(milliseconds: 185500));
      expect(tags.title, 'Un titre');
      expect(tags.artist, 'Un interprète');
      expect(tags.albumArtist, 'Un groupe');
      expect(tags.album, 'Un album');
      expect(tags.year, 2019);
      expect(tags.trackNumber, 5);
      expect(tags.picture?.bytes, [4, 2]);
    });
  });

  test('un numéro de piste et une année se lisent sous toutes leurs formes',
      () {
    expect(parseTrackNumber('3/12'), 3);
    expect(parseTrackNumber(' 07 '), 7);
    expect(parseTrackNumber('0'), isNull);
    expect(parseTrackNumber('sans numéro'), isNull);
    expect(parseYear('1987-03-02'), 1987);
    expect(parseYear('02/1987'), 1987);
    expect(parseYear('2024'), 2024);
    expect(parseYear('inconnu'), isNull);
  });

  // ═══════════════════════ Le rangement du dossier ═══════════════════════

  group('rangement', () {
    test('les titres se rangent en albums et artistes', () {
      final library = LocalLibrary.from(
        folder: '/musique',
        scannedAt: DateTime(2026),
        tracks: [
          _track('Piste 2', artist: 'A', album: 'Premier', track: 2),
          _track('Piste 1', artist: 'A', album: 'Premier', track: 1,
              year: 1999),
          _track('Ailleurs', artist: 'B', album: 'Second'),
        ],
      );

      expect(library.artists.map((a) => a.artist.name), ['A', 'B']);
      expect(library.albums.map((a) => a.album.name), ['Premier', 'Second']);

      final premier = library.albums.first;
      // L'ordre des pistes est celui du disque, pas celui du dossier.
      expect(premier.songs.map((s) => s.title), ['Piste 1', 'Piste 2']);
      expect(premier.album.year, 1999);
      expect(premier.album.songCount, 2);
      expect(premier.album.totalDuration, 400);
    });

    test('c\'est l\'interprète de l\'album qui range une compilation', () {
      final library = LocalLibrary.from(
        folder: '/musique',
        scannedAt: null,
        tracks: [
          _track('Une', artist: 'Chanteur X', albumArtist: 'Various',
              album: 'Compil', track: 1),
          _track('Deux', artist: 'Chanteur Y', albumArtist: 'Various',
              album: 'Compil', track: 2),
        ],
      );

      // Un seul artiste (« Various »), un seul album, deux interprètes.
      expect(library.artists.single.artist.name, 'Various');
      expect(library.albums.single.album.songCount, 2);
      expect(
        library.albums.single.songs.map((s) => s.artistName),
        ['Chanteur X', 'Chanteur Y'],
      );
    });

    test('deux albums du même nom ne se mélangent pas', () {
      final library = LocalLibrary.from(
        folder: '/musique',
        scannedAt: null,
        tracks: [
          _track('Un', artist: 'A', album: 'Greatest Hits'),
          _track('Deux', artist: 'B', album: 'Greatest Hits'),
        ],
      );

      expect(library.albums, hasLength(2));
      expect(library.albums.map((a) => a.album.artistName), ['A', 'B']);
      // Les identifiants d'album sont distincts : les adresses /local/album/…
      // doivent mener chacune au bon.
      expect(
        library.albums.map((a) => a.album.id).toSet(),
        hasLength(2),
      );
    });

    test('les titres locaux portent des identifiants négatifs et uniques', () {
      final library = LocalLibrary.from(
        folder: '/musique',
        scannedAt: null,
        tracks: [
          for (var i = 0; i < 5; i++) _track('Titre $i', artist: 'A'),
        ],
      );

      expect(library.songs.every((s) => s.id < 0), isTrue);
      expect(library.songs.map((s) => s.id).toSet(), hasLength(5));
      // Aucun album ni artiste du serveur ne doit être visé par un titre
      // local : le lecteur y renverrait vers des écrans qui ont besoin d'une
      // session.
      expect(library.songs.every((s) => s.albumId == null), isTrue);
      expect(library.songs.every((s) => s.artistId == null), isTrue);
    });

    test('sans étiquette d\'album, tout retombe sur « Sans album »', () {
      final library = LocalLibrary.from(
        folder: '/musique',
        scannedAt: null,
        tracks: [_track('Orpheline')],
      );

      expect(library.albums.single.album.name, kUnknownAlbum);
      expect(library.artists.single.artist.name, kUnknownArtist);
    });

    test('la recherche ignore la casse et les accents', () {
      final library = LocalLibrary.from(
        folder: '/musique',
        scannedAt: null,
        tracks: [
          _track('Été', artist: 'Étienne', album: 'Saisons'),
          _track('Hiver', artist: 'Étienne', album: 'Saisons'),
        ],
      );

      expect(library.search('ete').map((s) => s.title), ['Été']);
      expect(library.search('ETIENNE'), hasLength(2));
      expect(library.search('saisons'), hasLength(2));
      expect(library.search('rien'), isEmpty);
    });
  });

  // ═══════════════════ Le parcours d'un vrai dossier ═══════════════════

  group('parcours', () {
    late Directory root;
    late Directory work;

    setUp(() {
      root = Directory.systemTemp.createTempSync('gullify_local_');
      work = Directory.systemTemp.createTempSync('gullify_docs_');
      localLibraryDirForTest = work;
    });

    tearDown(() {
      localLibraryDirForTest = null;
      for (final d in [root, work]) {
        if (d.existsSync()) d.deleteSync(recursive: true);
      }
    });

    void write(String relative, List<int> bytes) {
      final f = File('${root.path}/$relative');
      f.parent.createSync(recursive: true);
      f.writeAsBytesSync(bytes);
    }

    ProviderContainer container() {
      final c = ProviderContainer(
        overrides: [authProvider.overrideWith(() => _LocalAuth(root.path))],
      );
      addTearDown(c.dispose);
      return c;
    }

    test('un dossier se parcourt, s\'étiquette et se retient', () async {
      write(
        'Étienne/Le grand album/03 - Où va le monde.mp3',
        _mp3(frames: [
          ..._id3TextFrame('TIT2', 'Où va le monde'),
          ..._id3TextFrame('TPE1', 'Étienne'),
          ..._id3TextFrame('TALB', 'Le grand album'),
          ..._id3TextFrame('TRCK', '3'),
          ..._id3PictureFrame([1, 2, 3]),
        ]),
      );
      // Deuxième piste du même album, SANS pochette : elle doit hériter de
      // celle de l'album.
      write(
        'Étienne/Le grand album/04 - La suite.mp3',
        _mp3(frames: [
          ..._id3TextFrame('TIT2', 'La suite'),
          ..._id3TextFrame('TPE1', 'Étienne'),
          ..._id3TextFrame('TALB', 'Le grand album'),
          ..._id3TextFrame('TRCK', '4'),
        ]),
      );
      // Aucune étiquette : c'est l'arborescence et le nom du fichier qui
      // parlent.
      write('Autre groupe/Un album/07 - Sans étiquette.mp3', _mp3Audio());
      // Ni de la musique, ni un format jouable : ignorés.
      write('Étienne/Le grand album/cover.jpg', [1, 2, 3]);
      write('Étienne/Le grand album/notes.txt', [65]);
      write('.cachés/Rien.mp3', _mp3Audio());

      final c = container();
      await c.read(localLibraryProvider.future);
      await c.read(localLibraryProvider.notifier).rescan();

      final library = c.read(localLibraryProvider).value!;
      expect(library.songs, hasLength(3));
      expect(library.scannedAt, isNotNull);
      // Le parcours est fini : plus d'avancement affiché.
      expect(c.read(localScanProvider), isNull);

      final album = library.albums
          .firstWhere((a) => a.album.name == 'Le grand album');
      expect(album.songs.map((s) => s.title), ['Où va le monde', 'La suite']);
      expect(album.album.artistName, 'Étienne');
      // La pochette extraite vit dans le dossier de travail de l'app, et
      // couvre tout l'album.
      expect(album.album.artworkUrl, startsWith(work.path));
      expect(File(album.album.artworkUrl!).readAsBytesSync(), [1, 2, 3]);
      expect(album.songs.every((s) => s.artworkUrl != null), isTrue);

      // Sans étiquette : le nom du fichier fait le titre (sans son numéro),
      // le dossier fait l'album, celui du dessus l'artiste.
      final orpheline = library.songs
          .firstWhere((s) => s.title == 'Sans étiquette');
      expect(orpheline.albumName, 'Un album');
      expect(orpheline.artistName, 'Autre groupe');
      expect(library.songs.firstWhere((s) => s.title == 'Sans étiquette')
          .duration, 1);

      // L'index est relu au démarrage suivant : pas de second parcours.
      final again = ProviderContainer(
        overrides: [authProvider.overrideWith(() => _LocalAuth(root.path))],
      );
      addTearDown(again.dispose);
      final restored = await again.read(localLibraryProvider.future);
      expect(restored!.songs, hasLength(3));
      expect(restored.scannedAt, isNotNull);
      expect(restored.albums.map((a) => a.album.name),
          library.albums.map((a) => a.album.name));
    });

    test('un dossier sans musique le dit, et ne retient rien', () async {
      write('lisez-moi.txt', [65]);

      final c = container();
      await c.read(localLibraryProvider.future);
      await c.read(localLibraryProvider.notifier).rescan();

      expect(c.read(localScanProvider)?.error, isNotNull);
      expect(c.read(localLibraryProvider).value!.isEmpty, isTrue);
    });

    test('changer de dossier oublie l\'index et les pochettes', () async {
      write(
        'A/B/01 - Titre.mp3',
        _mp3(frames: [
          ..._id3TextFrame('TIT2', 'Titre'),
          ..._id3PictureFrame([1]),
        ]),
      );

      final c = container();
      await c.read(localLibraryProvider.future);
      await c.read(localLibraryProvider.notifier).rescan();
      expect(File('${work.path}/local_library.json').existsSync(), isTrue);

      await c.read(localLibraryProvider.notifier).forget();
      expect(File('${work.path}/local_library.json').existsSync(), isFalse);
      expect(Directory('${work.path}/local_art').existsSync(), isFalse);
    });
  });

  // ══════════════════════════ Le lecteur ══════════════════════════

  group('lecture', () {
    test('un titre du dossier se joue depuis son fichier', () async {
      final handler = _localHandler();
      final song = Song(
        id: -1,
        title: 'Local',
        filePath: '/carte/musique/a.mp3',
        duration: 200,
      );
      _bind(handler, [song]);

      // Ce que le lecteur jouerait : le fichier, sans serveur ni flux.
      expect(handler.localPaths[-1], '/carte/musique/a.mp3');
      final items = await handler.getChildren(BrowseIds.localSongs);
      expect(items.any((i) => i.title == 'Local'), isTrue);
    });

    test('sans serveur, Android Auto parcourt le dossier', () async {
      final handler = _localHandler();
      _bind(handler, [
        const Song(id: -1, title: 'Local', filePath: '/carte/a.mp3',
            albumName: 'Album', artistName: 'Artiste'),
      ]);

      final root = await handler.getChildren(BrowseIds.root);
      expect(root.map((i) => i.title),
          ['Lecture aléatoire', 'Artistes', 'Albums', 'Titres']);

      // Les albums et les artistes s'ouvrent, comme avec un serveur.
      final albums = await handler.getChildren(BrowseIds.localAlbums);
      expect(albums.any((i) => i.title == 'Album'), isTrue);
      final tracks = await handler.getChildren(BrowseIds.localAlbum(1));
      expect(tracks.first.title, "Lire l'album");
      expect(tracks.any((i) => i.title == 'Local'), isTrue);
      final artists = await handler.getChildren(BrowseIds.localArtists);
      expect(artists.any((i) => i.title == 'Artiste'), isTrue);
    });

    test('une catégorie du serveur demandée en mode local ne fait pas '
        'attendre', () async {
      final handler = _localHandler();
      _bind(handler, [
        const Song(id: -1, title: 'Local', filePath: '/carte/a.mp3'),
      ]);

      // C'était là le « ça cherche toujours » de la voiture (idée #115) :
      // l'onglet du serveur attendait une session qui n'arrivait jamais.
      final items = await handler
          .getChildren(BrowseIds.albums)
          .timeout(const Duration(seconds: 2));
      expect(items.any((i) => i.title == 'Réessayer'), isFalse);
      expect(items.map((i) => i.title), contains('Titres'));
    });

    test('le marqueur en clair fait connaître le mode avant le coffre',
        () async {
      // Android Auto demande la racine avant que la session ne soit
      // restaurée : sans le marqueur, le lecteur répondait le menu d'un
      // serveur qui n'existe pas (idée #115).
      final dir = await Directory.systemTemp.createTemp('gullify_mode');
      addTearDown(() => dir.deleteSync(recursive: true));
      LocalModeFlag.dirForTest = dir;
      addTearDown(() => LocalModeFlag.dirForTest = null);
      await LocalModeFlag.write('/carte/musique');

      final handler = GullifyAudioHandler();
      addTearDown(handler.player.dispose);
      handler.localLibraryWait = Duration.zero;

      final root = await handler.getChildren(BrowseIds.root);
      expect(handler.localMode, isTrue);
      // Le dossier n'est pas encore relu : on le dit, plutôt que de proposer
      // un menu de serveur que rien ne viendra remplir.
      expect(root.single.title, 'Dossier local vide');

      await LocalModeFlag.write(null);
      expect(await LocalModeFlag.read(), isNull);
    });

    test('la recherche cherche dans le dossier, sans accents', () async {
      final handler = _localHandler();
      _bind(handler, [
        const Song(id: -1, title: 'Où va le monde', filePath: '/a.mp3',
            artistName: 'Étienne'),
        const Song(id: -2, title: 'Autre chose', filePath: '/b.mp3',
            artistName: 'Quelqu\'un'),
      ]);

      final items = await handler.search('etienne');
      expect(items, hasLength(1));
      expect(items.single.title, 'Où va le monde');
      expect(items.single.id, 'LOCAL_SEARCH_TRACK_0');
    });

    test('les téléchargements restent là en mode local', () async {
      final handler = _localHandler();
      _bind(handler, [
        const Song(id: -1, title: 'Local', filePath: '/carte/a.mp3'),
      ]);
      const downloaded =
          Song(id: 12, title: 'Descendu', filePath: 'srv/b.mp3');
      handler.offlineSongs = [downloaded];
      handler.offlinePaths = {12: '/telechargements/b.mp3'};

      final root = await handler.getChildren(BrowseIds.root);
      expect(root.map((i) => i.title), contains('Téléchargements'));
      final items = await handler.getChildren(BrowseIds.downloads);
      expect(items.any((i) => i.title == 'Descendu'), isTrue);
    });

    test('un titre local se décrit sans serveur', () async {
      final handler = _localHandler();
      _bind(handler, [
        const Song(id: -1, title: 'Local', filePath: '/carte/a.mp3',
            albumName: 'Album', artistName: 'Artiste', duration: 200),
      ]);

      // Android Auto demande la fiche avant de jouer : une fiche nulle, et la
      // sélection échoue.
      final item = await handler.getMediaItem('LOCAL_ALL_TRACK_0');
      expect(item?.title, 'Local');
      expect(item?.id, 'LOCAL_ALL_TRACK_0');
      expect(await handler.getMediaItem('LOCAL_ALBUM_1_TRACK_0'), isNotNull);
    });

    test('en mode serveur, la racine ne change pas', () async {
      final handler = GullifyAudioHandler();
      addTearDown(handler.player.dispose);

      final root = await handler.getChildren(BrowseIds.root);
      expect(root.map((i) => i.title),
          ['Accueil', 'Bibliothèque', 'Radios', 'Favoris']);
    });
  });

  // ══════════════════════════ Les écrans ══════════════════════════

  group('écrans', () {
    testWidgets('le dossier s\'affiche en albums, et un titre lance l\'album',
        (tester) async {
      tester.view.physicalSize = const Size(412, 892);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final library = LocalLibrary.from(
        folder: '/storage/emulated/0/Music',
        scannedAt: DateTime(2026, 9, 24),
        tracks: [
          _track('Piste 1', artist: 'Étienne', album: 'Le grand album',
              track: 1),
          _track('Piste 2', artist: 'Étienne', album: 'Le grand album',
              track: 2),
        ],
      );
      final actions = _FakeActions();

      await tester.pumpWidget(ProviderScope(
        overrides: [
          localLibraryProvider.overrideWith(() => _ReadyLibrary(library)),
          playerActionsProvider.overrideWithValue(actions),
        ],
        child: _app(const LocalLibraryScreen()),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Dossier local'), findsOneWidget);
      expect(find.text('Music'), findsOneWidget);
      expect(find.text('Le grand album'), findsWidgets);

      // La vue « Titres » lance la liste entière, au bon titre.
      await tester.tap(find.text('Titres'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Piste 2'));
      await tester.pumpAndSettle();

      expect(actions.played.single.songs, hasLength(2));
      expect(actions.played.single.index, 1);
    });

    testWidgets('un album du dossier se lit en entier', (tester) async {
      tester.view.physicalSize = const Size(412, 892);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final library = LocalLibrary.from(
        folder: '/musique',
        scannedAt: DateTime(2026),
        tracks: [
          _track('Une', artist: 'A', album: 'Album', track: 1),
          _track('Deux', artist: 'A', album: 'Album', track: 2),
        ],
      );
      final actions = _FakeActions();

      await tester.pumpWidget(ProviderScope(
        overrides: [
          localLibraryProvider.overrideWith(() => _ReadyLibrary(library)),
          playerActionsProvider.overrideWithValue(actions),
        ],
        child: _app(LocalAlbumScreen(albumId: library.albums.single.album.id)),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Album'), findsWidgets);
      expect(find.text('2 titres'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.play_arrow).first);
      await tester.pumpAndSettle();
      expect(actions.played.single.songs.map((s) => s.title), ['Une', 'Deux']);
    });

    testWidgets('la recherche trouve titre, album et artiste du dossier',
        (tester) async {
      tester.view.physicalSize = const Size(412, 892);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final library = LocalLibrary.from(
        folder: '/musique',
        scannedAt: DateTime(2026),
        tracks: [
          _track('Où va le monde', artist: 'Étienne', album: 'Le grand album'),
          _track('Ailleurs', artist: 'Quelqu\'un', album: 'Autre chose'),
        ],
      );
      final actions = _FakeActions();

      await tester.pumpWidget(ProviderScope(
        overrides: [
          localLibraryProvider.overrideWith(() => _ReadyLibrary(library)),
          playerActionsProvider.overrideWithValue(actions),
        ],
        child: _app(const LocalSearchScreen()),
      ));
      await tester.pumpAndSettle();

      // Sans accents ni casse : « etienne » doit trouver Étienne.
      await tester.enterText(find.byType(TextField), 'etienne');
      await tester.pumpAndSettle();

      expect(find.text('Artistes'), findsOneWidget);
      expect(find.text('Étienne'), findsWidgets);
      expect(find.text('Où va le monde'), findsOneWidget);
      expect(find.text('Ailleurs'), findsNothing);

      // Et le titre trouvé se joue, comme partout ailleurs dans l'app.
      await tester.tap(find.text('Où va le monde'));
      await tester.pumpAndSettle();
      expect(actions.played.single.songs.single.title, 'Où va le monde');
    });

    testWidgets('le parcours en cours se montre plutôt que la bibliothèque',
        (tester) async {
      tester.view.physicalSize = const Size(412, 892);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(ProviderScope(
        overrides: [
          localLibraryProvider.overrideWith(
            () => _ReadyLibrary(const LocalLibrary.empty('/musique')),
          ),
          localScanProvider.overrideWith(() => _Scanning()),
          playerActionsProvider.overrideWithValue(_FakeActions()),
        ],
        child: _app(const LocalLibraryScreen()),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Lecture des étiquettes'), findsOneWidget);
      expect(find.text('12 / 40 fichiers'), findsOneWidget);
      expect(find.text('Albums'), findsNothing);
    });
  });
}

/// Un parcours figé à mi-chemin.
class _Scanning extends LocalScan {
  @override
  LocalScanProgress? build() => const LocalScanProgress(
        done: 12,
        total: 40,
        current: 'Où va le monde.mp3',
      );
}
