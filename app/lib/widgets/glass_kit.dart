import 'package:flutter/material.dart';

import 'liquid_glass.dart';
import 'retro_chrome.dart';
import 'retro_lcd.dart';

/// Petits composants du langage « Liquid Glass Player » :
/// boutons ronds de verre, pilule Lecture accent, titres de section,
/// barres d'égaliseur animées pour la piste en cours.
///
/// Sous le rétro Winamp, les deux premiers changent de peau (idée #85) : le
/// rond de verre devient une plaque de chrome carrée, le titre de section un
/// libellé bitmap gravé. Même place, même rôle — c'est là que le skin se
/// gagne, dans les composants partagés, pas écran par écran.

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
    // Rétro Winamp : une plaque de chrome carrée, comme les cases STAT /
    // NOTIF / MOI du design (idée #85). Un rond de verre au-dessus d'un
    // châssis se voit à dix mètres.
    if (isRetroSkin(context)) {
      return RetroButton(
        width: size,
        height: size * 0.82,
        tooltip: tooltip,
        onPressed: onPressed,
        child: Icon(icon, size: size * 0.44, color: winampInk),
      );
    }
    // Apple Liquid Glass (idée #98) : le rond de verre devient une vraie
    // lentille — arête qui accroche la lumière comprise. Même diamètre, même
    // place : c'est la matière qui change, pas le bouton.
    if (isLiquidSkin(context)) {
      return LiquidGlass(
        circle: true,
        // Pas de flou sur un si petit disque : invisible, et multiplier les
        // BackdropFilter coûte cher (même raison qu'en verre Gullify).
        blur: false,
        child: SizedBox(
          width: size,
          height: size,
          child: IconButton(
            tooltip: tooltip,
            icon: Icon(icon, size: size * 0.5),
            color: Theme.of(context).colorScheme.onSurface,
            onPressed: onPressed,
          ),
        ),
      );
    }
    final light = Theme.of(context).brightness == Brightness.light;
    // Pas de BackdropFilter ici : sur un petit bouton le flou est invisible,
    // et multiplier les filtres cause des artefacts GPU sur certains
    // appareils. Un fond translucide + liseré suffit à l'effet verre.
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: light ? const Color(0x8CFFFFFF) : const Color(0x33FFFFFF),
        border: Border.all(
          color: light ? const Color(0xB3FFFFFF) : const Color(0x26FFFFFF),
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1A1A1E37),
            blurRadius: 16,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: IconButton(
        tooltip: tooltip,
        icon: Icon(icon, size: size * 0.5),
        color: Theme.of(context).colorScheme.onSurface,
        onPressed: onPressed,
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
    // Rétro Winamp : le titre de section est GRAVÉ dans la tôle — bitmap,
    // capitales, très espacé (idée #85). C'est le lettrage qui date l'objet,
    // pas la couleur.
    final retro = isRetroSkin(context);
    return Padding(
      padding: padding ?? const EdgeInsets.fromLTRB(20, 16, 20, 2),
      child: Text(
        retro ? text.toUpperCase() : text,
        style: retro
            ? retroLabelStyle(size: 11, color: const Color(0xFFE6E6EF))
            : const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w700),
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
