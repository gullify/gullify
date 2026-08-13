import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/game_track.dart';
import '../../state/games.dart';
import '../../state/library.dart';
import '../../state/player.dart';
import '../../widgets/artwork.dart';
import '../../widgets/glass_box.dart';
import '../../widgets/glass_kit.dart';
import 'game_fx.dart';
import 'game_kit.dart';

/// « Chrono » : le Hitster solo. Un extrait mystère est joué, il faut le
/// glisser au bon endroit d'une frise chronologique construite manche après
/// manche. Trois vies.
class ChronoGameScreen extends ConsumerStatefulWidget {
  const ChronoGameScreen({super.key});

  @override
  ConsumerState<ChronoGameScreen> createState() => _ChronoGameScreenState();
}

enum _Phase { loading, empty, placing, revealed, over }

class _ChronoGameScreenState extends ConsumerState<ChronoGameScreen> {
  static const _maxLives = 3;

  final _random = math.Random();
  final _snippet = SnippetPlayer();
  final _timelineScroll = ScrollController();

  _Phase _phase = _Phase.loading;
  String? _error;

  List<GameTrack> _deck = [];
  List<GameTrack> _timeline = [];
  GameTrack? _current;
  Duration _start = Duration.zero;

  int _lives = _maxLives;
  int _score = 0;

  /// Résultat de la manche révélée : trou choisi et verdict (null = passée).
  int? _lastGap;
  bool? _lastCorrect;

  /// Compteurs d'effets : une valeur qui change lance la fête ou la secousse.
  int _cheers = 0;
  int _shakes = 0;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  @override
  void dispose() {
    _snippet.dispose();
    _timelineScroll.dispose();
    super.dispose();
  }

  Future<void> _boot() async {
    // Le lecteur principal se tait : les extraits du jeu ne doivent pas se
    // superposer à la musique en cours.
    try {
      await ref.read(audioHandlerProvider).pause();
    } catch (_) {}
    await ref.read(gameStatsProvider.notifier).ready;
    if (!mounted) return;
    if (!ref.read(gameStatsProvider).rulesSeen.contains(kChronoGame.id)) {
      await showGameRules(context, ref, kChronoGame);
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
      if (pool.tracks.length < 6) {
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
    final deck = [...tracks]..shuffle(_random);
    setState(() {
      _timeline = [deck.removeLast()];
      _deck = deck;
      _lives = _maxLives;
      _score = 0;
    });
    _draw();
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
      _phase = _Phase.placing;
    });
    _start = snippetStart(track.song, _random);
    _snippet.playFrom(
      ref.read(libraryRepositoryProvider).streamUrl(track.song),
      _start,
    );
  }

  void _place(int gap) {
    final track = _current;
    if (track == null || _phase != _Phase.placing) return;
    final years = [for (final t in _timeline) t.year];
    final correct = chronoPlacementIsCorrect(years, gap, track.year);
    // Le verdict d'abord dans la main, ensuite à l'écran (idée #77).
    gameHaptic(correct ? GameFeel.good : GameFeel.bad);
    setState(() {
      _lastGap = gap;
      _lastCorrect = correct;
      _phase = _Phase.revealed;
      if (correct) {
        _timeline.insert(gap, track);
        _score++;
        _cheers++;
      } else {
        _lives--;
        _shakes++;
      }
    });
    if (correct) _scrollToPlacedCard(gap);
  }

  void _skip() {
    if (_phase != _Phase.placing) return;
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
    ref.read(gameStatsProvider.notifier).submitScore(kChronoGame.id, _score);
    setState(() => _phase = _Phase.over);
  }

  /// Amène la carte tout juste posée sous les yeux du joueur.
  void _scrollToPlacedCard(int index) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_timelineScroll.hasClients) return;
      const cardWidth = _TimelineCard.width + kDropZoneWidth;
      final target = (index * cardWidth) - 60;
      _timelineScroll.animateTo(
        target.clamp(0.0, _timelineScroll.position.maxScrollExtent),
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final best = ref.watch(gameStatsProvider).best[kChronoGame.id] ?? 0;

    return GameScaffold(
      game: kChronoGame,
      onQuit: _snippet.stop,
      onSourceChanged: () => _load(),
      status: _phase == _Phase.loading || _phase == _Phase.empty
          ? null
          : GameStatusBar(
              children: [
                GameStatChip(label: 'Frise', value: '$_score'),
                GameStatChip(
                  label: 'Vies',
                  value: '$_lives',
                  valueWidget: Padding(
                    padding: const EdgeInsets.only(top: 2, bottom: 1),
                    child: GameLives(lives: _lives, total: _maxLives),
                  ),
                ),
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
              'Chrono a besoin d\'albums qui portent une année et une '
                  'pochette. Lance un scan de la bibliothèque ou complète '
                  'les tags de tes albums.',
        ),
        _Phase.over => GameOverPanel(
          game: kChronoGame,
          score: _score,
          best: best,
          scoreSuffix: _score > 1 ? ' cartes' : ' carte',
          headline: _deck.isEmpty && _lives > 0
              ? 'Bibliothèque épuisée !'
              : null,
          onReplay: _load,
        ),
        _Phase.placing || _Phase.revealed => _buildBoard(),
      },
    );
  }

  Widget _buildBoard() {
    final revealed = _phase == _Phase.revealed;
    return Celebration(
      trigger: _cheers,
      child: ShakeBox(
        trigger: _shakes,
        child: Column(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
                child: revealed ? _buildReveal() : _buildMystery(),
              ),
            ),
            // La frise reste sous le pouce : c'est là qu'on dépose.
            _buildTimeline(),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  /// La carte mystère : aucune information, juste le son.
  Widget _buildMystery() {
    final scheme = Theme.of(context).colorScheme;
    return GlassBox(
      radius: 26,
      blur: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        // Défilable : sur un petit écran la carte peut dépasser la place
        // laissée par la frise.
        child: Center(
          child: SingleChildScrollView(
            child: StreamBuilder<bool>(
              stream: _snippet.playingStream,
              initialData: false,
              builder: (context, snap) {
                final playing = snap.data ?? false;
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Le vinyle mystère : il tourne tant que l'extrait joue
                    // (idée #77).
                    MysteryDisc(playing: playing, size: 116),
                    const SizedBox(height: 12),
                    SoundWave(playing: playing, height: 26),
                    const SizedBox(height: 8),
                    Text(
                      'Extrait mystère',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3,
                        color: scheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Plus ancien ? Plus récent ? À toi de placer la carte.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        GlassIconButton(
                          icon: Icons.replay_rounded,
                          tooltip: 'Réécouter depuis le début de l\'extrait',
                          onPressed: () {
                            gameHaptic(GameFeel.tap);
                            _snippet.replay(_start);
                          },
                        ),
                        const SizedBox(width: 14),
                        AccentPlayButton(
                          label: playing ? 'Pause' : 'Écouter',
                          icon: playing
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                          onPressed: () {
                            gameHaptic(GameFeel.tap);
                            _snippet.toggle();
                          },
                        ),
                        const SizedBox(width: 14),
                        GlassIconButton(
                          icon: Icons.skip_next_rounded,
                          tooltip: 'Passer cet extrait',
                          onPressed: _skip,
                        ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  /// La révélation : pochette, titre, année, et le verdict.
  Widget _buildReveal() {
    final scheme = Theme.of(context).colorScheme;
    final track = _current!;
    final passed = _lastCorrect == null;
    final correct = _lastCorrect ?? false;
    final color = passed
        ? scheme.onSurfaceVariant
        : correct
        ? const Color(0xFF2FA36B)
        : const Color(0xFFE5484D);

    return GlassBox(
      radius: 26,
      blur: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        child: Center(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Un extrait passé n'est ni gagné ni perdu : il garde sa
                // ligne discrète plutôt que la pilule de verdict.
                if (passed)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.skip_next_rounded, color: color, size: 20),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          'Extrait passé',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: color,
                          ),
                        ),
                      ),
                    ],
                  )
                else
                  GameVerdict(
                    correct: correct,
                    text: correct ? 'Bien vu !' : 'Raté — une vie en moins',
                  ),
                const SizedBox(height: 14),
                FlipReveal(
                  size: 96,
                  child: Artwork(
                    url: track.song.artworkUrl,
                    size: 96,
                    borderRadius: 18,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  '${track.year}',
                  style: TextStyle(
                    fontSize: 34,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -1.2,
                    color: scheme.primary,
                    height: 1,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  track.song.title,
                  maxLines: 2,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  track.song.artistName ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 14),
                AccentPlayButton(
                  label: _lives <= 0 ? 'Voir le score' : 'Manche suivante',
                  icon: Icons.arrow_forward_rounded,
                  onPressed: _continue,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// La frise : cartes posées, séparées par les trous où déposer la carte.
  Widget _buildTimeline() {
    final scheme = Theme.of(context).colorScheme;
    final active = _phase == _Phase.placing;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 2, 20, 6),
          child: Text(
            active ? 'Où le places-tu ?' : 'Ta frise',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
              color: active ? scheme.primary : scheme.onSurfaceVariant,
            ),
          ),
        ),
        SizedBox(
          height: 158,
          child: ListView(
            controller: _timelineScroll,
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            children: [
              for (var i = 0; i < _timeline.length; i++) ...[
                GlowDropZone(enabled: active, onTap: () => _place(i)),
                _TimelineCard(
                  track: _timeline[i],
                  highlight:
                      _phase == _Phase.revealed &&
                      (_lastCorrect ?? false) &&
                      _lastGap == i,
                ),
              ],
              GlowDropZone(
                enabled: active,
                onTap: () => _place(_timeline.length),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Une carte posée sur la frise : année, pochette, titre.
class _TimelineCard extends StatelessWidget {
  const _TimelineCard({required this.track, this.highlight = false});

  static const double width = 104;

  final GameTrack track;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      width: width,
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: highlight
            ? Border.all(color: const Color(0xFF2FA36B), width: 2)
            : null,
      ),
      child: GlassBox(
        radius: 18,
        blur: false,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Artwork(
                  url: track.song.artworkUrl,
                  size: 52,
                  borderRadius: 12,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '${track.year}',
                style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.6,
                  height: 1,
                  color: scheme.primary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                track.song.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                track.song.artistName ?? '',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10.5,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
