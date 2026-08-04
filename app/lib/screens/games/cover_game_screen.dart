import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/album.dart';
import '../../state/games.dart';
import '../../widgets/artwork.dart';
import 'game_kit.dart';

/// « Pochette mystère » : une pochette très floue se précise seconde après
/// seconde. Plus on la reconnaît tôt, plus on marque.
class CoverGameScreen extends ConsumerStatefulWidget {
  const CoverGameScreen({super.key});

  @override
  ConsumerState<CoverGameScreen> createState() => _CoverGameScreenState();
}

enum _Phase { loading, empty, guessing, revealed, over }

class _CoverGameScreenState extends ConsumerState<CoverGameScreen> {
  static const _rounds = 8;
  static const _roundTime = Duration(seconds: 15);
  static const _tick = Duration(milliseconds: 100);
  static const _maxBlur = 22.0;
  static const _minBlur = 1.2;

  final _random = math.Random();

  _Phase _phase = _Phase.loading;
  String? _error;

  List<Album> _pool = [];
  List<Album> _targets = [];
  List<Album> _options = [];
  int _round = 0;
  int _score = 0;
  Album? _picked;
  Duration _left = _roundTime;
  Timer? _timer;
  Timer? _advance;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _advance?.cancel();
    super.dispose();
  }

  Future<void> _boot() async {
    await ref.read(gameStatsProvider.notifier).ready;
    if (!mounted) return;
    if (!ref.read(gameStatsProvider).rulesSeen.contains(kCoverGame.id)) {
      await showGameRules(context, ref, kCoverGame);
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
          ? await ref.refresh(gamePoolProvider.future)
          : await ref.read(gamePoolProvider.future);
      if (!mounted) return;
      if (pool.albums.length < 8) {
        setState(() => _phase = _Phase.empty);
        return;
      }
      _pool = pool.albums;
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

  List<Album> _buildOptions(Album target) {
    final options = <Album>[target];
    final seen = <String>{target.name.toLowerCase()};
    final candidates = [..._pool]..shuffle(_random);
    for (final album in candidates) {
      if (options.length >= 4) break;
      if (album.id == target.id) continue;
      if (!seen.add(album.name.toLowerCase())) continue;
      options.add(album);
    }
    return options..shuffle(_random);
  }

  void _reveal(Album? picked) {
    if (_phase != _Phase.guessing) return;
    _timer?.cancel();
    final target = _targets[_round];
    final correct = picked != null && picked.id == target.id;
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
    ref.read(gameStatsProvider.notifier).submitScore(kCoverGame.id, _score);
    setState(() => _phase = _Phase.over);
  }

  @override
  Widget build(BuildContext context) {
    final best = ref.watch(gameStatsProvider).best[kCoverGame.id] ?? 0;
    final playable = _phase == _Phase.guessing || _phase == _Phase.revealed;

    return GameScaffold(
      game: kCoverGame,
      onQuit: () => _timer?.cancel(),
      onSourceChanged: () => _load(),
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
              ? 'Pas assez de pochettes'
              : 'Impossible de charger la partie',
          hint:
              _error ??
              'Il faut au moins huit albums avec une pochette. Un scan de '
                  'la bibliothèque peut en récupérer davantage.',
        ),
        _Phase.over => GameOverPanel(
          game: kCoverGame,
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
    final ratio = (_left.inMilliseconds / _roundTime.inMilliseconds).clamp(
      0.0,
      1.0,
    );
    final blur = revealed ? 0.0 : _minBlur + (_maxBlur - _minBlur) * ratio;
    final correct = _picked?.id == target.id;

    return Column(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
            child: Center(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // La pochette, nette seulement à la révélation. Le clip
                    // évite que le flou ne bave hors du cadre.
                    ClipRRect(
                      borderRadius: BorderRadius.circular(22),
                      child: SizedBox(
                        width: 196,
                        height: 196,
                        child: blur > 0
                            ? ImageFiltered(
                                imageFilter: ImageFilter.blur(
                                  sigmaX: blur,
                                  sigmaY: blur,
                                  tileMode: TileMode.decal,
                                ),
                                child: Artwork(
                                  url: target.artworkUrl,
                                  size: 196,
                                  borderRadius: 0,
                                ),
                              )
                            : Artwork(
                                url: target.artworkUrl,
                                size: 196,
                                borderRadius: 0,
                              ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (revealed) ...[
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            correct
                                ? Icons.check_circle_rounded
                                : Icons.cancel_rounded,
                            size: 20,
                            color: correct
                                ? const Color(0xFF2FA36B)
                                : const Color(0xFFE5484D),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            correct
                                ? 'Bien vu !'
                                : _picked == null
                                ? 'Temps écoulé'
                                : 'Raté',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: correct
                                  ? const Color(0xFF2FA36B)
                                  : const Color(0xFFE5484D),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        target.name,
                        maxLines: 2,
                        textAlign: TextAlign.center,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        [
                          target.artistName ?? '',
                          if (target.year != null) '${target.year}',
                        ].where((s) => s.isNotEmpty).join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ] else ...[
                      SizedBox(
                        width: 196,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: LinearProgressIndicator(
                            value: ratio,
                            minHeight: 7,
                            backgroundColor: scheme.onSurface.withValues(
                              alpha: 0.08,
                            ),
                            color: ratio < 0.25
                                ? const Color(0xFFE5484D)
                                : scheme.primary,
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Quel album se cache là-dessous ?',
                        style: TextStyle(
                          fontSize: 13.5,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: Column(
            children: [
              for (final option in _options)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: GameChoiceTile(
                    title: option.name,
                    subtitle: option.artistName ?? '',
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
            ],
          ),
        ),
      ],
    );
  }
}
