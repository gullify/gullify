import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';

/// Le tampon d'avance (idée #90).
///
/// Le lecteur garde déjà quelques dizaines de secondes de son sous le coude
/// (voir tuned_player.dart) : ça suffit à traverser un trou de réseau, pas à
/// traverser un tunnel. Comme la file dit ce qui va être joué, autant le
/// descendre pendant qu'on écoute autre chose : les titres qui arrivent sont
/// téléchargés d'avance, et joués depuis le disque le moment venu. Plus rien à
/// demander au réseau à l'instant précis où il n'y en a plus.
///
/// C'est le fonctionnement des grands lecteurs en flux : quelques titres
/// d'avance, un dossier borné, et les plus vieux fichiers qui s'effacent tout
/// seuls. Rien à voir avec les téléchargements (offline.dart), qui sont un
/// choix explicite, gardés pour toujours et affichés comme tels — le tampon,
/// lui, va et vient sans qu'on s'en occupe.
const _storage = FlutterSecureStorage();
const _kAhead = 'gullify_buffer_ahead';
const _kMaxBytes = 'gullify_buffer_max';

/// Le tampon écrit des fichiers : rien à faire sur le web.
bool get bufferSupported => !kIsWeb;

/// « Toute la file » — la valeur d'avance qui ne s'arrête qu'au bout de la
/// liste (ou au plafond de taille, qui a toujours le dernier mot).
const kBufferAll = -1;

/// Combien de titres d'avance par défaut. Trois, c'est une bonne dizaine de
/// minutes de musique déjà sur le disque : de quoi traverser un tunnel, un
/// ascenseur ou un bout de campagne sans s'en rendre compte, sans pour autant
/// télécharger la moitié de la bibliothèque à chaque écoute.
const kBufferAheadDefault = 3;

/// Les avances proposées dans les réglages.
const kBufferAheadChoices = <int>[0, 1, 3, 5, 10, kBufferAll];

/// La place que le tampon s'autorise, par défaut et au choix. 512 Mo font
/// autour d'une centaine de titres — largement plus que ce qu'une file
/// consomme, et assez petit pour qu'un téléphone plein n'en souffre pas.
const kBufferMaxBytesDefault = 512 * 1024 * 1024;
const kBufferMaxBytesChoices = <int>[
  128 * 1024 * 1024,
  256 * 1024 * 1024,
  512 * 1024 * 1024,
  1024 * 1024 * 1024,
  2048 * 1024 * 1024,
];

/// Un titre à descendre d'avance.
class BufferRequest {
  const BufferRequest({
    required this.songId,
    required this.url,
    required this.ext,
  });

  final int songId;
  final String url;

  /// L'extension du fichier d'origine : le tampon garde le flux tel quel, et
  /// le lecteur reconnaît le format au nom.
  final String ext;
}

/// Un titre déjà descendu.
class BufferedFile {
  const BufferedFile({
    required this.songId,
    required this.path,
    required this.size,
    required this.at,
  });

  final int songId;
  final String path;
  final int size;

  /// Quand le fichier est arrivé. C'est l'ordre d'effacement : le plus vieux
  /// part le premier.
  final DateTime at;
}

/// Les titres à descendre, dans l'ordre où le lecteur va les jouer.
///
/// [order] est l'ordre de lecture réel — les index de la file tels que le
/// lecteur les enchaîne, tirage aléatoire compris. [current] est l'index (dans
/// la file, pas dans l'ordre) du titre en cours : il n'est jamais du voyage,
/// il joue déjà. [loop] fait repartir la sélection au début de la file quand
/// on arrive au bout, comme la lecture en boucle.
///
/// [usable] écarte les titres que le lecteur ne saura pas faire basculer sur
/// leur fichier une fois descendus (voir `_adoptBuffered` : un titre placé
/// avant la piste en cours ne peut pas changer de source sans faire glisser
/// l'index du lecteur). On ne les descend pas : ils repasseraient par le
/// réseau de toute façon. La sélection continue au-delà et va chercher plus
/// loin de quoi tenir l'avance demandée.
///
/// Séparé du lecteur pour être vérifiable : c'est cette liste qui décide de ce
/// qui passe par le réseau à l'avance.
List<int> bufferTargets({
  required List<int> order,
  required int current,
  required int ahead,
  bool loop = false,
  bool Function(int index)? usable,
}) {
  if (ahead == 0 || order.isEmpty) return const [];
  final at = order.indexOf(current);
  if (at < 0) return const [];
  final wanted = ahead == kBufferAll ? order.length - 1 : ahead;
  final targets = <int>[];
  for (var step = 1;
      step <= order.length - 1 && targets.length < wanted;
      step++) {
    final pos = at + step;
    if (pos >= order.length && !loop) break;
    final index = order[pos % order.length];
    if (usable != null && !usable(index)) continue;
    targets.add(index);
  }
  return targets;
}

/// Ce que le tampon doit effacer pour tenir dans [maxBytes] : les plus vieux
/// fichiers d'abord, jusqu'à repasser sous le plafond.
///
/// [keep] met à l'abri les titres de la file en cours — un fichier vers lequel
/// le lecteur pointe déjà ne s'efface pas sous ses pieds. Une file plus grosse
/// que le plafond peut donc le dépasser : mieux vaut déborder un peu que
/// couper la musique.
List<int> bufferEviction({
  required List<BufferedFile> files,
  required int maxBytes,
  Set<int> keep = const {},
}) {
  var total = files.fold(0, (sum, f) => sum + f.size);
  if (total <= maxBytes) return const [];
  final oldest = [...files]..sort((a, b) => a.at.compareTo(b.at));
  final doomed = <int>[];
  for (final f in oldest) {
    if (total <= maxBytes) break;
    if (keep.contains(f.songId)) continue;
    doomed.add(f.songId);
    total -= f.size;
  }
  return doomed;
}

/// L'avance telle que l'écran l'affiche.
String formatBufferAhead(int ahead) => switch (ahead) {
      kBufferAll => 'Toute la file',
      <= 0 => 'Désactivé',
      1 => '1 titre d\'avance',
      _ => '$ahead titres d\'avance',
    };

/// Le tampon d'avance : le réglage, le dossier, et la descente des titres.
///
/// Vit à côté du lecteur, comme l'égaliseur et le fondu : le handler lui dit
/// ce qui arrive dans la file, l'écran de réglage le modifie, et il se
/// mémorise seul.
class PlaybackBuffer extends ChangeNotifier {
  int _ahead = kBufferAheadDefault;
  int _maxBytes = kBufferMaxBytesDefault;
  bool _loaded = false;

  /// Ce qui est déjà sur le disque, par id de titre.
  final _files = <int, BufferedFile>{};

  /// La file d'attente des descentes, et celle en cours.
  final _wanted = <BufferRequest>[];
  BufferRequest? _running;
  CancelToken? _cancel;
  bool _pumping = false;
  Set<int> _keep = const {};

  Directory? _dir;
  Dio? _dio;

  /// Prévient le lecteur qu'un titre vient d'arriver sur le disque : c'est le
  /// moment de le faire jouer depuis là plutôt que depuis le réseau.
  void Function(int songId)? onCached;

  /// Combien de titres d'avance ([kBufferAll] pour toute la file, 0 pour
  /// éteindre le tampon).
  int get ahead => _ahead;

  /// La place que le tampon s'autorise.
  int get maxBytes => _maxBytes;

  /// Ce qu'il occupe pour l'instant.
  int get bytes => _files.values.fold(0, (sum, f) => sum + f.size);

  /// Combien de titres il tient d'avance.
  int get count => _files.length;

  /// Un titre est-il en train de descendre ?
  bool get busy => _running != null;

  /// Le fichier du titre s'il est déjà descendu — et s'il est toujours là :
  /// un fichier effacé sous le tampon (nettoyage du système, utilisateur)
  /// vaut un titre absent, jamais une source morte.
  String? pathFor(int songId) {
    final f = _files[songId];
    if (f == null) return null;
    if (!File(f.path).existsSync()) {
      _files.remove(songId);
      return null;
    }
    return f.path;
  }

  /// Relit le réglage mémorisé et retrouve ce que le tampon avait déjà
  /// descendu (au démarrage de l'app).
  Future<void> loadSaved() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final ahead = int.tryParse(await _storage.read(key: _kAhead) ?? '');
      if (ahead != null && kBufferAheadChoices.contains(ahead)) _ahead = ahead;
      final max = int.tryParse(await _storage.read(key: _kMaxBytes) ?? '');
      if (max != null && max > 0) _maxBytes = max;
    } catch (_) {
      // Réglage illisible : on garde le tampon par défaut.
    }
    await _scan();
    notifyListeners();
  }

  Future<void> setAhead(int value) async {
    _ahead = value;
    if (value == 0) {
      _wanted.clear();
      _cancelRunning();
    }
    notifyListeners();
    await _save(_kAhead, '$value');
  }

  Future<void> setMaxBytes(int value) async {
    _maxBytes = value;
    notifyListeners();
    await _save(_kMaxBytes, '$value');
    await _makeRoom();
  }

  /// Annonce ce qui arrive : [upcoming] dans l'ordre de lecture, [keep] tous
  /// les titres de la file en cours (ceux-là ne s'effacent pas). Ce qui n'est
  /// plus annoncé n'est plus descendu — une file remplacée n'entraîne pas le
  /// téléchargement des titres qu'on ne va plus écouter.
  void prime(List<BufferRequest> upcoming, {Set<int> keep = const {}}) {
    _keep = keep;
    _wanted.clear();
    if (!bufferSupported || _ahead == 0) {
      _cancelRunning();
      return;
    }
    for (final r in upcoming) {
      if (_files.containsKey(r.songId)) continue;
      if (_wanted.any((w) => w.songId == r.songId)) continue;
      _wanted.add(r);
    }
    final running = _running;
    if (running != null && !upcoming.any((r) => r.songId == running.songId)) {
      _cancelRunning();
    }
    unawaited(_pump());
  }

  /// Vide le tampon : tout ce qui est descendu s'efface. Les titres de la file
  /// en cours pointent peut-être dessus — c'est un geste explicite, et le
  /// lecteur retombe sur le réseau à la piste suivante.
  Future<void> clear() async {
    _wanted.clear();
    _cancelRunning();
    for (final f in _files.values) {
      try {
        await File(f.path).delete();
      } catch (_) {}
    }
    _files.clear();
    notifyListeners();
  }

  // ── le dossier ─────────────────────────────────────────────────────────────

  Future<Directory?> _bufferDir() async {
    if (_dir != null) return _dir;
    if (!bufferSupported) return null;
    try {
      final docs = await getApplicationDocumentsDirectory();
      final d = Directory('${docs.path}/buffer');
      await d.create(recursive: true);
      return _dir = d;
    } catch (_) {
      // Pas de dossier (plugin absent, disque plein) : le tampon ne fait rien,
      // et la lecture continue comme avant, par le réseau.
      return null;
    }
  }

  /// Retrouve les fichiers déjà là. Le nom porte l'id du titre : pas d'index à
  /// tenir à jour, donc rien qui puisse mentir sur ce que contient le dossier.
  Future<void> _scan() async {
    final dir = await _bufferDir();
    if (dir == null) return;
    try {
      for (final entity in dir.listSync()) {
        if (entity is! File) continue;
        final name = entity.path.split(Platform.pathSeparator).last;
        // Une descente interrompue (app tuée en plein téléchargement) laisse un
        // .part : il ne vaut rien, on le ramasse.
        if (name.endsWith('.part')) {
          try {
            entity.deleteSync();
          } catch (_) {}
          continue;
        }
        final songId = int.tryParse(name.split('.').first);
        if (songId == null) continue;
        final stat = entity.statSync();
        _files[songId] = BufferedFile(
          songId: songId,
          path: entity.path,
          size: stat.size,
          at: stat.modified,
        );
      }
    } catch (_) {}
    await _makeRoom();
  }

  /// Efface les plus vieux fichiers jusqu'à repasser sous le plafond.
  /// Renvoie vrai s'il reste de la place pour un titre de plus.
  Future<bool> _makeRoom() async {
    final doomed = bufferEviction(
      files: _files.values.toList(),
      maxBytes: _maxBytes,
      keep: _keep,
    );
    for (final id in doomed) {
      final f = _files.remove(id);
      if (f == null) continue;
      try {
        await File(f.path).delete();
      } catch (_) {}
    }
    if (doomed.isNotEmpty) notifyListeners();
    return bytes < _maxBytes;
  }

  // ── la descente ────────────────────────────────────────────────────────────

  void _cancelRunning() {
    _running = null;
    try {
      _cancel?.cancel();
    } catch (_) {}
    _cancel = null;
  }

  /// Un titre à la fois : le tampon travaille dans le dos de la lecture en
  /// cours, il n'a aucune raison de lui disputer la bande passante.
  Future<void> _pump() async {
    if (_pumping) return;
    _pumping = true;
    try {
      while (_wanted.isNotEmpty) {
        final req = _wanted.removeAt(0);
        if (_files.containsKey(req.songId)) continue;
        // Plus de place, et rien d'effaçable (toute la file est à l'abri) :
        // on s'arrête là plutôt que de remplir le disque.
        if (!await _makeRoom()) break;
        await _fetch(req);
      }
    } finally {
      _pumping = false;
    }
  }

  Future<void> _fetch(BufferRequest req) async {
    final dir = await _bufferDir();
    if (dir == null) return;
    final path = '${dir.path}${Platform.pathSeparator}${req.songId}.${req.ext}';
    final part = '$path.part';
    final cancel = CancelToken();
    _running = req;
    _cancel = cancel;
    try {
      // Le fichier ne prend son vrai nom qu'une fois complet : une descente
      // coupée en route ne doit jamais devenir une source de lecture.
      await (_dio ??= Dio()).download(req.url, part, cancelToken: cancel);
      final file = await File(part).rename(path);
      _files[req.songId] = BufferedFile(
        songId: req.songId,
        path: path,
        size: file.lengthSync(),
        at: DateTime.now(),
      );
      notifyListeners();
      onCached?.call(req.songId);
    } catch (_) {
      // Réseau coupé, serveur muet, descente annulée : on nettoie et on passe
      // au suivant. Le titre sera simplement joué en flux, comme avant.
      try {
        final leftover = File(part);
        if (leftover.existsSync()) leftover.deleteSync();
      } catch (_) {}
    } finally {
      if (identical(_cancel, cancel)) {
        _running = null;
        _cancel = null;
      }
    }
  }

  Future<void> _save(String key, String value) async {
    _loaded = true;
    try {
      await _storage.write(key: key, value: value);
    } catch (_) {
      // Un échec d'écriture ne doit jamais remonter à l'interface.
    }
  }

  /// Le dossier du tampon, imposé par les tests (pas de path_provider hors
  /// téléphone) — et son contenu relu dans la foulée.
  @visibleForTesting
  Future<void> useDirectoryForTest(Directory dir) async {
    _dir = dir;
    _loaded = true;
    await _scan();
  }
}
