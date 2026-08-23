import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'tv_favorites_page.dart';
import 'tv_home_page.dart';
import 'tv_kit.dart';
import 'tv_library_page.dart';
import 'tv_party_page.dart';
import 'tv_radio_page.dart';
import 'tv_search_page.dart';

/// Les destinations du rail, dans l'ordre où on les rencontre en montant.
enum TvTab {
  home('Accueil', Icons.home_rounded),
  library('Bibliothèque', Icons.library_music_rounded),
  search('Recherche', Icons.search_rounded),
  favorites('Favoris', Icons.favorite_rounded),
  radio('Radio', Icons.radio_rounded),
  games('Jeux', Icons.sports_esports_rounded);

  const TvTab(this.label, this.icon);

  final String label;
  final IconData icon;
}

/// La coque de l'app sur téléviseur : un rail à gauche, un écran à droite.
///
/// Le rail ne s'ouvre qu'en recevant le focus — c'est ce qui permet de garder
/// [_railClosed] px de large le reste du temps, sans voler de place à la
/// musique. Il flotte au-dessus du contenu plutôt que de le pousser : voir
/// s'écarter toute une page parce qu'on est allé chercher le menu donne le
/// tournis sur un grand écran.
class TvShell extends ConsumerStatefulWidget {
  const TvShell({super.key, this.initialTab = TvTab.home});

  final TvTab initialTab;

  @override
  ConsumerState<TvShell> createState() => _TvShellState();
}

class _TvShellState extends ConsumerState<TvShell> {
  static const _railClosed = 108.0;
  static const _railOpen = 390.0;

  late TvTab _tab = widget.initialTab;
  bool _railFocused = false;

  void _select(TvTab tab) {
    if (tab != _tab) setState(() => _tab = tab);
    // Passer au contenu tout de suite : rester dans le rail après avoir
    // choisi obligerait à un aller-retour de plus à chaque navigation. On
    // pousse le focus vers la droite plutôt que de viser un nœud précis —
    // c'est le geste que l'utilisateur ferait, et la page suivante n'est pas
    // encore construite au moment du choix.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        FocusScope.of(context).focusInDirection(TraversalDirection.right);
      }
    });
  }

  Widget get _page => switch (_tab) {
    TvTab.home => const TvHomePage(),
    TvTab.library => const TvLibraryPage(),
    TvTab.search => const TvSearchPage(),
    TvTab.favorites => const TvFavoritesPage(),
    TvTab.radio => const TvRadioPage(),
    TvTab.games => const TvPartyPage(),
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          Positioned.fill(
            left: _railClosed + 42,
            // Pas de FocusScope autour du contenu : un périmètre de focus
            // enferme la navigation directionnelle, et la flèche gauche ne
            // sortirait jamais pour aller chercher le rail.
            //
            // La clé fait repartir chaque page de zéro : sans elle, Flutter
            // réutiliserait l'état de la précédente (position de défilement,
            // focus) d'un onglet à l'autre.
            child: KeyedSubtree(key: ValueKey(_tab), child: _page),
          ),
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            child: Focus(
              // Nœud non focalisable qui écoute ses descendants : c'est ce
              // qui dit « le focus est entré dans le rail ».
              canRequestFocus: false,
              skipTraversal: true,
              onFocusChange: (v) {
                if (v != _railFocused) setState(() => _railFocused = v);
              },
              child: _Rail(
                open: _railFocused,
                width: _railFocused ? _railOpen : _railClosed,
                current: _tab,
                onSelect: _select,
                onSettings: () => context.push('/settings'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Largeur utile du rail ouvert, marges déduites : c'est à cette largeur-là
/// que le contenu est composé, quelle que soit l'ouverture du tiroir.
const _railContent = 390.0 - 60 - 34;

class _Rail extends StatelessWidget {
  const _Rail({
    required this.open,
    required this.width,
    required this.current,
    required this.onSelect,
    required this.onSettings,
  });

  final bool open;
  final double width;
  final TvTab current;
  final ValueChanged<TvTab> onSelect;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
      width: width,
      padding: EdgeInsets.only(
        left: open ? 30 : 21,
        right: open ? 30 : 21,
        top: tvSafeV + 4,
        bottom: tvSafeV,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: open
              ? [
                  const Color(0xF01A1C22),
                  const Color(0xC0141620),
                  const Color(0x00141620),
                ]
              : [const Color(0x8C000000), const Color(0x00000000)],
          stops: open ? const [0, 0.75, 1] : const [0, 1],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Logo(open: open),
          const SizedBox(height: 26),
          for (final tab in TvTab.values)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _RailItem(
                tab: tab,
                icon: tab.icon,
                label: tab.label,
                open: open,
                selected: tab == current,
                onPressed: () => onSelect(tab),
              ),
            ),
          const Spacer(),
          // Les réglages restent ceux de l'app mobile : ils se manœuvrent très
          // bien à la croix directionnelle, et les redessiner pour la télé
          // aurait été du temps mal placé.
          _RailItem(
            tab: null,
            icon: Icons.settings_rounded,
            label: 'Réglages',
            open: open,
            selected: false,
            onPressed: onSettings,
          ),
          if (open) ...[
            const SizedBox(height: 14),
            Text(
              'Gullify',
              style: TextStyle(
                fontSize: tvMinText,
                color: scheme.onSurfaceVariant.withValues(alpha: 0.5),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Logo extends StatelessWidget {
  const _Logo({required this.open});

  final bool open;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Hauteur imposée : un OverflowBox prend tout ce qu'on lui laisse, et
    // dans une colonne il n'y a pas de limite en hauteur.
    return SizedBox(
      height: 56,
      child: ClipRect(
        child: OverflowBox(
          alignment: Alignment.centerLeft,
          maxWidth: _railContent,
          child: Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color.lerp(scheme.primary, Colors.white, 0.3)!,
                      scheme.primary,
                    ],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: scheme.primary.withValues(alpha: 0.45),
                      blurRadius: 24,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: const Center(
                  child: Text(
                    'G',
                    style: TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
              if (open) ...[
                const SizedBox(width: 16),
                const Expanded(
                  child: Text(
                    'Gullify',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.6,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _RailItem extends StatelessWidget {
  const _RailItem({
    required this.tab,
    required this.icon,
    required this.label,
    required this.open,
    required this.selected,
    required this.onPressed,
  });

  /// Nul pour l'entrée « Réglages », qui n'est pas une page de la coque mais
  /// un aller-retour vers les écrans tactiles.
  final TvTab? tab;
  final IconData icon;
  final String label;
  final bool open;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return TvFocusable(
      onPressed: onPressed,
      scale: 1.0,
      builder: (context, focused) => Container(
        height: 66,
        padding: EdgeInsets.symmetric(horizontal: open ? 17 : 0),
        decoration: BoxDecoration(
          color: focused ? Colors.white.withValues(alpha: 0.12) : null,
          borderRadius: BorderRadius.circular(20),
          border: focused ? tvFocusBorder(scheme.primary) : null,
          boxShadow: focused ? tvFocusGlow(scheme.primary, spread: 4) : null,
        ),
        // Le contenu est toujours composé à la largeur du rail OUVERT, et le
        // tiroir ne fait que le découvrir : le composer à la largeur du
        // moment le ferait déborder pendant toute l'animation.
        child: ClipRect(
          child: OverflowBox(
            alignment: Alignment.centerLeft,
            maxWidth: _railContent,
            child: Row(
              mainAxisAlignment: open
                  ? MainAxisAlignment.start
                  : MainAxisAlignment.center,
              mainAxisSize: open ? MainAxisSize.max : MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 30,
                  color: selected
                      ? scheme.primary
                      : focused
                      ? scheme.onSurface
                      : scheme.onSurfaceVariant,
                ),
                if (open) ...[
                  const SizedBox(width: 20),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 27,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.3,
                        color: selected || focused
                            ? scheme.onSurface
                            : scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
