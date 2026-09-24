import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

import '../audio/local_tags.dart';
import '../models/album.dart';
import '../models/artist.dart';
import '../models/song.dart';
import 'auth.dart';

/// Le mode « dossier local » (idée #114) : Gullify sans serveur.
///
/// Un dossier du téléphone est parcouru une fois, ses étiquettes lues sur
/// place (voir `audio/local_tags.dart`), et le résultat rangé dans un index
/// JSON — artistes, albums, titres, pochettes extraites. La lecture passe
/// ensuite par le même lecteur que d'habitude : le handler sait déjà jouer un
/// fichier du disque (c'est ce qui fait marcher les téléchargements sans
/// réseau), il suffit de lui donner les chemins.
///
/// Rien ici ne parle au serveur : ni écoutes, ni favoris, ni playlists. C'est
/// un mode volontairement étroit — de quoi écouter sa musique, et rien de plus.

/// Une piste rangée : ce que le fichier a dit de lui, plus son chemin.
@immutable
class LocalTrack {
  const LocalTrack({
    required this.path,
    required this.title,
    this.artist,
    this.albumArtist,
    this.album,
    this.genre,
    this.trackNumber,
    this.discNumber,
    this.year,
    this.duration = 0,
    this.artworkPath,
  });

  factory LocalTrack.fromJson(Map<String, dynamic> j) => LocalTrack(
        path: j['path'] as String,
        title: j['title'] as String,
        artist: j['artist'] as String?,
        albumArtist: j['albumArtist'] as String?,
        album: j['album'] as String?,
        genre: j['genre'] as String?,
        trackNumber: (j['trackNumber'] as num?)?.toInt(),
        discNumber: (j['discNumber'] as num?)?.toInt(),
        year: (j['year'] as num?)?.toInt(),
        duration: (j['duration'] as num?)?.toInt() ?? 0,
        artworkPath: j['artworkPath'] as String?,
      );

  final String path;
  final String title;
  final String? artist;
  final String? albumArtist;
  final String? album;
  final String? genre;
  final int? trackNumber;
  final int? discNumber;
  final int? year;

  /// Durée en secondes, `0` quand le fichier n'a pas su la dire (le lecteur la
  /// trouvera à la lecture).
  final int duration;

  /// Pochette extraite du fichier, sur le disque de l'app.
  final String? artworkPath;

  /// Celui sous lequel l'album se range : l'interprète de l'album d'abord
  /// (TPE2), comme côté serveur, sinon celui de la piste.
  String get rangedUnder => albumArtist ?? artist ?? kUnknownArtist;

  String get albumName => album ?? kUnknownAlbum;

  Map<String, dynamic> toJson() => {
        'path': path,
        'title': title,
        if (artist != null) 'artist': artist,
        if (albumArtist != null) 'albumArtist': albumArtist,
        if (album != null) 'album': album,
        if (genre != null) 'genre': genre,
        if (trackNumber != null) 'trackNumber': trackNumber,
        if (discNumber != null) 'discNumber': discNumber,
        if (year != null) 'year': year,
        'duration': duration,
        if (artworkPath != null) 'artworkPath': artworkPath,
      };
}

const kUnknownArtist = 'Artiste inconnu';
const kUnknownAlbum = 'Sans album';

/// Un album du dossier, avec ses pistes dans l'ordre.
@immutable
class LocalAlbum {
  const LocalAlbum({required this.album, required this.songs});

  final Album album;
  final List<Song> songs;
}

/// Un artiste du dossier, ses albums et tous ses titres.
@immutable
class LocalArtist {
  const LocalArtist({
    required this.artist,
    required this.albums,
    required this.songs,
  });

  final Artist artist;
  final List<LocalAlbum> albums;
  final List<Song> songs;
}

/// La bibliothèque locale : les pistes rangées en artistes et albums, avec des
/// identifiants attribués ici même.
///
/// Les titres portent des identifiants NÉGATIFS : ils ne viennent d'aucun
/// serveur, et ne doivent jamais pouvoir se confondre avec un titre
/// téléchargé (dont le chemin est rangé dans la même table du lecteur) ni avec
/// un favori. Les albums et les artistes, eux, ne servent qu'aux adresses
/// `/local/...` de l'app.
@immutable
class LocalLibrary {
  const LocalLibrary({
    required this.folder,
    required this.scannedAt,
    required this.songs,
    required this.albums,
    required this.artists,
  });

  /// Bibliothèque vide : un dossier choisi, pas encore parcouru.
  const LocalLibrary.empty(this.folder)
      : scannedAt = null,
        songs = const [],
        albums = const [],
        artists = const [];

  factory LocalLibrary.from({
    required String folder,
    required DateTime? scannedAt,
    required List<LocalTrack> tracks,
  }) {
    // Ordre de rangement : l'artiste, puis l'album, puis le disque et la
    // piste. C'est lui qui fixe les identifiants — l'index relu donne donc
    // toujours les mêmes, tant que le dossier n'a pas changé.
    final sorted = [...tracks]..sort(_compareTracks);

    final songs = <Song>[];
    final albums = <LocalAlbum>[];
    final artists = <LocalArtist>[];

    // Clé d'album : son interprète ET son nom — deux « Greatest Hits » de deux
    // artistes différents ne sont pas le même album.
    final byAlbum = <String, List<(LocalTrack, Song)>>{};
    final byArtist = <String, List<String>>{};

    for (var i = 0; i < sorted.length; i++) {
      final t = sorted[i];
      final song = Song(
        // Négatif, et jamais 0 : voir la note de classe.
        id: -(i + 1),
        title: t.title,
        filePath: t.path,
        trackNumber: t.trackNumber,
        duration: t.duration,
        albumName: t.album,
        artistName: t.artist ?? t.albumArtist,
        artworkUrl: t.artworkPath,
      );
      songs.add(song);
      final albumKey = '${t.rangedUnder}\u0000${t.albumName}';
      (byAlbum[albumKey] ??= []).add((t, song));
      final artistAlbums = byArtist[t.rangedUnder] ??= [];
      if (!artistAlbums.contains(albumKey)) artistAlbums.add(albumKey);
    }

    final albumByKey = <String, LocalAlbum>{};
    var albumId = 0;
    for (final entry in byAlbum.entries) {
      final tracks = entry.value;
      final first = tracks.first.$1;
      final local = LocalAlbum(
        album: Album(
          id: ++albumId,
          name: first.albumName,
          artistName: first.rangedUnder,
          year: tracks.map((e) => e.$1.year).firstWhere(
                (y) => y != null,
                orElse: () => null,
              ),
          artworkUrl: tracks
              .map((e) => e.$1.artworkPath)
              .firstWhere((a) => a != null, orElse: () => null),
          songCount: tracks.length,
          totalDuration:
              tracks.fold<int>(0, (sum, e) => sum + e.$1.duration),
        ),
        songs: [for (final e in tracks) e.$2],
      );
      albums.add(local);
      albumByKey[entry.key] = local;
    }

    var artistId = 0;
    for (final entry in byArtist.entries) {
      final albumsOf = [for (final k in entry.value) albumByKey[k]!];
      final songsOf = [for (final a in albumsOf) ...a.songs];
      artists.add(
        LocalArtist(
          artist: Artist(
            id: ++artistId,
            name: entry.key,
            imageUrl: albumsOf
                .map((a) => a.album.artworkUrl)
                .firstWhere((a) => a != null, orElse: () => null),
            albumCount: albumsOf.length,
            songCount: songsOf.length,
          ),
          albums: albumsOf,
          songs: songsOf,
        ),
      );
    }

    albums.sort((a, b) => _byName(a.album.name, b.album.name));
    artists.sort((a, b) => _byName(a.artist.name, b.artist.name));

    return LocalLibrary(
      folder: folder,
      scannedAt: scannedAt,
      songs: songs,
      albums: albums,
      artists: artists,
    );
  }

  final String folder;

  /// Date du dernier parcours, `null` si le dossier n'a pas encore été lu.
  final DateTime? scannedAt;

  final List<Song> songs;
  final List<LocalAlbum> albums;
  final List<LocalArtist> artists;

  bool get isEmpty => songs.isEmpty;

  /// Nom du dossier, tel qu'on l'affiche (« Music », pas le chemin entier).
  String get folderName {
    final parts = folder.split('/').where((p) => p.isNotEmpty);
    return parts.isEmpty ? folder : parts.last;
  }

  LocalAlbum? albumById(int id) =>
      albums.where((a) => a.album.id == id).firstOrNull;

  LocalArtist? artistById(int id) =>
      artists.where((a) => a.artist.id == id).firstOrNull;

  /// Les titres dont le titre, l'album ou l'interprète contient [query].
  List<Song> search(String query) {
    final q = _fold(query);
    if (q.isEmpty) return const [];
    return [
      for (final s in songs)
        if (_fold(s.title).contains(q) ||
            _fold(s.albumName ?? '').contains(q) ||
            _fold(s.artistName ?? '').contains(q))
          s,
    ];
  }

  static int _compareTracks(LocalTrack a, LocalTrack b) {
    final artist = _byName(a.rangedUnder, b.rangedUnder);
    if (artist != 0) return artist;
    final album = _byName(a.albumName, b.albumName);
    if (album != 0) return album;
    final disc = (a.discNumber ?? 1).compareTo(b.discNumber ?? 1);
    if (disc != 0) return disc;
    final track = (a.trackNumber ?? 9999).compareTo(b.trackNumber ?? 9999);
    if (track != 0) return track;
    return _byName(a.title, b.title);
  }

  static int _byName(String a, String b) =>
      _fold(a).compareTo(_fold(b));

  /// Comparaison et recherche insensibles à la casse et aux accents : « Étienne »
  /// se cherche aussi bien par « etienne ».
  static String _fold(String s) {
    const from = 'àáâãäåèéêëìíîïòóôõöùúûüçñÿ';
    const to = 'aaaaaaeeeeiiiiooooouuuucny';
    final lower = s.toLowerCase();
    final out = StringBuffer();
    for (final c in lower.codeUnits) {
      final i = from.codeUnits.indexOf(c);
      out.writeCharCode(i >= 0 ? to.codeUnitAt(i) : c);
    }
    return out.toString().trim();
  }
}

/// Où en est le parcours du dossier.
@immutable
class LocalScanProgress {
  const LocalScanProgress({
    required this.done,
    required this.total,
    this.current,
    this.error,
  });

  final int done;
  final int total;

  /// Nom du fichier en cours de lecture.
  final String? current;

  /// Message d'échec, quand le dossier n'a pas pu être lu.
  final String? error;

  bool get listing => total == 0 && error == null;
  double? get fraction => total > 0 ? done / total : null;
}

/// L'avancement du parcours, à part de la bibliothèque : l'écran suit les deux
/// sans que chaque fichier lu reconstruise la liste des albums.
class LocalScan extends Notifier<LocalScanProgress?> {
  @override
  LocalScanProgress? build() => null;

  void set(LocalScanProgress? progress) => state = progress;
}

final localScanProvider =
    NotifierProvider<LocalScan, LocalScanProgress?>(LocalScan.new);

/// Dossier de travail du mode local (index et pochettes extraites). Les tests
/// le remplacent : il n'y a pas de « documents » d'application hors téléphone.
@visibleForTesting
Directory? localLibraryDirForTest;

class LocalLibraryController extends AsyncNotifier<LocalLibrary?> {
  @override
  Future<LocalLibrary?> build() async {
    final folder = ref.watch(authProvider.select((a) => a.localFolder));
    if (folder == null || folder.isEmpty) return null;
    return _readIndex(await _index(), folder) ?? LocalLibrary.empty(folder);
  }

  Directory? _dir;

  Future<Directory> _appDir() async =>
      _dir ??= localLibraryDirForTest ?? await getApplicationDocumentsDirectory();

  File? _indexFile;

  Future<File> _index() async =>
      _indexFile ??= File('${(await _appDir()).path}/local_library.json');

  /// L'index relu, ou `null` s'il n'y en a pas pour ce dossier.
  LocalLibrary? _readIndex(File f, String folder) {
    try {
      if (!f.existsSync()) return null;
      final j = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
      if (j['folder'] != folder) return null;
      final tracks = [
        for (final t in (j['tracks'] as List<dynamic>? ?? const []))
          LocalTrack.fromJson(t as Map<String, dynamic>),
      ];
      final at = j['scannedAt'] as String?;
      return LocalLibrary.from(
        folder: folder,
        scannedAt: at == null ? null : DateTime.tryParse(at),
        tracks: tracks,
      );
    } catch (_) {
      // Index d'une version antérieure ou abîmé : on repart d'un parcours.
      return null;
    }
  }

  /// Parcourt le dossier s'il ne l'a jamais été. Appelé à l'ouverture de
  /// l'écran : choisir un dossier et devoir ensuite demander le parcours
  /// n'aurait aucun sens.
  Future<void> ensureScanned() async {
    final current = state.value;
    if (current == null || current.scannedAt != null) return;
    if (ref.read(localScanProvider) != null) return;
    await rescan();
  }

  /// (Re)parcourt le dossier : tous les fichiers audio, leurs étiquettes, et
  /// les pochettes extraites une fois par album.
  Future<void> rescan() async {
    // Le dossier d'AUTORITÉ est celui de la session : quand on vient d'en
    // changer, l'index relu peut encore porter l'ancien.
    final folder = ref.read(authProvider).localFolder ?? state.value?.folder;
    if (folder == null || folder.isEmpty) return;
    final scan = ref.read(localScanProvider.notifier);
    scan.set(const LocalScanProgress(done: 0, total: 0));

    if (!await ensureAudioPermission()) {
      scan.set(const LocalScanProgress(
        done: 0,
        total: 0,
        error: 'Gullify n\'a pas accès aux fichiers audio du téléphone. '
            'Autorise « Musique et audio » dans les réglages de l\'app, '
            'puis relance le parcours.',
      ));
      return;
    }

    List<File> files;
    try {
      files = await _listAudioFiles(Directory(folder));
    } catch (e) {
      scan.set(LocalScanProgress(
        done: 0,
        total: 0,
        error: 'Dossier illisible : $e',
      ));
      return;
    }
    if (files.isEmpty) {
      scan.set(const LocalScanProgress(
        done: 0,
        total: 0,
        error: 'Aucun fichier audio dans ce dossier.',
      ));
      state = AsyncData(LocalLibrary.empty(folder));
      return;
    }

    final artDir = Directory('${(await _appDir()).path}/local_art');
    try {
      if (artDir.existsSync()) artDir.deleteSync(recursive: true);
    } catch (_) {
      // Pochettes de l'ancien parcours impossibles à retirer : elles seront
      // simplement écrasées ou laissées là, ce n'est pas bloquant.
    }
    await artDir.create(recursive: true);

    final tracks = <LocalTrack>[];
    // Une pochette par album : la première trouvée sert à tout l'album, comme
    // côté serveur. Sans quoi un album de 20 pistes écrirait 20 fois la même
    // image de 2 Mo.
    final coverByAlbum = <String, String?>{};
    var done = 0;

    for (final file in files) {
      final name = _basename(file.path);
      scan.set(LocalScanProgress(
        done: done,
        total: files.length,
        current: name,
      ));
      final extension = _extension(file.path);
      AudioTags tags;
      ByteSource? source;
      try {
        source = await FileByteSource.open(file);
        tags = await readAudioTags(source, extension: extension);
      } catch (_) {
        // Fichier disparu entre le listage et la lecture, ou refusé par
        // Android : on le passe plutôt que d'arrêter tout le parcours.
        tags = const AudioTags();
      } finally {
        try {
          await source?.close();
        } catch (_) {}
      }

      final segments = _relativeSegments(folder, file.path);
      final album = tags.album ??
          (segments.length >= 2 ? segments[segments.length - 2] : null);
      final artist = tags.artist ??
          (segments.length >= 3 ? segments[segments.length - 3] : null);
      final rangedUnder = tags.albumArtist ?? artist ?? kUnknownArtist;
      final albumKey = '$rangedUnder\u0000${album ?? kUnknownAlbum}';

      String? artworkPath;
      if (coverByAlbum.containsKey(albumKey)) {
        artworkPath = coverByAlbum[albumKey];
      } else if (tags.picture != null) {
        artworkPath = await _writeCover(artDir, coverByAlbum.length, tags
            .picture!);
        coverByAlbum[albumKey] = artworkPath;
      }

      tracks.add(LocalTrack(
        path: file.path,
        title: tags.title ?? _titleFromFileName(name),
        artist: tags.artist ?? artist,
        albumArtist: tags.albumArtist,
        album: album,
        genre: tags.genre,
        trackNumber: tags.trackNumber ?? _trackFromFileName(name),
        discNumber: tags.discNumber,
        year: tags.year,
        duration: tags.duration?.inSeconds ?? 0,
        artworkPath: artworkPath,
      ));
      done++;
    }

    // Les pistes d'un album trouvé après coup (pochette sur la 3e piste)
    // doivent elles aussi porter sa pochette.
    final finished = [
      for (final t in tracks)
        t.artworkPath != null
            ? t
            : LocalTrack(
                path: t.path,
                title: t.title,
                artist: t.artist,
                albumArtist: t.albumArtist,
                album: t.album,
                genre: t.genre,
                trackNumber: t.trackNumber,
                discNumber: t.discNumber,
                year: t.year,
                duration: t.duration,
                artworkPath:
                    coverByAlbum['${t.rangedUnder}\u0000${t.albumName}'],
              ),
    ];

    final scannedAt = DateTime.now();
    final library = LocalLibrary.from(
      folder: folder,
      scannedAt: scannedAt,
      tracks: finished,
    );
    await _writeIndex(folder, scannedAt, finished);
    state = AsyncData(library);
    scan.set(null);
  }

  Future<void> _writeIndex(
    String folder,
    DateTime scannedAt,
    List<LocalTrack> tracks,
  ) async {
    try {
      await (await _index()).writeAsString(jsonEncode({
        'folder': folder,
        'scannedAt': scannedAt.toIso8601String(),
        'tracks': [for (final t in tracks) t.toJson()],
      }));
    } catch (_) {
      // Index non écrit : la bibliothèque est en mémoire pour cette session,
      // elle sera simplement reparcourue au prochain démarrage.
    }
  }

  /// Oublie l'index et les pochettes extraites (changement de dossier, retour
  /// au serveur).
  Future<void> forget() async {
    try {
      final f = await _index();
      if (f.existsSync()) await f.delete();
    } catch (_) {}
    try {
      final art = Directory('${(await _appDir()).path}/local_art');
      if (art.existsSync()) await art.delete(recursive: true);
    } catch (_) {}
    ref.read(localScanProvider.notifier).set(null);
  }

  Future<String?> _writeCover(
    Directory dir,
    int index,
    EmbeddedPicture picture,
  ) async {
    try {
      final file = File('${dir.path}/cover_$index.${picture.extension}');
      await file.writeAsBytes(picture.bytes, flush: false);
      return file.path;
    } catch (_) {
      return null;
    }
  }
}

final localLibraryProvider =
    AsyncNotifierProvider<LocalLibraryController, LocalLibrary?>(
  LocalLibraryController.new,
);

/// Demande l'accès aux fichiers audio du téléphone. Android 13 et plus a sa
/// permission dédiée (« Musique et audio ») ; avant, c'était le stockage.
Future<bool> ensureAudioPermission() async {
  if (kIsWeb || !Platform.isAndroid) return true;
  try {
    if (await Permission.audio.request().isGranted) return true;
    return (await Permission.storage.request()).isGranted;
  } catch (_) {
    // Greffon absent (test, bureau) : on tente la lecture, le système
    // trancherra.
    return true;
  }
}

/// Tous les fichiers audio d'un dossier et de ses sous-dossiers. Les dossiers
/// et fichiers cachés sont passés — un « .thumbnails » plein d'images n'a rien
/// à faire dans une bibliothèque.
Future<List<File>> _listAudioFiles(Directory root) async {
  final out = <File>[];
  await for (final entity in root.list(recursive: true, followLinks: false)) {
    if (entity is! File) continue;
    // Caché, ou dans un dossier caché : « .thumbnails », « .trashed »…
    final segments = _relativeSegments(root.path, entity.path);
    if (segments.any((s) => s.startsWith('.'))) continue;
    if (!kLocalAudioExtensions.contains(_extension(entity.path))) continue;
    out.add(entity);
  }
  out.sort((a, b) => a.path.compareTo(b.path));
  return out;
}

String _basename(String path) {
  final i = path.lastIndexOf('/');
  return i < 0 ? path : path.substring(i + 1);
}

String _extension(String path) {
  final name = _basename(path);
  final dot = name.lastIndexOf('.');
  return dot <= 0 ? '' : name.substring(dot + 1).toLowerCase();
}

/// Les segments du chemin de [path] sous [root] : de quoi retomber sur
/// « Artiste/Album/03 Titre.mp3 » quand le fichier n'a aucune étiquette.
List<String> _relativeSegments(String root, String path) {
  final relative = path.startsWith(root) ? path.substring(root.length) : path;
  return relative.split('/').where((s) => s.isNotEmpty).toList();
}

/// « 03 - Le titre.mp3 » → « Le titre ». Sans étiquette, c'est le nom du
/// fichier qui fait le titre — mais pas son numéro de piste ni son extension.
String _titleFromFileName(String name) {
  var base = name;
  final dot = base.lastIndexOf('.');
  if (dot > 0) base = base.substring(0, dot);
  base = base.replaceFirst(RegExp(r'^\s*\d{1,3}\s*[-–_.)]?\s+'), '');
  base = base.replaceAll('_', ' ').trim();
  return base.isEmpty ? name : base;
}

/// Le numéro de piste en tête du nom de fichier, à défaut d'étiquette.
int? _trackFromFileName(String name) {
  final m = RegExp(r'^\s*(\d{1,3})\s*[-–_.)]?\s+').firstMatch(name);
  if (m == null) return null;
  final n = int.tryParse(m.group(1)!);
  return (n != null && n > 0) ? n : null;
}
