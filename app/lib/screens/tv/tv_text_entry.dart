import 'dart:async';

import 'package:flutter/material.dart';

import '../../state/tv_log.dart';
import 'tv_kit.dart';

/// Un champ de saisie pour téléviseur, **avec le clavier de Google**.
///
/// Le piège d'Android TV n'est pas le clavier système — il fait très bien son
/// travail — c'est ce qui se passe quand il se referme : le champ Flutter
/// garde le focus, et la croix directionnelle se met alors à déplacer le
/// curseur au lieu de changer d'élément. On reste coincé dans le champ, et
/// l'app paraît figée.
///
/// D'où ce champ en deux temps, qui est le geste attendu sur un téléviseur :
///
///  1. au repos, c'est un simple élément focalisable — la croix le traverse
///     comme un bouton, rien ne peut la piéger ;
///  2. « OK » ouvre le clavier de Google, qui prend la main et se pilote
///     normalement ;
///  3. dès qu'il se referme — validation, retour, ou perte de focus — on rend
///     immédiatement le focus à l'élément, et la croix repart.
///
/// Le champ de texte réel n'existe donc que le temps de la frappe.
class TvImeField extends StatefulWidget {
  const TvImeField({
    super.key,
    required this.label,
    required this.controller,
    this.obscure = false,
    this.autofocus = false,
    this.keyboardType,
    this.hint,
    this.onSubmitted,
  });

  final String label;
  final TextEditingController controller;
  final bool obscure;
  final bool autofocus;
  final TextInputType? keyboardType;
  final String? hint;

  /// Appelé quand l'utilisateur valide au clavier. Sert à enchaîner sur le
  /// champ suivant, ou à lancer la connexion depuis le dernier.
  final VoidCallback? onSubmitted;

  @override
  State<TvImeField> createState() => _TvImeFieldState();
}

class _TvImeFieldState extends State<TvImeField> {
  /// Le nœud de l'élément « au repos » : celui que la croix visite.
  final _tile = FocusNode(debugLabel: 'tv-field');

  /// Le nœud du champ de texte, vivant seulement pendant la frappe.
  final _input = FocusNode(debugLabel: 'tv-input');

  bool _editing = false;
  Timer? _watchdog;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChanged);
    _input.addListener(_onInputFocus);
  }

  @override
  void dispose() {
    _watchdog?.cancel();
    widget.controller.removeListener(_onChanged);
    _input.removeListener(_onInputFocus);
    _tile.dispose();
    _input.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  /// Le champ a perdu le focus : le clavier s'est refermé (validation, retour,
  /// ou bascule d'application). On revient à l'état « au repos ».
  void _onInputFocus() {
    if (_input.hasFocus || !_editing) return;
    _stopEditing();
  }

  void _startEditing() {
    TvLog.add('clavier ouvert (${widget.label})');
    setState(() => _editing = true);
    _input.requestFocus();
    // Filet : si le clavier ne s'ouvre pas du tout (boîtier sans IME, ou
    // clavier physique branché), on ne doit pas rester bloqué dans un champ
    // invisible. Sans frappe ni focus au bout de deux secondes, on rend la
    // main.
    _watchdog?.cancel();
    _watchdog = Timer(const Duration(seconds: 2), () {
      if (mounted && _editing && !_input.hasFocus) {
        TvLog.add('clavier non ouvert : retour à la navigation');
        _stopEditing();
      }
    });
  }

  void _stopEditing() {
    _watchdog?.cancel();
    if (!mounted) return;
    setState(() => _editing = false);
    // Le focus retourne à l'élément : la croix directionnelle repart de là,
    // et surtout plus aucun champ de texte ne la retient.
    _tile.requestFocus();
    TvLog.add('clavier refermé (${widget.label})');
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final value = widget.controller.text;
    final shown = widget.obscure ? '•' * value.length : value;

    return Stack(
      children: [
        TvFocusable(
          focusNode: _tile,
          autofocus: widget.autofocus,
          onPressed: _startEditing,
          scale: 1.0,
          builder: (context, focused) => Container(
            height: 96,
            padding: const EdgeInsets.symmetric(horizontal: 28),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: focused ? 0.12 : 0.06),
              borderRadius: BorderRadius.circular(22),
              border: focused || _editing
                  ? tvFocusBorder(scheme.primary)
                  : Border.all(color: Colors.white.withValues(alpha: 0.14)),
              boxShadow: focused || _editing
                  ? tvFocusGlow(scheme.primary, spread: 4)
                  : null,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.label,
                        style: TextStyle(
                          fontSize: tvMinText,
                          height: 1.2,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.4,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        shown.isEmpty ? (widget.hint ?? 'Appuie sur OK') : shown,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 32,
                          height: 1.15,
                          fontWeight: FontWeight.w700,
                          color: shown.isEmpty
                              ? scheme.onSurfaceVariant.withValues(alpha: 0.55)
                              : scheme.onSurface,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  _editing ? Icons.keyboard_rounded : Icons.edit_rounded,
                  size: 30,
                  color: _editing ? scheme.primary : scheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
        // Le champ réel : invisible, mais bien monté pendant la frappe — c'est
        // lui qui fait apparaître le clavier de Google et reçoit les lettres.
        if (_editing)
          Positioned(
            left: 0,
            top: 0,
            width: 1,
            height: 1,
            child: Opacity(
              opacity: 0,
              child: TextField(
                focusNode: _input,
                controller: widget.controller,
                obscureText: widget.obscure,
                autocorrect: false,
                enableSuggestions: false,
                keyboardType: widget.keyboardType,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) {
                  _stopEditing();
                  widget.onSubmitted?.call();
                },
                onTapOutside: (_) => _stopEditing(),
              ),
            ),
          ),
      ],
    );
  }
}
