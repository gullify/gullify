import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../api/playlist_repository.dart';
import '../state/playlists.dart';
import '../state/app_update.dart';
import '../state/background_playback.dart';
import '../state/home_widget_sync.dart';
import '../state/player.dart';
import '../state/podcasts.dart';
import '../widgets/glass_box.dart';
import '../widgets/keyboard_guard.dart';
import '../widgets/liquid_glass.dart';
import '../widgets/mini_player.dart';
import '../widgets/retro_chrome.dart';
import '../widgets/retro_lcd.dart';
import '../widgets/update_dialog.dart';
import '../widgets/wordmark.dart';

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
    // Position d'écoute des podcasts retenue, écran ouvert ou non (idée #112).
    ref.watch(podcastProgressSyncProvider);

    ref.listen(appUpdateProvider, (prev, next) {
      if (prev?.status != UpdateStatus.available &&
          next.status == UpdateStatus.available) {
        showUpdateDialog(context);
      }
    });

    return Scaffold(
      // Le contenu défile sous les barres de verre (elles sont translucides).
      extendBody: true,
      body: _RetroScreenFrame(
        index: navigationShell.currentIndex,
        child: navigationShell,
      ),
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

/// Sous le rétro, chaque onglet se coiffe de la réglette du châssis (idée
/// #85) : nom de l'app gravé, hachures, nom de l'écran en phosphore. Elle est
/// posée ICI, une seule fois, plutôt qu'écran par écran — et l'encoche du
/// haut lui revient : les écrans en dessous n'ont plus à la reprendre, sinon
/// ils laisseraient deux fois la place du statut.
class _RetroScreenFrame extends StatelessWidget {
  const _RetroScreenFrame({required this.index, required this.child});

  final int index;
  final Widget child;

  static const _names = [
    'Accueil',
    'Media library',
    'Recherche',
    'Radio',
    'Favoris',
    'Jeux',
    'Vidéos',
  ];

  @override
  Widget build(BuildContext context) {
    if (!isRetroSkin(context)) return child;
    return Column(
      children: [
        RetroScreenBar(
          screen: index >= 0 && index < _names.length
              ? _names[index]
              : 'GulliFY',
        ),
        Expanded(
          child: MediaQuery.removePadding(
            context: context,
            removeTop: true,
            child: child,
          ),
        ),
      ],
    );
  }
}

/// Dock complet (mini-lecteur + navigation) pour les pages de DÉTAIL, hors
/// du shell : la navigation ramène à l'onglet correspondant. Aucun onglet
/// n'est actif (currentIndex -1). Rend la barre présente partout.
class DetailDock extends StatelessWidget {
  const DetailDock({super.key});

  /// Le chemin de chaque onglet, dans l'ordre du dock. Partagé avec le rail.
  static const paths = [
    '/',
    '/library',
    '/search',
    '/radio',
    '/favorites',
    '/games',
    '/videos',
  ];

  /// L'onglet auquel appartient un chemin, ou -1 pour une page de détail
  /// (fiche album, artiste…) : le rail n'y allume alors rien, comme le dock.
  static int indexForPath(String path) {
    if (path == '/') return 0;
    for (var i = 1; i < paths.length; i++) {
      if (path == paths[i] || path.startsWith('${paths[i]}/')) return i;
    }
    return -1;
  }

  @override
  Widget build(BuildContext context) =>
      HubDock(currentIndex: -1, onSelect: (i) => context.go(paths[i]));
}

/// Un onglet satellite du dock : icône (variante remplie/arrondie), teinte
/// accent + point animé quand actif.
class _DockDest {
  const _DockDest(
    this.branch,
    this.iconOff,
    this.iconOn,
    this.tooltip,
    this.retroLabel,
  );
  final int branch;
  final IconData iconOff;
  final IconData iconOn;
  final String tooltip;

  /// Le mot de trois lettres gravé sur la plaque sous le rétro (idée #85) :
  /// les lecteurs de 1999 étiquetaient leurs boutons, ils ne les
  /// pictogrammaient pas.
  final String retroLabel;
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
  // 4 Favoris, 5 Jeux, 6 Vidéos. Disposition : [1][2][6] (orbe 0) [3][4][5].
  static const _left = [
    _DockDest(
      1,
      Icons.library_music_outlined,
      Icons.library_music_rounded,
      'Bibliothèque',
      'LIB',
    ),
    _DockDest(
      2,
      Icons.search_rounded,
      Icons.search_rounded,
      'Recherche',
      'SRC',
    ),
    _DockDest(6, Icons.movie_outlined, Icons.movie_rounded, 'Vidéos', 'VID'),
  ];
  static const _right = [
    _DockDest(3, Icons.radio_outlined, Icons.radio_rounded, 'Radio', 'RAD'),
    _DockDest(
      4,
      Icons.favorite_border_rounded,
      Icons.favorite_rounded,
      'Favoris',
      'FAV',
    ),
    _DockDest(
      5,
      Icons.sports_esports_outlined,
      Icons.sports_esports_rounded,
      'Jeux',
      'JEU',
    ),
  ];

  /// Changer d'onglet ferme d'abord le clavier : un champ resté focalisé dans
  /// l'onglet qu'on quitte (il survit, masqué) laissait l'inset du clavier
  /// appliqué — d'où une bande vide en bas de l'onglet suivant.
  void _select(int branch) {
    dismissKeyboard();
    onSelect(branch);
  }

  Widget _satellites(List<_DockDest> dests, ColorScheme scheme) => Row(
    children: [
      for (final d in dests)
        Expanded(
          child: _Satellite(
            dest: d,
            selected: currentIndex == d.branch,
            scheme: scheme,
            onTap: () => _select(d.branch),
          ),
        ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    // Sur tablette et grand écran, la navigation est sur le côté et la
    // lecture dans la barre du bas de la fenêtre (voir `main.dart`) : le dock
    // n'a plus rien à porter.
    if (SideNavigationScope.visibleOf(context)) return const SizedBox.shrink();

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
        // En paysage, un téléphone réserve une marge du côté de sa caméra. La
        // pilule la respecte (son SafeArea) ; le mini-lecteur, sans elle,
        // débordait sous l'encoche — 50 px plus large que le menu et la page.
        // Les côtés seulement : le bas, la pilule dessous s'en charge déjà.
        const SafeArea(top: false, bottom: false, child: MiniPlayer()),
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
                onTap: () => _select(0),
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
    this.withTooltip = true,
  });

  final bool selected;
  final ColorScheme scheme;
  final VoidCallback onTap;

  /// Une infobulle exige un `Overlay` au-dessus d'elle. Le rail est posé
  /// au-dessus du navigateur, là où il n'y en a pas : il s'en passe.
  final bool withTooltip;

  @override
  Widget build(BuildContext context) {
    final accent = scheme.primary;
    // Rétro Winamp (idée #83) : un châssis n'a pas d'orbe qui brille. Le
    // bouton d'accueil devient une plaque carrée, enfoncée quand on y est —
    // et gravée « HOME » comme le reste de la barre (idée #85).
    if (isRetroSkin(context)) {
      return RetroButton(
        width: 60,
        height: 54,
        active: selected,
        onPressed: onTap,
        tooltip: withTooltip ? 'Accueil' : null,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.home_rounded,
              size: 20,
              color: selected ? winampGreen : winampInk,
            ),
            Text(
              'HOME',
              style: retroLabelStyle(
                size: 7,
                color: selected ? winampGreen : winampInk,
                letterSpacing: 0.8,
              ),
            ),
          ],
        ),
      );
    }
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
    // Rétro Winamp (idée #85) : une plaque de chrome gravée de trois lettres,
    // enfoncée et allumée en vert quand on y est. C'est la barre de boutons
    // d'un lecteur de 1999 — l'infobulle garde le nom complet pour ceux qui
    // n'ont pas connu.
    if (isRetroSkin(context)) {
      return Center(
        child: LayoutBuilder(
          builder: (context, constraints) => RetroButton(
            width: math.min(38, constraints.maxWidth),
            height: 26,
            active: selected,
            tooltip: dest.tooltip,
            onPressed: onTap,
            child: Text(
              dest.retroLabel,
              style: retroLabelStyle(
                size: 8,
                color: selected ? winampGreen : winampInk,
                letterSpacing: 0.6,
              ),
            ),
          ),
        ),
      );
    }
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
                // Rétro : carré. Apple : une gélule, comme l'onglet actif
                // d'iOS (idée #98). Verre Gullify : l'arrondi de toujours.
                borderRadius: BorderRadius.circular(
                  isRetroSkin(context)
                      ? 0
                      : isLiquidSkin(context)
                      ? 20
                      : 14,
                ),
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

/// Dit aux écrans si la navigation et la lecture sont passées hors de la
/// page — sur le côté et en bas de la fenêtre. Posée par l'app au-dessus du
/// navigateur (voir `main.dart`), elle permet au dock de s'effacer exactement
/// quand elles apparaissent : ni les deux, ni aucun.
class SideNavigationScope extends InheritedWidget {
  const SideNavigationScope({
    super.key,
    required this.visible,
    required super.child,
  });

  final bool visible;

  static bool visibleOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<SideNavigationScope>()
          ?.visible ??
      false;

  @override
  bool updateShouldNotify(SideNavigationScope oldWidget) =>
      visible != oldWidget.visible;
}

/// Le dock, debout : la même navigation, posée sur le côté d'une tablette ou
/// d'une petite fenêtre, réduite à ses icônes. Mêmes destinations, mêmes
/// icônes, même orbe d'accueil, même habillage rétro. Sur grand écran, c'est
/// [HubSidebar] qui prend le relais, avec la place de porter ses noms.
///
/// Il vit au-dessus du navigateur pour rester là d'un écran à l'autre, fiches
/// album et artiste comprises. À cet étage, ni `Overlay` ni `Material` : pas
/// d'infobulle ni d'encre donc — chaque destination porte plutôt son nom sous
/// l'icône, ce qui se lit mieux qu'une infobulle à la souris.
class HubRail extends StatelessWidget {
  const HubRail({
    super.key,
    required this.currentIndex,
    required this.onSelect,
  });

  final int currentIndex;
  final ValueChanged<int> onSelect;

  void _select(int branch) {
    dismissKeyboard();
    onSelect(branch);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Dans l'ordre des onglets, plutôt que la répartition gauche/droite du
    // dock, qui n'existe que pour garder l'orbe au centre de la pilule.
    final dests = [...HubDock._left, ...HubDock._right]
      ..sort((a, b) => a.branch.compareTo(b.branch));

    // Material transparent : sans lui, au-dessus du navigateur, les libellés
    // n'héritent d'aucun style de texte et Flutter les souligne en jaune.
    return Material(
      type: MaterialType.transparency,
      child: SafeArea(
        right: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 0, 12),
          child: GlassBox(
            radius: 28,
            // Hors du shell : ni flou en direct (voir GlassBox — certains GPU
            // le peignent en plein écran), ni ombre, qui n'a nulle part où
            // tomber au bord de la fenêtre.
            blur: false,
            shadow: false,
            child: SizedBox(
              width: 88,
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(vertical: 18),
                child: Column(
                  children: [
                    _HomeOrb(
                      selected: currentIndex == 0,
                      scheme: scheme,
                      onTap: () => _select(0),
                      withTooltip: false,
                    ),
                    const SizedBox(height: 18),
                    for (final d in dests)
                      _RailItem(
                        dest: d,
                        selected: currentIndex == d.branch,
                        scheme: scheme,
                        onTap: () => _select(d.branch),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RailItem extends StatelessWidget {
  const _RailItem({
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
    if (isRetroSkin(context)) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: RetroButton(
          width: 60,
          height: 34,
          active: selected,
          onPressed: onTap,
          child: Text(
            dest.retroLabel,
            style: retroLabelStyle(
              size: 9,
              color: selected ? winampGreen : winampInk,
              letterSpacing: 0.6,
            ),
          ),
        ),
      );
    }

    final color = selected ? scheme.primary : scheme.onSurfaceVariant;
    return Semantics(
      button: true,
      selected: selected,
      label: dest.tooltip,
      excludeSemantics: true,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 7),
            child: Column(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  width: 52,
                  height: 34,
                  decoration: BoxDecoration(
                    color: selected
                        ? scheme.primary.withValues(alpha: 0.16)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(
                      isLiquidSkin(context) ? 17 : 12,
                    ),
                  ),
                  child: Icon(
                    selected ? dest.iconOn : dest.iconOff,
                    size: 24,
                    color: color,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  dest.tooltip,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: color,
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

/// La barre latérale d'un grand écran : la navigation avec ses noms, et vos
/// playlists en dessous — comme la bibliothèque qu'on garde sous la main sur
/// un site de musique. Mêmes destinations que le dock et le rail.
///
/// Même contrainte que le rail : au-dessus du navigateur, ni infobulle ni
/// encre, et le style de texte fourni par un `Material` transparent.
class HubSidebar extends ConsumerWidget {
  const HubSidebar({
    super.key,
    required this.currentPath,
    required this.onNavigate,
  });

  /// Le chemin affiché : allume la destination, ou la playlist ouverte.
  final String currentPath;
  final ValueChanged<String> onNavigate;

  void _go(String path) {
    dismissKeyboard();
    onNavigate(path);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final current = DetailDock.indexForPath(currentPath);
    final dests = [...HubDock._left, ...HubDock._right]
      ..sort((a, b) => a.branch.compareTo(b.branch));
    final playlists = ref.watch(playlistsProvider).value ?? const <Playlist>[];

    return Material(
      type: MaterialType.transparency,
      child: SafeArea(
        right: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 0, 12),
          child: GlassBox(
            radius: 24,
            // Hors du shell : ni flou en direct (voir GlassBox — certains GPU
            // le peignent en plein écran), ni ombre, qui n'a nulle part où
            // tomber au bord de la fenêtre.
            blur: false,
            shadow: false,
            child: SizedBox(
              width: 236,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _SidebarBrand(onTap: () => _go('/')),
                  _SidebarItem(
                    icon: Icons.home_outlined,
                    iconOn: Icons.home_rounded,
                    label: 'Accueil',
                    selected: current == 0,
                    onTap: () => _go('/'),
                  ),
                  for (final d in dests)
                    _SidebarItem(
                      icon: d.iconOff,
                      iconOn: d.iconOn,
                      label: d.tooltip,
                      selected: current == d.branch,
                      onTap: () => _go(DetailDock.paths[d.branch]),
                    ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(22, 18, 16, 6),
                    child: Text(
                      'PLAYLISTS',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  Expanded(
                    child: playlists.isEmpty
                        ? Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 22),
                            child: Text(
                              'Aucune playlist pour l\'instant',
                              style: TextStyle(
                                fontSize: 12.5,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          )
                        : ListView(
                            padding: EdgeInsets.zero,
                            children: [
                              for (final p in playlists)
                                _SidebarItem(
                                  icon: Icons.queue_music_rounded,
                                  label: p.name,
                                  detail: '${p.songCount}',
                                  dense: true,
                                  selected: currentPath == '/playlist/${p.id}',
                                  onTap: () => _go(
                                    '/playlist/${p.id}'
                                    '?name=${Uri.encodeQueryComponent(p.name)}',
                                  ),
                                ),
                            ],
                          ),
                  ),
                  const Divider(height: 1),
                  _SidebarItem(
                    icon: Icons.settings_outlined,
                    iconOn: Icons.settings_rounded,
                    label: 'Paramètres',
                    selected: currentPath.startsWith('/settings'),
                    onTap: () => _go('/settings'),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// La tête de la barre : la mascotte et le nom, qui ramènent à l'accueil.
class _SidebarBrand extends StatelessWidget {
  const _SidebarBrand({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 18, 16, 14),
          // Les mêmes proportions qu'à l'accueil : le signe fait 1,74 fois
          // la taille du nom. Ici il était à 1,58 — un rien trop petit.
          child: const GulliLogo(fontSize: 20),
        ),
      ),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  const _SidebarItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.iconOn,
    this.detail,
    this.dense = false,
  });

  final IconData icon;
  final IconData? iconOn;
  final String label;

  /// Un complément discret à droite (le nombre de titres d'une playlist).
  final String? detail;
  final bool selected;
  final bool dense;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final retro = isRetroSkin(context);
    final color = selected
        ? (retro ? winampGreen : scheme.primary)
        : (retro ? winampInk : scheme.onSurface);

    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 1),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: EdgeInsets.symmetric(
                horizontal: 12,
                vertical: dense ? 7 : 10,
              ),
              decoration: BoxDecoration(
                color: selected
                    ? scheme.primary.withValues(alpha: retro ? 0.0 : 0.14)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(
                  retro ? 0 : (isLiquidSkin(context) ? 20 : 12),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    selected ? (iconOn ?? icon) : icon,
                    size: dense ? 20 : 22,
                    color: selected ? color : scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: dense ? 13.5 : 14.5,
                        fontWeight: selected
                            ? FontWeight.w700
                            : FontWeight.w500,
                        color: color,
                      ),
                    ),
                  ),
                  if (detail != null)
                    Text(
                      detail!,
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurfaceVariant,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
