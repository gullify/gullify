import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../state/app_update.dart';
import '../state/background_playback.dart';
import '../state/home_widget_sync.dart';
import '../state/player.dart';
import '../widgets/glass_box.dart';
import '../widgets/mini_player.dart';
import '../widgets/update_dialog.dart';

/// Tab shell: content + mini player + bottom navigation.
class ShellScreen extends ConsumerStatefulWidget {
  const ShellScreen({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  ConsumerState<ShellScreen> createState() => _ShellScreenState();
}

class _ShellScreenState extends ConsumerState<ShellScreen> {
  StatefulNavigationShell get navigationShell => widget.navigationShell;

  @override
  void initState() {
    super.initState();
    // Vérification silencieuse au démarrage; propose la mise à jour une fois.
    Future.microtask(
      () => ref.read(appUpdateProvider.notifier).check(silent: true),
    );
    // Lecture écran éteint : demande l'exemption batterie (une seule fois).
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) maybePromptBackgroundPlayback(context);
    });
  }

  @override
  Widget build(BuildContext context) {
    // Keep the audio handler's repository bound to the current auth state.
    ref.watch(audioHandlerBinderProvider);
    // Widget d'écran d'accueil synchronisé avec la lecture.
    ref.watch(homeWidgetSyncProvider);

    ref.listen(appUpdateProvider, (prev, next) {
      if (prev?.status != UpdateStatus.available &&
          next.status == UpdateStatus.available) {
        showUpdateDialog(context);
      }
    });

    return Scaffold(
      // Le contenu défile sous les barres de verre (elles sont translucides).
      extendBody: true,
      body: navigationShell,
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const MiniPlayer(),
          _GlassTabBar(navigationShell: navigationShell),
        ],
      ),
    );
  }
}

/// Barre d'onglets « liquid glass » : pilule de verre, onglet actif en
/// pilule accent avec libellé, inactifs en icônes seules.
class _GlassTabBar extends StatelessWidget {
  const _GlassTabBar({required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  static const _tabs = [
    (Icons.home_outlined, Icons.home, 'Accueil'),
    (Icons.search, Icons.search, 'Recherche'),
    (Icons.radio_outlined, Icons.radio, 'Radio'),
    (Icons.library_music_outlined, Icons.library_music, 'Bibliothèque'),
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final current = navigationShell.currentIndex;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: SafeArea(
        top: false,
        child: GlassBox(
          radius: 22,
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Row(
              children: [
                for (final (i, tab) in _tabs.indexed)
                  Expanded(
                    flex: current == i ? 5 : 2,
                    child: _TabButton(
                      icon: current == i ? tab.$2 : tab.$1,
                      label: tab.$3,
                      selected: current == i,
                      scheme: scheme,
                      onTap: () => navigationShell.goBranch(
                        i,
                        initialLocation: i == current,
                      ),
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

class _TabButton extends StatelessWidget {
  const _TabButton({
    required this.icon,
    required this.label,
    required this.selected,
    required this.scheme,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final ColorScheme scheme;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      height: 48,
      margin: const EdgeInsets.symmetric(horizontal: 3),
      decoration: BoxDecoration(
        color: selected ? scheme.primary : Colors.transparent,
        borderRadius: BorderRadius.circular(16),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 23,
              color: selected ? scheme.onPrimary : scheme.onSurfaceVariant,
            ),
            if (selected) ...[
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: scheme.onPrimary,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
