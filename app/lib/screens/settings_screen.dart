import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../audio/equalizer.dart';
import '../state/app_theme.dart';
import '../state/app_update.dart';
import '../state/auth.dart';
import '../state/background_playback.dart';
import '../state/offline.dart';
import '../theme.dart';
import '../widgets/update_dialog.dart';

const appVersion = '2.98.0';

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
          const _ProfilePhotoTile(),
          ListTile(
            leading: const Icon(Icons.dns_outlined),
            title: const Text('Serveur'),
            subtitle: Text(auth.serverUrl ?? ''),
          ),
          ListTile(
            leading: const Icon(Icons.storage_outlined),
            title: const Text('Infos du serveur'),
            subtitle: const Text('Espace disque, bibliothèque, versions'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/settings/server-info'),
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
          const _SectionHeader('Bibliothèque'),
          ListTile(
            leading: const Icon(Icons.label_outline),
            title: const Text('Gérer les genres'),
            subtitle: const Text('Renommer ou supprimer un genre'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/genres'),
          ),
          ListTile(
            leading: const Icon(Icons.library_music_outlined),
            title: const Text('Scanner la bibliothèque'),
            subtitle: const Text('Détecter les nouveaux titres et les genres'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/settings/scan'),
          ),
          const Divider(),
          const _SectionHeader('Apparence'),
          const _ModePicker(),
          const _AccentPicker(),
          const SizedBox(height: 8),
          const Divider(),
          const _SectionHeader('Développement'),
          ListTile(
            leading: const Icon(Icons.lightbulb_outline),
            title: const Text('Mes idées'),
            subtitle: const Text('Note tes idées de développement'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/settings/ideas'),
          ),
          if (!kIsWeb && Platform.isAndroid)
            ListTile(
              leading: const Icon(Icons.directions_car_outlined),
              title: const Text('Diagnostic Android Auto'),
              subtitle: const Text('Journal en cas de « Aucune sélection »'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/settings/aa-diagnostic'),
            ),
          ListTile(
            leading: const Icon(Icons.troubleshoot),
            title: const Text('Diagnostic de lecture'),
            subtitle: const Text('Journal si la musique s\'arrête en veille'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/settings/playback-diagnostic'),
          ),
          const Divider(),
          const _SectionHeader('À propos'),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('Gullify'),
            subtitle: const Text('Version $appVersion'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/settings/changelog'),
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

/// Ligne « Compte » avec la photo de profil : tape pour en choisir une
/// (galerie) ou la supprimer.
class _ProfilePhotoTile extends ConsumerStatefulWidget {
  const _ProfilePhotoTile();

  @override
  ConsumerState<_ProfilePhotoTile> createState() => _ProfilePhotoTileState();
}

class _ProfilePhotoTileState extends ConsumerState<_ProfilePhotoTile> {
  bool _busy = false;

  Future<void> _pick() async {
    final messenger = ScaffoldMessenger.of(context);
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1024,
      maxHeight: 1024,
    );
    if (picked == null) return;
    setState(() => _busy = true);
    try {
      await ref.read(authProvider.notifier).setAvatar(picked.path);
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text("Échec de l'envoi : $e")),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove() async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await ref.read(authProvider.notifier).removeAvatar();
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Échec : $e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _openMenu(bool hasAvatar) {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choisir une photo'),
              onTap: () {
                Navigator.pop(sheet);
                _pick();
              },
            ),
            if (hasAvatar)
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: const Text('Supprimer la photo'),
                onTap: () {
                  Navigator.pop(sheet);
                  _remove();
                },
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider).user;
    final avatarUrl = user?.avatarUrl;
    final scheme = Theme.of(context).colorScheme;

    return ListTile(
      onTap: _busy ? null : () => _openMenu(avatarUrl != null),
      leading: CircleAvatar(
        radius: 22,
        backgroundColor: scheme.surfaceContainerHighest,
        backgroundImage: (avatarUrl != null && avatarUrl.isNotEmpty)
            ? NetworkImage(avatarUrl)
            : null,
        child: (avatarUrl == null || avatarUrl.isEmpty)
            ? Icon(Icons.person_outline, color: scheme.onSurfaceVariant)
            : null,
      ),
      title: Text(user?.fullName ?? user?.username ?? ''),
      subtitle: Text(
        user == null ? '' : '${user.username} · Photo de profil',
      ),
      trailing: _busy
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            )
          : const Icon(Icons.edit_outlined, size: 20),
    );
  }
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

/// Interrupteur clair / sombre / système (même structure de verre).
class _ModePicker extends ConsumerWidget {
  const _ModePicker();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: SegmentedButton<ThemeMode>(
        segments: const [
          ButtonSegment(
            value: ThemeMode.system,
            icon: Icon(Icons.brightness_auto),
            label: Text('Système'),
          ),
          ButtonSegment(
            value: ThemeMode.light,
            icon: Icon(Icons.light_mode),
            label: Text('Clair'),
          ),
          ButtonSegment(
            value: ThemeMode.dark,
            icon: Icon(Icons.dark_mode),
            label: Text('Sombre'),
          ),
        ],
        selected: {mode},
        showSelectedIcon: false,
        onSelectionChanged: (s) =>
            ref.read(themeModeProvider.notifier).set(s.first),
      ),
    );
  }
}

/// Pastilles de couleur d'accent : la teinte change, la structure reste.
class _AccentPicker extends ConsumerWidget {
  const _AccentPicker();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(accentColorProvider);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Wrap(
        spacing: 14,
        runSpacing: 12,
        children: [
          for (final accent in GullifyAccent.values)
            _AccentSwatch(
              accent: accent,
              selected: accent == current,
              onTap: () => ref.read(accentColorProvider.notifier).set(accent),
            ),
        ],
      ),
    );
  }
}

class _AccentSwatch extends StatelessWidget {
  const _AccentSwatch({
    required this.accent,
    required this.selected,
    required this.onTap,
  });

  final GullifyAccent accent;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(24),
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: accent.color,
              shape: BoxShape.circle,
              border: Border.all(
                color: selected ? scheme.onSurface : Colors.transparent,
                width: 2.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: accent.color.withValues(alpha: 0.4),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: selected
                ? const Icon(Icons.check, color: Colors.white, size: 22)
                : null,
          ),
          const SizedBox(height: 4),
          Text(
            accent.label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: scheme.onSurfaceVariant,
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
