import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Ferme le clavier logiciel et libère la connexion IME.
///
/// `unfocus()` seul suffit quand le champ est encore à l'écran; l'appel
/// explicite à `TextInput.hide` couvre le cas où le champ a déjà perdu le
/// focus (onglet masqué, écran dépilé) alors que le clavier, lui, est resté
/// ouvert côté Android.
void dismissKeyboard() {
  FocusManager.instance.primaryFocus?.unfocus();
  SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
}

/// Ferme le clavier à chaque changement d'écran.
///
/// Sans ça, ouvrir un album depuis la recherche (ou revenir en arrière)
/// laissait le clavier ouvert par-dessus la page suivante. Les routes
/// « pop-up » (dialogues, feuilles) sont exclues : plusieurs d'entre elles
/// ouvrent justement un champ en `autofocus`.
class KeyboardDismissObserver extends NavigatorObserver {
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is! PopupRoute) dismissKeyboard();
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is! PopupRoute) dismissKeyboard();
  }
}

/// Vrai quand un champ *à l'écran* a le focus — donc quand le clavier a une
/// raison d'être ouvert.
///
/// Un champ peut garder le focus après avoir quitté l'écran : l'onglet qu'on
/// vient de quitter survit dans l'IndexedStack du shell, et un écran recouvert
/// reste monté. Son clavier, lui, est parti depuis longtemps. `TickerMode`
/// sépare les deux cas : go_router désactive les tickers de la branche
/// masquée, et Flutter ceux d'une route hors écran.
bool _hasLiveEditableFocus() {
  final focus = FocusManager.instance.primaryFocus;
  // Quand rien n'est focalisé, le focus primaire est le FocusScopeNode de la
  // route (ou null).
  if (focus == null || focus is FocusScopeNode) return false;
  final context = focus.context;
  if (context == null || !context.mounted) return false;
  return TickerMode.valuesOf(context).enabled;
}

/// Filet de sécurité contre l'« espace du clavier resté vide ».
///
/// Symptôme : une bande vide de la hauteur du clavier reste réservée en bas
/// de l'écran — le contenu est comprimé au-dessus, seule la barre du bas
/// paraît normale — alors qu'aucun clavier n'est visible. C'est un inset IME
/// resté appliqué après que le champ ait perdu le focus (changement
/// d'onglet, écran dépilé, dialogue fermé).
///
/// Le garde se réveille à chaque changement de métriques, de focus, et au
/// retour dans l'app. Quand l'inset du clavier est appliqué sans qu'aucun
/// champ ne soit à l'écran, il fait deux choses :
///
/// 1. il demande la fermeture de l'IME (cas où le clavier est encore ouvert
///    côté Android alors que plus personne ne l'attend) ;
/// 2. il cesse de réserver la place — l'inset est neutralisé pour tout ce qui
///    est en dessous. C'est ce deuxième point qui rend vraiment la bande :
///    demander la fermeture ne sert à rien quand le clavier est DÉJÀ fermé et
///    que seul l'inset est resté collé (2.65.0 s'arrêtait là).
///
/// La neutralisation est levée dès que l'inset disparaît ou qu'un champ
/// reprend le focus : un clavier légitime réserve toujours sa place.
class KeyboardInsetGuard extends StatefulWidget {
  const KeyboardInsetGuard({super.key, required this.child});

  final Widget child;

  @override
  State<KeyboardInsetGuard> createState() => _KeyboardInsetGuardState();
}

class _KeyboardInsetGuardState extends State<KeyboardInsetGuard>
    with WidgetsBindingObserver {
  // Assez long pour laisser un `autofocus` prendre le focus après l'ouverture
  // d'un dialogue, assez court pour que la bande vide ne s'installe pas.
  static const _delay = Duration(milliseconds: 700);

  Timer? _check;

  /// Vrai quand on a constaté un inset de clavier sans clavier : la place
  /// n'est plus réservée en dessous du garde.
  bool _ignoreInset = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    FocusManager.instance.addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    _check?.cancel();
    FocusManager.instance.removeListener(_onFocusChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeMetrics() => _schedule();

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Revenir dans l'app peut restaurer l'inset d'un clavier qui, lui, ne
    // revient pas.
    if (state == AppLifecycleState.resumed) _schedule();
  }

  void _onFocusChanged() {
    // Un champ qui reprend le focus reprend aussitôt sa place : attendre le
    // délai de garde ferait ouvrir le clavier par-dessus lui.
    if (_ignoreInset && _hasLiveEditableFocus()) {
      setState(() => _ignoreInset = false);
    }
    _schedule();
  }

  void _schedule() {
    _check?.cancel();
    _check = Timer(_delay, _verify);
  }

  void _verify() {
    if (!mounted) return;
    // L'inset brut : le garde lit le MediaQuery de son parent, jamais celui
    // qu'il fabrique lui-même.
    final stuck =
        MediaQuery.viewInsetsOf(context).bottom > 0 && !_hasLiveEditableFocus();
    if (stuck) dismissKeyboard();
    if (stuck != _ignoreInset) setState(() => _ignoreInset = stuck);
  }

  @override
  Widget build(BuildContext context) {
    if (!_ignoreInset) return widget.child;
    final media = MediaQuery.of(context);
    return MediaQuery(
      data: media.copyWith(
        viewInsets: media.viewInsets.copyWith(bottom: 0),
        // Sans clavier, la marge du bas redevient celle du système (barre de
        // gestes) : sinon les SafeArea colleraient au bord de l'écran.
        padding: media.padding.copyWith(bottom: media.viewPadding.bottom),
      ),
      child: widget.child,
    );
  }
}
