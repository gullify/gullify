import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../audio/alarm_platform.dart';
import '../models/alarm.dart';
import '../state/alarm.dart';
import 'games/game_source_sheet.dart';

/// Réglage du réveil matinal (idée #81) : une heure, des jours, de la musique
/// (ou une sonnerie), et une montée progressive du volume.
class AlarmScreen extends ConsumerWidget {
  const AlarmScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final alarm = ref.watch(alarmProvider);
    final notifier = ref.read(alarmProvider.notifier);
    final config = alarm.config;
    final scheme = Theme.of(context).colorScheme;

    Future<void> edit(AlarmConfig next) => notifier.set(next);

    return Scaffold(
      appBar: AppBar(title: const Text('Réveil')),
      body: ListView(
        children: [
          if (!alarmSupported)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Text(
                'Le réveil n\'existe que sur Android : ailleurs, rien ne peut '
                'garantir qu\'il sonne l\'app fermée.',
                style: TextStyle(fontSize: 12.5, color: scheme.error),
              ),
            ),
          SwitchListTile(
            secondary: const Icon(Icons.alarm),
            title: const Text('Réveil matinal'),
            subtitle: Text(
              config.enabled
                  ? '${config.timeLabel} · ${config.daysLabel}'
                  : 'Éteint',
            ),
            value: config.enabled,
            onChanged: (v) => edit(config.copyWith(enabled: v)),
          ),
          _NextRing(state: alarm),
          if (config.enabled && !alarm.exactAllowed)
            ListTile(
              leading: Icon(Icons.warning_amber_rounded, color: scheme.error),
              title: const Text('Alarme exacte non autorisée'),
              subtitle: const Text(
                'Android se réserve le droit de décaler la sonnerie de '
                'plusieurs minutes. Touche pour l\'autoriser.',
              ),
              onTap: notifier.askExactPermission,
            ),
          const Divider(height: 24),
          ListTile(
            leading: const Icon(Icons.schedule),
            title: const Text('Heure'),
            trailing: Text(
              config.timeLabel,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
                color: scheme.primary,
              ),
            ),
            onTap: () async {
              final picked = await showTimePicker(
                context: context,
                initialTime: TimeOfDay(
                  hour: config.hour,
                  minute: config.minute,
                ),
              );
              if (picked == null) return;
              await edit(
                config.copyWith(hour: picked.hour, minute: picked.minute),
              );
            },
          ),
          const _SectionLabel('Jours'),
          _DayPicker(
            days: config.days,
            onChanged: (days) => edit(config.copyWith(days: days)),
          ),
          const Divider(height: 24),
          const _SectionLabel('Ce qu\'on entend'),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: SegmentedButton<AlarmSound>(
              segments: const [
                ButtonSegment(
                  value: AlarmSound.music,
                  icon: Icon(Icons.music_note),
                  label: Text('Musique'),
                ),
                ButtonSegment(
                  value: AlarmSound.buzz,
                  icon: Icon(Icons.notifications_active_outlined),
                  label: Text('Sonnerie'),
                ),
              ],
              selected: {config.sound},
              showSelectedIcon: false,
              onSelectionChanged: (s) =>
                  edit(config.copyWith(sound: s.first)),
            ),
          ),
          if (config.sound == AlarmSound.music)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: GameSourceTile(
                source: config.source,
                label: 'Le réveil pioche dans',
                subtitle:
                    'La musique du réveil sort d\'ici, mélangée. Sans réseau '
                    'au petit matin, la sonnerie prend le relais.',
                onChanged: (source) => edit(config.copyWith(source: source)),
              ),
            ),
          const Divider(height: 24),
          const _SectionLabel('Montée du volume'),
          ListTile(
            leading: const Icon(Icons.trending_up),
            title: const Text('Fondu montant'),
            subtitle: Text(
              config.riseMinutes == 0
                  ? 'Plein volume tout de suite'
                  : 'Le son part de rien et met ${config.riseMinutes} min à '
                        'atteindre le volume réglé',
            ),
            trailing: Text(
              config.riseMinutes == 0 ? '—' : '${config.riseMinutes} min',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: scheme.primary,
              ),
            ),
          ),
          Slider(
            value: config.riseMinutes.toDouble(),
            max: AlarmConfig.maxRiseMinutes.toDouble(),
            divisions: AlarmConfig.maxRiseMinutes,
            label: config.riseMinutes == 0 ? 'aucun' : '${config.riseMinutes} min',
            onChanged: (v) => edit(config.copyWith(riseMinutes: v.round())),
          ),
          ListTile(
            leading: const Icon(Icons.volume_up_outlined),
            title: const Text('Volume visé'),
            subtitle: const Text(
              'Le volume média est monté à ce niveau au réveil, puis remis '
              'comme il était quand on arrête',
            ),
            trailing: Text(
              '${config.volumePercent} %',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: scheme.primary,
              ),
            ),
          ),
          Slider(
            value: config.volumePercent.toDouble(),
            min: 10,
            max: 100,
            divisions: 18,
            label: '${config.volumePercent} %',
            onChanged: (v) => edit(config.copyWith(volumePercent: v.round())),
          ),
          const Divider(height: 24),
          ListTile(
            leading: const Icon(Icons.snooze),
            title: const Text('Rappel'),
            subtitle: const Text('Le temps que « Encore un peu » fait gagner'),
            trailing: Text(
              '${config.snoozeMinutes} min',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: scheme.primary,
              ),
            ),
          ),
          Slider(
            value: config.snoozeMinutes.toDouble(),
            min: 1,
            max: 30,
            divisions: 29,
            label: '${config.snoozeMinutes} min',
            onChanged: (v) => edit(config.copyWith(snoozeMinutes: v.round())),
          ),
          const Divider(height: 24),
          ListTile(
            leading: const Icon(Icons.play_circle_outline),
            title: const Text('Sonner dans une minute'),
            subtitle: const Text(
              'L\'essai à faire une fois : éteins l\'écran, pose le téléphone '
              'et regarde si le réveil s\'ouvre tout seul',
            ),
            onTap: () async {
              final messenger = ScaffoldMessenger.of(context);
              final at = await notifier.testInAMinute();
              messenger.showSnackBar(
                SnackBar(
                  content: Text(
                    'Essai programmé à '
                    '${at.hour.toString().padLeft(2, '0')}:'
                    '${at.minute.toString().padLeft(2, '0')} — écran éteint, '
                    'la sonnerie doit ouvrir Gullify toute seule.',
                  ),
                ),
              );
            },
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
            child: Text(
              'À l\'heure dite, Android réveille le téléphone et ouvre '
              'Gullify : la musique démarre à volume nul et monte doucement. '
              'La sonnerie du système ne prend le relais que si l\'app n\'a '
              'pas démarré — c\'est le filet, pas le réveil.\n\n'
              'Pour que ça marche à coup sûr : garde l\'exemption de batterie '
              '(Paramètres → Lecture → « Lecture écran éteint ») et laisse '
              'l\'alarme exacte autorisée. Un téléphone éteint à l\'heure du '
              'réveil, lui, ne sonnera pas — mais l\'alarme est reposée dès '
              'qu\'il redémarre.',
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}

/// Quand le réveil doit sonner, en toutes lettres.
class _NextRing extends StatelessWidget {
  const _NextRing({required this.state});

  final AlarmState state;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final next = state.snoozedUntil ?? state.next;
    if (!state.config.enabled && state.snoozedUntil == null) {
      return const SizedBox.shrink();
    }
    if (next == null) return const SizedBox.shrink();
    final left = next.difference(DateTime.now());
    final day = _dayWord(next);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Row(
        children: [
          Icon(Icons.notifications_active_outlined,
              size: 18, color: scheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              state.snoozedUntil != null
                  ? 'Rappel $day à '
                        '${next.hour.toString().padLeft(2, '0')}:'
                        '${next.minute.toString().padLeft(2, '0')} '
                        '(${formatUntilRing(left)})'
                  : 'Prochaine sonnerie $day à '
                        '${next.hour.toString().padLeft(2, '0')}:'
                        '${next.minute.toString().padLeft(2, '0')} '
                        '(${formatUntilRing(left)})',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: scheme.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _dayWord(DateTime at) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(at.year, at.month, at.day);
    final diff = day.difference(today).inDays;
    if (diff <= 0) return 'aujourd\'hui';
    if (diff == 1) return 'demain';
    const names = [
      'lundi',
      'mardi',
      'mercredi',
      'jeudi',
      'vendredi',
      'samedi',
      'dimanche',
    ];
    return names[at.weekday - 1];
  }
}

/// Les sept jours, à cocher. Rien de coché = tous les jours.
class _DayPicker extends StatelessWidget {
  const _DayPicker({required this.days, required this.onChanged});

  final Set<int> days;
  final ValueChanged<Set<int>> onChanged;

  static const _labels = ['L', 'M', 'M', 'J', 'V', 'S', 'D'];

  @override
  Widget build(BuildContext context) {
    final everyDay = days.isEmpty || days.length == 7;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (var d = 1; d <= 7; d++)
            FilterChip(
              label: Text(_labels[d - 1]),
              selected: everyDay || days.contains(d),
              onSelected: (on) {
                // « Tous les jours » se décoche jour par jour : le premier
                // décochage part de la semaine complète.
                final base = everyDay ? {1, 2, 3, 4, 5, 6, 7} : {...days};
                if (on) {
                  base.add(d);
                } else {
                  base.remove(d);
                }
                // Plus rien de coché : on revient à « tous les jours » plutôt
                // qu'à un réveil qui ne sonnerait jamais.
                onChanged(base.isEmpty ? const {} : base);
              },
            ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
    child: Text(
      label,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: Theme.of(context).colorScheme.primary,
      ),
    ),
  );
}
