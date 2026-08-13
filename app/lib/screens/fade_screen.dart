import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../audio/fade.dart';
import '../state/player.dart';

/// Réglage du fondu du lecteur (idée #75) : la musique monte et descend en
/// douceur au lieu de démarrer et de s'arrêter net.
class FadeScreen extends ConsumerWidget {
  const FadeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fade = ref.watch(playbackFadeProvider);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Fondu')),
      body: ListenableBuilder(
        listenable: fade,
        builder: (context, _) => ListView(
          children: [
            SwitchListTile(
              secondary: const Icon(Icons.graphic_eq),
              title: const Text('Fondu à la lecture et à la pause'),
              subtitle: const Text(
                'Le son monte au démarrage et descend avant la pause',
              ),
              value: fade.enabled,
              onChanged: fade.setEnabled,
            ),
            ListTile(
              enabled: fade.enabled,
              leading: const Icon(Icons.timer_outlined),
              title: const Text('Durée du fondu'),
              trailing: Text(
                formatFadeSeconds(fade.seconds),
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: fade.enabled ? scheme.primary : scheme.outline,
                ),
              ),
            ),
            Slider(
              value: fade.seconds,
              min: kFadeMinSeconds,
              max: kFadeMaxSeconds,
              // Un demi-pas : c'est la plus petite marche qui s'entende.
              divisions: ((kFadeMaxSeconds - kFadeMinSeconds) * 2).round(),
              label: formatFadeSeconds(fade.seconds),
              onChanged: fade.enabled ? fade.setSeconds : null,
            ),
            const Divider(height: 24),
            SwitchListTile(
              secondary: const Icon(Icons.repeat_one_on_outlined),
              title: const Text('Fondu enchaîné'),
              subtitle: const Text(
                'Le titre suivant démarre et monte pendant que celui en cours '
                'descend : les deux se croisent, sans blanc entre les deux',
              ),
              value: fade.betweenTracks,
              onChanged: fade.enabled ? fade.setBetweenTracks : null,
            ),
            SwitchListTile(
              secondary: const Icon(Icons.auto_awesome_outlined),
              title: const Text('Croisement intelligent'),
              subtitle: const Text(
                'Le passage se cale sur le morceau : blanc de fin sauté, '
                'descente naturelle couverte, intro du suivant anticipée',
              ),
              value: fade.smart,
              onChanged: fade.fadesTracks ? fade.setSmart : null,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              child: Text(
                'Le croisement dure la durée réglée plus haut, sans jamais '
                'prendre plus du tiers d\'un titre. Le dernier titre d\'une '
                'file n\'a personne avec qui se croiser : il s\'éteint seul. '
                'Une radio n\'est pas concernée : elle n\'a pas de fin à '
                'annoncer. Un fondu long retarde d\'autant la pause — le son '
                'descend d\'abord, la musique s\'arrête ensuite.\n\n'
                'Le croisement intelligent, lui, écoute d\'abord : le serveur '
                'mesure le niveau sonore des bords de chaque titre. Un morceau '
                'qui finit sur un blanc voit le suivant partir avant ce blanc ; '
                'un morceau qui s\'éteint tout seul se fait couvrir pendant '
                'toute sa descente, jusqu\'au double de la durée réglée ; un '
                'titre qui met du temps à démarrer part en avance, mais celui '
                'qui joue garde son volume tant que rien ne vient. Sans réseau, '
                'ou sur un titre que le serveur ne sait pas mesurer, le '
                'croisement reprend la durée réglée.',
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
