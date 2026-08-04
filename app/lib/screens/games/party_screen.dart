import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../api/party_repository.dart';
import '../../state/games.dart';
import '../../state/party.dart';
import '../../state/party_voice.dart';
import '../../state/player.dart';
import '../../widgets/glass_box.dart';
import '../../widgets/glass_kit.dart';
import 'game_kit.dart';
import 'game_source_sheet.dart';
import 'party_round.dart';
import 'party_talk.dart';

/// Écran unique du multijoueur : réglages du salon tant qu'aucune partie n'est
/// ouverte, puis salon d'attente, manches et classement final.
///
/// L'hôte joue avec les invités : il a un jeton de partie comme eux, et c'est
/// son appareil qui fait sonner les extraits quand l'audio reste « chez
/// l'hôte ».
class PartyScreen extends ConsumerStatefulWidget {
  const PartyScreen({super.key});

  @override
  ConsumerState<PartyScreen> createState() => _PartyScreenState();
}

class _PartyScreenState extends ConsumerState<PartyScreen> {
  final _snippet = SnippetPlayer();

  /// Redessine le décompte sans attendre le prochain sondage réseau.
  Timer? _ticker;

  /// Manche dont l'extrait est déjà lancé (pour ne pas le relancer à chaque
  /// rafraîchissement).
  String? _playingKey;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (mounted) setState(() {});
    });
    // Le lecteur principal se tait : un extrait mystère ne doit jamais se
    // superposer à la musique en cours.
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

  /// Lance l'extrait de la manche en cours si elle en a un.
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

  Future<void> _quit() async {
    final session = ref.read(partyProvider);
    if (!session.active) {
      if (mounted) context.pop();
      return;
    }
    final leave = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Fermer la partie ?'),
        content: const Text(
          'Le lien envoyé aux invités cessera immédiatement de fonctionner.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Continuer à jouer'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Fermer'),
          ),
        ],
      ),
    );
    if (leave != true) return;
    _snippet.stop();
    await ref.read(partyProvider.notifier).close();
    if (mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(partyProvider);
    final party = session.state;
    _syncAudio(party);

    // Quand quelqu'un parle (ou qu'on parle), l'extrait passe en sourdine :
    // la voix doit rester intelligible par-dessus la musique.
    ref.listen<PartyVoiceState>(partyVoiceProvider, (previous, next) {
      final quiet = next.listening || next.busy;
      if (quiet != ((previous?.listening ?? false) || (previous?.busy ?? false))) {
        _snippet.duck(quiet);
      }
    });

    final title = party == null
        ? 'Jouer à plusieurs'
        : (gameById(party.game)?.name ?? 'Partie');

    return PopScope(
      canPop: !session.active,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _quit();
      },
      child: Scaffold(
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
                      onPressed: _quit,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.5,
                        ),
                      ),
                    ),
                    if (session.code != null)
                      _CodeChip(code: session.code!),
                  ],
                ),
              ),
              Expanded(child: _body(session)),
              if (session.active && party != null)
                PartyTalkBar(maxMs: party.voiceMaxMs),
            ],
          ),
        ),
      ),
    );
  }

  Widget _body(PartySession session) {
    final party = session.state;
    if (!session.active || party == null) return _Setup(error: session.error);
    if (party.isLobby) {
      return _Lobby(session: session, party: party);
    }
    if (party.isFinished) {
      return _Finished(party: party, snippet: _snippet);
    }
    return PartyRoundView(party: party, snippet: _snippet);
  }
}

/// Le code du salon, bien lisible, tapotable pour le copier.
class _CodeChip extends StatelessWidget {
  const _CodeChip({required this.code});

  final String code;

  @override
  Widget build(BuildContext context) {
    return GlassBox(
      radius: 14,
      blur: false,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () {
          Clipboard.setData(ClipboardData(text: code));
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Code copié')),
          );
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          child: Text(
            code,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              letterSpacing: 3,
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────── réglages ──

class _Setup extends ConsumerStatefulWidget {
  const _Setup({this.error});

  final String? error;

  @override
  ConsumerState<_Setup> createState() => _SetupState();
}

class _SetupState extends ConsumerState<_Setup> {
  String _game = kBlindGame.id;
  String _audioMode = 'host';

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final busy = ref.watch(partyProvider).busy;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 24),
      children: [
        Text(
          'Crée un salon, envoie le lien par SMS : chacun joue depuis son '
          'téléphone, sans compte ni installation.',
          style: TextStyle(fontSize: 14, color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 18),
        const SectionTitle('Le jeu', padding: EdgeInsets.fromLTRB(2, 4, 2, 8)),
        for (final game in kGames.where((g) => g.multiplayer))
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: GamePickTile(
              icon: game.icon,
              title: game.name,
              subtitle: game.tagline,
              selected: _game == game.id,
              onTap: () => setState(() => _game = game.id),
            ),
          ),
        const SizedBox(height: 14),
        const SectionTitle('Le vivier', padding: EdgeInsets.fromLTRB(2, 4, 2, 8)),
        GameSourceTile(
          source: ref.watch(gameSourceProvider),
          onChanged: (source) =>
              ref.read(gameSourceProvider.notifier).set(source),
        ),
        const SizedBox(height: 6),
        Text(
          'Les manches sont tirées de ta bibliothèque : ce réglage est le '
          'même qu\'en solo.',
          style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 14),
        const SectionTitle('L\'écoute', padding: EdgeInsets.fromLTRB(2, 4, 2, 8)),
        GamePickTile(
          icon: Icons.speaker_rounded,
          title: 'Ensemble, sur mon appareil',
          subtitle:
              'Les extraits ne sortent que d\'ici. Les invités répondent '
              'depuis leur téléphone.',
          selected: _audioMode == 'host',
          onTap: () => setState(() => _audioMode = 'host'),
        ),
        const SizedBox(height: 8),
        GamePickTile(
          icon: Icons.headphones_rounded,
          title: 'Chacun sur son appareil',
          subtitle:
              'Pour jouer à distance : chaque invité entend l\'extrait dans '
              'son navigateur.',
          selected: _audioMode == 'guests',
          onTap: () => setState(() => _audioMode = 'guests'),
        ),
        if (widget.error != null) ...[
          const SizedBox(height: 14),
          Text(
            widget.error!,
            style: TextStyle(color: scheme.error, fontSize: 13.5),
          ),
        ],
        const SizedBox(height: 22),
        AccentPlayButton(
          label: busy ? 'Création…' : 'Créer le salon',
          icon: Icons.group_add_rounded,
          expand: true,
          onPressed: busy
              ? null
              : () => ref.read(partyProvider.notifier).create(
                  game: _game,
                  audioMode: _audioMode,
                  source: ref.read(gameSourceProvider),
                ),
        ),
        const SizedBox(height: 10),
        Text(
          'Le lien expire à la fin de la partie — et au plus tard six heures '
          'après sa création.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

// ────────────────────────────────────────────────────────────────── salon ──

/// Ce qui change par rapport à la version solo, en une phrase — les règles
/// détaillées de chaque jeu restent celles de sa fiche.
String _partyRules(String game) => switch (game) {
  'blind' =>
    'Dix manches. Tout le monde répond en même temps : plus tu es rapide, '
        'plus tu marques.',
  'cover' =>
    'Huit pochettes qui se précisent seconde après seconde. Le plus rapide '
        'à reconnaître marque le plus.',
  'duel' =>
    'Dix duels. Chacun désigne le plus ancien des deux albums, en même temps.',
  'chrono' =>
    'Chacun sa frise et ses trois vies, chacun son tour. Premier à dix '
        'cartes bien placées.',
  _ => '',
};

class _Lobby extends ConsumerWidget {
  const _Lobby({required this.session, required this.party});

  final PartySession session;
  final PartyState party;

  Future<void> _sms(BuildContext context, String url) async {
    final game = gameById(party.game)?.name ?? 'Gullify';
    final body = Uri.encodeComponent(
      'On joue au $game sur Gullify ! Rejoins-moi : $url',
    );
    final uri = Uri.parse('sms:?body=$body');
    if (!await launchUrl(uri) && context.mounted) {
      await Clipboard.setData(ClipboardData(text: url));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Lien copié — colle-le dans un message')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final url = session.shareUrl ?? '';
    final enough = party.players.length >= 2;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 24),
      children: [
        GlassBox(
          radius: 22,
          blur: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
            child: Column(
              children: [
                Text(
                  party.code,
                  style: TextStyle(
                    fontSize: 46,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 10,
                    color: scheme.primary,
                  ),
                ),
                const SizedBox(height: 4),
                SelectableText(
                  url,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 16),
                AccentPlayButton(
                  label: 'Envoyer par SMS',
                  icon: Icons.sms_rounded,
                  expand: true,
                  onPressed: () => _sms(context, url),
                ),
                const SizedBox(height: 6),
                TextButton.icon(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: url));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Lien copié')),
                    );
                  },
                  icon: const Icon(Icons.link_rounded, size: 18),
                  label: const Text('Copier le lien'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: SectionTitle(
                'Joueurs (${party.players.length}/${party.maxPlayers})',
                padding: const EdgeInsets.fromLTRB(2, 4, 2, 6),
              ),
            ),
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 8),
          ],
        ),
        PartyPlayerList(party: party, showScores: false),
        const SizedBox(height: 10),
        Text(
          _partyRules(party.game),
          style: TextStyle(fontSize: 12.5, height: 1.3, color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 6),
        Text(
          party.guestsHearAudio
              ? 'Chacun écoutera l\'extrait sur son propre appareil.'
              : 'L\'audio ne sortira que de cet appareil : monte le son et '
                  'pose le téléphone au milieu.',
          style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 6),
        Text(
          'Pour vous parler : maintiens le bouton du bas et parle. Les invités '
          'ont le même dans leur navigateur.',
          style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 20),
        AccentPlayButton(
          label: enough ? 'Démarrer la partie' : 'En attente d\'un joueur…',
          icon: Icons.play_arrow_rounded,
          expand: true,
          onPressed: enough && !session.busy
              ? () => ref.read(partyProvider.notifier).start()
              : null,
        ),
        if (session.error != null) ...[
          const SizedBox(height: 12),
          Text(
            session.error!,
            textAlign: TextAlign.center,
            style: TextStyle(color: scheme.error, fontSize: 13.5),
          ),
        ],
      ],
    );
  }
}

// ───────────────────────────────────────────────────────── fin de partie ──

class _Finished extends ConsumerWidget {
  const _Finished({required this.party, required this.snippet});

  final PartyState party;
  final SnippetPlayer snippet;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final ranking = party.ranking;
    final winner = ranking.isEmpty ? null : ranking.first;
    final unit = party.game == kChronoGame.id ? 'cartes' : 'points';

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 24),
      children: [
        GlassBox(
          radius: 24,
          blur: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
            child: Column(
              children: [
                const Icon(
                  Icons.emoji_events_rounded,
                  size: 44,
                  color: Color(0xFFE0A32E),
                ),
                const SizedBox(height: 10),
                Text(
                  winner == null ? 'Partie terminée' : '${winner.name} gagne !',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.4,
                  ),
                ),
                if (winner != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    '${winner.score} $unit',
                    style: TextStyle(
                      fontSize: 34,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -1,
                      color: scheme.primary,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        const SectionTitle('Classement', padding: EdgeInsets.fromLTRB(2, 4, 2, 6)),
        PartyPlayerList(party: party, showScores: true, ranked: true),
        const SizedBox(height: 22),
        AccentPlayButton(
          label: 'Nouvelle partie',
          icon: Icons.refresh_rounded,
          expand: true,
          onPressed: () async {
            snippet.stop();
            await ref.read(partyProvider.notifier).close();
          },
        ),
        const SizedBox(height: 6),
        TextButton(
          onPressed: () async {
            snippet.stop();
            await ref.read(partyProvider.notifier).close();
            if (context.mounted) context.pop();
          },
          child: const Text('Retour aux jeux'),
        ),
      ],
    );
  }
}
