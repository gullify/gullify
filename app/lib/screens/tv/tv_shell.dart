import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../state/tv_log.dart';
import 'tv_favorites_page.dart';
import 'tv_home_page.dart';
import 'tv_kit.dart';
import 'tv_library_page.dart';
import 'tv_party_page.dart';
import 'tv_radio_page.dart';
import 'tv_search_page.dart';
import 'tv_update.dart';

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

  /// Deux périmètres de focus, et des passages explicites entre les deux.
  ///
  /// Laissé au calcul géométrique, le déplacement haut/bas dans le rail
  /// s'échappait vers la page — qui vit juste derrière lui, le rail ouvert la
  /// recouvrant. On enferme donc chacun chez soi : haut et bas ne quittent
  /// jamais la liste, et ce sont la flèche droite (sortir du menu) et la
  /// flèche gauche en butée (y entrer) qui font le passage.
  final _railScope = FocusScopeNode(debugLabel: 'tv-rail');
  final _contentScope = FocusScopeNode(debugLabel: 'tv-content');

  /// L'entrée du menu correspondant à la page ouverte. Entrer dans le menu
  /// doit viser CET élément — un `FocusScopeNode` à qui l'on demande le focus
  /// ne désigne aucun de ses enfants, et l'écran paraît alors ne rien faire.
  final _railCurrent = FocusNode(debugLabel: 'tv-rail-current');

  /// Filet de sécurité du focus, différé (voir [_rescueFocus]).
  Timer? _rescue;

  @override
  void initState() {
    super.initState();
    TvLog.add('coque ouverte (${widget.initialTab.name})');
    // Le périmètre du contenu doit être actif dès l'ouverture : un `autofocus`
    // ne s'applique qu'à un périmètre qui détient le focus, sinon plus rien
    // n'est visé du tout.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _contentScope.requestFocus();
    });
    _rescueFocus();
  }

  @override
  void dispose() {
    _rescue?.cancel();
    _railScope.dispose();
    _contentScope.dispose();
    _railCurrent.dispose();
    super.dispose();
  }

  bool get _railFocused => _railScope.hasFocus;

  /// Sortir du menu vers la page.
  KeyEventResult _leaveRail() {
    _contentScope.requestFocus();
    return KeyEventResult.handled;
  }

  /// Entrer dans le menu — mais seulement depuis la première colonne.
  ///
  /// « Rien à gauche » ne suffit pas comme critère : Flutter accepte alors un
  /// candidat situé plus bas à gauche, et la flèche gauche partait dans une
  /// rangée au lieu d'aller au menu. On regarde donc où se trouve vraiment
  /// l'élément visé dans la page ; ailleurs qu'en tête, on laisse la
  /// traversée normale faire son travail.
  KeyEventResult _maybeEnterRail() {
    final current = FocusManager.instance.primaryFocus;
    final rect = current?.rect;
    if (current == null || rect == null) {
      _railCurrent.requestFocus();
      return KeyEventResult.handled;
    }
    // Y a-t-il quelque chose à viser à gauche, SUR LA MÊME LIGNE ? C'est la
    // seule question qui compte : « rien à gauche » tout court laisserait
    // Flutter partir vers une rangée située plus bas.
    final hasLeftNeighbour = _contentScope.traversalDescendants.any((node) {
      if (node == current) return false;
      final other = node.rect;
      final sameRow = other.top < rect.bottom && other.bottom > rect.top;
      return sameRow && other.center.dx < rect.center.dx;
    });
    if (hasLeftNeighbour) return KeyEventResult.ignored;
    _railCurrent.requestFocus();
    return KeyEventResult.handled;
  }

  KeyEventResult _onKey(KeyEvent event, KeyEventResult Function() action) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    return action();
  }

  /// Rattrape un focus tombé dans le vide.
  ///
  /// En arrivant de l'écran de connexion, les nœuds de l'écran précédent ont
  /// disparu et plus rien n'est visé : les flèches ne font alors strictement
  /// rien, et l'app a l'air plantée. Même chose quand une page se vide en
  /// attendant ses données. On redonne donc le focus au premier élément
  /// atteignable, à chaque image où il n'y en a plus.
  void _rescueFocus() {
    // Différé : les `autofocus` de la page sont posés au fil des premières
    // images, et rattraper trop tôt volerait le focus à la page pour le
    // donner au rail (le premier élément atteignable de la pile).
    _rescue?.cancel();
    _rescue = Timer(const Duration(milliseconds: 450), () {
      if (!mounted) return;
      final primary = FocusManager.instance.primaryFocus;
      if (primary == null || primary is FocusScopeNode) {
        FocusScope.of(context).nextFocus();
      }
    });
  }

  void _select(TvTab tab) {
    if (tab != _tab) {
      setState(() => _tab = tab);
      TvLog.add('onglet ${tab.name}');
    }
    _rescueFocus();
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
    // Une mise à jour occupe l'écran : tout ce qui est derrière devient
    // intouchable, sans quoi la croix directionnelle continue de parcourir la
    // page et l'on ne peut jamais atteindre « Mettre à jour ».
    final blocked = ref.watch(tvUpdateBlockingProvider);
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
            child: Focus(
              canRequestFocus: false,
              skipTraversal: true,
              onKeyEvent: (_, event) =>
                  event.logicalKey == LogicalKeyboardKey.arrowLeft
                  ? _onKey(event, _maybeEnterRail)
                  : KeyEventResult.ignored,
              child: FocusScope(
                node: _contentScope,
                child: ExcludeFocus(
                  excluding: blocked,
                  child: KeyedSubtree(key: ValueKey(_tab), child: _page),
                ),
              ),
            ),
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
              onFocusChange: (_) => setState(() {}),
              onKeyEvent: (_, event) =>
                  event.logicalKey == LogicalKeyboardKey.arrowRight
                  ? _onKey(event, _leaveRail)
                  : KeyEventResult.ignored,
              child: FocusScope(
                node: _railScope,
                child: ExcludeFocus(
                  excluding: blocked,
                  child: _Rail(
                    open: _railFocused,
                    width: _railFocused ? _railOpen : _railClosed,
                    current: _tab,
                    onSelect: _select,
                    currentNode: _railCurrent,
                    onSettings: () => context.push('/settings'),
                  ),
                ),
              ),
            ),
          ),
          // Par-dessus tout le reste : devant une télé, personne n'ira
          // chercher une mise à jour dans les réglages. Positionnée, sinon un
          // enfant libre de zéro pixel ferait s'effondrer toute la pile.
          const Positioned.fill(child: TvUpdateOverlay()),
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
    required this.currentNode,
    required this.onSettings,
  });

  final bool open;
  final double width;
  final TvTab current;
  final ValueChanged<TvTab> onSelect;

  /// Attaché à l'entrée de la page ouverte : c'est là qu'on arrive en entrant
  /// dans le menu.
  final FocusNode currentNode;
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
                focusNode: tab == current ? currentNode : null,
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
              // Le vrai logo, pas une pastille à initiale : c'est lui qu'on
              // reconnaît sur la rangée d'applications du téléviseur.
              Image.asset(
                'assets/icon/logo.png',
                width: 56,
                height: 56,
                filterQuality: FilterQuality.medium,
              ),
              if (open) ...[
                const SizedBox(width: 14),
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
    this.focusNode,
  });

  /// Nul pour l'entrée « Réglages », qui n'est pas une page de la coque mais
  /// un aller-retour vers les écrans tactiles.
  final TvTab? tab;
  final IconData icon;
  final String label;
  final bool open;
  final bool selected;
  final VoidCallback onPressed;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return TvFocusable(
      onPressed: onPressed,
      focusNode: focusNode,
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
