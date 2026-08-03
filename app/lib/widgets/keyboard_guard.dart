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

/// Filet de sécurité contre l'« espace du clavier resté vide ».
///
/// Symptôme : une bande vide de la hauteur du clavier reste réservée en bas
/// de l'écran — le contenu est comprimé au-dessus, seule la barre du bas
/// paraît normale — alors qu'aucun clavier n'est visible. C'est un inset IME
/// resté appliqué après que le champ ait perdu le focus (changement
/// d'onglet, écran dépilé, dialogue fermé).
///
/// Ce garde surveille les changements de métriques : si l'inset du clavier
/// est appliqué alors qu'aucun champ n'a le focus, il force la fermeture de
/// l'IME, ce qui rend la bande à l'écran.
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    _check?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    _check?.cancel();
    _check = Timer(_delay, _verify);
  }

  void _verify() {
    if (!mounted) return;
    if (MediaQuery.viewInsetsOf(context).bottom <= 0) return;
    // Un champ focalisé = clavier légitime. Quand rien n'est focalisé, le
    // focus primaire est le FocusScopeNode de la route (ou null).
    final focus = FocusManager.instance.primaryFocus;
    if (focus != null && focus is! FocusScopeNode) return;
    dismissKeyboard();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
