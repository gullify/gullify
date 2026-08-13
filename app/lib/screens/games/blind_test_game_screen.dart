import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/song.dart';
import '../../state/games.dart';
import '../../state/library.dart';
import '../../state/player.dart';
import '../../widgets/artwork.dart';
import '../../widgets/glass_box.dart';
import '../../widgets/glass_kit.dart';
import 'game_fx.dart';
import 'game_kit.dart';

/// « Blind test » : dix extraits, quatre réponses, quinze secondes. Plus la
/// réponse tombe vite, plus elle rapporte.
class BlindTestGameScreen extends ConsumerStatefulWidget {
  const BlindTestGameScreen({super.key});

  @override
  ConsumerState<BlindTestGameScreen> createState() =>
      _BlindTestGameScreenState();
}

enum _Phase { loading, empty, guessing, revealed, over }

class _BlindTestGameScreenState extends ConsumerState<BlindTestGameScreen> {
  static const _rounds = 10;
  static const _roundTime = Duration(seconds: 15);
  static const _tick = Duration(milliseconds: 100);

  final _random = math.Random();
  final _snippet = SnippetPlayer();

  _Phase _phase = _Phase.loading;
  String? _error;

  List<Song> _pool = [];
  List<Song> _targets = [];
  List<Song> _options = [];
  int _round = 0;
  int _score = 0;
  Song? _picked;
  Duration _start = Duration.zero;
  Duration _left = _roundTime;
  Timer? _timer;
  Timer? _advance;

  /// Compteurs de fête et de secousse : ils ne servent qu'à déclencher les
  /// animations (une valeur qui change = un effet qui part).
  int _cheers = 0;
  int _shakes = 0;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _advance?.cancel();
    _snippet.dispose();
    super.dispose();
  }

  Future<void> _boot() async {
    try {
      await ref.read(audioHandlerProvider).pause();
    } catch (_) {}
    await ref.read(gameStatsProvider.notifier).ready;
    if (!mounted) return;
    if (!ref.read(gameStatsProvider).rulesSeen.contains(kBlindGame.id)) {
      await showGameRules(context, ref, kBlindGame);
      if (!mounted) return;
    }
    await _load(refresh: false);
  }

  Future<void> _load({bool refresh = true}) async {
    setState(() {
      _phase = _Phase.loading;
      _error = null;
    });
    try {
      final pool = refresh
          ? await ref.refresh(blindPoolProvider.future)
          : await ref.read(blindPoolProvider.future);
      if (!mounted) return;
      // Un titre par manche + trois leurres : il faut de quoi tirer.
      if (pool.length < 8) {
        setState(() => _phase = _Phase.empty);
        return;
      }
      _pool = pool;
      _startGame();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.empty;
        _error = '$e';
      });
    }
  }

  void _startGame() {
    final shuffled = [..._pool]..shuffle(_random);
    setState(() {
      _targets = shuffled.take(_rounds).toList();
      _round = 0;
      _score = 0;
    });
    _startRound();
  }

  void _startRound() {
    final target = _targets[_round];
    setState(() {
      _options = _buildOptions(target);
      _picked = null;
      _left = _roundTime;
      _phase = _Phase.guessing;
    });
    _start = snippetStart(target, _random);
    _snippet.playFrom(
      ref.read(libraryRepositoryProvider).streamUrl(target),
      _start,
    );
    _timer?.cancel();
    _timer = Timer.periodic(_tick, (_) {
      if (!mounted) return;
      final left = _left - _tick;
      if (left <= Duration.zero) {
        _reveal(null);
      } else {
        setState(() => _left = left);
      }
    });
  }

  /// La bonne réponse et trois leurres, titres distincts, mélangés.
  List<Song> _buildOptions(Song target) {
    final options = <Song>[target];
    final seen = <String>{target.title.toLowerCase()};
    final candidates = [..._pool]..shuffle(_random);
    // Les leurres d'un autre artiste sont préférés (moins de confusion sur
    // les albums où tous les titres se ressemblent).
    candidates.sort((a, b) {
      final aSame = a.artistName == target.artistName ? 1 : 0;
      final bSame = b.artistName == target.artistName ? 1 : 0;
      return aSame - bSame;
    });
    for (final song in candidates) {
      if (options.length >= 4) break;
      if (song.id == target.id) continue;
      if (!seen.add(song.title.toLowerCase())) continue;
      options.add(song);
    }
    return options..shuffle(_random);
  }

  void _reveal(Song? picked) {
    if (_phase != _Phase.guessing) return;
    _timer?.cancel();
    final target = _targets[_round];
    final correct = picked != null && picked.id == target.id;
    // Le verdict se sent dans la main avant même d'être lu (idée #77) : une
    // tape franche pour la bonne réponse, un coup sec pour la mauvaise.
    gameHaptic(correct ? GameFeel.good : GameFeel.bad);
    if (correct) {
      _cheers++;
    } else {
      _shakes++;
    }
    // 30 points pour la bonne réponse, jusqu'à 70 de plus pour la vitesse.
    final speed = (_left.inMilliseconds / _roundTime.inMilliseconds).clamp(
      0.0,
      1.0,
    );
    setState(() {
      _picked = picked;
      _phase = _Phase.revealed;
      if (correct) _score += 30 + (speed * 70).round();
    });
    _advance?.cancel();
    _advance = Timer(const Duration(milliseconds: 2200), _nextRound);
  }

  void _nextRound() {
    if (!mounted) return;
    if (_round + 1 >= _targets.length) {
      _finish();
      return;
    }
    setState(() => _round++);
    _startRound();
  }

  void _finish() {
    _timer?.cancel();
    _snippet.stop();
    ref.read(gameStatsProvider.notifier).submitScore(kBlindGame.id, _score);
    setState(() => _phase = _Phase.over);
  }

  @override
  Widget build(BuildContext context) {
    final best = ref.watch(gameStatsProvider).best[kBlindGame.id] ?? 0;
    final playable = _phase == _Phase.guessing || _phase == _Phase.revealed;

    return GameScaffold(
      game: kBlindGame,
      onSourceChanged: () => _load(),
      onQuit: () {
        _timer?.cancel();
        _snippet.stop();
      },
      status: !playable
          ? null
          : GameStatusBar(
              children: [
                GameStatChip(
                  label: 'Manche',
                  value: '${_round + 1}/${_targets.length}',
                ),
                GameStatChip(label: 'Score', value: '$_score'),
                GameStatChip(label: 'Record', value: '$best'),
              ],
            ),
      child: switch (_phase) {
        _Phase.loading => const Center(child: CircularProgressIndicator()),
        _Phase.empty => GameNotEnoughData(
          message: _error == null
              ? 'Bibliothèque trop petite'
              : 'Impossible de charger la partie',
          hint:
              _error ??
              'Le blind test a besoin d\'au moins huit titres pour '
                  'proposer des réponses crédibles.',
        ),
        _Phase.over => GameOverPanel(
          game: kBlindGame,
          score: _score,
          best: best,
          scoreSuffix: ' pts',
          onReplay: _load,
        ),
        _Phase.guessing || _Phase.revealed => _buildRound(),
      },
    );
  }

  Widget _buildRound() {
    final scheme = Theme.of(context).colorScheme;
    final revealed = _phase == _Phase.revealed;
    final target = _targets[_round];
    final ratio = _left.inMilliseconds / _roundTime.inMilliseconds;

    // La fête (bonne réponse) se peint par-dessus toute la manche, la secousse
    // (mauvaise) la fait encaisser en entier : c'est le jeu qui réagit, pas
    // une pastille dans un coin.
    return Celebration(
      trigger: _cheers,
      child: ShakeBox(
      trigger: _shakes,
      child: Column(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
            child: GlassBox(
              radius: 26,
              blur: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 14,
                ),
                child: Center(
                  child: SingleChildScrollView(
                    child: revealed
                        ? _buildReveal(target)
                        : _buildMystery(ratio),
                  ),
                ),
              ),
            ),
          ),
        ),
        // Les réponses vivent dans la zone du pouce : c'est là qu'on tape
        // vite, l'écran du haut ne sert qu'à écouter.
        ThumbZone(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: Column(
            children: [
              for (final option in _options)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: GameChoiceTile(
                    title: option.title,
                    subtitle: option.artistName ?? option.albumName ?? '',
                    state: !revealed
                        ? GameChoiceState.idle
                        : option.id == target.id
                        ? GameChoiceState.correct
                        : option.id == _picked?.id
                        ? GameChoiceState.wrong
                        : GameChoiceState.faded,
                    onTap: revealed ? null : () => _reveal(option),
                  ),
                ),
              if (revealed)
                Text(
                  'Manche suivante…',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
      ],
    ),
    ),
    );
  }

  Widget _buildMystery(double ratio) {
    final scheme = Theme.of(context).colorScheme;
    final left = ratio.clamp(0.0, 1.0);
    final seconds = (_left.inMilliseconds / 1000).ceil();
    return StreamBuilder<bool>(
      stream: _snippet.playingStream,
      initialData: false,
      builder: (context, snap) {
        final playing = snap.data ?? false;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Le vinyle tourne au centre du chrono : le temps qui reste fait
            // le tour de ce qu'on écoute, au lieu d'une barre posée à côté.
            CountdownRing(
              ratio: left,
              size: 168,
              child: MysteryDisc(playing: playing, size: 126),
            ),
            const SizedBox(height: 6),
            Text(
              '$seconds s',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.2,
                color: left < 0.25 ? gameBad : scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 6),
            SoundWave(playing: playing, height: 30),
            const SizedBox(height: 8),
            Text(
              'Quel est ce titre ?',
              style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.3,
                color: scheme.onSurface,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                GlassIconButton(
                  icon: Icons.replay_rounded,
                  tooltip: 'Réécouter l\'extrait',
                  onPressed: () {
                    gameHaptic(GameFeel.tap);
                    _snippet.replay(_start);
                  },
                ),
                const SizedBox(width: 14),
                GlassIconButton(
                  icon: playing
                      ? Icons.pause_rounded
                      : Icons.play_arrow_rounded,
                  tooltip: playing ? 'Pause' : 'Écouter',
                  size: 52,
                  onPressed: () {
                    gameHaptic(GameFeel.tap);
                    _snippet.toggle();
                  },
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _buildReveal(Song target) {
    final scheme = Theme.of(context).colorScheme;
    final correct = _picked?.id == target.id;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GameVerdict(
          correct: correct,
          text: correct
              ? 'Bien vu !'
              : _picked == null
              ? 'Temps écoulé'
              : 'Raté',
        ),
        const SizedBox(height: 12),
        // La pochette se retourne pour se montrer : la réponse s'ouvre, elle
        // n'apparaît pas.
        FlipReveal(
          size: 104,
          child: Artwork(url: target.artworkUrl, size: 104, borderRadius: 18),
        ),
        const SizedBox(height: 10),
        Text(
          target.title,
          maxLines: 2,
          textAlign: TextAlign.center,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        Text(
          target.artistName ?? '',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }
}
