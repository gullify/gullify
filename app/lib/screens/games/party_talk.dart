import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/party_voice.dart';
import '../../widgets/glass_box.dart';
import '../../widgets/glass_kit.dart';

/// La barre du talkie-walkie, en bas de l'écran de partie : on maintient le
/// bouton pour parler aux autres joueurs, on relâche pour envoyer.
///
/// Elle vit hors de la liste qui se redessine à chaque sondage — un appui sur
/// le micro ne doit pas être annulé parce qu'un joueur vient de répondre.
class PartyTalkBar extends ConsumerWidget {
  const PartyTalkBar({super.key, required this.maxMs});

  /// Durée maximale d'un message, dictée par le serveur.
  final int maxMs;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final voice = ref.watch(partyVoiceProvider);
    final notifier = ref.read(partyVoiceProvider.notifier);
    return TalkBarView(
      voice: voice,
      maxMs: maxMs,
      onTalkStart: notifier.startTalking,
      onTalkStop: notifier.stopTalking,
      onToggleSpeaker: notifier.toggleSpeaker,
    );
  }
}

/// La barre elle-même, sans état : ce qu'on voit pour un état donné.
class TalkBarView extends StatelessWidget {
  const TalkBarView({
    super.key,
    required this.voice,
    required this.maxMs,
    required this.onTalkStart,
    required this.onTalkStop,
    required this.onToggleSpeaker,
  });

  final PartyVoiceState voice;
  final int maxMs;
  final VoidCallback onTalkStart;
  final VoidCallback onTalkStop;
  final VoidCallback onToggleSpeaker;

  String _label() {
    if (voice.recording) {
      final started = voice.startedAt;
      final ms = started == null
          ? 0
          : DateTime.now().difference(started).inMilliseconds.clamp(0, maxMs);
      return 'Relâche pour envoyer · ${(ms / 1000).toStringAsFixed(1)} s';
    }
    if (voice.arming) return 'Micro…';
    if (voice.message != null) return voice.message!;
    return 'Maintiens pour parler';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final speaking = voice.speakingName;

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (speaking != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.graphic_eq_rounded,
                    size: 16,
                    color: scheme.primary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '$speaking parle…',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: scheme.primary,
                    ),
                  ),
                ],
              ),
            ),
          Row(
            children: [
              Expanded(
                child: Listener(
                  // Un appui long ne doit pas partir dans l'arène des gestes :
                  // on écoute le doigt directement, poser = parler, lever =
                  // envoyer, quoi qu'il arrive entre les deux.
                  onPointerDown: (_) => onTalkStart(),
                  onPointerUp: (_) => onTalkStop(),
                  onPointerCancel: (_) => onTalkStop(),
                  child: _TalkPill(
                    label: _label(),
                    recording: voice.recording,
                    denied: voice.micDenied && !voice.busy,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              GlassIconButton(
                icon: voice.speakerOn
                    ? Icons.volume_up_rounded
                    : Icons.volume_off_rounded,
                tooltip: voice.speakerOn
                    ? 'Couper les voix'
                    : 'Entendre les autres',
                size: 52,
                onPressed: onToggleSpeaker,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TalkPill extends StatelessWidget {
  const _TalkPill({
    required this.label,
    required this.recording,
    required this.denied,
  });

  final String label;
  final bool recording;
  final bool denied;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = recording ? scheme.error : null;

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: color,
        boxShadow: recording
            ? [
                BoxShadow(
                  color: scheme.error.withValues(alpha: 0.4),
                  blurRadius: 18,
                  offset: const Offset(0, 6),
                ),
              ]
            : null,
      ),
      child: GlassBox(
        radius: 18,
        blur: false,
        child: SizedBox(
          height: 52,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                denied ? Icons.mic_off_rounded : Icons.mic_rounded,
                size: 20,
                color: recording ? Colors.white : scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    color: recording ? Colors.white : scheme.onSurface,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
