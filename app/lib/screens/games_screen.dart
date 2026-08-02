import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../state/games.dart';
import '../widgets/glass_box.dart';

/// Onglet « Jeux » : le catalogue des jeux musicaux, jouables avec sa propre
/// bibliothèque. Chaque carte affiche le meilleur score déjà réalisé.
class GamesScreen extends ConsumerWidget {
  const GamesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final stats = ref.watch(gameStatsProvider);

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: EdgeInsets.only(
            bottom: MediaQuery.paddingOf(context).bottom + 110,
          ),
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 14, 20, 2),
              child: Text(
                'Jeux',
                style: TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.6,
                  height: 1.02,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
              child: Text(
                'Quatre façons de jouer avec ta propre bibliothèque.',
                style: TextStyle(fontSize: 14, color: scheme.onSurfaceVariant),
              ),
            ),
            for (final game in kGames)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
                child: _GameCard(game: game, best: stats.best[game.id]),
              ),
          ],
        ),
      ),
    );
  }
}

class _GameCard extends StatelessWidget {
  const _GameCard({required this.game, this.best});

  final GameInfo game;
  final int? best;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GlassBox(
      radius: 22,
      blur: false,
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: () => context.push(game.route),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
          child: Row(
            children: [
              // Pastille accent : la signature colorée du design.
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color.lerp(scheme.primary, Colors.white, 0.25)!,
                      scheme.primary,
                    ],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: scheme.primary.withValues(alpha: 0.4),
                      blurRadius: 16,
                      offset: const Offset(0, 7),
                    ),
                  ],
                ),
                child: Icon(game.icon, color: Colors.white, size: 27),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      game.name,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      game.tagline,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.25,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    if (best != null && best! > 0) ...[
                      const SizedBox(height: 7),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.emoji_events_rounded,
                            size: 14,
                            color: scheme.primary,
                          ),
                          const SizedBox(width: 5),
                          Text(
                            '${game.scoreLabel} : $best',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: scheme.primary,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: scheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}
