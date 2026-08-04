import 'dart:convert';

/// D'où les jeux tirent leur musique.
///
/// Par défaut toute la bibliothèque. On peut restreindre à un ou plusieurs
/// genres, à une ou plusieurs playlists, ou aux favoris — le même réglage
/// vaut pour les parties solo et pour les salons à plusieurs (c'est alors la
/// bibliothèque de l'hôte qui est filtrée).
enum GameSourceMode { all, genres, playlists, favorites }

/// Une playlist retenue : l'identifiant part au serveur, le nom sert à
/// afficher le réglage sans avoir à recharger la liste des playlists.
class GameSourcePlaylist {
  const GameSourcePlaylist({required this.id, required this.name});

  final int id;
  final String name;

  @override
  bool operator ==(Object other) =>
      other is GameSourcePlaylist && other.id == id && other.name == name;

  @override
  int get hashCode => Object.hash(id, name);
}

class GameSource {
  const GameSource({
    this.mode = GameSourceMode.all,
    this.genres = const [],
    this.playlists = const [],
  });

  /// Toute la bibliothèque : le réglage par défaut.
  static const GameSource all = GameSource();

  final GameSourceMode mode;
  final List<String> genres;
  final List<GameSourcePlaylist> playlists;

  /// Le mode réellement appliqué : une sélection vide ne filtre rien, sinon
  /// le jeu n'aurait plus rien à tirer.
  GameSourceMode get effectiveMode => switch (mode) {
    GameSourceMode.genres when genres.isEmpty => GameSourceMode.all,
    GameSourceMode.playlists when playlists.isEmpty => GameSourceMode.all,
    _ => mode,
  };

  bool get isAll => effectiveMode == GameSourceMode.all;

  GameSource copyWith({
    GameSourceMode? mode,
    List<String>? genres,
    List<GameSourcePlaylist>? playlists,
  }) => GameSource(
    mode: mode ?? this.mode,
    genres: genres ?? this.genres,
    playlists: playlists ?? this.playlists,
  );

  /// Le réglage, en une ligne, tel qu'il s'affiche dans l'app.
  String get label => switch (effectiveMode) {
    GameSourceMode.all => 'Toute la bibliothèque',
    GameSourceMode.favorites => 'Mes favoris',
    GameSourceMode.genres =>
      genres.length == 1 ? genres.first : '${genres.length} genres',
    GameSourceMode.playlists => playlists.length == 1
        ? playlists.first.name
        : '${playlists.length} playlists',
  };

  /// Ce que le serveur attend : la fiche complète en JSON, dans un seul
  /// paramètre — un nom de genre peut contenir une virgule.
  Map<String, dynamic> toApi() => {
    'mode': effectiveMode.name,
    'genres': effectiveMode == GameSourceMode.genres ? genres : const <String>[],
    'playlists': effectiveMode == GameSourceMode.playlists
        ? [for (final p in playlists) p.id]
        : const <int>[],
  };

  /// Paramètres de requête (vides quand rien n'est filtré, pour ne pas
  /// alourdir les appels les plus courants).
  Map<String, String> get query =>
      isAll ? const {} : {'source': jsonEncode(toApi())};

  /// Forme stockée sur l'appareil : les noms de playlists y sont gardés.
  String encode() => jsonEncode({
    'mode': mode.name,
    'genres': genres,
    'playlists': [
      for (final p in playlists) {'id': p.id, 'name': p.name},
    ],
  });

  /// Relit un réglage stocké. Toute valeur douteuse retombe sur « tout » :
  /// un réglage illisible ne doit jamais empêcher de jouer.
  static GameSource decode(String? raw) {
    if (raw == null || raw.isEmpty) return all;
    try {
      final json = jsonDecode(raw);
      if (json is! Map) return all;
      return GameSource(
        mode: GameSourceMode.values.firstWhere(
          (m) => m.name == json['mode'],
          orElse: () => GameSourceMode.all,
        ),
        genres: [
          for (final g in json['genres'] as List<dynamic>? ?? [])
            if (g is String && g.isNotEmpty) g,
        ],
        playlists: [
          for (final p in json['playlists'] as List<dynamic>? ?? [])
            if (p is Map && p['id'] is num)
              GameSourcePlaylist(
                id: (p['id'] as num).toInt(),
                name: p['name'] as String? ?? 'Playlist',
              ),
        ],
      );
    } catch (_) {
      return all;
    }
  }

  @override
  bool operator ==(Object other) =>
      other is GameSource &&
      other.mode == mode &&
      _sameStrings(other.genres, genres) &&
      _samePlaylists(other.playlists, playlists);

  @override
  int get hashCode => Object.hash(
    mode,
    Object.hashAll(genres),
    Object.hashAll(playlists),
  );

  static bool _sameStrings(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  static bool _samePlaylists(
    List<GameSourcePlaylist> a,
    List<GameSourcePlaylist> b,
  ) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
