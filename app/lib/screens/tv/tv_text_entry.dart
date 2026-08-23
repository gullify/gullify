import 'package:flutter/material.dart';

import 'tv_kit.dart';

/// Saisie de texte à la télécommande, **sans le clavier d'Android**.
///
/// Le clavier système d'un téléviseur est une loterie : selon le boîtier il
/// prend la croix directionnelle ou la laisse à l'application, s'ouvre en
/// plein écran ou en bandeau, et se referme au premier déplacement de focus.
/// Impossible de garantir une saisie qui marche partout en s'appuyant dessus.
///
/// On dessine donc notre propre clavier : chaque touche est un élément
/// focalisable comme les autres, la croix le parcourt par construction, et
/// « OK » tape la lettre. Rien à négocier avec le système.

/// Un champ de la saisie : ce qu'on tape, et où ça va.
class TvEntryField {
  const TvEntryField({
    required this.label,
    required this.value,
    this.obscure = false,
  });

  final String label;
  final String value;

  /// Mot de passe : on montre des points, pas les lettres.
  final bool obscure;
}

/// Le clavier et ses champs, sur un écran de connexion.
class TvTextEntry extends StatefulWidget {
  const TvTextEntry({
    super.key,
    required this.fields,
    required this.active,
    required this.onSelectField,
    required this.onType,
    required this.onBackspace,
    required this.onSubmit,
    required this.submitLabel,
    this.submitEnabled = true,
    this.symbols = const ['.', '-', '_', '/', ':', '@'],
  });

  final List<TvEntryField> fields;

  /// Index du champ que le clavier alimente.
  final int active;

  final ValueChanged<int> onSelectField;
  final ValueChanged<String> onType;
  final VoidCallback onBackspace;
  final VoidCallback onSubmit;
  final String submitLabel;
  final bool submitEnabled;

  /// Caractères utiles au contexte (une adresse de serveur en demande
  /// d'autres qu'un nom d'utilisateur).
  final List<String> symbols;

  @override
  State<TvTextEntry> createState() => _TvTextEntryState();
}

class _TvTextEntryState extends State<TvTextEntry> {
  bool _caps = false;

  @override
  Widget build(BuildContext context) {
    const letters = 'abcdefghijklmnopqrstuvwxyz';
    const digits = '0123456789';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < widget.fields.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _Field(
              field: widget.fields[i],
              active: i == widget.active,
              autofocus: i == 0,
              onPressed: () => widget.onSelectField(i),
            ),
          ),
        const SizedBox(height: 8),
        // Six colonnes : traverser un clavier de dix demanderait deux fois
        // plus de trajet à la croix.
        GridView.count(
          crossAxisCount: 6,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: 1.62,
          children: [
            for (final c in letters.split(''))
              _Key(
                label: _caps ? c.toUpperCase() : c,
                onPressed: () => widget.onType(_caps ? c.toUpperCase() : c),
              ),
            for (final c in digits.split(''))
              _Key(label: c, onPressed: () => widget.onType(c)),
            for (final c in widget.symbols)
              _Key(label: c, onPressed: () => widget.onType(c)),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _Key(
                label: _caps ? 'abc' : 'ABC',
                small: true,
                onPressed: () => setState(() => _caps = !_caps),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _Key(
                label: 'espace',
                small: true,
                onPressed: () => widget.onType(' '),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _Key(
                label: 'effacer',
                small: true,
                icon: Icons.backspace_outlined,
                onPressed: widget.onBackspace,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        TvPill(
          label: widget.submitLabel,
          icon: Icons.arrow_forward_rounded,
          expand: true,
          onPressed: widget.submitEnabled ? widget.onSubmit : null,
        ),
      ],
    );
  }
}

/// Un champ : son intitulé, ce qu'il contient, et un curseur quand c'est lui
/// que le clavier alimente.
class _Field extends StatelessWidget {
  const _Field({
    required this.field,
    required this.active,
    required this.onPressed,
    this.autofocus = false,
  });

  final TvEntryField field;
  final bool active;
  final bool autofocus;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final shown = field.obscure ? '•' * field.value.length : field.value;

    return TvFocusable(
      onPressed: onPressed,
      autofocus: autofocus,
      scale: 1.0,
      builder: (context, focused) => Container(
        height: 72,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: focused ? 0.12 : 0.06),
          borderRadius: BorderRadius.circular(20),
          border: focused
              ? tvFocusBorder(scheme.primary)
              : Border.all(
                  color: active
                      ? scheme.primary.withValues(alpha: 0.8)
                      : Colors.white.withValues(alpha: 0.14),
                  width: active ? 2 : 1,
                ),
          boxShadow: focused ? tvFocusGlow(scheme.primary, spread: 4) : null,
        ),
        child: Row(
          children: [
            SizedBox(
              width: 210,
              child: Text(
                field.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: tvMinText,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.4,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
            Expanded(
              child: Text(
                shown,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
                style: const TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            if (active) ...[
              const SizedBox(width: 8),
              Container(
                width: 3,
                height: 34,
                decoration: BoxDecoration(
                  color: scheme.primary,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Key extends StatelessWidget {
  const _Key({
    required this.label,
    required this.onPressed,
    this.small = false,
    this.icon,
  });

  final String label;
  final VoidCallback onPressed;
  final bool small;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return TvFocusable(
      onPressed: onPressed,
      scale: 1.1,
      builder: (context, focused) => Container(
        height: small ? 58 : null,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: focused
              ? scheme.primary
              : Colors.white.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(16),
          border: focused
              ? tvFocusBorder(scheme.primary)
              : Border.all(color: Colors.white.withValues(alpha: 0.15)),
          boxShadow: focused ? tvFocusGlow(scheme.primary, spread: 4) : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                size: 22,
                color: focused ? Colors.white : scheme.onSurface,
              ),
              const SizedBox(width: 8),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: small ? 22 : 30,
                fontWeight: FontWeight.w700,
                color: focused ? Colors.white : scheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
