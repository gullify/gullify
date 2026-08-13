import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/alarm.dart';
import '../state/alarm.dart';
import '../state/player.dart';
import '../widgets/glass_box.dart';

/// L'écran du réveil (idée #81) : ce que Maxime voit à 7 h du matin, l'app
/// ouverte toute seule par l'alarme, souvent par-dessus l'écran verrouillé.
///
/// Trois gestes, tous dans le bas de l'écran (on est à moitié réveillé, une
/// seule main sort de la couette) : arrêter, un rappel, ou garder la musique.
class AlarmRingScreen extends ConsumerStatefulWidget {
  const AlarmRingScreen({super.key});

  @override
  ConsumerState<AlarmRingScreen> createState() => _AlarmRingScreenState();
}

class _AlarmRingScreenState extends ConsumerState<AlarmRingScreen> {
  Timer? _clock;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _clock = Timer.periodic(
      const Duration(seconds: 10),
      (_) => setState(() => _now = DateTime.now()),
    );
  }

  @override
  void dispose() {
    _clock?.cancel();
    super.dispose();
  }

  void _leave() {
    if (!mounted) return;
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/');
    }
  }

  @override
  Widget build(BuildContext context) {
    final alarm = ref.watch(alarmProvider);
    final notifier = ref.read(alarmProvider.notifier);
    final scheme = Theme.of(context).colorScheme;
    final item = ref.watch(currentMediaItemProvider).value;

    // Le réveil a été arrêté d'ailleurs (notification, minuterie de sécurité) :
    // l'écran n'a plus de raison d'être.
    ref.listen(alarmProvider, (prev, next) {
      if ((prev?.ringing ?? false) && !next.ringing) _leave();
    });

    final hour = _now.hour.toString().padLeft(2, '0');
    final minute = _now.minute.toString().padLeft(2, '0');

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(flex: 2),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.wb_twilight, color: scheme.primary, size: 26),
                  const SizedBox(width: 10),
                  Text(
                    'Réveil',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.4,
                      color: scheme.primary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Center(
                child: Text(
                  '$hour:$minute',
                  style: const TextStyle(
                    fontSize: 78,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -3,
                    height: 1.05,
                  ),
                ),
              ),
              const SizedBox(height: 18),
              GlassBox(
                radius: 22,
                blur: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        alarm.fellBackToTone
                            ? 'Serveur injoignable — sonnerie de secours'
                            : alarm.config.sound == AlarmSound.buzz
                                ? 'Sonnerie'
                                : 'En ce moment',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.3,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        item?.title ?? 'Chargement…',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.4,
                        ),
                      ),
                      if ((item?.artist ?? '').isNotEmpty)
                        Text(
                          item!.artist!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13.5,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      if (alarm.config.riseMinutes > 0) ...[
                        const SizedBox(height: 10),
                        Text(
                          'Le son monte pendant '
                          '${alarm.config.riseMinutes} min.',
                          style: TextStyle(
                            fontSize: 12,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const Spacer(flex: 3),
              // Tout ce qui se touche vit dans le tiers du bas : à cette
              // heure-là, le pouce ne monte pas plus haut.
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  minimumSize: const Size(64, 62),
                  textStyle: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                onPressed: () async {
                  await notifier.snooze();
                  _leave();
                },
                icon: const Icon(Icons.snooze, size: 24),
                label: Text('Encore ${alarm.config.snoozeMinutes} min'),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(64, 56),
                ),
                onPressed: () async {
                  await notifier.keepPlaying();
                  _leave();
                },
                icon: const Icon(Icons.headphones_outlined),
                label: const Text('Garder la musique'),
              ),
              const SizedBox(height: 10),
              TextButton.icon(
                style: TextButton.styleFrom(
                  minimumSize: const Size(64, 52),
                  foregroundColor: scheme.onSurfaceVariant,
                ),
                onPressed: () async {
                  await notifier.stop();
                  _leave();
                },
                icon: const Icon(Icons.stop_circle_outlined),
                label: const Text('Arrêter'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
