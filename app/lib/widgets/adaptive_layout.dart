import 'package:flutter/widgets.dart';

/// Où vit la navigation, selon la place.
///
/// C'est la même app à toutes les tailles, qui se réorganise — comme YouTube
/// Music entre son app mobile et son site :
///  - [dock] : téléphone. La barre du bas, le mini-lecteur au-dessus.
///  - [rail] : tablette, petite fenêtre. La navigation debout sur le côté,
///    réduite à ses icônes, et la barre de lecture en bas de la fenêtre.
///  - [sidebar] : grand écran. La barre latérale complète — les noms à côté
///    des icônes, les playlists en dessous — et la barre de lecture.
///
/// Le contenu, lui, prend toute la largeur qui reste : sur un grand écran,
/// c'est la place qu'on vient chercher.
enum NavLayout { dock, rail, sidebar }

/// À partir de là, la navigation quitte le bas de l'écran (classe
/// « étendue » de Material).
const kNavigationRailMinWidth = 840.0;

/// À partir de là, elle a la place de porter ses noms et les playlists.
const kSidebarMinWidth = 1200.0;

/// Le téléphone couché est assez large pour un rail, mais sept destinations
/// empilées n'y tiennent pas en hauteur — et le dock y marche très bien.
const kNavigationRailMinHeight = 560.0;

/// Pas sur la télé, dont l'interface est dessinée pour le plein cadre ; pas
/// avant la connexion, où il n'y a rien vers quoi naviguer.
NavLayout navLayoutFor({
  required Size window,
  required bool tv,
  required bool authenticated,
}) {
  if (tv || !authenticated) return NavLayout.dock;
  if (window.width < kNavigationRailMinWidth ||
      window.height < kNavigationRailMinHeight) {
    return NavLayout.dock;
  }
  return window.width >= kSidebarMinWidth ? NavLayout.sidebar : NavLayout.rail;
}

/// Largeur à partir de laquelle un bloc se réorganise pour la place dont il
/// dispose (une fiche, une rangée de titres). Mesurée sur le [MediaQuery].
const kWideLayoutBreakpoint = 720.0;

bool isWideLayout(BuildContext context) =>
    MediaQuery.sizeOf(context).width >= kWideLayoutBreakpoint;

/// Le bouton d'action principal d'une rangée (« Lecture », « Tout lire ») :
/// toute la place au téléphone, où il se vise au pouce ; une largeur de bouton
/// sur grand écran, où un bouton de 900 px ne se lit plus comme un bouton.
///
/// À poser directement dans une `Row` : il y rend un `Expanded`.
class PrimaryActionSlot extends StatelessWidget {
  const PrimaryActionSlot({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => isWideLayout(context)
      ? SizedBox(width: 300, child: child)
      : Expanded(child: child);
}
