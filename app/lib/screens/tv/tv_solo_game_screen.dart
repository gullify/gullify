import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../api/library_repository.dart';
import '../../models/album.dart';
import '../../models/game_track.dart';
import '../../models/song.dart';
import '../../state/games.dart';
import '../../state/library.dart';
import '../../state/player.dart';
import '../../state/playlists.dart';
import '../games/game_fx.dart';
import '../games/game_kit.dart';
import 'tv_kit.dart';

/// Les jeux, en solo, sur le téléviseur.
///
/// Mêmes règles, mêmes barèmes et mêmes records que sur téléphone — c'est le
/// même `gameStatsProvider` qui les garde : battre son score au salon compte
/// aussi dans la poche. Seule la manœuvre change : tout se vise à la croix
/// directionnelle et se valide avec « OK ».
class TvSoloGameScreen extends ConsumerWidget {
  const TvSoloGameScreen({super.key, required this.gameId});

  final String gameId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final game = gameById(gameId);
    if (game == null) {
      return const TvScaffold(
        child: TvEmpty(
          message: 'Jeu inconnu',
          icon: Icons.help_outline_rounded,
        ),
      );
    }
    return switch (gameId) {
      'blind' => _BlindGame(game: game),
      'cover' => _CoverGame(game: game),
      'duel' => _DuelGame(game: game),
      'chrono' => _ChronoGame(game: game),
      'swipe' => _SwipeGame(game: game),
      _ => TvScaffold(
        child: TvEmpty(
          message: '${game.name} n\'est pas encore jouable ici',
          hint: 'Il reste disponible dans l\'app mobile.',
          icon: game.icon,
        ),
      ),
    };
  }
}

/// Coque commune : titre, pastilles d'état, et le plateau.
class _GameFrame extends StatelessWidget {
  const _GameFrame({
    required this.game,
    required this.child,
    this.stats = const [],
    this.hints = const [],
  });

  final GameInfo game;
  final Widget child;
  final List<Widget> stats;
  final List<(String, String)> hints;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return TvScaffold(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(game.icon, size: 34, color: scheme.primary),
              const SizedBox(width: 14),
              Expanded(child: TvTitle(game.name, size: 40)),
              ...stats,
            ],
          ),
          const SizedBox(height: 18),
          Expanded(child: child),
          if (hints.isNotEmpty) ...[
            const SizedBox(height: 10),
            TvKeyHints(hints: hints),
          ],
        ],
      ),
    );
  }
}

/// Pastille d'état : libellé discret, valeur en gras.
class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, this.child});

  final String label;
  final String value;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(left: 12),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label.toUpperCase(),
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 2),
          child ??
              Text(
                value,
                style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.4,
                ),
              ),
        ],
      ),
    );
  }
}

/// Fin de partie : score, record, rejouer.
class _GameOver extends ConsumerWidget {
  const _GameOver({
    required this.game,
    required this.score,
    required this.onReplay,
    this.headline,
    this.suffix,
  });

  final GameInfo game;
  final int score;
  final VoidCallback onReplay;
  final String? headline;
  final String? suffix;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final best = ref.watch(gameStatsProvider).best[game.id] ?? 0;
    final record = score >= best && score > 0;
    return Center(
      child: SizedBox(
        width: 620,
        child: TvGlass(
          padding: const EdgeInsets.fromLTRB(40, 34, 40, 30),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                record ? Icons.emoji_events_rounded : game.icon,
                size: 52,
                color: record ? const Color(0xFFE3A94F) : scheme.primary,
              ),
              const SizedBox(height: 12),
              Text(
                headline ?? (record ? 'Nouveau record !' : 'Partie terminée'),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.8,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                '$score${suffix ?? ''}',
                style: TextStyle(
                  fontSize: 62,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -2,
                  color: scheme.primary,
                ),
              ),
              Text(
                '${game.scoreLabel} : ${math.max(best, score)}',
                style: TextStyle(fontSize: 20, color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 22),
              TvPill(
                label: 'Rejouer',
                icon: Icons.refresh_rounded,
                autofocus: true,
                expand: true,
                compact: true,
                onPressed: onReplay,
              ),
              const SizedBox(height: 10),
              TvPill(
                label: 'Retour aux jeux',
                accent: false,
                expand: true,
                compact: true,
                onPressed: () => context.pop(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Une proposition de réponse, visable à la croix.
class _Choice extends StatelessWidget {
  const _Choice({
    required this.title,
    required this.subtitle,
    required this.state,
    required this.onPressed,
    this.autofocus = false,
  });

  final String title;
  final String subtitle;
  final GameChoiceState state;
  final VoidCallback? onPressed;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final verdict = switch (state) {
      GameChoiceState.correct => TvDot.ok,
      GameChoiceState.wrong => TvDot.ko,
      GameChoiceState.idle || GameChoiceState.faded => null,
    };
    return Opacity(
      opacity: state == GameChoiceState.faded ? 0.45 : 1,
      child: TvFocusable(
        onPressed: onPressed,
        autofocus: autofocus,
        scale: 1.0,
        builder: (context, focused) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          decoration: BoxDecoration(
            color:
                verdict?.withValues(alpha: 0.18) ??
                Colors.white.withValues(alpha: focused ? 0.12 : 0.06),
            borderRadius: BorderRadius.circular(18),
            border: focused
                ? tvFocusBorder(scheme.primary)
                : Border.all(
                    color: verdict ?? Colors.white.withValues(alpha: 0.14),
                    width: verdict != null ? 2 : 1,
                  ),
            boxShadow: focused ? tvFocusGlow(scheme.primary, spread: 4) : null,
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 26,
                        height: 1.15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (subtitle.isNotEmpty)
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 19,
                          height: 1.2,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
              if (verdict != null)
                Icon(
                  state == GameChoiceState.correct
                      ? Icons.check_circle_rounded
                      : Icons.cancel_rounded,
                  color: verdict,
                  size: 30,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Le chrono d'une manche.
class _RoundBar extends StatelessWidget {
  const _RoundBar({required this.ratio, required this.seconds});

  final double ratio;
  final int seconds;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: ratio,
            minHeight: 10,
            backgroundColor: scheme.onSurface.withValues(alpha: 0.08),
            color: ratio < 0.25 ? TvDot.ko : scheme.primary,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '$seconds s',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: scheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

// ────────────────────────────────────────────────────────────── blind test ──

class _BlindGame extends ConsumerStatefulWidget {
  const _BlindGame({required this.game});

  final GameInfo game;

  @override
  ConsumerState<_BlindGame> createState() => _BlindGameState();
}

enum _Phase { loading, empty, playing, revealed, over }

class _BlindGameState extends ConsumerState<_BlindGame> {
  static const _rounds = 10;
  static const _roundTime = Duration(seconds: 15);
  static const _tick = Duration(milliseconds: 100);

  final _random = math.Random();
  final _snippet = SnippetPlayer();

  _Phase _phase = _Phase.loading;
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
    await _load(refresh: false);
  }

  Future<void> _load({bool refresh = true}) async {
    setState(() => _phase = _Phase.loading);
    try {
      final pool = refresh
          ? await ref.refresh(blindPoolProvider.future)
          : await ref.read(blindPoolProvider.future);
      if (!mounted) return;
      if (pool.length < 8) {
        setState(() => _phase = _Phase.empty);
        return;
      }
      _pool = pool;
      final shuffled = [..._pool]..shuffle(_random);
      setState(() {
        _targets = shuffled.take(_rounds).toList();
        _round = 0;
        _score = 0;
      });
      _startRound();
    } catch (_) {
      if (mounted) setState(() => _phase = _Phase.empty);
    }
  }

  void _startRound() {
    final target = _targets[_round];
    setState(() {
      _options = _buildOptions(target);
      _picked = null;
      _left = _roundTime;
      _phase = _Phase.playing;
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

  /// La bonne réponse et trois leurres, titres distincts, mélangés. Les
  /// leurres d'un autre artiste sont préférés : sur un même album, tous les
  /// titres se ressemblent.
  List<Song> _buildOptions(Song target) {
    final options = <Song>[target];
    final seen = <String>{target.title.toLowerCase()};
    final candidates = [..._pool]..shuffle(_random);
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
    if (_phase != _Phase.playing) return;
    _timer?.cancel();
    final target = _targets[_round];
    final correct = picked != null && picked.id == target.id;
    // 30 points pour la bonne réponse, jusqu'à 70 de plus pour la vitesse —
    // même barème que sur téléphone.
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
    _advance = Timer(const Duration(milliseconds: 2200), _next);
  }

  void _next() {
    if (!mounted) return;
    if (_round + 1 >= _targets.length) {
      _timer?.cancel();
      _snippet.stop();
      ref.read(gameStatsProvider.notifier).submitScore(widget.game.id, _score);
      setState(() => _phase = _Phase.over);
      return;
    }
    setState(() => _round++);
    _startRound();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final best = ref.watch(gameStatsProvider).best[widget.game.id] ?? 0;
    final playing = _phase == _Phase.playing || _phase == _Phase.revealed;
    final target = _targets.isEmpty ? null : _targets[_round];

    return _GameFrame(
      game: widget.game,
      stats: !playing
          ? const []
          : [
              _Stat(label: 'Manche', value: '${_round + 1}/${_targets.length}'),
              _Stat(label: 'Score', value: '$_score'),
              _Stat(label: 'Record', value: '$best'),
            ],
      hints: playing
          ? const [('OK', 'Répondre'), ('Retour', 'Quitter')]
          : const [],
      child: switch (_phase) {
        _Phase.loading => const Center(child: CircularProgressIndicator()),
        _Phase.empty => const TvEmpty(
          message: 'Bibliothèque trop petite',
          hint: 'Le blind test a besoin d\'au moins huit titres.',
          icon: Icons.headphones_rounded,
        ),
        _Phase.over => _GameOver(
          game: widget.game,
          score: _score,
          suffix: ' pts',
          onReplay: _load,
        ),
        _Phase.playing || _Phase.revealed => Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 520,
              child: _phase == _Phase.revealed
                  ? _Reveal(
                      song: target!,
                      correct: _picked?.id == target.id,
                      answered: _picked != null,
                    )
                  : Column(
                      children: [
                        const SizedBox(height: 30),
                        MysteryDisc(playing: true, size: 240),
                        const SizedBox(height: 26),
                        Text(
                          'Quel est ce titre ?',
                          style: TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.6,
                            color: scheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 22),
                        _RoundBar(
                          ratio:
                              _left.inMilliseconds / _roundTime.inMilliseconds,
                          seconds: (_left.inMilliseconds / 1000).ceil(),
                        ),
                      ],
                    ),
            ),
            const SizedBox(width: 50),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < _options.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _Choice(
                        title: _options[i].title,
                        subtitle: _options[i].artistName ?? '',
                        autofocus: i == 0,
                        state: _phase != _Phase.revealed
                            ? GameChoiceState.idle
                            : _options[i].id == target!.id
                            ? GameChoiceState.correct
                            : _options[i].id == _picked?.id
                            ? GameChoiceState.wrong
                            : GameChoiceState.faded,
                        onPressed: _phase == _Phase.revealed
                            ? null
                            : () => _reveal(_options[i]),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      },
    );
  }
}

/// Le titre dévoilé, avec le verdict.
class _Reveal extends StatelessWidget {
  const _Reveal({
    required this.song,
    required this.correct,
    required this.answered,
  });

  final Song song;
  final bool correct;
  final bool answered;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = correct ? TvDot.ok : TvDot.ko;
    return Column(
      children: [
        const SizedBox(height: 20),
        TvArtwork(url: song.artworkUrl, size: 240, borderRadius: 24),
        const SizedBox(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              correct ? Icons.check_circle_rounded : Icons.cancel_rounded,
              color: color,
              size: 30,
            ),
            const SizedBox(width: 10),
            Text(
              correct ? 'Bien vu !' : (answered ? 'Raté' : 'Temps écoulé'),
              style: TextStyle(
                fontSize: 30,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          song.title,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700),
        ),
        Text(
          song.artistName ?? '',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 21, color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

// ────────────────────────────────────────────────────────── pochette mystère ──

class _CoverGame extends ConsumerStatefulWidget {
  const _CoverGame({required this.game});

  final GameInfo game;

  @override
  ConsumerState<_CoverGame> createState() => _CoverGameState();
}

class _CoverGameState extends ConsumerState<_CoverGame> {
  static const _rounds = 8;
  static const _roundTime = Duration(seconds: 15);
  static const _tick = Duration(milliseconds: 100);
  static const _maxBlur = 22.0;
  static const _minBlur = 1.2;

  final _random = math.Random();

  _Phase _phase = _Phase.loading;
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
    _load(refresh: false);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _advance?.cancel();
    super.dispose();
  }

  Future<void> _load({bool refresh = true}) async {
    setState(() => _phase = _Phase.loading);
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
      final shuffled = [..._pool]..shuffle(_random);
      setState(() {
        _targets = shuffled.take(_rounds).toList();
        _round = 0;
        _score = 0;
      });
      _startRound();
    } catch (_) {
      if (mounted) setState(() => _phase = _Phase.empty);
    }
  }

  void _startRound() {
    final target = _targets[_round];
    final options = <Album>[target];
    final seen = <String>{target.name.toLowerCase()};
    final candidates = [..._pool]..shuffle(_random);
    for (final album in candidates) {
      if (options.length >= 4) break;
      if (album.id == target.id) continue;
      if (!seen.add(album.name.toLowerCase())) continue;
      options.add(album);
    }
    setState(() {
      _options = options..shuffle(_random);
      _picked = null;
      _left = _roundTime;
      _phase = _Phase.playing;
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

  void _reveal(Album? picked) {
    if (_phase != _Phase.playing) return;
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
    _advance = Timer(const Duration(milliseconds: 2200), _next);
  }

  void _next() {
    if (!mounted) return;
    if (_round + 1 >= _targets.length) {
      ref.read(gameStatsProvider.notifier).submitScore(widget.game.id, _score);
      setState(() => _phase = _Phase.over);
      return;
    }
    setState(() => _round++);
    _startRound();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final best = ref.watch(gameStatsProvider).best[widget.game.id] ?? 0;
    final playing = _phase == _Phase.playing || _phase == _Phase.revealed;
    final target = _targets.isEmpty ? null : _targets[_round];
    final ratio = _left.inMilliseconds / _roundTime.inMilliseconds;
    // La pochette se précise seconde après seconde.
    final blur = _phase == _Phase.revealed
        ? 0.0
        : _minBlur + (_maxBlur - _minBlur) * ratio;

    return _GameFrame(
      game: widget.game,
      stats: !playing
          ? const []
          : [
              _Stat(label: 'Manche', value: '${_round + 1}/${_targets.length}'),
              _Stat(label: 'Score', value: '$_score'),
              _Stat(label: 'Record', value: '$best'),
            ],
      hints: playing
          ? const [('OK', 'Répondre'), ('Retour', 'Quitter')]
          : const [],
      child: switch (_phase) {
        _Phase.loading => const Center(child: CircularProgressIndicator()),
        _Phase.empty => const TvEmpty(
          message: 'Bibliothèque trop petite',
          hint: 'Il faut au moins huit albums pochettés.',
          icon: Icons.image_search_rounded,
        ),
        _Phase.over => _GameOver(
          game: widget.game,
          score: _score,
          suffix: ' pts',
          onReplay: _load,
        ),
        _Phase.playing || _Phase.revealed => Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 520,
              child: Column(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: SizedBox(
                      width: 340,
                      height: 340,
                      child: blur <= 0.02
                          ? TvArtwork(
                              url: target!.artworkUrl,
                              size: 340,
                              borderRadius: 0,
                            )
                          : ImageFiltered(
                              imageFilter: ImageFilter.blur(
                                sigmaX: blur,
                                sigmaY: blur,
                                tileMode: TileMode.decal,
                              ),
                              child: TvArtwork(
                                url: target!.artworkUrl,
                                size: 340,
                                borderRadius: 0,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(height: 22),
                  if (_phase == _Phase.revealed) ...[
                    Text(
                      _picked?.id == target.id
                          ? 'Bien vu !'
                          : (_picked == null ? 'Temps écoulé' : 'Raté'),
                      style: TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w800,
                        color: _picked?.id == target.id ? TvDot.ok : TvDot.ko,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      target.name,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      target.artistName ?? '',
                      style: TextStyle(
                        fontSize: 21,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ] else ...[
                    Text(
                      'Quel est cet album ?',
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.6,
                        color: scheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 18),
                    _RoundBar(
                      ratio: ratio,
                      seconds: (_left.inMilliseconds / 1000).ceil(),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 50),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < _options.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _Choice(
                        title: _options[i].name,
                        subtitle: _options[i].artistName ?? '',
                        autofocus: i == 0,
                        state: _phase != _Phase.revealed
                            ? GameChoiceState.idle
                            : _options[i].id == target.id
                            ? GameChoiceState.correct
                            : _options[i].id == _picked?.id
                            ? GameChoiceState.wrong
                            : GameChoiceState.faded,
                        onPressed: _phase == _Phase.revealed
                            ? null
                            : () => _reveal(_options[i]),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      },
    );
  }
}

// ────────────────────────────────────────────────────────────── duel d'années ──

class _DuelGame extends ConsumerStatefulWidget {
  const _DuelGame({required this.game});

  final GameInfo game;

  @override
  ConsumerState<_DuelGame> createState() => _DuelGameState();
}

class _DuelGameState extends ConsumerState<_DuelGame> {
  final _random = math.Random();

  _Phase _phase = _Phase.loading;
  List<GameTrack> _deck = [];
  GameTrack? _left;
  GameTrack? _right;
  GameTrack? _picked;
  int _streak = 0;
  Timer? _advance;

  @override
  void initState() {
    super.initState();
    _load(refresh: false);
  }

  @override
  void dispose() {
    _advance?.cancel();
    super.dispose();
  }

  Future<void> _load({bool refresh = true}) async {
    setState(() => _phase = _Phase.loading);
    try {
      final pool = refresh
          ? await ref.refresh(gamePoolProvider.future)
          : await ref.read(gamePoolProvider.future);
      if (!mounted) return;
      final years = {for (final t in pool.tracks) t.year};
      if (pool.tracks.length < 4 || years.length < 2) {
        setState(() => _phase = _Phase.empty);
        return;
      }
      _deck = [...pool.tracks]..shuffle(_random);
      _streak = 0;
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
        _phase = _Phase.playing;
      });
    } catch (_) {
      if (mounted) setState(() => _phase = _Phase.empty);
    }
  }

  /// Un adversaire d'une autre année : sans ça le duel serait indécidable.
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
    _deck.insertAll(0, skipped);
    return found;
  }

  void _choose(GameTrack pick) {
    if (_phase != _Phase.playing) return;
    final oldest = _left!.year <= _right!.year ? _left! : _right!;
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
      _finish();
      return;
    }
    setState(() {
      _left = champion;
      _right = challenger;
      _picked = null;
      _phase = _Phase.playing;
    });
  }

  void _finish() {
    if (!mounted) return;
    ref.read(gameStatsProvider.notifier).submitScore(widget.game.id, _streak);
    setState(() => _phase = _Phase.over);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final best = ref.watch(gameStatsProvider).best[widget.game.id] ?? 0;
    final playing = _phase == _Phase.playing || _phase == _Phase.revealed;

    return _GameFrame(
      game: widget.game,
      stats: !playing
          ? const []
          : [
              _Stat(label: 'Série', value: '$_streak'),
              _Stat(label: 'Record', value: '$best'),
            ],
      hints: playing
          ? const [('← →', 'Choisir'), ('OK', 'Valider'), ('Retour', 'Quitter')]
          : const [],
      child: switch (_phase) {
        _Phase.loading => const Center(child: CircularProgressIndicator()),
        _Phase.empty => const TvEmpty(
          message: 'Pas assez d\'albums datés',
          hint: 'Le duel a besoin de deux millésimes différents.',
          icon: Icons.compare_arrows_rounded,
        ),
        _Phase.over => _GameOver(
          game: widget.game,
          score: _streak,
          headline: 'Série interrompue',
          onReplay: _load,
        ),
        _Phase.playing || _Phase.revealed => Column(
          children: [
            Text(
              'Lequel est le plus ancien ?',
              style: TextStyle(
                fontSize: 34,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.8,
                color: scheme.onSurface,
              ),
            ),
            const SizedBox(height: 24),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _DuelCard(track: _left!, state: this, first: true),
                  ),
                  const SizedBox(width: 30),
                  Expanded(
                    child: _DuelCard(track: _right!, state: this, first: false),
                  ),
                ],
              ),
            ),
          ],
        ),
      },
    );
  }
}

class _DuelCard extends StatelessWidget {
  const _DuelCard({
    required this.track,
    required this.state,
    required this.first,
  });

  final GameTrack track;
  final _DuelGameState state;
  final bool first;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final revealed = state._phase == _Phase.revealed;
    final oldest = state._left!.year <= state._right!.year
        ? state._left!
        : state._right!;
    final isOldest = track.year == oldest.year;
    final picked = state._picked == track;
    final verdict = !revealed
        ? null
        : isOldest
        ? TvDot.ok
        : (picked ? TvDot.ko : null);

    return Opacity(
      opacity: revealed && !isOldest && !picked ? 0.5 : 1,
      child: TvFocusable(
        autofocus: first,
        onPressed: revealed ? null : () => state._choose(track),
        scale: 1.0,
        builder: (context, focused) => Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color:
                verdict?.withValues(alpha: 0.16) ??
                Colors.white.withValues(alpha: focused ? 0.12 : 0.06),
            borderRadius: BorderRadius.circular(26),
            border: focused
                ? tvFocusBorder(scheme.primary)
                : Border.all(
                    color: verdict ?? Colors.white.withValues(alpha: 0.14),
                    width: verdict != null ? 2.5 : 1,
                  ),
            boxShadow: focused ? tvFocusGlow(scheme.primary, spread: 4) : null,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TvArtwork(
                url: track.song.artworkUrl,
                size: 250,
                borderRadius: 20,
              ),
              const SizedBox(height: 16),
              Text(
                track.song.albumName ?? track.song.title,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 26,
                  height: 1.2,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                track.song.artistName ?? '',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 21, color: scheme.onSurfaceVariant),
              ),
              if (revealed) ...[
                const SizedBox(height: 12),
                Text(
                  '${track.year}',
                  style: TextStyle(
                    fontSize: 46,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -1.2,
                    color: verdict ?? scheme.primary,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────── chrono ──

class _ChronoGame extends ConsumerStatefulWidget {
  const _ChronoGame({required this.game});

  final GameInfo game;

  @override
  ConsumerState<_ChronoGame> createState() => _ChronoGameState();
}

class _ChronoGameState extends ConsumerState<_ChronoGame> {
  static const _maxLives = 3;

  final _random = math.Random();
  final _snippet = SnippetPlayer();
  final _scroll = ScrollController();

  _Phase _phase = _Phase.loading;
  List<GameTrack> _deck = [];
  List<GameTrack> _timeline = [];
  GameTrack? _current;
  Duration _start = Duration.zero;
  int _lives = _maxLives;
  int _score = 0;
  int? _lastGap;
  bool? _lastCorrect;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  @override
  void dispose() {
    _snippet.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _boot() async {
    try {
      await ref.read(audioHandlerProvider).pause();
    } catch (_) {}
    await _load(refresh: false);
  }

  Future<void> _load({bool refresh = true}) async {
    setState(() => _phase = _Phase.loading);
    try {
      final pool = refresh
          ? await ref.refresh(gamePoolProvider.future)
          : await ref.read(gamePoolProvider.future);
      if (!mounted) return;
      if (pool.tracks.length < 6) {
        setState(() => _phase = _Phase.empty);
        return;
      }
      final deck = [...pool.tracks]..shuffle(_random);
      setState(() {
        _timeline = [deck.removeLast()];
        _deck = deck;
        _lives = _maxLives;
        _score = 0;
      });
      _draw();
    } catch (_) {
      if (mounted) setState(() => _phase = _Phase.empty);
    }
  }

  void _draw() {
    if (_deck.isEmpty) {
      _finish();
      return;
    }
    final track = _deck.removeLast();
    setState(() {
      _current = track;
      _lastGap = null;
      _lastCorrect = null;
      _phase = _Phase.playing;
    });
    _start = snippetStart(track.song, _random);
    _snippet.playFrom(
      ref.read(libraryRepositoryProvider).streamUrl(track.song),
      _start,
    );
  }

  void _place(int gap) {
    final track = _current;
    if (track == null || _phase != _Phase.playing) return;
    final years = [for (final t in _timeline) t.year];
    final correct = chronoPlacementIsCorrect(years, gap, track.year);
    setState(() {
      _lastGap = gap;
      _lastCorrect = correct;
      _phase = _Phase.revealed;
      if (correct) {
        _timeline.insert(gap, track);
        _score++;
      } else {
        _lives--;
      }
    });
  }

  void _skip() {
    if (_phase != _Phase.playing) return;
    setState(() {
      _lastGap = null;
      _lastCorrect = null;
      _phase = _Phase.revealed;
    });
  }

  void _continue() {
    if (_lives <= 0) {
      _finish();
    } else {
      _draw();
    }
  }

  void _finish() {
    _snippet.stop();
    ref.read(gameStatsProvider.notifier).submitScore(widget.game.id, _score);
    setState(() => _phase = _Phase.over);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final best = ref.watch(gameStatsProvider).best[widget.game.id] ?? 0;
    final playing = _phase == _Phase.playing || _phase == _Phase.revealed;
    final canPlace = _phase == _Phase.playing;

    return _GameFrame(
      game: widget.game,
      stats: !playing
          ? const []
          : [
              _Stat(label: 'Frise', value: '$_score'),
              _Stat(
                label: 'Vies',
                value: '',
                child: Text('❤' * _lives, style: const TextStyle(fontSize: 22)),
              ),
              _Stat(label: 'Record', value: '$best'),
            ],
      hints: canPlace
          ? const [('← →', 'Choisir le trou'), ('OK', 'Placer')]
          : const [],
      child: switch (_phase) {
        _Phase.loading => const Center(child: CircularProgressIndicator()),
        _Phase.empty => const TvEmpty(
          message: 'Pas assez d\'albums datés',
          hint: 'La frise a besoin d\'au moins six titres millésimés.',
          icon: Icons.timeline_rounded,
        ),
        _Phase.over => _GameOver(
          game: widget.game,
          score: _score,
          headline: _lives > 0 ? 'Paquet épuisé' : 'Plus de vies',
          onReplay: _load,
        ),
        _Phase.playing || _Phase.revealed => Column(
          children: [
            SizedBox(
              // Disque, question et bouton « Passer » : compté au plus juste,
              // le bandeau débordait de 21 px.
              height: 286,
              child: _phase == _Phase.revealed
                  ? _ChronoVerdict(
                      track: _current!,
                      correct: _lastCorrect,
                      onContinue: _continue,
                    )
                  : Column(
                      children: [
                        MysteryDisc(playing: true, size: 150),
                        const SizedBox(height: 14),
                        Text(
                          'Où se place ce titre ?',
                          style: TextStyle(
                            fontSize: 30,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.6,
                            color: scheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 12),
                        TvPill(
                          label: 'Passer',
                          icon: Icons.skip_next_rounded,
                          accent: false,
                          compact: true,
                          onPressed: _skip,
                        ),
                      ],
                    ),
            ),
            const SizedBox(height: 20),
            Expanded(
              child: ListView(
                controller: _scroll,
                scrollDirection: Axis.horizontal,
                children: [
                  for (var gap = 0; gap <= _timeline.length; gap++) ...[
                    _ChronoGap(
                      enabled: canPlace,
                      autofocus: canPlace && gap == 0,
                      highlight: _lastGap == gap,
                      correct: _lastCorrect,
                      onPressed: () => _place(gap),
                    ),
                    if (gap < _timeline.length)
                      _ChronoCard(track: _timeline[gap]),
                  ],
                ],
              ),
            ),
          ],
        ),
      },
    );
  }
}

class _ChronoVerdict extends StatelessWidget {
  const _ChronoVerdict({
    required this.track,
    required this.correct,
    required this.onContinue,
  });

  final GameTrack track;
  final bool? correct;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = correct == null
        ? scheme.onSurfaceVariant
        : (correct! ? TvDot.ok : TvDot.ko);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        TvArtwork(url: track.song.artworkUrl, size: 150, borderRadius: 18),
        const SizedBox(width: 24),
        Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              correct == null
                  ? 'Passé'
                  : (correct! ? 'Bien placé !' : 'Mal placé'),
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
            Text(
              '${track.year}',
              style: TextStyle(
                fontSize: 52,
                fontWeight: FontWeight.w800,
                letterSpacing: -1.4,
                color: scheme.primary,
              ),
            ),
            SizedBox(
              width: 420,
              child: Text(
                track.song.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(width: 30),
        TvPill(
          label: 'Continuer',
          icon: Icons.arrow_forward_rounded,
          autofocus: true,
          compact: true,
          onPressed: onContinue,
        ),
      ],
    );
  }
}

class _ChronoGap extends StatelessWidget {
  const _ChronoGap({
    required this.enabled,
    required this.autofocus,
    required this.highlight,
    required this.correct,
    required this.onPressed,
  });

  final bool enabled;
  final bool autofocus;
  final bool highlight;
  final bool? correct;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final mark = highlight && correct != null
        ? (correct! ? TvDot.ok : TvDot.ko)
        : null;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 40),
      child: Opacity(
        opacity: enabled || mark != null ? 1 : 0.2,
        child: TvFocusable(
          autofocus: autofocus,
          onPressed: enabled ? onPressed : null,
          scale: 1.1,
          builder: (context, focused) => Container(
            width: 54,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: mark?.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(16),
              border: focused
                  ? tvFocusBorder(scheme.primary)
                  : Border.all(
                      color: mark ?? scheme.primary.withValues(alpha: 0.6),
                      style: mark == null
                          ? BorderStyle.solid
                          : BorderStyle.solid,
                    ),
              boxShadow: focused
                  ? tvFocusGlow(scheme.primary, spread: 3)
                  : null,
            ),
            child: Icon(
              mark == null
                  ? Icons.add_rounded
                  : (correct == true
                        ? Icons.check_rounded
                        : Icons.close_rounded),
              color: mark ?? scheme.primary,
              size: 26,
            ),
          ),
        ),
      ),
    );
  }
}

class _ChronoCard extends StatelessWidget {
  const _ChronoCard({required this.track});

  final GameTrack track;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: SizedBox(
        width: 170,
        child: TvGlass(
          radius: 20,
          padding: const EdgeInsets.all(14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TvArtwork(
                url: track.song.artworkUrl,
                size: 100,
                borderRadius: 14,
              ),
              const SizedBox(height: 10),
              Text(
                '${track.year}',
                style: const TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.7,
                ),
              ),
              Text(
                track.song.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 17, color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────── défricheur ──

class _SwipeGame extends ConsumerStatefulWidget {
  const _SwipeGame({required this.game});

  final GameInfo game;

  @override
  ConsumerState<_SwipeGame> createState() => _SwipeGameState();
}

class _SwipeGameState extends ConsumerState<_SwipeGame> {
  static const _rounds = 10;
  static const _roundTime = Duration(seconds: 30);
  static const _tick = Duration(milliseconds: 200);

  final _snippet = SnippetPlayer();

  _Phase _phase = _Phase.loading;
  List<DiscoveryTrack> _deck = [];
  final _kept = <DiscoveryTrack>[];
  int _round = 0;
  Duration _left = _roundTime;
  Timer? _timer;
  String? _saveError;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _snippet.dispose();
    super.dispose();
  }

  Future<void> _boot() async {
    try {
      await ref.read(audioHandlerProvider).pause();
    } catch (_) {}
    await ref.read(swipeMemoryProvider.notifier).ready;
    await _load(refresh: false);
  }

  Future<void> _load({bool refresh = true}) async {
    setState(() {
      _phase = _Phase.loading;
      _saveError = null;
    });
    try {
      final pool = refresh
          ? await ref.refresh(discoveryTracksProvider.future)
          : await ref.read(discoveryTracksProvider.future);
      if (!mounted) return;
      if (pool.isEmpty) {
        setState(() => _phase = _Phase.empty);
        return;
      }
      _deck = pool.take(_rounds).toList();
      _kept.clear();
      _round = 0;
      _startRound();
    } catch (_) {
      if (mounted) setState(() => _phase = _Phase.empty);
    }
  }

  void _startRound() {
    final track = _deck[_round];
    setState(() {
      _left = _roundTime;
      _phase = _Phase.playing;
    });
    _snippet.playFrom(
      ref.read(libraryRepositoryProvider).streamUrl(track.song),
      Duration.zero,
    );
    _timer?.cancel();
    _timer = Timer.periodic(_tick, (_) {
      if (!mounted) return;
      final left = _left - _tick;
      if (left <= Duration.zero) {
        _decide(keep: false);
      } else {
        setState(() => _left = left);
      }
    });
  }

  void _decide({required bool keep}) {
    if (_phase != _Phase.playing) return;
    _timer?.cancel();
    if (keep) _kept.add(_deck[_round]);
    if (_round + 1 >= _deck.length) {
      _finish();
      return;
    }
    setState(() => _round++);
    _startRound();
  }

  /// Fin de tournée : la récolte rejoint la playlist, et tous les titres vus
  /// sont retenus pour ne plus revenir.
  Future<void> _finish() async {
    _timer?.cancel();
    _snippet.stop();
    setState(() => _phase = _Phase.over);

    await ref.read(swipeMemoryProvider.notifier).remember([
      for (final t in _deck) t.song.id,
    ]);
    if (_kept.isNotEmpty) {
      try {
        final actions = ref.read(playlistActionsProvider);
        final playlistId = await actions.ensureNamed(kSwipePlaylist);
        for (final track in _kept) {
          await actions.addSong(playlistId, track.song.id);
        }
      } catch (e) {
        // La récolte est perdue pour la playlist, pas la partie : on le dit
        // plutôt que de laisser croire que tout est rangé.
        if (mounted) setState(() => _saveError = '$e');
      }
    }
    if (!mounted) return;
    await ref
        .read(gameStatsProvider.notifier)
        .submitScore(widget.game.id, _kept.length);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final playing = _phase == _Phase.playing;

    return _GameFrame(
      game: widget.game,
      stats: !playing
          ? const []
          : [
              _Stat(label: 'Titre', value: '${_round + 1}/${_deck.length}'),
              _Stat(label: 'Gardés', value: '${_kept.length}'),
            ],
      hints: playing
          ? const [('←', 'Passer'), ('→', 'Garder'), ('Retour', 'Quitter')]
          : const [],
      child: switch (_phase) {
        _Phase.loading => const Center(child: CircularProgressIndicator()),
        _Phase.empty => const TvEmpty(
          message: 'Plus rien à défricher',
          hint:
              'Tous tes titres jamais écoutés sont déjà passés. Ajoute de la '
              'musique, ou reviens plus tard.',
          icon: Icons.explore_off_rounded,
        ),
        _Phase.over => Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _GameOver(
              game: widget.game,
              score: _kept.length,
              headline: _kept.isEmpty ? 'Rien gardé' : 'Récolte rangée',
              suffix: ' titres',
              onReplay: _load,
            ),
            if (_saveError != null)
              Padding(
                padding: const EdgeInsets.only(top: 14),
                child: Text(
                  'La playlist n\'a pas pu être mise à jour : $_saveError',
                  style: TextStyle(fontSize: 19, color: scheme.error),
                ),
              ),
          ],
        ),
        _Phase.playing || _Phase.revealed => _SwipeRound(
          track: _deck[_round],
          left: _left,
          total: _roundTime,
          onKeep: () => _decide(keep: true),
          onSkip: () => _decide(keep: false),
        ),
      },
    );
  }
}

/// Un titre à juger. Les flèches valent les gestes du téléphone : gauche pour
/// passer, droite pour garder.
class _SwipeRound extends StatelessWidget {
  const _SwipeRound({
    required this.track,
    required this.left,
    required this.total,
    required this.onKeep,
    required this.onSkip,
  });

  final DiscoveryTrack track;
  final Duration left;
  final Duration total;
  final VoidCallback onKeep;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
          onSkip();
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
          onKeep();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const Spacer(),
          _SwipeAction(
            icon: Icons.close_rounded,
            label: 'Passer',
            color: TvDot.ko,
            onPressed: onSkip,
          ),
          const SizedBox(width: 40),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TvArtwork(
                url: track.song.artworkUrl,
                size: 320,
                borderRadius: 26,
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: 420,
                child: Text(
                  track.song.title,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 30,
                    height: 1.2,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.6,
                  ),
                ),
              ),
              Text(
                [
                  track.song.artistName ?? '',
                  if (track.year != null) '${track.year}',
                ].where((s) => s.isNotEmpty).join(' · '),
                style: TextStyle(fontSize: 22, color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: 320,
                child: _RoundBar(
                  ratio: left.inMilliseconds / total.inMilliseconds,
                  seconds: (left.inMilliseconds / 1000).ceil(),
                ),
              ),
            ],
          ),
          const SizedBox(width: 40),
          _SwipeAction(
            icon: Icons.favorite_rounded,
            label: 'Garder',
            color: TvDot.ok,
            onPressed: onKeep,
          ),
          const Spacer(),
        ],
      ),
    );
  }
}

class _SwipeAction extends StatelessWidget {
  const _SwipeAction({
    required this.icon,
    required this.label,
    required this.color,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return TvFocusable(
      onPressed: onPressed,
      scale: 1.08,
      builder: (context, focused) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 110,
            height: 110,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withValues(alpha: focused ? 0.3 : 0.14),
              border: Border.all(
                color: focused ? Colors.white.withValues(alpha: 0.75) : color,
                width: focused ? 3 : 1.5,
              ),
              boxShadow: focused ? tvFocusGlow(color, spread: 4) : null,
            ),
            child: Icon(icon, size: 46, color: color),
          ),
          const SizedBox(height: 10),
          Text(
            label,
            style: TextStyle(
              fontSize: 21,
              fontWeight: FontWeight.w700,
              color: focused ? scheme.onSurface : scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
