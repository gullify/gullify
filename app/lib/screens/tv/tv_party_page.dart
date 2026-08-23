import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../api/party_repository.dart';
import '../../models/game_source.dart';
import '../../state/games.dart';
import '../../state/party.dart';
import '../../state/player.dart';
import '../../screens/games/game_kit.dart';
import 'tv_kit.dart';

/// Les jeux à plusieurs, la télé en hôte.
///
/// C'est l'écran qui justifie à lui seul une app de téléviseur : le salon a
/// enfin un grand écran commun, et chacun garde son téléphone en buzzer. Le
/// mode « ensemble » est fait pour ça — le son ne sort que de l'hôte, et
/// l'hôte, c'est la télé.
///
/// Rien de neuf côté serveur : la télé est un joueur hôte de plus, avec le
/// même jeton et le même `party.php` que l'app mobile.
class TvPartyPage extends ConsumerStatefulWidget {
  const TvPartyPage({super.key});

  @override
  ConsumerState<TvPartyPage> createState() => _TvPartyPageState();
}

class _TvPartyPageState extends ConsumerState<TvPartyPage> {
  final _snippet = SnippetPlayer();

  /// Redessine le décompte entre deux réponses du serveur.
  Timer? _ticker;

  /// Manche dont l'extrait est déjà lancé.
  String? _playingKey;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(milliseconds: 120), (_) {
      if (mounted) setState(() {});
    });
    // La musique en cours se tait : un extrait mystère ne doit pas se
    // superposer à l'album qu'on écoutait avant de lancer la partie.
    Future.microtask(() async {
      try {
        await ref.read(audioHandlerProvider).pause();
      } catch (_) {}
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _snippet.dispose();
    super.dispose();
  }

  /// C'est la télé qui fait sonner les extraits, quel que soit le mode : elle
  /// est l'appareil de l'hôte.
  void _syncAudio(PartyState? party) {
    if (party == null || !party.isPlaying || party.phase != 'guessing') {
      if (_playingKey != null) {
        _playingKey = null;
        _snippet.stop();
      }
      return;
    }
    final round = party.round;
    final path = round?.filePath;
    if (round == null || path == null || path.isEmpty) return;
    final key = '${party.code}:${party.roundIndex}';
    if (key == _playingKey) return;
    _playingKey = key;
    _snippet.playFrom(
      ref.read(partyStreamUrlProvider)(path),
      Duration(seconds: round.startSec),
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(partyProvider);
    final party = session.state;
    _syncAudio(party);

    if (!session.active || party == null) return _Setup(error: session.error);
    if (party.isLobby) return _Lobby(session: session, party: party);
    if (party.isFinished) return _Finished(party: party);
    return _Round(party: party, snippet: _snippet);
  }
}

// ───────────────────────────────────────────────────────────────── réglages ──

class _Setup extends ConsumerStatefulWidget {
  const _Setup({this.error});

  final String? error;

  @override
  ConsumerState<_Setup> createState() => _SetupState();
}

class _SetupState extends ConsumerState<_Setup> {
  String _game = kBlindGame.id;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final busy = ref.watch(partyProvider).busy;

    return TvScaffold(
      title: 'Jouer à plusieurs',
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Choisis un jeu. La télé affichera le code, tes invités '
                  'joueront depuis leur téléphone.',
                  style: TextStyle(
                    fontSize: 26,
                    height: 1.4,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 30),
                for (var i = 0; i < kGames.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _GameRow(
                      game: kGames[i],
                      selected: _game == kGames[i].id,
                      autofocus: i == 0,
                      onPressed: () => setState(() => _game = kGames[i].id),
                    ),
                  ),
                const Spacer(),
                if (widget.error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Text(
                      widget.error!,
                      style: TextStyle(fontSize: 24, color: scheme.error),
                    ),
                  ),
                TvPill(
                  label: busy ? 'Ouverture du salon…' : 'Ouvrir le salon',
                  icon: Icons.group_add_rounded,
                  onPressed: busy
                      ? null
                      : () => ref
                            .read(partyProvider.notifier)
                            .create(
                              game: _game,
                              // Sur un téléviseur, l'audio sort forcément
                              // d'ici : c'est le seul appareil de la pièce
                              // qui a des haut-parleurs qui comptent.
                              audioMode: 'host',
                              source: GameSource.all,
                            ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 70),
          SizedBox(width: 560, child: _Rules(gameId: _game)),
        ],
      ),
    );
  }
}

class _GameRow extends StatelessWidget {
  const _GameRow({
    required this.game,
    required this.selected,
    required this.onPressed,
    this.autofocus = false,
  });

  final GameInfo game;
  final bool selected;
  final bool autofocus;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return TvFocusable(
      onPressed: onPressed,
      autofocus: autofocus,
      scale: 1.0,
      builder: (context, focused) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        decoration: BoxDecoration(
          color: selected
              ? scheme.primary.withValues(alpha: 0.16)
              : Colors.white.withValues(alpha: focused ? 0.10 : 0.05),
          borderRadius: BorderRadius.circular(22),
          border: focused
              ? tvFocusBorder(scheme.primary)
              : Border.all(
                  color: selected
                      ? scheme.primary.withValues(alpha: 0.8)
                      : Colors.white.withValues(alpha: 0.12),
                  width: selected ? 2 : 1,
                ),
          boxShadow: focused ? tvFocusGlow(scheme.primary, spread: 4) : null,
        ),
        child: Row(
          children: [
            Icon(
              game.icon,
              size: 36,
              color: selected ? scheme.primary : scheme.onSurfaceVariant,
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
                      fontSize: 30,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    game.tagline,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 23,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            if (selected)
              Icon(Icons.check_circle_rounded, size: 34, color: scheme.primary),
          ],
        ),
      ),
    );
  }
}

class _Rules extends StatelessWidget {
  const _Rules({required this.gameId});

  final String gameId;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final game = gameById(gameId);
    if (game == null) return const SizedBox.shrink();
    return TvGlass(
      padding: const EdgeInsets.all(34),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'LE BUT',
            style: TextStyle(
              fontSize: tvMinText,
              fontWeight: FontWeight.w700,
              letterSpacing: 2.4,
              color: scheme.primary,
            ),
          ),
          const SizedBox(height: 10),
          Text(game.goal, style: const TextStyle(fontSize: 26, height: 1.4)),
          const SizedBox(height: 26),
          Text(
            'COMMENT ON JOUE',
            style: TextStyle(
              fontSize: tvMinText,
              fontWeight: FontWeight.w700,
              letterSpacing: 2.4,
              color: scheme.primary,
            ),
          ),
          const SizedBox(height: 12),
          for (final rule in game.rules)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 10, right: 14),
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: scheme.primary,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      rule,
                      style: TextStyle(
                        fontSize: 23,
                        height: 1.35,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────── salon ──

class _Lobby extends ConsumerWidget {
  const _Lobby({required this.session, required this.party});

  final PartySession session;
  final PartyState party;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final url = session.shareUrl ?? '';
    final enough = party.players.length >= 2;

    return TvScaffold(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 620,
            child: TvGlass(
              padding: const EdgeInsets.all(44),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    (gameById(party.game)?.name ?? 'Partie').toUpperCase(),
                    style: TextStyle(
                      fontSize: tvMinText,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 3,
                      color: scheme.primary,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    party.code,
                    style: TextStyle(
                      fontSize: 124,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 18,
                      height: 1,
                      color: scheme.primary,
                      shadows: [
                        Shadow(
                          color: scheme.primary.withValues(alpha: 0.55),
                          blurRadius: 60,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    url.replaceFirst(RegExp('^https?://'), ''),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 26,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 28),
                  if (url.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: QrImageView(
                        data: url,
                        size: 220,
                        // Un QR ne se scanne bien qu'en noir sur blanc : le
                        // verre translucide ferait échouer la moitié des
                        // téléphones.
                        backgroundColor: Colors.white,
                        eyeStyle: const QrEyeStyle(
                          eyeShape: QrEyeShape.square,
                          color: Color(0xFF0B0D12),
                        ),
                        dataModuleStyle: const QrDataModuleStyle(
                          dataModuleShape: QrDataModuleShape.square,
                          color: Color(0xFF0B0D12),
                        ),
                      ),
                    ),
                  const SizedBox(height: 22),
                  Text(
                    'Scanne le code, ou tape l\'adresse. Le lien meurt avec '
                    'la partie.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 23,
                      height: 1.4,
                      color: scheme.onSurfaceVariant.withValues(alpha: 0.75),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 60),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Joueurs (${party.players.length}/${party.maxPlayers})',
                  style: const TextStyle(
                    fontSize: 40,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -1,
                  ),
                ),
                const SizedBox(height: 22),
                Expanded(
                  child: ListView.builder(
                    itemCount: party.players.length,
                    itemBuilder: (context, i) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Row(
                        children: [
                          TvDot(color: scheme.primary, size: 16),
                          const SizedBox(width: 18),
                          Expanded(
                            child: Text(
                              party.players[i].name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 32,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          if (party.players[i].isHost)
                            Text(
                              'cette télé',
                              style: TextStyle(
                                fontSize: tvMinText,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                Row(
                  children: [
                    TvPill(
                      label: enough
                          ? 'Démarrer la partie'
                          : 'En attente d\'un joueur…',
                      icon: Icons.play_arrow_rounded,
                      autofocus: true,
                      onPressed: enough && !session.busy
                          ? () => ref.read(partyProvider.notifier).start()
                          : null,
                    ),
                    const SizedBox(width: 16),
                    TvPill(
                      label: 'Fermer',
                      accent: false,
                      onPressed: () => ref.read(partyProvider.notifier).close(),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────── manche ──

class _Round extends ConsumerWidget {
  const _Round({required this.party, required this.snippet});

  final PartyState party;
  final SnippetPlayer snippet;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final round = party.round;
    if (round == null) {
      return const TvScaffold(
        child: Center(child: CircularProgressIndicator()),
      );
    }

    return TvScaffold(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'Manche ${party.roundIndex + 1} sur ${party.roundCount}',
                      style: const TextStyle(
                        fontSize: 34,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.7,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      party.isRevealed
                          ? 'Manche suivante…'
                          : '${(party.remaining.inMilliseconds / 1000).ceil()} s',
                      style: TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w700,
                        color: party.isRevealed
                            ? scheme.onSurfaceVariant
                            : scheme.primary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                ClipRRect(
                  borderRadius: BorderRadius.circular(7),
                  child: LinearProgressIndicator(
                    value: party.progress,
                    minHeight: 12,
                    backgroundColor: scheme.onSurface.withValues(alpha: 0.1),
                    color: !party.isRevealed && party.progress < 0.25
                        ? TvDot.ko
                        : scheme.primary,
                  ),
                ),
                const SizedBox(height: 38),
                Expanded(
                  child: _RoundBody(party: party, round: round),
                ),
              ],
            ),
          ),
          const SizedBox(width: 60),
          SizedBox(width: 480, child: _Scores(party: party)),
        ],
      ),
    );
  }
}

class _RoundBody extends StatelessWidget {
  const _RoundBody({required this.party, required this.round});

  final PartyState party;
  final PartyRound round;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    Widget question(String text) => Text(
      text,
      style: const TextStyle(
        fontSize: 46,
        fontWeight: FontWeight.w800,
        letterSpacing: -1.3,
      ),
    );

    Widget option(PartyOption o) {
      final correct = party.isRevealed && round.answerId == o.id;
      final dimmed = party.isRevealed && !correct;
      return Opacity(
        opacity: dimmed ? 0.4 : 1,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 22),
          decoration: BoxDecoration(
            color: correct
                ? TvDot.ok.withValues(alpha: 0.2)
                : Colors.white.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: correct ? TvDot.ok : Colors.white.withValues(alpha: 0.14),
              width: correct ? 2.5 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                o.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (o.subtitle != null && o.subtitle!.isNotEmpty)
                Text(
                  o.subtitle!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 23,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
      );
    }

    // Deux colonnes, en hauteur intrinsèque : un rapport d'aspect fixe
    // rognerait la deuxième ligne dès qu'un titre passe à la ligne.
    Widget grid(List<PartyOption> options) => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < options.length; i += 2)
          Padding(
            padding: const EdgeInsets.only(bottom: 18),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: option(options[i])),
                  const SizedBox(width: 18),
                  if (i + 1 < options.length)
                    Expanded(child: option(options[i + 1]))
                  else
                    const Spacer(),
                ],
              ),
            ),
          ),
      ],
    );

    switch (round.kind) {
      case 'blind':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            question(
              party.isRevealed
                  ? (round.title ?? 'Réponse')
                  : 'Quel est ce titre ?',
            ),
            if (party.isRevealed && round.artist != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  round.artist!,
                  style: TextStyle(
                    fontSize: 30,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            const SizedBox(height: 30),
            grid(round.options),
          ],
        );

      case 'cover':
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _BlurredCover(
              url: round.artworkUrl,
              // La pochette se précise à mesure que le temps passe.
              blur: party.isRevealed ? 0 : 1.2 + 20.8 * party.progress,
            ),
            const SizedBox(width: 40),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  question(
                    party.isRevealed
                        ? (round.title ?? 'Réponse')
                        : 'Quel est cet album ?',
                  ),
                  const SizedBox(height: 26),
                  grid(round.options),
                ],
              ),
            ),
          ],
        );

      case 'duel':
        final left = round.left;
        final right = round.right;
        if (left == null || right == null) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            question('Lequel est le plus ancien ?'),
            const SizedBox(height: 30),
            Expanded(
              child: Row(
                children: [
                  Expanded(
                    child: _DuelSide(
                      side: left,
                      winner: party.isRevealed && round.answerId == left.id,
                      revealed: party.isRevealed,
                    ),
                  ),
                  const SizedBox(width: 26),
                  Expanded(
                    child: _DuelSide(
                      side: right,
                      winner: party.isRevealed && round.answerId == right.id,
                      revealed: party.isRevealed,
                    ),
                  ),
                ],
              ),
            ),
          ],
        );

      case 'chrono':
        final turn = party.playerById(party.turnPlayerId);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            question(
              party.isRevealed && round.year != null
                  ? '${round.year}'
                  : 'Au tour de ${turn?.name ?? '…'}',
            ),
            if (party.isRevealed && round.title != null) ...[
              const SizedBox(height: 10),
              Text(
                round.title!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                round.artist ?? '',
                style: TextStyle(fontSize: 26, color: scheme.onSurfaceVariant),
              ),
            ] else
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(
                  '${turn?.name ?? 'Le joueur'} place la carte sur sa frise, '
                  'depuis son téléphone.',
                  style: TextStyle(
                    fontSize: 26,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            const SizedBox(height: 34),
            if (turn?.timeline != null) _Timeline(cards: turn!.timeline!),
          ],
        );

      default:
        return const SizedBox.shrink();
    }
  }
}

class _BlurredCover extends StatelessWidget {
  const _BlurredCover({required this.url, required this.blur});

  final String? url;
  final double blur;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(24),
    child: SizedBox(
      width: 340,
      height: 340,
      child: blur <= 0.02
          ? TvArtwork(url: url, size: 340, borderRadius: 0)
          : ImageFiltered(
              imageFilter: ImageFilter.blur(
                sigmaX: blur,
                sigmaY: blur,
                tileMode: TileMode.decal,
              ),
              child: TvArtwork(url: url, size: 340, borderRadius: 0),
            ),
    ),
  );
}

class _DuelSide extends StatelessWidget {
  const _DuelSide({
    required this.side,
    required this.winner,
    required this.revealed,
  });

  final PartyDuelSide side;
  final bool winner;
  final bool revealed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Opacity(
      opacity: revealed && !winner ? 0.45 : 1,
      child: Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: winner
              ? TvDot.ok.withValues(alpha: 0.18)
              : Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(26),
          border: Border.all(
            color: winner ? TvDot.ok : Colors.white.withValues(alpha: 0.14),
            width: winner ? 2.5 : 1,
          ),
        ),
        child: Row(
          children: [
            TvArtwork(url: side.artworkUrl, size: 150, borderRadius: 18),
            const SizedBox(width: 22),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    side.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                      height: 1.15,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    side.subtitle ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 23,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  if (side.year != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      '${side.year}',
                      style: TextStyle(
                        fontSize: 44,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -1.2,
                        color: winner ? TvDot.ok : scheme.primary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Timeline extends StatelessWidget {
  const _Timeline({required this.cards});

  final List<PartyCard> cards;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 176,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: cards.length,
        separatorBuilder: (_, _) => const SizedBox(width: 14),
        itemBuilder: (context, i) => Container(
          width: 138,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TvArtwork(url: cards[i].artworkUrl, size: 62, borderRadius: 12),
              const SizedBox(height: 8),
              Text(
                '${cards[i].year}',
                style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.6,
                ),
              ),
              Text(
                cards[i].title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 16, color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Le tableau d'affichage : c'est tout ce que la télé a à faire pendant une
/// manche — personne ne vise rien ici, tout le monde répond sur son téléphone.
class _Scores extends StatelessWidget {
  const _Scores({required this.party});

  final PartyState party;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final players = party.ranking;
    final answered = party.players.where((p) => p.answered).length;

    return TvGlass(
      padding: const EdgeInsets.all(30),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'CLASSEMENT',
            style: TextStyle(
              fontSize: tvMinText,
              fontWeight: FontWeight.w700,
              letterSpacing: 2.6,
              color: scheme.primary,
            ),
          ),
          const SizedBox(height: 18),
          Expanded(
            child: ListView.builder(
              itemCount: players.length,
              itemBuilder: (context, i) => Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Row(
                  children: [
                    SizedBox(
                      width: 34,
                      child: Text(
                        '${i + 1}',
                        style: TextStyle(
                          fontSize: tvMinText,
                          fontWeight: FontWeight.w800,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    TvDot(
                      color: !players[i].answered
                          ? scheme.onSurfaceVariant.withValues(alpha: 0.3)
                          : players[i].correct == null
                          ? scheme.primary
                          : (players[i].correct! ? TvDot.ok : TvDot.ko),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        players[i].name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 27,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (party.game == kChronoGame.id)
                      Padding(
                        padding: const EdgeInsets.only(right: 12),
                        child: Text(
                          '❤' * players[i].lives,
                          style: const TextStyle(fontSize: 18),
                        ),
                      ),
                    Text(
                      '${players[i].score}',
                      style: const TextStyle(
                        fontSize: 27,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Text(
            '$answered sur ${party.players.length} ont répondu',
            style: TextStyle(
              fontSize: tvMinText,
              color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }
}

// ───────────────────────────────────────────────────────────── fin de partie ──

class _Finished extends ConsumerWidget {
  const _Finished({required this.party});

  final PartyState party;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final ranking = party.ranking;
    final winner = ranking.isEmpty ? null : ranking.first;
    final unit = party.game == kChronoGame.id ? 'cartes' : 'points';

    return TvScaffold(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(height: 20),
          const Icon(
            Icons.emoji_events_rounded,
            size: 88,
            color: Color(0xFFE3A94F),
          ),
          const SizedBox(height: 18),
          Text(
            winner == null ? 'Partie terminée' : '${winner.name} gagne !',
            style: const TextStyle(
              fontSize: 64,
              fontWeight: FontWeight.w800,
              letterSpacing: -2,
            ),
          ),
          if (winner != null) ...[
            const SizedBox(height: 10),
            Text(
              '${winner.score} $unit',
              style: TextStyle(fontSize: 34, color: scheme.onSurfaceVariant),
            ),
          ],
          const SizedBox(height: 40),
          Expanded(
            child: SizedBox(
              width: 760,
              child: ListView.builder(
                itemCount: ranking.length,
                itemBuilder: (context, i) => Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 60,
                        child: Text(
                          '${i + 1}',
                          style: TextStyle(
                            fontSize: 30,
                            fontWeight: FontWeight.w800,
                            color: i == 0
                                ? const Color(0xFFE3A94F)
                                : scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          ranking[i].name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      Text(
                        '${ranking[i].score}',
                        style: const TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          TvPill(
            label: 'Nouvelle partie',
            icon: Icons.refresh_rounded,
            autofocus: true,
            onPressed: () => ref.read(partyProvider.notifier).close(),
          ),
        ],
      ),
    );
  }
}
