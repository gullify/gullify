import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../state/app_update.dart';
import '../state/home_widget_sync.dart';
import '../state/player.dart';
import '../theme.dart';
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

    final surfaces = Theme.of(context).extension<GullifySurfaces>();
    final frosted = surfaces?.frosted ?? false;

    Widget bottom = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const MiniPlayer(),
        NavigationBar(
            selectedIndex: navigationShell.currentIndex,
            onDestinationSelected: (i) => navigationShell.goBranch(
              i,
              initialLocation: i == navigationShell.currentIndex,
            ),
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.home_outlined),
                selectedIcon: Icon(Icons.home),
                label: 'Accueil',
              ),
              NavigationDestination(
                icon: Icon(Icons.search),
                label: 'Recherche',
              ),
              NavigationDestination(
                icon: Icon(Icons.radio_outlined),
                selectedIcon: Icon(Icons.radio),
                label: 'Radio',
              ),
              NavigationDestination(
                icon: Icon(Icons.library_music_outlined),
                selectedIcon: Icon(Icons.library_music),
                label: 'Bibliothèque',
              ),
            ],
          ),
      ],
    );

    if (frosted) {
      // Effet verre : le contenu défile sous les barres, floutées en direct.
      bottom = ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: ColoredBox(
            color: surfaces?.barColor ?? Colors.transparent,
            child: bottom,
          ),
        ),
      );
    }

    return Scaffold(
      extendBody: frosted,
      body: navigationShell,
      bottomNavigationBar: bottom,
    );
  }
}
