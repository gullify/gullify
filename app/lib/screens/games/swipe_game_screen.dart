import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/library_repository.dart';
import '../../state/games.dart';
import '../../state/library.dart';
import '../../state/player.dart';
import '../../state/playlists.dart';
import '../../widgets/artwork.dart';
import '../../widgets/glass_box.dart';
import '../../widgets/glass_kit.dart';
import 'game_fx.dart';
import 'game_kit.dart';

/// « Défricheur » : trente secondes d'un titre jamais écouté, on garde ou on
/// passe. Ce qu'on garde rejoint la playlist du même nom — de quoi enfin
/// écouter ce qu'on a accumulé sans jamais l'ouvrir.
class SwipeGameScreen extends ConsumerStatefulWidget {
  const SwipeGameScreen({super.key});

  @override
  ConsumerState<SwipeGameScreen> createState() => _SwipeGameScreenState();
}

enum _Phase { loading, empty, playing, saving, over }

class _SwipeGameScreenState extends ConsumerState<SwipeGameScreen>
    with SingleTickerProviderStateMixin {
  /// Titres proposés par tournée : assez pour défricher, assez court pour
  /// qu'on ait envie d'y revenir.
  static const _rounds = 10;

  /// La durée de l'extrait — c'est tout le principe du jeu.
  static const _clip = Duration(seconds: 30);
  static const _tick = Duration(milliseconds: 100);

  /// Au-delà de ce déplacement horizontal, la carte part.
  static const _threshold = 90.0;

  final _random = math.Random();
  final _snippet = SnippetPlayer();

  late final AnimationController _fly = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 240),
  );

  _Phase _phase = _Phase.loading;
  String? _error;
  String? _saveError;

  List<DiscoveryTrack> _deck = [];
  final List<DiscoveryTrack> _kept = [];
  int _index = 0;
  int _addedSongs = 0;

  /// Déplacement de la carte du dessus, à la main puis à l'animation.
  Offset _drag = Offset.zero;
  Offset _flyFrom = Offset.zero;
  bool _keeping = false;
  bool _flying = false;

  Duration _start = Duration.zero;
  Duration _left = _clip;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _fly
      ..addListener(() => setState(() {}))
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed) _commit();
      });
    _boot();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _fly.dispose();
    _snippet.dispose();
    super.dispose();
  }

  Future<void> _boot() async {
    try {
      await ref.read(audioHandlerProvider).pause();
    } catch (_) {}
    // Les deux relectures de stockage en parallèle : leurs délais de garde
    // s'additionneraient sinon.
    await Future.wait([
      ref.read(gameStatsProvider.notifier).ready,
      ref.read(swipeMemoryProvider.notifier).ready,
    ]);
    if (!mounted) return;
    if (!ref.read(gameStatsProvider).rulesSeen.contains(kSwipeGame.id)) {
      await showGameRules(context, ref, kSwipeGame);
      if (!mounted) return;
    }
    await _load(refresh: false);
  }

  Future<void> _load({bool refresh = true}) async {
    _timer?.cancel();
    _snippet.stop();
    setState(() {
      _phase = _Phase.loading;
      _error = null;
      _saveError = null;
    });
    try {
      final pool = refresh
          ? await ref.refresh(discoveryTracksProvider.future)
          : await ref.read(discoveryTracksProvider.future);
      if (!mounted) return;
      // Ce qui a déjà été jugé ne revient pas : le serveur, lui, continue de
      // le proposer tant qu'on ne l'a pas écouté.
      final seen = ref.read(swipeMemoryProvider);
      final fresh = [
        for (final track in pool)
          if (!seen.contains(track.song.id)) track,
      ]..shuffle(_random);
      if (fresh.isEmpty) {
        setState(() => _phase = _Phase.empty);
        return;
      }
      setState(() {
        _deck = fresh.take(_rounds).toList();
        _kept.clear();
        _index = 0;
        _addedSongs = 0;
        _drag = Offset.zero;
        _phase = _Phase.playing;
      });
      _startRound();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.empty;
        _error = '$e';
      });
    }
  }

  DiscoveryTrack get _current => _deck[_index];

  void _startRound() {
    final sample = _current.song;
    _start = snippetStart(sample, _random);
    _snippet.playFrom(
      ref.read(libraryRepositoryProvider).streamUrl(sample),
      _start,
    );
    _runClock();
  }

  /// Relance les trente secondes depuis le début de l'extrait.
  void _replay() {
    _snippet.replay(_start);
    _runClock();
  }

  /// Les trente secondes s'écoulent, puis l'extrait se tait — le verdict,
  /// lui, reste possible aussi longtemps qu'on veut.
  void _runClock() {
    setState(() => _left = _clip);
    _timer?.cancel();
    _timer = Timer.periodic(_tick, (_) {
      if (!mounted) return;
      final left = _left - _tick;
      if (left <= Duration.zero) {
        _timer?.cancel();
        _snippet.stop();
        setState(() => _left = Duration.zero);
      } else {
        setState(() => _left = left);
      }
    });
  }

  /// Lance la sortie de carte : à droite on garde, à gauche on passe.
  void _decide(bool keep) {
    if (_phase != _Phase.playing || _flying) return;
    // Garder, c'est un oui franc ; passer, un simple déclic (idée #77).
    gameHaptic(keep ? GameFeel.good : GameFeel.tap);
    _timer?.cancel();
    _snippet.stop();
    setState(() {
      _keeping = keep;
      _flying = true;
      _flyFrom = _drag;
    });
    _fly.forward(from: 0);
  }

  /// La carte est sortie de l'écran : on enregistre le verdict et on enchaîne.
  void _commit() {
    if (!mounted) return;
    if (_keeping) _kept.add(_current);
    _fly.value = 0;
    if (_index + 1 >= _deck.length) {
      setState(() {
        _flying = false;
        _drag = Offset.zero;
      });
      _finish();
      return;
    }
    setState(() {
      _index++;
      _flying = false;
      _drag = Offset.zero;
    });
    _startRound();
  }

  /// Fin de tournée : la récolte rejoint la playlist, et tous les titres vus
  /// (gardés comme passés) sont retenus pour ne plus revenir.
  Future<void> _finish() async {
    _timer?.cancel();
    _snippet.stop();
    setState(() => _phase = _Phase.saving);

    await ref.read(swipeMemoryProvider.notifier).remember([
      for (final t in _deck) t.song.id,
    ]);

    var added = 0;
    if (_kept.isNotEmpty) {
      try {
        final actions = ref.read(playlistActionsProvider);
        final playlistId = await actions.ensureNamed(kSwipePlaylist);
        for (final track in _kept) {
          await actions.addSong(playlistId, track.song.id);
          added++;
        }
      } catch (e) {
        // La récolte est perdue pour la playlist, pas la partie : on le dit
        // au lieu de faire croire que tout est rangé.
        if (mounted) setState(() => _saveError = '$e');
      }
    }
    if (!mounted) return;
    await ref
        .read(gameStatsProvider.notifier)
        .submitScore(kSwipeGame.id, _kept.length);
    if (!mounted) return;
    setState(() {
      _addedSongs = added;
      _phase = _Phase.over;
    });
  }

  @override
  Widget build(BuildContext context) {
    final best = ref.watch(gameStatsProvider).best[kSwipeGame.id] ?? 0;

    return GameScaffold(
      game: kSwipeGame,
      onSourceChanged: () => _load(),
      onQuit: () {
        _timer?.cancel();
        _snippet.stop();
      },
      status: _phase != _Phase.playing
          ? null
          : GameStatusBar(
              children: [
                GameStatChip(
                  label: 'Titre',
                  value: '${_index + 1}/${_deck.length}',
                ),
                GameStatChip(label: 'Gardés', value: '${_kept.length}'),
                GameStatChip(label: 'Record', value: '$best'),
              ],
            ),
      child: switch (_phase) {
        _Phase.loading => const Center(child: CircularProgressIndicator()),
        _Phase.empty => _buildEmpty(),
        _Phase.saving => const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 14),
              Text('On range la récolte…'),
            ],
          ),
        ),
        _Phase.over => _buildOver(best),
        _Phase.playing => _buildRound(),
      },
    );
  }

  Widget _buildEmpty() {
    final judged = ref.watch(swipeMemoryProvider).isNotEmpty;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Flexible(
          child: GameNotEnoughData(
            message: _error == null
                ? 'Plus rien à défricher'
                : 'Impossible de charger la partie',
            hint:
                _error ??
                'Tous les titres de ta bibliothèque ont déjà été écoutés — '
                    'ou déjà jugés ici.',
          ),
        ),
        if (_error == null && judged)
          Padding(
            padding: const EdgeInsets.only(bottom: 20),
            child: TextButton.icon(
              onPressed: () async {
                await ref.read(swipeMemoryProvider.notifier).forget();
                await _load();
              },
              icon: const Icon(Icons.restart_alt_rounded, size: 18),
              label: const Text('Tout remettre à défricher'),
            ),
          ),
      ],
    );
  }

  Widget _buildOver(int best) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        Expanded(
          child: GameOverPanel(
            game: kSwipeGame,
            score: _kept.length,
            best: best,
            headline: _kept.isEmpty
                ? 'Rien gardé cette fois'
                : '${_kept.length} titre${_kept.length > 1 ? 's' : ''} '
                      'à écouter',
            scoreSuffix: ' gardés',
            onReplay: _load,
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
          child: Text(
            _saveError != null
                ? 'La playlist « $kSwipePlaylist » n\'a pas pu être mise à '
                      'jour : $_saveError'
                : _kept.isEmpty
                ? 'Rien n\'a rejoint la playlist « $kSwipePlaylist ».'
                : '$_addedSongs titre${_addedSongs > 1 ? 's' : ''} '
                      'ajouté${_addedSongs > 1 ? 's' : ''} à la playlist '
                      '« $kSwipePlaylist ».',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12.5,
              height: 1.3,
              color: _saveError != null
                  ? scheme.error
                  : scheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRound() {
    return Column(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 6),
            child: LayoutBuilder(
              builder: (context, constraints) {
                // La pochette prend ce que l'écran veut bien lui laisser :
                // sur un petit téléphone, la carte doit tenir entière.
                final art = math.min(
                  240.0,
                  math.min(
                    constraints.maxWidth - 72,
                    constraints.maxHeight - 132,
                  ),
                );
                return Stack(
                  alignment: Alignment.center,
                  children: [
                    // La carte suivante, à peine visible derrière : la pile
                    // donne le sentiment qu'il en reste.
                    if (_index + 1 < _deck.length)
                      Transform.scale(
                        scale: 0.94,
                        child: Opacity(
                          opacity: 0.55,
                          child: _card(
                            _deck[_index + 1],
                            art: art,
                            interactive: false,
                          ),
                        ),
                      ),
                    _draggableCard(constraints.maxWidth, art),
                  ],
                );
              },
            ),
          ),
        ),
        _buildControls(),
      ],
    );
  }

  Widget _draggableCard(double width, double art) {
    final offset = _flying
        ? Offset.lerp(
            _flyFrom,
            Offset((_keeping ? 1 : -1) * (width + 220), _flyFrom.dy + 60),
            Curves.easeOut.transform(_fly.value),
          )!
        : _drag;
    // La carte s'incline dans le sens du geste — juste assez pour qu'on sente
    // la matière.
    final angle = (offset.dx / (width == 0 ? 1 : width)) * 0.28;

    return GestureDetector(
      onPanUpdate: (details) {
        if (_flying) return;
        setState(() => _drag += details.delta);
      },
      onPanEnd: (_) {
        if (_flying) return;
        if (_drag.dx.abs() >= _threshold) {
          _decide(_drag.dx > 0);
        } else {
          setState(() => _drag = Offset.zero);
        }
      },
      child: Transform.translate(
        offset: offset,
        child: Transform.rotate(
          angle: angle,
          child: _card(_current, art: art),
        ),
      ),
    );
  }

  /// La carte d'un titre : pochette en grand, identité dessous, et le verdict
  /// qui s'affiche dès que le geste penche d'un côté.
  Widget _card(
    DiscoveryTrack entry, {
    required double art,
    bool interactive = true,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final song = entry.song;
    final dx = interactive && !_flying ? _drag.dx : 0.0;
    final keeping = interactive && (_flying ? _keeping : dx > 0);
    final verdict = interactive
        ? (_flying ? 1.0 : (dx.abs() / _threshold).clamp(0.0, 1.0))
        : 0.0;

    // Largeur imposée : les deux cartes de la pile doivent se superposer
    // exactement, quelle que soit la longueur des titres.
    return SizedBox(
      width: double.infinity,
      child: GlassBox(
        radius: 26,
        blur: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                alignment: Alignment.topCenter,
                children: [
                  Artwork(url: song.artworkUrl, size: art, borderRadius: 20),
                  if (verdict > 0.05)
                    Positioned(
                      top: 14,
                      child: Opacity(
                        opacity: verdict,
                        child: _VerdictBadge(keeping: keeping),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                song.title,
                maxLines: 2,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.4,
                  height: 1.15,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                song.artistName ?? '',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 14, color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 6),
              // L'album d'où vient le titre, et son année : de quoi situer ce
              // qu'on entend sans rien dévoiler de plus.
              Text(
                [
                  if ((song.albumName ?? '').isNotEmpty) song.albumName!,
                  if (entry.year != null) '${entry.year}',
                ].join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: scheme.primary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Le chrono de l'extrait et les deux verdicts, sous la carte.
  Widget _buildControls() {
    final scheme = Theme.of(context).colorScheme;
    final ratio = _left.inMilliseconds / _clip.inMilliseconds;

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          StreamBuilder<bool>(
            stream: _snippet.playingStream,
            initialData: false,
            builder: (context, snap) => Row(
              children: [
                SizedBox(
                  width: 42,
                  child: SoundWave(
                    playing: snap.data ?? false,
                    height: 22,
                    bars: 7,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: ratio.clamp(0.0, 1.0),
                      minHeight: 6,
                      backgroundColor: scheme.onSurface.withValues(alpha: 0.08),
                      color: scheme.primary,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                GlassIconButton(
                  icon: Icons.replay_rounded,
                  tooltip: 'Réécouter les trente secondes',
                  size: 38,
                  onPressed: _replay,
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _VerdictButton(
                icon: Icons.close_rounded,
                label: 'Passer',
                color: gameBad,
                onPressed: () => _decide(false),
              ),
              _VerdictButton(
                icon: Icons.favorite_rounded,
                label: 'Garder',
                color: gameGood,
                onPressed: () => _decide(true),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Le tampon « GARDÉ » / « PASSÉ » qui apparaît sur la pochette pendant le
/// geste.
class _VerdictBadge extends StatelessWidget {
  const _VerdictBadge({required this.keeping});

  final bool keeping;

  @override
  Widget build(BuildContext context) {
    final color = keeping ? gameGood : gameBad;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: color.withValues(alpha: 0.9),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.4),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Text(
        keeping ? 'GARDÉ' : 'PASSÉ',
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.5,
          color: Colors.white,
        ),
      ),
    );
  }
}

class _VerdictButton extends StatelessWidget {
  const _VerdictButton({
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
    // Le libellé fait partie du bouton : viser la pastille seule serait
    // inutilement précis.
    return PressPop(
      onTap: onPressed,
      scale: 0.92,
      feel: null,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withValues(alpha: 0.18),
              border: Border.all(
                color: color.withValues(alpha: 0.85),
                width: 1.8,
              ),
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.3),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Icon(icon, color: color, size: 32),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.1,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
