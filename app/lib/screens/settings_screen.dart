import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../state/app_theme.dart';
import '../state/background_playback.dart';
import '../state/app_update.dart';
// ignore: unused_import — GullifyStyle et son extension viennent du thème.
import '../theme.dart';
import '../state/auth.dart';
import '../state/equalizer.dart';
import '../state/offline.dart';
import '../widgets/update_dialog.dart';

const appVersion = '2.17.0';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    final offline = ref.watch(offlineProvider).value ?? {};

    return Scaffold(
      appBar: AppBar(title: const Text('Paramètres')),
      body: ListView(
        children: [
          const _SectionHeader('Compte'),
          ListTile(
            leading: const Icon(Icons.person_outline),
            title: Text(auth.user?.fullName ?? auth.user?.username ?? ''),
            subtitle: auth.user != null ? Text(auth.user!.username) : null,
          ),
          ListTile(
            leading: const Icon(Icons.dns_outlined),
            title: const Text('Serveur'),
            subtitle: Text(auth.serverUrl ?? ''),
          ),
          ListTile(
            leading: const Icon(Icons.swap_horiz),
            title: const Text('Changer de serveur'),
            onTap: () => _confirm(
              context,
              'Changer de serveur ?',
              'Vous serez déconnecté et devrez saisir une nouvelle adresse.',
              () => ref.read(authProvider.notifier).changeServer(),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.logout),
            title: const Text('Déconnexion'),
            onTap: () => _confirm(
              context,
              'Se déconnecter ?',
              null,
              () => ref.read(authProvider.notifier).logout(),
            ),
          ),
          const Divider(),
          if (equalizerSupported || offlineSupported)
            const _SectionHeader('Lecture'),
          if (equalizerSupported)
            ListTile(
              leading: const Icon(Icons.equalizer),
              title: const Text('Égaliseur'),
              onTap: () => context.push('/settings/equalizer'),
            ),
          if (offlineSupported)
            ListTile(
              leading: const Icon(Icons.download_outlined),
              title: const Text('Téléchargements'),
              subtitle: Text(
                '${offline.length} titre${offline.length > 1 ? 's' : ''}'
                ' · ${formatBytes(ref.read(offlineProvider.notifier).totalSize())}',
              ),
              onTap: () => context.push('/settings/downloads'),
            ),
          if (!kIsWeb && Platform.isAndroid) const _BackgroundPlaybackTile(),
          if (equalizerSupported || offlineSupported) const Divider(),
          const _SectionHeader('Apparence'),
          const _ThemePicker(),
          const Divider(),
          const _SectionHeader('À propos'),
          const ListTile(
            leading: Icon(Icons.info_outline),
            title: Text('Gullify'),
            subtitle: Text('Version $appVersion'),
          ),
          const _UpdateTile(),
        ],
      ),
    );
  }

  Future<void> _confirm(
    BuildContext context,
    String title,
    String? message,
    Future<void> Function() action,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: message != null ? Text(message) : null,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirmer'),
          ),
        ],
      ),
    );
    if (ok == true) await action();
  }
}

String formatBytes(int bytes) {
  if (bytes >= 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} Go';
  }
  if (bytes >= 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} Mo';
  }
  return '${(bytes / 1024).toStringAsFixed(0)} Ko';
}

class _BackgroundPlaybackTile extends StatefulWidget {
  const _BackgroundPlaybackTile();

  @override
  State<_BackgroundPlaybackTile> createState() =>
      _BackgroundPlaybackTileState();
}

class _BackgroundPlaybackTileState extends State<_BackgroundPlaybackTile> {
  bool? _ok;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final ok = await backgroundPlaybackOk();
    if (mounted) setState(() => _ok = ok);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      leading: Icon(
        _ok == true ? Icons.battery_saver : Icons.battery_alert,
        color: _ok == false ? scheme.error : null,
      ),
      title: const Text('Lecture écran éteint'),
      subtitle: Text(
        switch (_ok) {
          true => 'Exemption de batterie accordée',
          false => 'À autoriser — sinon la musique se coupe en veille',
          null => 'Vérification…',
        },
      ),
      onTap: _ok == true
          ? null
          : () async {
              await requestBackgroundPlayback();
              await _refresh();
            },
    );
  }
}

class _ThemePicker extends ConsumerWidget {
  const _ThemePicker();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(themeStyleProvider);
    final scheme = Theme.of(context).colorScheme;

    return SizedBox(
      height: 118,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        children: [
          for (final style in GullifyStyle.values)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () =>
                    ref.read(themeStyleProvider.notifier).set(style),
                child: Container(
                  width: 96,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      width: 2,
                      color: current == style
                          ? scheme.primary
                          : scheme.outlineVariant,
                    ),
                  ),
                  child: Column(
                    children: [
                      // Aperçu : fond + surface + pastille d'accent.
                      Expanded(
                        child: Builder(builder: (context) {
                          final (bg, surface, accent) = style.preview;
                          return Container(
                            width: double.infinity,
                            decoration: BoxDecoration(
                              color: bg,
                              borderRadius: BorderRadius.circular(8),
                              border:
                                  Border.all(color: scheme.outlineVariant),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Container(
                                  width: 44,
                                  height: 10,
                                  decoration: BoxDecoration(
                                    color: surface,
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Container(
                                  width: 16,
                                  height: 16,
                                  decoration: BoxDecoration(
                                    color: accent,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        style.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: current == style
                              ? FontWeight.w700
                              : FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _UpdateTile extends ConsumerWidget {
  const _UpdateTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final update = ref.watch(appUpdateProvider);

    final subtitle = switch (update.status) {
      UpdateStatus.checking => 'Vérification…',
      UpdateStatus.upToDate => 'Vous avez la dernière version',
      UpdateStatus.available =>
        'Version ${update.available!.versionName} disponible',
      UpdateStatus.downloading => 'Téléchargement en cours…',
      UpdateStatus.readyToInstall => 'Prêt à installer',
      UpdateStatus.error => update.message ?? 'Erreur',
      UpdateStatus.idle => null,
    };

    return ListTile(
      leading: update.status == UpdateStatus.checking
          ? const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(
              update.status == UpdateStatus.available
                  ? Icons.system_update
                  : Icons.update,
            ),
      title: const Text('Rechercher des mises à jour'),
      subtitle: subtitle != null ? Text(subtitle) : null,
      onTap: () async {
        final notifier = ref.read(appUpdateProvider.notifier);
        if (ref.read(appUpdateProvider).status == UpdateStatus.available) {
          showUpdateDialog(context);
          return;
        }
        await notifier.check();
        if (context.mounted &&
            ref.read(appUpdateProvider).status == UpdateStatus.available) {
          showUpdateDialog(context);
        }
      },
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
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
}
