import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../models/song.dart';

/// Ce qu'on écoutait en dernier, gardé sur le téléphone (idée #103).
///
/// Android Auto (comme la reprise de lecture d'Android) demande au démarrage
/// une racine à part, « recent », et attend UN élément jouable : ce qu'il faut
/// pour reprendre là où on s'était arrêté. Répondre une liste vide, c'est
/// l'erreur « Impossible de charger votre sélection » sur l'écran d'accueil de
/// la voiture — et elle revient à chaque fois qu'Android Auto redemande cette
/// racine. Le disque est le seul endroit qui sache répondre : la question
/// arrive souvent avant que la session ne soit restaurée, parfois sans réseau,
/// et même après que le système a tué l'app.
class ResumePoint {
  const ResumePoint({
    required this.songs,
    required this.index,
    this.position = Duration.zero,
  });

  factory ResumePoint.fromJson(Map<String, dynamic> j) {
    final songs = [
      for (final s in (j['songs'] as List<dynamic>? ?? const []))
        Song.fromJson(s as Map<String, dynamic>),
    ];
    final index = (j['index'] as num?)?.toInt() ?? 0;
    return ResumePoint(
      songs: songs,
      index: songs.isEmpty ? 0 : index.clamp(0, songs.length - 1),
      position: Duration(seconds: (j['position'] as num?)?.toInt() ?? 0),
    );
  }

  /// La file telle qu'elle était : reprendre, ce n'est pas jouer un titre seul
  /// et se taire ensuite.
  final List<Song> songs;
  final int index;
  final Duration position;

  Song get song => songs[index];

  /// Où on en était, de 0 à 1 — ce qu'Android Auto affiche en barre de
  /// progression sur la vignette de reprise.
  double get progress {
    final total = song.duration;
    if (total <= 0 || position <= Duration.zero) return 0;
    return (position.inSeconds / total).clamp(0.0, 1.0);
  }

  ResumePoint at(Duration position) =>
      ResumePoint(songs: songs, index: index, position: position);

  Map<String, dynamic> toJson() => {
        'songs': [for (final s in songs) s.toJson()],
        'index': index,
        'position': position.inSeconds,
      };
}

/// Combien de titres de la file on garde autour de celui qui joue. Une file
/// peut compter toute la bibliothèque ; on n'écrit pas neuf cents fiches sur le
/// disque à chaque changement de piste pour une reprise qui n'ira jamais
/// jusque-là.
const _kKeptSongs = 200;

/// Et combien de titres déjà passés on garde devant, pour que « précédent »
/// fonctionne encore après une reprise.
const _kKeptBefore = 20;

class ResumeStore {
  Directory? _dir;

  /// Le dernier état connu. L'app qui tourne répond avec lui, sans disque.
  ResumePoint? _cache;
  bool _read = false;

  /// Les écritures se suivent au lieu de se marcher dessus : deux
  /// changements de piste rapprochés écriraient le même fichier en même temps.
  Future<void> _writes = Future<void>.value();

  Future<Directory?> _resumeDir() async {
    if (_dir != null) return _dir;
    if (kIsWeb) return null;
    try {
      return _dir = await getApplicationDocumentsDirectory();
    } catch (_) {
      // Pas de dossier (plugin absent hors téléphone) : on garde l'état en
      // mémoire, la reprise marchera tant que l'app vit.
      return null;
    }
  }

  Future<File?> _file() async {
    final dir = await _resumeDir();
    return dir == null ? null : File('${dir.path}/last_played.json');
  }

  /// Ce qu'on écoutait, ou `null` si on n'a encore jamais rien joué.
  Future<ResumePoint?> load() async {
    if (_read) return _cache;
    _read = true;
    try {
      final f = await _file();
      if (f == null || !f.existsSync()) return null;
      final point = ResumePoint.fromJson(
        jsonDecode(await f.readAsString()) as Map<String, dynamic>,
      );
      if (point.songs.isEmpty) return null;
      return _cache = point;
    } catch (_) {
      // Fichier illisible ou d'une version antérieure : on repart de rien
      // plutôt que de faire échouer la racine de reprise.
      return null;
    }
  }

  /// Une nouvelle file : on retient la fenêtre utile autour du titre lancé.
  Future<void> remember(List<Song> songs, {required int index}) {
    if (songs.isEmpty) return Future<void>.value();
    final safeIndex = index.clamp(0, songs.length - 1);
    var start = safeIndex - _kKeptBefore;
    if (start < 0) start = 0;
    var end = start + _kKeptSongs;
    if (end > songs.length) end = songs.length;
    return _save(ResumePoint(
      songs: songs.sublist(start, end),
      index: safeIndex - start,
    ));
  }

  /// Changement de piste dans la file déjà retenue. La file jouée peut être
  /// plus longue que la fenêtre gardée : on retrouve la piste par son
  /// identifiant, pas par sa place, et on ne touche à rien si elle est hors
  /// fenêtre.
  Future<void> rememberCurrent(int? songId) {
    final point = _cache;
    if (point == null || songId == null) return Future<void>.value();
    final at = point.songs.indexWhere((s) => s.id == songId);
    if (at < 0 || at == point.index) return Future<void>.value();
    return _save(ResumePoint(songs: point.songs, index: at));
  }

  /// Où on en est dans la piste en cours (mise en pause, passage en veille).
  /// [songId] dit de quelle piste il s'agit : sans lui, un état de lecteur au
  /// repos — l'app qui démarre, une file qu'on remplace — effacerait la
  /// position d'une écoute qu'on vient de relire du disque.
  Future<void> rememberPosition(Duration position, {required int? songId}) {
    final point = _cache;
    if (point == null || songId == null || songId != point.song.id) {
      return Future<void>.value();
    }
    // Un début de piste est déjà noté par le changement de piste lui-même.
    if (position <= Duration.zero) return Future<void>.value();
    if ((point.position - position).abs() < const Duration(seconds: 5)) {
      return Future<void>.value();
    }
    return _save(point.at(position));
  }

  Future<void> _save(ResumePoint point) {
    _cache = point;
    _read = true;
    return _writes = _writes.then((_) async {
      try {
        final f = await _file();
        await f?.writeAsString(jsonEncode(point.toJson()));
      } catch (_) {
        // Un échec d'écriture ne doit jamais remonter à la lecture en cours.
      }
    });
  }

  /// Le dossier, imposé par les tests (pas de path_provider hors téléphone).
  @visibleForTesting
  void useDirectoryForTest(Directory dir) {
    _dir = dir;
    _cache = null;
    _read = false;
  }
}
