import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:just_audio/just_audio.dart';

import '../../models/song.dart';
import '../../state/games.dart';
import '../../widgets/glass_box.dart';
import '../../widgets/glass_kit.dart';
import '../../widgets/mascot_empty.dart';

/// Briques communes aux jeux : en-tête, feuille de règles, boutons de
/// réponse, écran de fin et lecteur d'extraits.

/// Lecteur d'extraits **isolé** du lecteur principal : aucune notification,
/// aucun mini-lecteur, donc aucun titre dévoilé pendant une manche.
class SnippetPlayer {
  final AudioPlayer _player = AudioPlayer();

  /// Exposé pour écouter l'état (lecture / pause) dans l'interface.
  AudioPlayer get player => _player;

  Stream<bool> get playingStream =>
      _player.playerStateStream.map((s) => s.playing);

  bool get playing => _player.playing;

  /// Charge un extrait et le lance. Les erreurs réseau sont avalées : une
  /// manche muette reste jouable (l'extrait peut être relancé).
  Future<void> playFrom(String url, Duration start) async {
    try {
      await _player.stop();
      await _player.setUrl(url, initialPosition: start);
      await _player.play();
    } catch (_) {}
  }

  Future<void> replay(Duration start) async {
    try {
      await _player.seek(start);
      await _player.play();
    } catch (_) {}
  }

  Future<void> toggle() async {
    try {
      _player.playing ? await _player.pause() : await _player.play();
    } catch (_) {}
  }

  Future<void> stop() async {
    try {
      await _player.stop();
    } catch (_) {}
  }

  /// Met l'extrait en sourdine pendant qu'on parle ou qu'on écoute quelqu'un
  /// (talkie-walkie des parties) : la voix doit passer devant la musique.
  Future<void> duck(bool quiet) async {
    try {
      await _player.setVolume(quiet ? 0.18 : 1);
    } catch (_) {}
  }

  Future<void> dispose() async {
    try {
      await _player.dispose();
    } catch (_) {}
  }
}

/// Début d'extrait : jamais l'intro (trop facile ou silencieuse), jamais la
/// fin. Entre 15 % et 55 % du morceau.
Duration snippetStart(Song song, math.Random random) {
  final seconds = song.duration;
  if (seconds <= 45) return Duration.zero;
  final low = (seconds * 0.15).round();
  final high = (seconds * 0.55).round();
  return Duration(seconds: low + random.nextInt(math.max(1, high - low)));
}

/// Coque commune : fond transparent (le dégradé du thème vit derrière),
/// en-tête retour / titre / règles, puis le contenu du jeu.
class GameScaffold extends ConsumerWidget {
  const GameScaffold({
    super.key,
    required this.game,
    required this.child,
    this.status,
    this.onQuit,
  });

  final GameInfo game;
  final Widget child;

  /// Bandeau d'état du jeu (score, vies, manche…), sous l'en-tête.
  final Widget? status;

  /// Appelé avant de quitter (arrêt de l'extrait en cours).
  final VoidCallback? onQuit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
              child: Row(
                children: [
                  GlassIconButton(
                    icon: Icons.arrow_back_rounded,
                    tooltip: 'Retour',
                    size: 42,
                    onPressed: () {
                      onQuit?.call();
                      context.pop();
                    },
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      game.name,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                      ),
                    ),
                  ),
                  GlassIconButton(
                    icon: Icons.help_outline_rounded,
                    tooltip: 'Règles du jeu',
                    size: 42,
                    onPressed: () => showGameRules(context, ref, game),
                  ),
                ],
              ),
            ),
            if (status != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 2),
                child: status!,
              ),
            Expanded(child: child),
          ],
        ),
      ),
    );
  }
}

/// Feuille des règles : but du jeu puis les règles, une puce par ligne.
/// Affichée automatiquement à la première ouverture, puis à la demande.
Future<void> showGameRules(
  BuildContext context,
  WidgetRef ref,
  GameInfo game,
) async {
  final scheme = Theme.of(context).colorScheme;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
      child: GlassBox(
        radius: 26,
        blur: false,
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 18, 22, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 42,
                    height: 4,
                    decoration: BoxDecoration(
                      color: scheme.onSurfaceVariant.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Icon(game.icon, color: scheme.primary, size: 26),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        game.name,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.4,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  'Le but',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: scheme.primary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  game.goal,
                  style: const TextStyle(fontSize: 15, height: 1.35),
                ),
                const SizedBox(height: 16),
                Text(
                  'Comment on joue',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: scheme.primary,
                  ),
                ),
                const SizedBox(height: 6),
                for (final rule in game.rules)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 7, right: 10),
                          child: Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: scheme.primary,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            rule,
                            style: const TextStyle(
                              fontSize: 14.5,
                              height: 1.35,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                if (game.needsSound) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(
                        Icons.volume_up_rounded,
                        size: 18,
                        color: scheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Monte le son : tout se joue à l\'oreille.',
                          style: TextStyle(
                            fontSize: 13,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 16),
                AccentPlayButton(
                  label: 'Compris, on joue !',
                  icon: Icons.sports_esports_rounded,
                  expand: true,
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  // Lues une fois = plus d'affichage automatique (le bouton « ? » reste).
  // L'écriture n'est pas attendue : la partie démarre tout de suite.
  unawaited(ref.read(gameStatsProvider.notifier).markRulesSeen(game.id));
}

/// Bandeau d'état : une suite de petites pastilles de verre (score, manche…).
class GameStatusBar extends StatelessWidget {
  const GameStatusBar({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      for (var i = 0; i < children.length; i++) ...[
        if (i > 0) const SizedBox(width: 10),
        Expanded(child: children[i]),
      ],
    ],
  );
}

/// Pastille d'état : libellé discret + valeur en gras.
class GameStatChip extends StatelessWidget {
  const GameStatChip({
    super.key,
    required this.label,
    required this.value,
    this.valueWidget,
  });

  final String label;
  final String value;
  final Widget? valueWidget;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GlassBox(
      radius: 16,
      blur: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label.toUpperCase(),
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 2),
            valueWidget ??
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

/// Les vies restantes, en cœurs.
class GameLives extends StatelessWidget {
  const GameLives({super.key, required this.lives, this.total = 3});

  final int lives;
  final int total;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < total; i++)
          Padding(
            padding: const EdgeInsets.only(right: 3),
            child: Icon(
              i < lives
                  ? Icons.favorite_rounded
                  : Icons.favorite_border_rounded,
              size: 18,
              color: i < lives
                  ? const Color(0xFFE5484D)
                  : scheme.onSurfaceVariant.withValues(alpha: 0.5),
            ),
          ),
      ],
    );
  }
}

/// Réponse proposée : carte de verre qui vire au vert (bonne) ou au rouge
/// (mauvaise) une fois la manche révélée.
class GameChoiceTile extends StatelessWidget {
  const GameChoiceTile({
    super.key,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.state = GameChoiceState.idle,
  });

  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final GameChoiceState state;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = switch (state) {
      GameChoiceState.correct => const Color(0xFF2FA36B),
      GameChoiceState.wrong => const Color(0xFFE5484D),
      GameChoiceState.idle || GameChoiceState.faded => null,
    };
    return Opacity(
      opacity: state == GameChoiceState.faded ? 0.45 : 1,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          color: color?.withValues(alpha: 0.18),
          border: color == null
              ? null
              : Border.all(color: color.withValues(alpha: 0.9), width: 1.6),
        ),
        child: GlassBox(
          radius: 18,
          blur: false,
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12.5,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (color != null)
                    Icon(
                      state == GameChoiceState.correct
                          ? Icons.check_circle_rounded
                          : Icons.cancel_rounded,
                      color: color,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

enum GameChoiceState { idle, correct, wrong, faded }

/// Fin de partie : score, record, rejouer / quitter.
class GameOverPanel extends StatelessWidget {
  const GameOverPanel({
    super.key,
    required this.game,
    required this.score,
    required this.best,
    required this.onReplay,
    this.headline,
    this.scoreSuffix,
  });

  final GameInfo game;
  final int score;
  final int best;
  final VoidCallback onReplay;
  final String? headline;
  final String? scoreSuffix;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final record = score >= best && score > 0;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: GlassBox(
          radius: 26,
          blur: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  record ? Icons.emoji_events_rounded : game.icon,
                  size: 44,
                  color: record ? const Color(0xFFE0A32E) : scheme.primary,
                ),
                const SizedBox(height: 10),
                Text(
                  headline ?? (record ? 'Nouveau record !' : 'Partie terminée'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.4,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  '$score${scoreSuffix ?? ''}',
                  style: TextStyle(
                    fontSize: 44,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -1.5,
                    color: scheme.primary,
                  ),
                ),
                Text(
                  '${game.scoreLabel} : ${math.max(best, score)}',
                  style: TextStyle(
                    fontSize: 13.5,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 20),
                AccentPlayButton(
                  label: 'Rejouer',
                  icon: Icons.refresh_rounded,
                  expand: true,
                  onPressed: onReplay,
                ),
                const SizedBox(height: 6),
                TextButton(
                  onPressed: () => context.pop(),
                  child: const Text('Retour aux jeux'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Message affiché quand la bibliothèque ne fournit pas assez de matière.
class GameNotEnoughData extends StatelessWidget {
  const GameNotEnoughData({super.key, required this.message, this.hint});

  final String message;
  final String? hint;

  @override
  Widget build(BuildContext context) =>
      MascotEmpty(message: message, hint: hint, size: 112);
}
