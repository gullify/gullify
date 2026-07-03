import 'package:flutter/material.dart';

import 'glass_box.dart';

/// Petits composants du langage « Liquid Glass Player » :
/// boutons ronds de verre, pilule Lecture accent, titres de section,
/// barres d'égaliseur animées pour la piste en cours.

/// Bouton rond de verre (retour, actions secondaires) — 44 px.
class GlassIconButton extends StatelessWidget {
  const GlassIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.tooltip,
    this.size = 44,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: GlassBox(
        radius: size / 2,
        child: IconButton(
          tooltip: tooltip,
          icon: Icon(icon, size: size * 0.5),
          color: Theme.of(context).colorScheme.onSurface,
          onPressed: onPressed,
        ),
      ),
    );
  }
}

/// Pilule « Lecture » accent avec ombre colorée — signature du design.
class AccentPlayButton extends StatelessWidget {
  const AccentPlayButton({
    super.key,
    required this.onPressed,
    this.label = 'Lecture',
    this.icon = Icons.play_arrow,
    this.expand = false,
  });

  final VoidCallback? onPressed;
  final String label;
  final IconData icon;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final button = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        boxShadow: [
          BoxShadow(
            color: scheme.primary.withValues(alpha: 0.45),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: FilledButton.icon(
        style: FilledButton.styleFrom(
          minimumSize: const Size(64, 52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(26),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
        ),
        onPressed: onPressed,
        icon: Icon(icon),
        label: Text(label),
      ),
    );
    return expand ? SizedBox(width: double.infinity, child: button) : button;
  }
}

/// Titre de section : 16.5 / w700 (design).
class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.padding});

  final String text;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding ?? const EdgeInsets.fromLTRB(20, 16, 20, 2),
      child: Text(
        text,
        style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w700),
      ),
    );
  }
}

/// Trois barres d'égaliseur animées — indicateur « en lecture ».
class EqBars extends StatefulWidget {
  const EqBars({super.key, this.color, this.playing = true, this.height = 16});

  final Color? color;
  final bool playing;
  final double height;

  @override
  State<EqBars> createState() => _EqBarsState();
}

class _EqBarsState extends State<EqBars> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 850),
  );

  @override
  void initState() {
    super.initState();
    if (widget.playing) _controller.repeat();
  }

  @override
  void didUpdateWidget(EqBars oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.playing && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!widget.playing && _controller.isAnimating) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  double _scale(double t, double phase) {
    final v = (t + phase) % 1.0;
    // 0.28 → 1 → 0.28, sinusoïde comme l'animation CSS du design.
    final s = v < 0.5 ? v * 2 : (1 - v) * 2;
    return 0.28 + 0.72 * s;
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? Theme.of(context).colorScheme.primary;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final phase in const [0.0, 0.33, 0.6]) ...[
            Container(
              width: 3,
              height: widget.height *
                  (widget.playing ? _scale(_controller.value, phase) : 0.5),
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            if (phase != 0.6) const SizedBox(width: 2.5),
          ],
        ],
      ),
    );
  }
}
