import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Ce qui fait qu'un jeu se *joue* au lieu de se consulter (idée #77).
///
/// Les jeux partagent le langage « Liquid Glass » du reste de l'app — même
/// verre, mêmes pilules, même accent — mais un jeu demande en plus ce qu'aucun
/// écran de bibliothèque ne demande : que ça bouge au rythme du son, que la
/// bonne réponse s'entende dans la main, que la mauvaise secoue l'écran, et
/// que les boutons sur lesquels on tape vite soient gros et en bas.
///
/// Tout ce qui suit s'anime seul et s'arrête seul : rien ne tourne quand rien
/// ne joue (batterie), et aucune animation ne retient une manche — le contenu
/// est toujours là, même à mi-transition.

/// Ce qu'on fait sentir au bout des doigts.
enum GameFeel {
  /// Un choix pris en compte.
  tap,

  /// Bonne réponse.
  good,

  /// Mauvaise réponse (ou temps écoulé).
  bad,

  /// Fin de partie, record battu.
  big,
}

/// Retour haptique d'un jeu. Silencieux si l'appareil n'en a pas — jamais une
/// exception à cause d'une vibration.
void gameHaptic(GameFeel feel) {
  try {
    switch (feel) {
      case GameFeel.tap:
        HapticFeedback.selectionClick();
      case GameFeel.good:
        HapticFeedback.mediumImpact();
      case GameFeel.bad:
        HapticFeedback.heavyImpact();
      case GameFeel.big:
        HapticFeedback.vibrate();
    }
  } catch (_) {}
}

/// Les couleurs du verdict, communes à tous les jeux.
const gameGood = Color(0xFF2FA36B);
const gameBad = Color(0xFFE5484D);
const gameGold = Color(0xFFE0A32E);

/// Un élément qui s'enfonce sous le doigt et rebondit au relâchement. C'est le
/// minimum qu'un jeu doit à celui qui tape : un bouton qui ne répond pas
/// immédiatement donne l'impression d'avoir raté son geste.
class PressPop extends StatefulWidget {
  const PressPop({
    super.key,
    required this.child,
    this.onTap,
    this.scale = 0.955,
    this.feel = GameFeel.tap,
  });

  final Widget child;
  final VoidCallback? onTap;

  /// Taille au creux de l'appui.
  final double scale;

  /// Ce qu'on sent en tapant (null : rien).
  final GameFeel? feel;

  @override
  State<PressPop> createState() => _PressPopState();
}

class _PressPopState extends State<PressPop> {
  bool _down = false;

  void _set(bool down) {
    if (_down == down || !mounted) return;
    setState(() => _down = down);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: enabled ? (_) => _set(true) : null,
      onTapUp: enabled ? (_) => _set(false) : null,
      onTapCancel: enabled ? () => _set(false) : null,
      onTap: enabled
          ? () {
              if (widget.feel != null) gameHaptic(widget.feel!);
              widget.onTap!();
            }
          : null,
      child: AnimatedScale(
        scale: _down && enabled ? widget.scale : 1,
        duration: const Duration(milliseconds: 90),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}

/// Battement : l'élément respire tant que la musique joue, et se fige dès
/// qu'elle s'arrête. C'est le repère visuel que quelque chose *sonne*, même
/// téléphone en sourdine.
class BeatPulse extends StatefulWidget {
  const BeatPulse({
    super.key,
    required this.child,
    this.playing = true,
    this.period = const Duration(milliseconds: 700),
    this.depth = 0.05,
  });

  final Widget child;
  final bool playing;
  final Duration period;

  /// Amplitude du battement (0,05 = 5 % de plus au sommet).
  final double depth;

  @override
  State<BeatPulse> createState() => _BeatPulseState();
}

class _BeatPulseState extends State<BeatPulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: widget.period,
  );

  @override
  void initState() {
    super.initState();
    if (widget.playing) _c.repeat();
  }

  @override
  void didUpdateWidget(BeatPulse old) {
    super.didUpdateWidget(old);
    if (widget.playing && !_c.isAnimating) {
      _c.repeat();
    } else if (!widget.playing && _c.isAnimating) {
      _c.stop();
      _c.value = 0;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _c,
    builder: (context, child) {
      // Une frappe sèche puis une détente : le sommet arrive tôt dans la
      // mesure, comme un battement, pas comme une respiration.
      final t = _c.value;
      final beat = t < 0.25
          ? Curves.easeOut.transform(t / 0.25)
          : 1 - Curves.easeOut.transform((t - 0.25) / 0.75);
      return Transform.scale(
        scale: 1 + widget.depth * (widget.playing ? beat : 0),
        child: child,
      );
    },
    child: widget.child,
  );
}

/// Le disque mystère : un vinyle qui tourne tant que l'extrait joue, halo
/// accent qui bat avec lui. Remplace le rond d'attente des jeux à l'oreille —
/// une manche doit avoir l'air d'être en train de tourner.
class MysteryDisc extends StatefulWidget {
  const MysteryDisc({
    super.key,
    required this.playing,
    this.size = 132,
    this.icon = Icons.question_mark_rounded,
    this.color,
  });

  final bool playing;
  final double size;
  final IconData icon;
  final Color? color;

  @override
  State<MysteryDisc> createState() => _MysteryDiscState();
}

class _MysteryDiscState extends State<MysteryDisc>
    with SingleTickerProviderStateMixin {
  // 33 tours et un tiers par minute : le tour dure 1,8 s. C'est lent, c'est
  // juste, et c'est ce qui donne l'impression du vinyle.
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  );

  @override
  void initState() {
    super.initState();
    if (widget.playing) _spin.repeat();
  }

  @override
  void didUpdateWidget(MysteryDisc old) {
    super.didUpdateWidget(old);
    if (widget.playing && !_spin.isAnimating) {
      _spin.repeat();
    } else if (!widget.playing && _spin.isAnimating) {
      _spin.stop();
    }
  }

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = widget.color ?? Theme.of(context).colorScheme.primary;
    final size = widget.size;
    return BeatPulse(
      playing: widget.playing,
      depth: 0.035,
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Halo : l'ombre colorée de la signature du design, en plus large.
            Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: accent.withValues(alpha: widget.playing ? 0.5 : 0.25),
                    blurRadius: widget.playing ? 34 : 20,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
            ),
            AnimatedBuilder(
              animation: _spin,
              builder: (context, child) => Transform.rotate(
                angle: _spin.value * 2 * math.pi,
                child: child,
              ),
              child: CustomPaint(
                size: Size.square(size),
                painter: _VinylPainter(accent: accent),
              ),
            ),
            // La pastille centrale ne tourne pas : l'icône reste lisible.
            Container(
              width: size * 0.36,
              height: size * 0.36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color.lerp(accent, Colors.white, 0.32)!,
                    accent,
                  ],
                ),
              ),
              child: Icon(
                widget.icon,
                color: Colors.white,
                size: size * 0.19,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VinylPainter extends CustomPainter {
  const _VinylPainter({required this.accent});

  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    // Le galet noir, un peu plus clair d'un côté : la lumière d'un vinyle.
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: const [Color(0xFF2A2D36), Color(0xFF101218)],
        ).createShader(Rect.fromCircle(center: center, radius: radius)),
    );
    // Les sillons.
    final groove = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = Colors.white.withValues(alpha: 0.06);
    for (var r = radius * 0.42; r < radius * 0.97; r += radius * 0.055) {
      canvas.drawCircle(center, r, groove);
    }
    // Le reflet qui tourne avec le disque : sans lui, une rotation parfaitement
    // ronde ne se voit pas.
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius * 0.78),
      -math.pi / 3,
      math.pi / 2.2,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = radius * 0.2
        ..color = Colors.white.withValues(alpha: 0.06),
    );
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = accent.withValues(alpha: 0.55),
    );
  }

  @override
  bool shouldRepaint(_VinylPainter old) => old.accent != accent;
}

/// L'onde sonore : une vague de barres qui traverse l'écran tant que l'extrait
/// joue, et qui retombe à plat au silence. Sert à *voir* la lecture quand le
/// son est bas — et à occuper l'attention pendant qu'on cherche.
class SoundWave extends StatefulWidget {
  const SoundWave({
    super.key,
    required this.playing,
    this.height = 34,
    this.bars = 21,
    this.color,
  });

  final bool playing;
  final double height;
  final int bars;
  final Color? color;

  @override
  State<SoundWave> createState() => _SoundWaveState();
}

class _SoundWaveState extends State<SoundWave>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  @override
  void initState() {
    super.initState();
    if (widget.playing) _c.repeat();
  }

  @override
  void didUpdateWidget(SoundWave old) {
    super.didUpdateWidget(old);
    if (widget.playing && !_c.isAnimating) {
      _c.repeat();
    } else if (!widget.playing && _c.isAnimating) {
      _c.stop();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? Theme.of(context).colorScheme.primary;
    return SizedBox(
      height: widget.height,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) => CustomPaint(
          painter: _WavePainter(
            t: _c.value,
            bars: widget.bars,
            color: color,
            playing: widget.playing,
          ),
          size: Size.infinite,
        ),
      ),
    );
  }
}

class _WavePainter extends CustomPainter {
  const _WavePainter({
    required this.t,
    required this.bars,
    required this.color,
    required this.playing,
  });

  final double t;
  final int bars;
  final Color color;
  final bool playing;

  @override
  void paint(Canvas canvas, Size size) {
    final gap = size.width / bars;
    final width = math.min(gap * 0.5, 5.0);
    final middle = size.height / 2;
    for (var i = 0; i < bars; i++) {
      final x = gap * (i + 0.5);
      // Deux ondes de périodes différentes : le motif ne se répète pas à l'œil,
      // là où une seule sinusoïde donnerait une vague de dessin animé.
      final phase = i / bars;
      final a = math.sin((t + phase) * 2 * math.pi);
      final b = math.sin((t * 1.7 + phase * 2.3) * 2 * math.pi);
      final wave = playing ? (0.55 * a + 0.45 * b).abs() : 0.0;
      // Le milieu de la vague monte plus haut que les bords : la vague a un
      // corps, elle ne fait pas un mur.
      final envelope = 0.45 + 0.55 * math.sin(phase * math.pi);
      final h = math.max(width, size.height * (0.12 + 0.88 * wave) * envelope);
      final rect = RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(x, middle), width: width, height: h),
        Radius.circular(width),
      );
      canvas.drawRRect(
        rect,
        Paint()..color = color.withValues(alpha: 0.35 + 0.55 * wave),
      );
    }
  }

  @override
  bool shouldRepaint(_WavePainter old) =>
      old.t != t || old.playing != playing || old.color != color;
}

/// Le chrono en anneau, autour de ce qu'on regarde. Il se vide, il rougit, et
/// il bat de plus en plus vite sur la fin : le temps qui presse doit se voir
/// sans lire un nombre.
class CountdownRing extends StatelessWidget {
  const CountdownRing({
    super.key,
    required this.ratio,
    required this.child,
    this.size = 172,
    this.thickness = 7,
  });

  /// Ce qu'il reste, de 1 (tout) à 0 (fini).
  final double ratio;
  final Widget child;
  final double size;
  final double thickness;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final left = ratio.clamp(0.0, 1.0);
    final urgent = left < 0.25;
    final color = urgent ? gameBad : scheme.primary;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          BeatPulse(
            playing: urgent,
            period: const Duration(milliseconds: 480),
            depth: 0.05,
            child: CustomPaint(
              size: Size.square(size),
              painter: _RingPainter(
                ratio: left,
                color: color,
                track: scheme.onSurface.withValues(alpha: 0.09),
                thickness: thickness,
              ),
            ),
          ),
          child,
        ],
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter({
    required this.ratio,
    required this.color,
    required this.track,
    required this.thickness,
  });

  final double ratio;
  final Color color;
  final Color track;
  final double thickness;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - thickness) / 2;
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = thickness
        ..color = track,
    );
    if (ratio <= 0) return;
    final rect = Rect.fromCircle(center: center, radius: radius);
    // Lueur d'abord, trait ensuite : l'anneau doit avoir l'air allumé.
    canvas.drawArc(
      rect,
      -math.pi / 2,
      2 * math.pi * ratio,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = thickness * 1.9
        ..color = color.withValues(alpha: 0.22)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7),
    );
    canvas.drawArc(
      rect,
      -math.pi / 2,
      2 * math.pi * ratio,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = thickness
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.ratio != ratio || old.color != color || old.thickness != thickness;
}

/// Secousse : l'écran encaisse le coup quand la réponse est mauvaise. Se
/// déclenche au changement de [trigger] — un compteur de manches suffit.
class ShakeBox extends StatefulWidget {
  const ShakeBox({
    super.key,
    required this.trigger,
    required this.child,
    this.amplitude = 9,
  });

  final int trigger;
  final Widget child;
  final double amplitude;

  @override
  State<ShakeBox> createState() => _ShakeBoxState();
}

class _ShakeBoxState extends State<ShakeBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );

  @override
  void didUpdateWidget(ShakeBox old) {
    super.didUpdateWidget(old);
    if (widget.trigger != old.trigger && widget.trigger > 0) {
      _c.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _c,
    builder: (context, child) {
      if (!_c.isAnimating) return child!;
      // Trois allers-retours qui s'amortissent.
      final decay = 1 - _c.value;
      final dx = math.sin(_c.value * math.pi * 6) * widget.amplitude * decay;
      return Transform.translate(offset: Offset(dx, 0), child: child);
    },
    child: widget.child,
  );
}

/// Étincelles : la petite fête d'une bonne réponse ou d'un record. Se
/// déclenche au changement de [trigger], se peint par-dessus l'écran sans rien
/// intercepter, et s'éteint toute seule.
class Celebration extends StatefulWidget {
  const Celebration({
    super.key,
    required this.trigger,
    required this.child,
    this.count = 26,
    this.colors,
  });

  final int trigger;
  final Widget child;
  final int count;
  final List<Color>? colors;

  @override
  State<Celebration> createState() => _CelebrationState();
}

class _CelebrationState extends State<Celebration>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1300),
  );

  // Semé une fois pour toutes : les étincelles ne doivent pas se redistribuer
  // à chaque image.
  late final List<_Spark> _sparks = [
    for (var i = 0; i < widget.count; i++) _Spark.seeded(i, widget.count),
  ];

  @override
  void initState() {
    super.initState();
    // Un panneau de fin de partie arrive déjà fêté : sa fête part à
    // l'apparition, pas au changement suivant.
    if (widget.trigger > 0) _c.forward(from: 0);
  }

  @override
  void didUpdateWidget(Celebration old) {
    super.didUpdateWidget(old);
    if (widget.trigger != old.trigger && widget.trigger > 0) {
      _c.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors =
        widget.colors ??
        [Theme.of(context).colorScheme.primary, gameGood, gameGold];
    return Stack(
      children: [
        widget.child,
        Positioned.fill(
          child: IgnorePointer(
            child: AnimatedBuilder(
              animation: _c,
              builder: (context, _) => _c.value == 0 || _c.isCompleted
                  ? const SizedBox.shrink()
                  : CustomPaint(
                      painter: _SparkPainter(
                        t: _c.value,
                        sparks: _sparks,
                        colors: colors,
                      ),
                    ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Spark {
  const _Spark({
    required this.angle,
    required this.speed,
    required this.size,
    required this.spin,
    required this.tint,
  });

  /// Semées à la main plutôt qu'au hasard : une manche rejouée doit refaire la
  /// même petite fête, et un test qui repasse doit repeindre la même image.
  factory _Spark.seeded(int i, int total) {
    final r = math.Random(i * 7919);
    final spread = -math.pi / 2 + (i / total - 0.5) * 2.2;
    return _Spark(
      angle: spread + (r.nextDouble() - 0.5) * 0.35,
      speed: 0.55 + r.nextDouble() * 0.65,
      size: 3.5 + r.nextDouble() * 4.5,
      spin: (r.nextDouble() - 0.5) * 8,
      tint: i % 3,
    );
  }

  final double angle;
  final double speed;
  final double size;
  final double spin;
  final int tint;
}

class _SparkPainter extends CustomPainter {
  const _SparkPainter({
    required this.t,
    required this.sparks,
    required this.colors,
  });

  final double t;
  final List<_Spark> sparks;
  final List<Color> colors;

  @override
  void paint(Canvas canvas, Size size) {
    final origin = Offset(size.width / 2, size.height * 0.42);
    final reach = size.height * 0.75;
    for (final s in sparks) {
      // Jetées vers le haut, rattrapées par leur poids.
      final d = s.speed * reach * t;
      final x = origin.dx + math.cos(s.angle) * d;
      final y = origin.dy + math.sin(s.angle) * d + reach * 0.9 * t * t;
      final fade = (1 - t * t).clamp(0.0, 1.0);
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(s.spin * t);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset.zero, width: s.size, height: s.size * 1.7),
          Radius.circular(s.size * 0.4),
        ),
        Paint()
          ..color = colors[s.tint % colors.length].withValues(alpha: fade),
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_SparkPainter old) => old.t != t;
}

/// La carte qui se retourne pour se montrer. Une réponse qui *s'ouvre* se
/// retient mieux qu'une réponse qui apparaît — et c'est le geste de tous les
/// jeux de cartes.
class FlipReveal extends StatefulWidget {
  const FlipReveal({super.key, required this.child, this.size});

  final Widget child;

  /// Côté de la carte, quand elle est carrée (sert à réserver la place).
  final double? size;

  @override
  State<FlipReveal> createState() => _FlipRevealState();
}

class _FlipRevealState extends State<FlipReveal>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 460),
  )..forward();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _c,
    builder: (context, child) {
      final t = Curves.easeOutCubic.transform(_c.value);
      return Transform(
        alignment: Alignment.center,
        // Un soupçon de perspective : sans elle, la carte a l'air de
        // rétrécir, pas de tourner.
        transform: Matrix4.identity()
          ..setEntry(3, 2, 0.0015)
          ..rotateY((1 - t) * math.pi / 2),
        child: child,
      );
    },
    child: SizedBox(
      width: widget.size,
      height: widget.size,
      child: widget.child,
    ),
  );
}

/// Le verdict d'une manche : une pilule qui débarque en sautant, verte ou
/// rouge. Remplace la ligne icône + texte que chaque jeu réécrivait.
class GameVerdict extends StatelessWidget {
  const GameVerdict({super.key, required this.correct, required this.text});

  final bool correct;
  final String text;

  @override
  Widget build(BuildContext context) {
    final color = correct ? gameGood : gameBad;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 420),
      curve: Curves.elasticOut,
      builder: (context, t, child) =>
          Transform.scale(scale: 0.6 + 0.4 * t, child: child),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          color: color.withValues(alpha: 0.16),
          border: Border.all(color: color.withValues(alpha: 0.55)),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.28),
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              correct ? Icons.check_circle_rounded : Icons.cancel_rounded,
              size: 22,
              color: color,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                text,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.2,
                  color: color,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Un nombre qui saute quand il change : le score qui monte doit se voir du
/// coin de l'œil, sans quitter la manche des yeux.
class PoppingNumber extends StatefulWidget {
  const PoppingNumber({
    super.key,
    required this.text,
    this.style,
    this.color,
  });

  final String text;
  final TextStyle? style;

  /// Couleur du flash au changement (l'accent par défaut).
  final Color? color;

  @override
  State<PoppingNumber> createState() => _PoppingNumberState();
}

class _PoppingNumberState extends State<PoppingNumber>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
  );

  @override
  void didUpdateWidget(PoppingNumber old) {
    super.didUpdateWidget(old);
    if (widget.text != old.text) _c.forward(from: 0);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = widget.color ?? Theme.of(context).colorScheme.primary;
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final pop = _c.isAnimating ? math.sin(_c.value * math.pi) : 0.0;
        return Transform.scale(
          scale: 1 + 0.22 * pop,
          child: Text(
            widget.text,
            style: (widget.style ?? const TextStyle()).copyWith(
              color: Color.lerp(
                widget.style?.color ?? DefaultTextStyle.of(context).style.color,
                accent,
                pop,
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Largeur d'une zone de dépôt. Les frises la comptent pour se déplacer d'une
/// carte à l'autre.
const double kDropZoneWidth = 56;

/// Zone de dépôt : large, lumineuse, et elle appelle le doigt tant qu'elle
/// attend une carte. Une frise chronologique se joue à la volée — un trou de
/// trente pixels se rate une fois sur deux.
class GlowDropZone extends StatefulWidget {
  const GlowDropZone({
    super.key,
    required this.enabled,
    required this.onTap,
    this.width = kDropZoneWidth,
    this.height = 104,
  });

  final bool enabled;
  final VoidCallback onTap;
  final double width;
  final double height;

  @override
  State<GlowDropZone> createState() => _GlowDropZoneState();
}

class _GlowDropZoneState extends State<GlowDropZone>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  );

  @override
  void initState() {
    super.initState();
    if (widget.enabled) _c.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(GlowDropZone old) {
    super.didUpdateWidget(old);
    if (widget.enabled && !_c.isAnimating) {
      _c.repeat(reverse: true);
    } else if (!widget.enabled && _c.isAnimating) {
      _c.stop();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return SizedBox(
      width: widget.width,
      child: Center(
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 200),
          opacity: widget.enabled ? 1 : 0.22,
          child: PressPop(
            onTap: widget.enabled ? widget.onTap : null,
            scale: 0.9,
            child: AnimatedBuilder(
              animation: _c,
              builder: (context, child) {
                final glow = widget.enabled ? _c.value : 0.0;
                return Container(
                  width: widget.width - 8,
                  height: widget.height,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    color: accent.withValues(alpha: 0.10 + 0.10 * glow),
                    border: Border.all(
                      color: accent.withValues(alpha: 0.45 + 0.45 * glow),
                      width: 1.6,
                    ),
                    boxShadow: widget.enabled
                        ? [
                            BoxShadow(
                              color: accent.withValues(alpha: 0.18 + 0.2 * glow),
                              blurRadius: 12 + 10 * glow,
                            ),
                          ]
                        : null,
                  ),
                  child: child,
                );
              },
              child: Icon(Icons.add_rounded, size: 24, color: accent),
            ),
          ),
        ),
      ),
    );
  }
}

/// Le bandeau d'action, posé dans la zone du pouce : tout ce sur quoi on tape
/// vite (valider, réécouter, passer) vit dans le tiers bas de l'écran, jamais
/// en haut.
class ThumbZone extends StatelessWidget {
  const ThumbZone({super.key, required this.child, this.padding});

  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) => Padding(
    padding: padding ?? const EdgeInsets.fromLTRB(16, 6, 16, 14),
    child: child,
  );
}
