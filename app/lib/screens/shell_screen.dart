import 'dart:math' as math;

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
      bottomNavigationBar: HubDock(
        currentIndex: navigationShell.currentIndex,
        onSelect: (i) => navigationShell.goBranch(
          i,
          initialLocation: i == navigationShell.currentIndex,
        ),
      ),
    );
  }
}

/// Dock complet (mini-lecteur + navigation) pour les pages de DÉTAIL, hors
/// du shell : la navigation ramène à l'onglet correspondant. Aucun onglet
/// n'est actif (currentIndex -1). Rend la barre présente partout.
class DetailDock extends StatelessWidget {
  const DetailDock({super.key});

  static const _paths = [
    '/',
    '/library',
    '/search',
    '/radio',
    '/favorites',
    '/games',
  ];

  @override
  Widget build(BuildContext context) =>
      HubDock(currentIndex: -1, onSelect: (i) => context.go(_paths[i]));
}

/// Un onglet satellite du dock : icône (variante remplie/arrondie), teinte
/// accent + point animé quand actif.
class _DockDest {
  const _DockDest(this.branch, this.iconOff, this.iconOn, this.tooltip);
  final int branch;
  final IconData iconOff;
  final IconData iconOn;
  final String tooltip;
}

/// Dock de navigation réinventé : mini-lecteur + pilule de verre flottante,
/// avec un ORBE d'accueil accent surélevé au centre qui fait le pont entre
/// les deux. Satellites en icônes épurées (sans texte), 2 de chaque côté.
class HubDock extends StatelessWidget {
  const HubDock({
    super.key,
    required this.currentIndex,
    required this.onSelect,
  });

  final int currentIndex;
  final ValueChanged<int> onSelect;

  // Branches : 0 Accueil (orbe), 1 Bibliothèque, 2 Recherche, 3 Radio,
  // 4 Favoris, 5 Jeux. Disposition : [1][2] (orbe 0) [3][4][5].
  static const _left = [
    _DockDest(
      1,
      Icons.library_music_outlined,
      Icons.library_music_rounded,
      'Bibliothèque',
    ),
    _DockDest(2, Icons.search_rounded, Icons.search_rounded, 'Recherche'),
  ];
  static const _right = [
    _DockDest(3, Icons.radio_outlined, Icons.radio_rounded, 'Radio'),
    _DockDest(
      4,
      Icons.favorite_border_rounded,
      Icons.favorite_rounded,
      'Favoris',
    ),
    _DockDest(
      5,
      Icons.sports_esports_outlined,
      Icons.sports_esports_rounded,
      'Jeux',
    ),
  ];

  Widget _satellites(List<_DockDest> dests, ColorScheme scheme) => Row(
    children: [
      for (final d in dests)
        Expanded(
          child: _Satellite(
            dest: d,
            selected: currentIndex == d.branch,
            scheme: scheme,
            onTap: () => onSelect(d.branch),
          ),
        ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    final pill = Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
      child: SafeArea(
        top: false,
        child: GlassBox(
          radius: 28,
          child: SizedBox(
            height: 62,
            child: Row(
              // Les deux moitiés ont la MÊME largeur (même si elles n'ont pas
              // le même nombre d'icônes) : c'est ce qui garde l'orbe
              // exactement au centre de la pilule.
              children: [
                Expanded(child: _satellites(_left, scheme)),
                // Emplacement de l'orbe (rendu par-dessus dans le Stack).
                const SizedBox(width: 64),
                Expanded(child: _satellites(_right, scheme)),
              ],
            ),
          ),
        ),
      ),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const MiniPlayer(),
        // Stack sans clip : l'orbe déborde vers le haut pour ponter le
        // mini-lecteur et le dock.
        Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.topCenter,
          children: [
            pill,
            Positioned(
              top: -20,
              child: _HomeOrb(
                selected: currentIndex == 0,
                scheme: scheme,
                onTap: () => onSelect(0),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Orbe central « Accueil » : disque accent avec halo, légèrement surélevé.
class _HomeOrb extends StatelessWidget {
  const _HomeOrb({
    required this.selected,
    required this.scheme,
    required this.onTap,
  });

  final bool selected;
  final ColorScheme scheme;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = scheme.primary;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedScale(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutBack,
        scale: selected ? 1.0 : 0.92,
        child: Container(
          width: 60,
          height: 60,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color.lerp(accent, Colors.white, 0.22)!, accent],
            ),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.35),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: accent.withValues(alpha: selected ? 0.55 : 0.35),
                blurRadius: selected ? 22 : 14,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: const Icon(Icons.home_rounded, color: Colors.white, size: 28),
        ),
      ),
    );
  }
}

class _Satellite extends StatelessWidget {
  const _Satellite({
    required this.dest,
    required this.selected,
    required this.scheme,
    required this.onTap,
  });

  final _DockDest dest;
  final bool selected;
  final ColorScheme scheme;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // Icône centrée verticalement; l'état actif = pastille de verre
    // accent derrière l'icône (pas de point qui déséquilibre l'alignement).
    return Tooltip(
      message: dest.tooltip,
      child: InkResponse(
        onTap: onTap,
        radius: 34,
        child: Center(
          // La pastille ne dépasse jamais la place disponible : avec trois
          // satellites d'un côté, les écrans étroits sont vite à l'étroit.
          child: LayoutBuilder(
            builder: (context, constraints) => AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              width: math.min(46, constraints.maxWidth),
              height: 40,
              decoration: BoxDecoration(
                color: selected
                    ? scheme.primary.withValues(alpha: 0.16)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                selected ? dest.iconOn : dest.iconOff,
                size: 25,
                color: selected ? scheme.primary : scheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
