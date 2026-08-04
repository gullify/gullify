import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/game_track.dart';
import '../../state/games.dart';
import '../../widgets/artwork.dart';
import '../../widgets/glass_box.dart';
import 'game_kit.dart';

/// « Duel d'années » : deux albums s'affrontent, le joueur désigne le plus
/// ancien. Une erreur et la série s'arrête.
class DuelGameScreen extends ConsumerStatefulWidget {
  const DuelGameScreen({super.key});

  @override
  ConsumerState<DuelGameScreen> createState() => _DuelGameScreenState();
}

enum _Phase { loading, empty, choosing, revealed, over }

class _DuelGameScreenState extends ConsumerState<DuelGameScreen> {
  final _random = math.Random();

  _Phase _phase = _Phase.loading;
  String? _error;

  List<GameTrack> _deck = [];
  GameTrack? _left;
  GameTrack? _right;
  GameTrack? _picked;
  int _streak = 0;
  bool _exhausted = false;
  Timer? _advance;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  @override
  void dispose() {
    _advance?.cancel();
    super.dispose();
  }

  Future<void> _boot() async {
    await ref.read(gameStatsProvider.notifier).ready;
    if (!mounted) return;
    if (!ref.read(gameStatsProvider).rulesSeen.contains(kDuelGame.id)) {
      await showGameRules(context, ref, kDuelGame);
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
      // Sans deux millésimes différents, aucun duel n'est jouable.
      final years = {for (final t in pool.tracks) t.year};
      if (pool.tracks.length < 4 || years.length < 2) {
        setState(() => _phase = _Phase.empty);
        return;
      }
      _startGame(pool.tracks);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.empty;
        _error = '$e';
      });
    }
  }

  void _startGame(List<GameTrack> tracks) {
    _deck = [...tracks]..shuffle(_random);
    _streak = 0;
    _exhausted = false;
    final first = _deck.removeLast();
    final second = _drawAgainst(first);
    if (second == null) {
      setState(() => _phase = _Phase.empty);
      return;
    }
    setState(() {
      _left = first;
      _right = second;
      _picked = null;
      _phase = _Phase.choosing;
    });
  }

  /// Tire un adversaire d'une autre année : sans ça le duel serait indécidable.
  GameTrack? _drawAgainst(GameTrack champion) {
    final skipped = <GameTrack>[];
    GameTrack? found;
    while (_deck.isNotEmpty) {
      final candidate = _deck.removeLast();
      if (candidate.year != champion.year) {
        found = candidate;
        break;
      }
      skipped.add(candidate);
    }
    // Les écartés retournent au fond du paquet (ils pourront servir plus tard).
    _deck.insertAll(0, skipped);
    return found;
  }

  void _choose(GameTrack pick) {
    if (_phase != _Phase.choosing) return;
    final left = _left!;
    final right = _right!;
    final oldest = left.year <= right.year ? left : right;
    final correct = pick.year == oldest.year;
    setState(() {
      _picked = pick;
      _phase = _Phase.revealed;
      if (correct) _streak++;
    });
    _advance?.cancel();
    _advance = Timer(
      const Duration(milliseconds: 1600),
      correct ? _nextDuel : _finish,
    );
  }

  void _nextDuel() {
    if (!mounted) return;
    final champion = _right!;
    final challenger = _drawAgainst(champion);
    if (challenger == null) {
      _exhausted = true;
      _finish();
      return;
    }
    setState(() {
      _left = champion;
      _right = challenger;
      _picked = null;
      _phase = _Phase.choosing;
    });
  }

  void _finish() {
    if (!mounted) return;
    ref.read(gameStatsProvider.notifier).submitScore(kDuelGame.id, _streak);
    setState(() => _phase = _Phase.over);
  }

  @override
  Widget build(BuildContext context) {
    final best = ref.watch(gameStatsProvider).best[kDuelGame.id] ?? 0;
    final playable = _phase == _Phase.choosing || _phase == _Phase.revealed;

    return GameScaffold(
      game: kDuelGame,
      onSourceChanged: () => _load(),
      status: !playable
          ? null
          : GameStatusBar(
              children: [
                GameStatChip(label: 'Série', value: '$_streak'),
                GameStatChip(label: 'Record', value: '$best'),
              ],
            ),
      child: switch (_phase) {
        _Phase.loading => const Center(child: CircularProgressIndicator()),
        _Phase.empty => GameNotEnoughData(
          message: _error == null
              ? 'Pas assez d\'albums datés'
              : 'Impossible de charger la partie',
          hint:
              _error ??
              'Le duel a besoin d\'albums qui portent une année et une '
                  'pochette, avec au moins deux millésimes différents.',
        ),
        _Phase.over => GameOverPanel(
          game: kDuelGame,
          score: _streak,
          best: best,
          scoreSuffix: _streak > 1 ? ' duels' : ' duel',
          headline: _exhausted ? 'Bibliothèque épuisée !' : null,
          onReplay: _load,
        ),
        _Phase.choosing || _Phase.revealed => _buildDuel(),
      },
    );
  }

  Widget _buildDuel() {
    final scheme = Theme.of(context).colorScheme;
    final revealed = _phase == _Phase.revealed;
    final left = _left!;
    final right = _right!;
    final oldest = left.year <= right.year ? left : right;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 2),
          child: Text(
            'Lequel est le plus ancien ?',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: scheme.primary,
            ),
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
            child: Column(
              children: [
                Expanded(
                  child: _DuelCard(
                    track: left,
                    revealed: revealed,
                    winner: revealed && oldest == left,
                    picked: _picked == left,
                    onTap: () => _choose(left),
                  ),
                ),
                // Le « VS » sépare les deux prétendants.
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: scheme.primary.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      'VS',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1,
                        color: scheme.primary,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: _DuelCard(
                    track: right,
                    revealed: revealed,
                    winner: revealed && oldest == right,
                    picked: _picked == right,
                    onTap: () => _choose(right),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Un prétendant du duel : pochette, album, artiste — et l'année une fois
/// la manche jouée.
class _DuelCard extends StatelessWidget {
  const _DuelCard({
    required this.track,
    required this.revealed,
    required this.winner,
    required this.picked,
    required this.onTap,
  });

  final GameTrack track;
  final bool revealed;

  /// Vrai si c'est le plus ancien des deux (la bonne réponse).
  final bool winner;

  /// Vrai si le joueur a désigné cette carte.
  final bool picked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = !revealed
        ? null
        : picked
        ? (winner ? const Color(0xFF2FA36B) : const Color(0xFFE5484D))
        : (winner ? const Color(0xFF2FA36B) : null);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        border: color == null
            ? null
            : Border.all(color: color.withValues(alpha: 0.9), width: 2),
      ),
      child: GlassBox(
        radius: 22,
        blur: false,
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: revealed ? null : onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Artwork(url: track.song.artworkUrl, size: 86, borderRadius: 16),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        track.song.albumName ?? track.song.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.3,
                          height: 1.15,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        track.song.artistName ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 6),
                      AnimatedOpacity(
                        duration: const Duration(milliseconds: 250),
                        opacity: revealed ? 1 : 0,
                        child: Text(
                          '${track.year}',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.8,
                            height: 1,
                            color: color ?? scheme.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (!revealed)
                  Icon(
                    Icons.touch_app_rounded,
                    color: scheme.onSurfaceVariant.withValues(alpha: 0.6),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
