import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../api/library_repository.dart';
import '../models/game_source.dart';
import '../models/song.dart';
import 'library.dart';

const _storage = FlutterSecureStorage();

/// Fiche d'un jeu de l'onglet « Jeux » : identité, but, règles.
class GameInfo {
  const GameInfo({
    required this.id,
    required this.name,
    required this.tagline,
    required this.route,
    required this.icon,
    required this.goal,
    required this.rules,
    this.scoreLabel = 'Meilleur score',
    this.needsSound = false,
    this.multiplayer = true,
  });

  /// Clé de stockage (meilleur score, règles déjà lues).
  final String id;
  final String name;
  final String tagline;
  final String route;
  final IconData icon;

  /// Le but du jeu, en une phrase.
  final String goal;

  /// Les règles, une puce par ligne.
  final List<String> rules;
  final String scoreLabel;

  /// Le jeu fait entendre des extraits (utile de le dire avant de lancer).
  final bool needsSound;

  /// Le jeu se joue aussi en salon (le serveur en connaît les manches).
  /// Faux pour les jeux qui n'ont de sens que seul.
  final bool multiplayer;
}

const kChronoGame = GameInfo(
  id: 'chrono',
  name: 'Chrono',
  tagline: 'Place les titres sur ta frise, à l\'oreille',
  route: '/games/chrono',
  icon: Icons.timeline_rounded,
  goal:
      'Construire la plus longue frise chronologique possible, sans '
      'jamais voir ni le titre ni l\'année avant de te décider.',
  needsSound: true,
  rules: [
    'Un extrait mystère est joué : ni titre, ni artiste, ni pochette.',
    'À toi de deviner s\'il est plus ancien ou plus récent que les cartes '
        'déjà posées, et de le glisser au bon endroit de la frise.',
    'Bien placé : la carte rejoint la frise et te rapporte un point.',
    'Mal placé : tu perds une vie. Trois vies et la partie s\'arrête.',
    'Tu peux passer un extrait, mais il est alors perdu pour la partie.',
  ],
);

const kBlindGame = GameInfo(
  id: 'blind',
  name: 'Blind test',
  tagline: 'Reconnais le titre avant la fin du chrono',
  route: '/games/blind',
  icon: Icons.headphones_rounded,
  goal: 'Reconnaître dix extraits de ta bibliothèque, le plus vite possible.',
  needsSound: true,
  rules: [
    'Un extrait est joué, quatre réponses sont proposées.',
    'Tu as 15 secondes pour trancher.',
    'Plus tu réponds vite, plus tu marques de points (100 au maximum).',
    'Mauvaise réponse ou temps écoulé : zéro point, on passe au suivant.',
    'La partie se joue en 10 manches.',
  ],
);

const kCoverGame = GameInfo(
  id: 'cover',
  name: 'Pochette mystère',
  tagline: 'La pochette se dévoile… reconnais l\'album',
  route: '/games/cover',
  icon: Icons.image_search_rounded,
  goal:
      'Reconnaître huit pochettes de ta bibliothèque avant qu\'elles ne '
      'soient complètement nettes.',
  rules: [
    'Une pochette floutée se précise seconde après seconde.',
    'Quatre albums sont proposés : trouve le bon.',
    'Plus tu réponds tôt (donc plus c\'est flou), plus tu marques.',
    'Mauvaise réponse ou temps écoulé : zéro point pour la manche.',
    'La partie se joue en 8 manches.',
  ],
);

const kDuelGame = GameInfo(
  id: 'duel',
  name: 'Duel d\'années',
  tagline: 'Lequel des deux est le plus ancien ?',
  route: '/games/duel',
  icon: Icons.compare_arrows_rounded,
  scoreLabel: 'Meilleure série',
  goal:
      'Enchaîner la plus longue série de bons duels — une seule erreur '
      'et tout s\'arrête.',
  rules: [
    'Deux albums s\'affrontent : à toi de désigner le plus ancien.',
    'Bonne réponse : le gagnant reste en lice et affronte un nouveau '
        'challenger.',
    'Mauvaise réponse : la partie s\'arrête immédiatement.',
    'Le score, c\'est la longueur de la série.',
  ],
);

const kSwipeGame = GameInfo(
  id: 'swipe',
  name: 'Défricheur',
  tagline: 'Trente secondes pour juger un album jamais écouté',
  route: '/games/swipe',
  icon: Icons.swipe_rounded,
  scoreLabel: 'Meilleure récolte',
  needsSound: true,
  // Chacun défriche sa propre bibliothèque : rien à partager en salon.
  multiplayer: false,
  goal:
      'Faire le tri dans les albums que tu as accumulés sans jamais les '
      'écouter — et repartir avec une playlist de ce qui t\'a plu.',
  rules: [
    'Un album dont aucun titre n\'a jamais été joué se présente : pochette, '
        'artiste, et trente secondes pour se faire une idée.',
    'Glisse la carte vers la droite (ou touche le cœur) pour garder, vers la '
        'gauche (ou la croix) pour passer.',
    'Chaque album gardé rejoint la playlist « $kSwipePlaylist », en entier.',
    'Un album déjà jugé ne revient plus : la partie suivante en propose '
        'd\'autres.',
    'Dix albums par tournée — le score, c\'est ce que tu as gardé.',
  ],
);

/// La playlist que le Défricheur alimente : toujours la même, elle se
/// remplit tournée après tournée.
const kSwipePlaylist = 'Défricheur';

/// Le catalogue affiché dans l'onglet « Jeux » (ordre d'affichage).
const kGames = <GameInfo>[
  kChronoGame,
  kBlindGame,
  kCoverGame,
  kDuelGame,
  kSwipeGame,
];

/// La fiche d'un jeu à partir de son identifiant (celui qu'emploie le
/// serveur pour les parties multijoueur).
GameInfo? gameById(String id) {
  for (final game in kGames) {
    if (game.id == id) return game;
  }
  return null;
}

/// Matière première des jeux (titres datés + albums pochettés). Rechargée à
/// chaque partie via `ref.refresh` pour ne pas rejouer le même tirage.
final gamePoolProvider = FutureProvider<GamePool>(
  (ref) => ref
      .watch(libraryRepositoryProvider)
      .gamePool(source: ref.watch(gameSourceProvider)),
);

/// Vivier du blind test : n'importe quel titre de la bibliothèque (pas
/// besoin d'année ni de pochette).
final blindPoolProvider = FutureProvider<List<Song>>(
  (ref) => ref
      .watch(libraryRepositoryProvider)
      .randomSongs(limit: 120, source: ref.watch(gameSourceProvider)),
);

/// Vivier du Défricheur : les albums dont aucun titre n'a jamais été joué.
final discoveryAlbumsProvider = FutureProvider<List<DiscoveryAlbum>>(
  (ref) => ref
      .watch(libraryRepositoryProvider)
      .discoveryAlbums(limit: 80, source: ref.watch(gameSourceProvider)),
);

/// Vrai si glisser un titre de l'année [year] dans le trou n° [gap] de la
/// frise respecte l'ordre chronologique. [timelineYears] est déjà trié ;
/// les trous vont de 0 (avant la première carte) à `length` (après la
/// dernière). Les années identiques rendent plusieurs trous valides — c'est
/// voulu, on ne peut pas départager deux albums de la même année.
bool chronoPlacementIsCorrect(List<int> timelineYears, int gap, int year) =>
    (gap == 0 || timelineYears[gap - 1] <= year) &&
    (gap == timelineYears.length || year <= timelineYears[gap]);

/// Meilleurs scores et règles déjà lues, par jeu.
class GameStatsState {
  const GameStatsState({this.best = const {}, this.rulesSeen = const {}});

  final Map<String, int> best;
  final Set<String> rulesSeen;

  GameStatsState copyWith({Map<String, int>? best, Set<String>? rulesSeen}) =>
      GameStatsState(
        best: best ?? this.best,
        rulesSeen: rulesSeen ?? this.rulesSeen,
      );
}

class GameStats extends Notifier<GameStatsState> {
  bool _alive = true;
  final Completer<void> _ready = Completer<void>();

  /// Résolu quand les records et les règles lues ont été relus du stockage :
  /// les écrans de jeu l'attendent avant de décider d'afficher les règles.
  /// Borné : un stockage muet ne doit jamais empêcher une partie de démarrer.
  Future<void> get ready =>
      _ready.future.timeout(const Duration(seconds: 2), onTimeout: () {});

  @override
  GameStatsState build() {
    ref.onDispose(() => _alive = false);
    _restore();
    return const GameStatsState();
  }

  Future<void> _restore() async {
    final best = <String, int>{};
    final seen = <String>{};
    try {
      for (final game in kGames) {
        final b = await _storage.read(key: 'game_best_${game.id}');
        final score = b == null ? null : int.tryParse(b);
        if (score != null) best[game.id] = score;
        if (await _storage.read(key: 'game_rules_${game.id}') == '1') {
          seen.add(game.id);
        }
      }
      if (_alive) state = GameStatsState(best: best, rulesSeen: seen);
    } catch (_) {
      // Stockage indisponible (tests, plateforme sans plugin) : on joue sans
      // historique plutôt que de casser l'écran.
    } finally {
      if (!_ready.isCompleted) _ready.complete();
    }
  }

  /// Enregistre un score s'il bat le précédent record du jeu.
  Future<void> submitScore(String gameId, int score) async {
    if (score <= (state.best[gameId] ?? 0)) return;
    state = state.copyWith(best: {...state.best, gameId: score});
    try {
      await _storage.write(key: 'game_best_$gameId', value: '$score');
    } catch (_) {}
  }

  /// Mémorise que les règles de ce jeu ont été lues (plus d'affichage auto).
  Future<void> markRulesSeen(String gameId) async {
    if (state.rulesSeen.contains(gameId)) return;
    state = state.copyWith(rulesSeen: {...state.rulesSeen, gameId});
    try {
      await _storage.write(key: 'game_rules_$gameId', value: '1');
    } catch (_) {}
  }
}

final gameStatsProvider = NotifierProvider<GameStats, GameStatsState>(
  GameStats.new,
);

/// Le vivier des jeux, retenu d'une partie à l'autre : c'est un réglage, pas
/// un choix à refaire à chaque lancement.
class GameSourceController extends Notifier<GameSource> {
  static const _key = 'game_source';

  bool _alive = true;
  final Completer<void> _ready = Completer<void>();

  /// Résolu quand le réglage a été relu du stockage. Borné, comme pour les
  /// records : un stockage muet ne doit jamais retarder une partie.
  Future<void> get ready =>
      _ready.future.timeout(const Duration(seconds: 2), onTimeout: () {});

  @override
  GameSource build() {
    ref.onDispose(() => _alive = false);
    _restore();
    return GameSource.all;
  }

  Future<void> _restore() async {
    try {
      final raw = await _storage.read(key: _key);
      final source = GameSource.decode(raw);
      if (_alive && source != state) state = source;
    } catch (_) {
      // Stockage indisponible (tests, plateforme sans plugin) : on joue avec
      // toute la bibliothèque.
    } finally {
      if (!_ready.isCompleted) _ready.complete();
    }
  }

  Future<void> set(GameSource source) async {
    if (source == state) return;
    state = source;
    try {
      await _storage.write(key: _key, value: source.encode());
    } catch (_) {}
  }
}

final gameSourceProvider = NotifierProvider<GameSourceController, GameSource>(
  GameSourceController.new,
);

/// Les albums déjà jugés au Défricheur (gardés comme passés) : ils ne
/// reviennent plus. Le serveur, lui, continuerait de les proposer — un album
/// gardé mais pas encore écouté reste « jamais joué ».
class SwipeMemory extends Notifier<Set<int>> {
  static const _key = 'game_swipe_seen';

  /// Au-delà, on oublie les plus anciens : la bibliothèque finirait par ne
  /// plus rien proposer, et le stockage n'est pas un journal.
  static const _cap = 600;

  bool _alive = true;
  final Completer<void> _ready = Completer<void>();

  /// Résolu quand la mémoire a été relue du stockage (borné, comme le reste).
  Future<void> get ready =>
      _ready.future.timeout(const Duration(seconds: 2), onTimeout: () {});

  @override
  Set<int> build() {
    ref.onDispose(() => _alive = false);
    _restore();
    return const {};
  }

  Future<void> _restore() async {
    try {
      final raw = await _storage.read(key: _key);
      final ids = <int>{
        for (final part in (raw ?? '').split(','))
          if (int.tryParse(part) != null) int.parse(part),
      };
      if (_alive && ids.isNotEmpty) state = ids;
    } catch (_) {
      // Stockage indisponible : on rejouera peut-être les mêmes albums, ce
      // qui reste préférable à un jeu qui refuse de démarrer.
    } finally {
      if (!_ready.isCompleted) _ready.complete();
    }
  }

  Future<void> remember(Iterable<int> albumIds) async {
    final ids = [...state, ...albumIds];
    final kept = ids.length <= _cap ? ids : ids.sublist(ids.length - _cap);
    state = kept.toSet();
    try {
      await _storage.write(key: _key, value: kept.join(','));
    } catch (_) {}
  }

  /// Repart de zéro : tout redevient à défricher.
  Future<void> forget() async {
    state = const {};
    try {
      await _storage.delete(key: _key);
    } catch (_) {}
  }
}

final swipeMemoryProvider = NotifierProvider<SwipeMemory, Set<int>>(
  SwipeMemory.new,
);
