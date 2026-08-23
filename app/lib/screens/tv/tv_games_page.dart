import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../state/games.dart';
import 'tv_kit.dart';

/// L'onglet « Jeux » : la liste des jeux, et la partie à plusieurs.
///
/// Solo d'abord — c'est ce qu'on lance le plus souvent, et jouer seul devant
/// sa télé n'a rien d'un cas particulier. La partie à plusieurs garde sa
/// place en tête, en carte à part : elle demande d'autres joueurs et un
/// téléphone chacun.
class TvGamesPage extends ConsumerWidget {
  const TvGamesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final stats = ref.watch(gameStatsProvider);

    return TvScaffold(
      title: 'Jeux',
      child: ListView(
        padding: const EdgeInsets.only(bottom: 40),
        children: [
          _PartyCard(autofocus: true),
          const SizedBox(height: 26),
          Text(
            'JOUER SEUL',
            style: TextStyle(
              fontSize: tvMinText,
              fontWeight: FontWeight.w700,
              letterSpacing: 2.6,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 14),
          for (final game in kGames)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _GameRow(game: game, best: stats.best[game.id]),
            ),
        ],
      ),
    );
  }
}

class _PartyCard extends StatelessWidget {
  const _PartyCard({this.autofocus = false});

  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return TvFocusable(
      autofocus: autofocus,
      scale: 1.0,
      onPressed: () => context.push('/tv/party'),
      builder: (context, focused) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 22),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [
              scheme.primary.withValues(alpha: focused ? 0.45 : 0.28),
              scheme.primary.withValues(alpha: 0.08),
            ],
          ),
          borderRadius: BorderRadius.circular(24),
          border: focused
              ? tvFocusBorder(scheme.primary)
              : Border.all(color: scheme.primary.withValues(alpha: 0.45)),
          boxShadow: focused ? tvFocusGlow(scheme.primary, spread: 5) : null,
        ),
        child: Row(
          children: [
            Icon(Icons.groups_rounded, size: 42, color: scheme.onSurface),
            const SizedBox(width: 22),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Jouer à plusieurs',
                    style: TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'La télé affiche le code, chacun rejoint depuis son '
                    'téléphone.',
                    style: TextStyle(
                      fontSize: 21,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              size: 34,
              color: scheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}

class _GameRow extends StatelessWidget {
  const _GameRow({required this.game, this.best});

  final GameInfo game;
  final int? best;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return TvFocusable(
      scale: 1.0,
      onPressed: () => context.push('/tv/game/${game.id}'),
      builder: (context, focused) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: focused ? 0.12 : 0.05),
          borderRadius: BorderRadius.circular(22),
          border: focused
              ? tvFocusBorder(scheme.primary)
              : Border.all(color: Colors.white.withValues(alpha: 0.12)),
          boxShadow: focused ? tvFocusGlow(scheme.primary, spread: 4) : null,
        ),
        child: Row(
          children: [
            Container(
              width: 62,
              height: 62,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color.lerp(scheme.primary, Colors.white, 0.25)!,
                    scheme.primary,
                  ],
                ),
              ),
              child: Icon(game.icon, color: Colors.white, size: 32),
            ),
            const SizedBox(width: 22),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    game.name,
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.4,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    game.tagline,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 21,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            if (best != null && best! > 0) ...[
              Icon(Icons.emoji_events_rounded, size: 22, color: scheme.primary),
              const SizedBox(width: 8),
              Text(
                '$best',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: scheme.primary,
                ),
              ),
              const SizedBox(width: 14),
            ],
            Icon(
              Icons.chevron_right_rounded,
              size: 32,
              color: scheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}
