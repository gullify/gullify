import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/party_repository.dart';
import '../../state/games.dart';
import '../../state/party.dart';
import '../../widgets/artwork.dart';
import '../../widgets/glass_box.dart';
import '../../widgets/glass_kit.dart';
import 'game_kit.dart';

const _ok = Color(0xFF2FA36B);
const _ko = Color(0xFFE5484D);

/// La manche en cours, côté hôte : le même contenu que la page invité, dans
/// le langage visuel de l'app. C'est toujours le serveur qui décide de ce qui
/// est visible — l'écran ne fait que peindre ce qu'il reçoit.
class PartyRoundView extends ConsumerWidget {
  const PartyRoundView({
    super.key,
    required this.party,
    required this.snippet,
  });

  final PartyState party;
  final SnippetPlayer snippet;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final round = party.round;
    if (round == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final ratio = party.progress;
    final revealed = party.isRevealed;
    final me = party.me;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 24),
      children: [
        GameStatusBar(
          children: [
            GameStatChip(
              label: 'Manche',
              value: '${party.roundIndex + 1}/${party.roundCount}',
            ),
            GameStatChip(label: 'Mon score', value: '${me?.score ?? 0}'),
            if (party.game == kChronoGame.id)
              GameStatChip(
                label: 'Vies',
                value: '',
                valueWidget: GameLives(lives: me?.lives ?? 0),
              )
            else
              GameStatChip(label: 'Joueurs', value: '${party.players.length}'),
          ],
        ),
        const SizedBox(height: 12),
        // Le chrono de la manche, tenu par le serveur.
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: ratio,
            minHeight: 7,
            backgroundColor: scheme.onSurface.withValues(alpha: 0.08),
            color: !revealed && ratio < 0.25 ? _ko : scheme.primary,
          ),
        ),
        const SizedBox(height: 5),
        Center(
          child: Text(
            revealed
                ? 'Manche suivante…'
                : '${(party.remaining.inMilliseconds / 1000).ceil()} s',
            style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
          ),
        ),
        const SizedBox(height: 12),
        switch (round.kind) {
          'blind' => _BlindRound(party: party, round: round, snippet: snippet),
          'cover' => _CoverRound(party: party, round: round),
          'duel' => _DuelRound(party: party, round: round),
          'chrono' =>
            _ChronoRound(party: party, round: round, snippet: snippet),
          _ => const SizedBox.shrink(),
        },
        const SizedBox(height: 18),
        PartyPlayerList(party: party, showScores: true),
      ],
    );
  }
}

/// L'état d'une proposition une fois la manche révélée.
GameChoiceState _choiceState(PartyState party, PartyRound round, String id) {
  final picked = round.myAnswer == id;
  if (!party.isRevealed || round.answerId == null) {
    // Avant la révélation on montre seulement ce qu'on a choisi — surtout pas
    // en vert, qui laisserait croire que c'est la bonne réponse.
    if (!round.answered) return GameChoiceState.idle;
    return picked ? GameChoiceState.idle : GameChoiceState.faded;
  }
  if (id == round.answerId) return GameChoiceState.correct;
  if (picked) return GameChoiceState.wrong;
  return GameChoiceState.faded;
}

/// Bandeau de verdict commun aux jeux à propositions.
class _Verdict extends StatelessWidget {
  const _Verdict({required this.correct, required this.answered});

  final bool correct;
  final bool answered;

  @override
  Widget build(BuildContext context) {
    final color = correct ? _ok : _ko;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          correct ? Icons.check_circle_rounded : Icons.cancel_rounded,
          size: 20,
          color: color,
        ),
        const SizedBox(width: 8),
        Text(
          correct ? 'Bien vu !' : (answered ? 'Raté' : 'Temps écoulé'),
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: color,
          ),
        ),
      ],
    );
  }
}

/// Commandes d'écoute de l'extrait (l'hôte a toujours le son).
class _SnippetControls extends StatelessWidget {
  const _SnippetControls({required this.snippet, required this.startSec});

  final SnippetPlayer snippet;
  final int startSec;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<bool>(
      stream: snippet.playingStream,
      initialData: false,
      builder: (context, snap) {
        final playing = snap.data ?? false;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(height: 26, child: EqBars(playing: playing, height: 26)),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                GlassIconButton(
                  icon: Icons.replay_rounded,
                  tooltip: 'Réécouter l\'extrait',
                  onPressed: () =>
                      snippet.replay(Duration(seconds: startSec)),
                ),
                const SizedBox(width: 14),
                GlassIconButton(
                  icon: playing
                      ? Icons.pause_rounded
                      : Icons.play_arrow_rounded,
                  tooltip: playing ? 'Pause' : 'Écouter',
                  size: 52,
                  onPressed: snippet.toggle,
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

// ────────────────────────────────────────────────────────────── blind test ──

class _BlindRound extends ConsumerWidget {
  const _BlindRound({
    required this.party,
    required this.round,
    required this.snippet,
  });

  final PartyState party;
  final PartyRound round;
  final SnippetPlayer snippet;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final revealed = party.isRevealed;
    final correct = round.myAnswer != null && round.myAnswer == round.answerId;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GlassBox(
          radius: 24,
          blur: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            child: revealed
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _Verdict(correct: correct, answered: round.answered),
                      const SizedBox(height: 12),
                      Artwork(
                        url: round.artworkUrl,
                        size: 84,
                        borderRadius: 16,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        round.title ?? '',
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        round.artist ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Quel est ce titre ?',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.3,
                          color: scheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 10),
                      _SnippetControls(
                        snippet: snippet,
                        startSec: round.startSec,
                      ),
                    ],
                  ),
          ),
        ),
        const SizedBox(height: 12),
        for (final option in round.options)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: GameChoiceTile(
              title: option.title,
              subtitle: option.subtitle ?? '',
              state: _choiceState(party, round, option.id),
              onTap: revealed || round.answered
                  ? null
                  : () => ref.read(partyProvider.notifier).answer(option.id),
            ),
          ),
      ],
    );
  }
}

// ───────────────────────────────────────────────────────── pochette mystère ──

class _CoverRound extends ConsumerWidget {
  const _CoverRound({required this.party, required this.round});

  final PartyState party;
  final PartyRound round;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final revealed = party.isRevealed;
    final correct = round.myAnswer != null && round.myAnswer == round.answerId;
    // La pochette se précise à mesure que le temps passe (22 px → 1,2 px).
    final blur = revealed ? 0.0 : 1.2 + 20.8 * party.progress;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: SizedBox(
              width: 210,
              height: 210,
              child: blur <= 0.01
                  ? Artwork(url: round.artworkUrl, size: 210, borderRadius: 0)
                  : ImageFiltered(
                      imageFilter: ImageFilter.blur(
                        sigmaX: blur,
                        sigmaY: blur,
                        tileMode: TileMode.decal,
                      ),
                      child: Artwork(
                        url: round.artworkUrl,
                        size: 210,
                        borderRadius: 0,
                      ),
                    ),
            ),
          ),
        ),
        const SizedBox(height: 14),
        if (revealed) ...[
          _Verdict(correct: correct, answered: round.answered),
          const SizedBox(height: 6),
          Text(
            round.title ?? '',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          Text(
            round.artist ?? '',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
          ),
        ] else
          Center(
            child: Text(
              'Quel est cet album ?',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.3,
                color: scheme.onSurface,
              ),
            ),
          ),
        const SizedBox(height: 14),
        for (final option in round.options)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: GameChoiceTile(
              title: option.title,
              subtitle: option.subtitle ?? '',
              state: _choiceState(party, round, option.id),
              onTap: revealed || round.answered
                  ? null
                  : () => ref.read(partyProvider.notifier).answer(option.id),
            ),
          ),
      ],
    );
  }
}

// ──────────────────────────────────────────────────────────── duel d'années ──

class _DuelRound extends ConsumerWidget {
  const _DuelRound({required this.party, required this.round});

  final PartyState party;
  final PartyRound round;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final left = round.left;
    final right = round.right;
    if (left == null || right == null) return const SizedBox.shrink();
    final revealed = party.isRevealed;
    final correct = round.myAnswer != null && round.myAnswer == round.answerId;

    return Column(
      children: [
        Text(
          'Lequel est le plus ancien ?',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.3,
            color: scheme.onSurface,
          ),
        ),
        const SizedBox(height: 14),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _DuelCard(party: party, round: round, side: left)),
            const SizedBox(width: 10),
            Expanded(child: _DuelCard(party: party, round: round, side: right)),
          ],
        ),
        if (revealed) ...[
          const SizedBox(height: 14),
          _Verdict(correct: correct, answered: round.answered),
        ],
      ],
    );
  }
}

class _DuelCard extends ConsumerWidget {
  const _DuelCard({
    required this.party,
    required this.round,
    required this.side,
  });

  final PartyState party;
  final PartyRound round;
  final PartyDuelSide side;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final state = _choiceState(party, round, side.id);
    final color = switch (state) {
      GameChoiceState.correct => _ok,
      GameChoiceState.wrong => _ko,
      GameChoiceState.idle || GameChoiceState.faded => null,
    };
    final enabled = !party.isRevealed && !round.answered;

    return Opacity(
      opacity: state == GameChoiceState.faded ? 0.45 : 1,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          color: color?.withValues(alpha: 0.16),
          border: color == null
              ? null
              : Border.all(color: color.withValues(alpha: 0.9), width: 1.6),
        ),
        child: GlassBox(
          radius: 20,
          blur: false,
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: enabled
                ? () => ref.read(partyProvider.notifier).answer(side.id)
                : null,
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AspectRatio(
                    aspectRatio: 1,
                    child: Artwork(url: side.artworkUrl, borderRadius: 14),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    side.title,
                    maxLines: 2,
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      height: 1.2,
                    ),
                  ),
                  Text(
                    side.subtitle ?? '',
                    maxLines: 1,
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  if (side.year != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      '${side.year}',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.6,
                        color: color ?? scheme.primary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────── chrono ──

class _ChronoRound extends ConsumerWidget {
  const _ChronoRound({
    required this.party,
    required this.round,
    required this.snippet,
  });

  final PartyState party;
  final PartyRound round;
  final SnippetPlayer snippet;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final mine = party.myTurn;
    final turn = party.playerById(party.turnPlayerId);
    final shown = mine ? party.me : turn;
    final cards = shown?.timeline ?? const <PartyCard>[];
    final canPlace = mine && !party.isRevealed && !round.answered;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GlassBox(
          radius: 24,
          blur: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  party.isRevealed
                      ? (mine ? 'Ton tour' : 'Tour de ${turn?.name ?? ''}')
                      : (mine
                            ? 'À toi de placer'
                            : 'Au tour de ${turn?.name ?? '…'}'),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                    color: scheme.onSurface,
                  ),
                ),
                if (party.isRevealed && round.year != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    '${round.year}',
                    style: TextStyle(
                      fontSize: 40,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -1.4,
                      color: scheme.primary,
                    ),
                  ),
                  Text(
                    round.title ?? '',
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    round.artist ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ] else ...[
                  const SizedBox(height: 10),
                  _SnippetControls(snippet: snippet, startSec: round.startSec),
                  if (!mine) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Écoute avec — c\'est à ${turn?.name ?? 'quelqu\'un d\'autre'} de placer la carte.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        Text(
          mine ? 'Ta frise' : 'La frise de ${turn?.name ?? ''}',
          style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 6),
        SizedBox(
          // Hauteur d'une carte de frise : pochette + année + titre, avec la
          // marge qu'il faut pour ne pas rogner la dernière ligne.
          height: 126,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              for (var gap = 0; gap <= cards.length; gap++) ...[
                _TimelineGap(
                  enabled: canPlace,
                  onTap: () => ref.read(partyProvider.notifier).answer('$gap'),
                ),
                if (gap < cards.length) _TimelineCard(card: cards[gap]),
              ],
            ],
          ),
        ),
        if (canPlace) ...[
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: () => ref.read(partyProvider.notifier).skip(),
            icon: const Icon(Icons.skip_next_rounded, size: 18),
            label: const Text('Passer mon tour'),
          ),
        ],
      ],
    );
  }
}

class _TimelineGap extends StatelessWidget {
  const _TimelineGap({required this.enabled, required this.onTap});

  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 30),
      child: Opacity(
        opacity: enabled ? 1 : 0.2,
        child: SizedBox(
          width: 40,
          child: OutlinedButton(
            onPressed: enabled ? onTap : null,
            style: OutlinedButton.styleFrom(
              padding: EdgeInsets.zero,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              side: BorderSide(
                color: scheme.primary.withValues(alpha: 0.7),
              ),
            ),
            child: Icon(Icons.add_rounded, color: scheme.primary, size: 20),
          ),
        ),
      ),
    );
  }
}

class _TimelineCard extends StatelessWidget {
  const _TimelineCard({required this.card});

  final PartyCard card;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: SizedBox(
        width: 112,
        child: GlassBox(
          radius: 16,
          blur: false,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Artwork(url: card.artworkUrl, size: 40, borderRadius: 10),
                const SizedBox(height: 4),
                Text(
                  '${card.year}',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                  ),
                ),
                Text(
                  card.title,
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
      ),
    );
  }
}

// ───────────────────────────────────────────────────────────────── joueurs ──

/// La liste des joueurs : pastille de réponse, score, vies au Chrono.
class PartyPlayerList extends StatelessWidget {
  const PartyPlayerList({
    super.key,
    required this.party,
    required this.showScores,
    this.ranked = false,
  });

  final PartyState party;
  final bool showScores;

  /// Trié par score et numéroté (classement final).
  final bool ranked;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final players = ranked ? party.ranking : party.players;

    return GlassBox(
      radius: 20,
      blur: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        child: Column(
          children: [
            for (var i = 0; i < players.length; i++)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 9),
                child: Row(
                  children: [
                    if (ranked)
                      SizedBox(
                        width: 24,
                        child: Text(
                          '${i + 1}',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    _AnswerDot(player: players[i], party: party),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        players[i].id == party.meId
                            ? '${players[i].name} (toi)'
                            : players[i].name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (party.game == kChronoGame.id && party.isPlaying) ...[
                      GameLives(lives: players[i].lives),
                      const SizedBox(width: 8),
                    ],
                    if (showScores)
                      Text(
                        players[i].gained != null && players[i].gained! > 0
                            ? '${players[i].score} (+${players[i].gained})'
                            : '${players[i].score}',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.3,
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
}

/// Pastille d'état : grise (pas répondu), verte / rouge une fois révélé.
class _AnswerDot extends StatelessWidget {
  const _AnswerDot({required this.player, required this.party});

  final PartyPlayer player;
  final PartyState party;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = !player.answered
        ? scheme.onSurfaceVariant.withValues(alpha: 0.3)
        : player.correct == null
        ? scheme.primary
        : (player.correct! ? _ok : _ko);
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}
