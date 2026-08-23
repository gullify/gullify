import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../state/tv_log.dart';
import 'tv_kit.dart';

/// Un champ de saisie pour téléviseur, **avec le clavier de Google**.
///
/// La difficulté n'est pas le clavier de Google, c'est **à qui Android confie
/// les touches**.
///
/// Flutter dessine ses propres champs : le clavier système s'affiche bien,
/// mais il est raccordé à la vue Flutter et ne reçoit jamais la croix
/// directionnelle — il reste inerte. Les applications natives d'un téléviseur
/// n'ont pas ce problème parce qu'elles utilisent un `EditText`, une vraie vue
/// Android à qui le système remet les touches.
///
/// On fait donc pareil : « OK » ouvre une boîte de dialogue native contenant
/// un `EditText`, le clavier de la télé s'y comporte comme partout ailleurs,
/// et le texte saisi revient à Flutter. Le reste du temps, ce champ n'est
/// qu'un élément focalisable de plus — la croix le traverse comme un bouton,
/// et rien ne peut la piéger.
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
  static const _native = MethodChannel('gullify/textinput');

  /// Le nœud de l'élément : celui que la croix visite, tout le temps.
  final _tile = FocusNode(debugLabel: 'tv-field');

  bool _editing = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChanged);
    _tile.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _startEditing() async {
    if (_editing) return;
    setState(() => _editing = true);
    TvLog.add('saisie native ouverte (${widget.label})');
    String? typed;
    try {
      typed = await _native.invokeMethod<String>('prompt', {
        'title': widget.label,
        'value': widget.controller.text,
        'password': widget.obscure,
        'url': widget.keyboardType == TextInputType.url,
      });
    } catch (e) {
      // Plateforme sans le canal (ancien APK, autre système) : on ne bloque
      // pas l'utilisateur, on le dit dans le journal.
      TvLog.add('saisie native indisponible : $e');
    }
    if (!mounted) return;
    setState(() => _editing = false);
    TvLog.add(
      'saisie native fermée (${typed == null ? "annulée" : "validée"})',
    );
    if (typed != null) {
      widget.controller.text = typed;
      widget.onSubmitted?.call();
    }
    // Le focus n'a jamais quitté l'élément, mais la boîte native a pu le
    // brouiller : on le redemande explicitement.
    _tile.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final value = widget.controller.text;
    final shown = widget.obscure ? '•' * value.length : value;

    return TvFocusable(
      focusNode: _tile,
      autofocus: widget.autofocus,
      onPressed: _startEditing,
      scale: 1.0,
      builder: (context, focused) => Container(
        height: 82,
        padding: const EdgeInsets.symmetric(horizontal: 24),
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
                      fontSize: 28,
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
              size: 26,
              color: _editing ? scheme.primary : scheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}
