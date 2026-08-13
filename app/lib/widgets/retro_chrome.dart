import 'package:flutter/material.dart';

/// Le MEUBLE du rétro Winamp (idée #82) : biseaux à deux traits, tôle brossée,
/// barre de titre, boutons et glissières carrés. L'afficheur vert, lui, vit
/// dans retro_lcd.dart.
///
/// Retour de Maxime (idée #83) : « ça met juste des carrés et du texte vert,
/// ça ne ressemble pas vraiment ». Ce qui manquait n'était pas la couleur mais
/// le RELIEF. Un biseau de 1999 se pose à DEUX traits — clair puis très clair
/// en haut à gauche, sombre puis très sombre en bas à droite ; à un seul
/// trait on ne dessine qu'un cadre, et un cadre, ce n'est qu'un carré. Le gris
/// n'est jamais un aplat non plus : la tôle a son grain de rayures.
///
/// Ce fichier ne connaît pas le thème : il ne peint que du châssis, avec ses
/// propres teintes. C'est theme.dart qui vient y chercher sa palette (sens
/// unique : rien ici n'importe theme.dart).

/// Le gris du châssis et les quatre teintes de ses arêtes.
const winampChassis = Color(0xFF3F4249);
const winampBevelLight = Color(0xFF8E939E);
const winampBevelHighlight = Color(0xFFC3C8D2);
const winampBevelDark = Color(0xFF121419);
const winampBevelShade = Color(0xFF2B2E34);

/// L'encre claire des glyphes et des étiquettes gravées dans le châssis.
const winampInk = Color(0xFFD7DBE3);

/// Le bleu nuit de la barre de titre.
const winampTitleTop = Color(0xFF4A568E);
const winampTitleBottom = Color(0xFF1B2039);

/// Une plaque biseautée : en relief par défaut, en creux pour tout ce qui
/// s'enfonce (afficheur, glissière, bouton pressé).
class RetroBevel extends StatelessWidget {
  const RetroBevel({
    super.key,
    required this.child,
    this.fill,
    this.gradient,
    this.sunken = false,
    this.padding = EdgeInsets.zero,
  });

  final Widget child;
  final Color? fill;
  final Gradient? gradient;
  final bool sunken;
  final EdgeInsetsGeometry padding;

  static Border _edge(Color topLeft, Color bottomRight) => Border(
    top: BorderSide(color: topLeft),
    left: BorderSide(color: topLeft),
    right: BorderSide(color: bottomRight),
    bottom: BorderSide(color: bottomRight),
  );

  @override
  Widget build(BuildContext context) {
    // Angles vifs, jamais de rayon : un biseau a deux couleurs, et Flutter
    // refuse d'arrondir une bordure qui n'est pas d'une seule teinte.
    return DecoratedBox(
      decoration: BoxDecoration(
        color: gradient == null ? fill : null,
        gradient: gradient,
        border: _edge(
          sunken ? winampBevelDark : winampBevelLight,
          sunken ? winampBevelLight : winampBevelDark,
        ),
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: _edge(
            sunken ? winampBevelShade : winampBevelHighlight,
            sunken ? winampBevelHighlight : winampBevelShade,
          ),
        ),
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

/// Le même biseau, mais peint à la main (curseurs de glissière, analyseur).
void paintRetroBevel(
  Canvas canvas,
  Rect rect, {
  Color? fill,
  bool sunken = false,
}) {
  if (fill != null) canvas.drawRect(rect, Paint()..color = fill);
  _paintEdge(
    canvas,
    rect,
    sunken ? winampBevelDark : winampBevelLight,
    sunken ? winampBevelLight : winampBevelDark,
  );
  _paintEdge(
    canvas,
    rect.deflate(1),
    sunken ? winampBevelShade : winampBevelHighlight,
    sunken ? winampBevelHighlight : winampBevelShade,
  );
}

void _paintEdge(Canvas canvas, Rect r, Color topLeft, Color bottomRight) {
  final light = Paint()
    ..color = topLeft
    ..strokeWidth = 1;
  final dark = Paint()
    ..color = bottomRight
    ..strokeWidth = 1;
  canvas
    ..drawLine(
      Offset(r.left, r.top + 0.5),
      Offset(r.right, r.top + 0.5),
      light,
    )
    ..drawLine(
      Offset(r.left + 0.5, r.top),
      Offset(r.left + 0.5, r.bottom),
      light,
    )
    ..drawLine(
      Offset(r.left, r.bottom - 0.5),
      Offset(r.right, r.bottom - 0.5),
      dark,
    )
    ..drawLine(
      Offset(r.right - 0.5, r.top),
      Offset(r.right - 0.5, r.bottom),
      dark,
    );
}

/// La tôle brossée du châssis : de fines rayures horizontales sous tout
/// l'écran. C'est ce grain, plus que le gris, qui fait la façade de 1999 — un
/// aplat de gris n'est qu'un aplat de gris (idée #83).
class RetroChassis extends StatelessWidget {
  const RetroChassis({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: const _BrushedMetal(),
    willChange: false,
    child: child,
  );
}

class _BrushedMetal extends CustomPainter {
  const _BrushedMetal();

  @override
  void paint(Canvas canvas, Size size) {
    final groove = Paint()
      ..color = const Color(0x18000000)
      ..strokeWidth = 1;
    final crest = Paint()
      ..color = const Color(0x0DFFFFFF)
      ..strokeWidth = 1;
    // Un creux, une crête, puis deux lignes de repos : plus serré, le grain
    // moire à l'écran ; plus lâche, on ne le voit plus.
    for (var y = 0.5; y < size.height; y += 4) {
      canvas
        ..drawLine(Offset(0, y), Offset(size.width, y), groove)
        ..drawLine(Offset(0, y + 1), Offset(size.width, y + 1), crest);
    }
  }

  @override
  bool shouldRepaint(_BrushedMetal oldDelegate) => false;
}

/// La barre de titre : dégradé bleu nuit, hachures de part et d'autre du nom,
/// et la petite croix carrée à droite. C'est l'élément qu'on reconnaît en
/// premier — plus encore que le vert.
class RetroTitleBar extends StatelessWidget implements PreferredSizeWidget {
  const RetroTitleBar({
    super.key,
    required this.title,
    this.onTitleTap,
    this.onClose,
  });

  final String title;

  /// Le nom gravé reste cliquable quand il mène quelque part (l'album du
  /// titre en cours, idée #64) : l'habillage ne retire pas de chemin.
  final VoidCallback? onTitleTap;
  final VoidCallback? onClose;

  @override
  Size get preferredSize => const Size.fromHeight(30);

  @override
  Widget build(BuildContext context) => SafeArea(
    bottom: false,
    child: SizedBox(
      height: 30,
      child: RetroBevel(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [winampTitleTop, winampTitleBottom],
        ),
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(
          children: [
            const Expanded(child: _TitleHatching()),
            Flexible(
              flex: 6,
              child: GestureDetector(
                onTap: onTitleTap,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    title.toUpperCase(),
                    maxLines: 1,
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontFamilyFallback: ['Roboto Mono', 'Courier'],
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 2,
                      color: winampInk,
                    ),
                  ),
                ),
              ),
            ),
            const Expanded(child: _TitleHatching()),
            if (onClose != null)
              Padding(
                padding: const EdgeInsets.only(left: 6),
                child: RetroButton(
                  width: 18,
                  height: 16,
                  tooltip: 'Fermer',
                  onPressed: onClose,
                  child: const RetroGlyph(RetroGlyphKind.close, size: 7),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

/// Les hachures qui remplissent la barre de titre autour du nom.
class _TitleHatching extends StatelessWidget {
  const _TitleHatching();

  @override
  Widget build(BuildContext context) =>
      const CustomPaint(painter: _Hatching(), size: Size.infinite);
}

class _Hatching extends CustomPainter {
  const _Hatching();

  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      ..color = const Color(0x59FFFFFF)
      ..strokeWidth = 1;
    // Quatre traits centrés, un pixel de vide entre chacun.
    final top = (size.height - 7) / 2;
    for (var i = 0; i < 4; i++) {
      final y = top + i * 2 + 0.5;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), line);
    }
  }

  @override
  bool shouldRepaint(_Hatching oldDelegate) => false;
}

/// Un bouton du châssis : plaque en relief qui s'enfonce sous le doigt. Les
/// bascules (aléatoire, répétition) restent enfoncées tant qu'elles sont
/// actives — c'est comme ça qu'on lisait l'état d'un lecteur avant les
/// couleurs d'accent.
class RetroButton extends StatefulWidget {
  const RetroButton({
    super.key,
    required this.child,
    this.onPressed,
    this.width = 40,
    this.height = 32,
    this.active = false,
    this.tooltip,
  });

  final Widget child;
  final VoidCallback? onPressed;
  final double width;
  final double height;
  final bool active;
  final String? tooltip;

  @override
  State<RetroButton> createState() => _RetroButtonState();
}

class _RetroButtonState extends State<RetroButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    Widget button = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: enabled ? (_) => setState(() => _down = true) : null,
      onTapUp: enabled ? (_) => setState(() => _down = false) : null,
      onTapCancel: enabled ? () => setState(() => _down = false) : null,
      onTap: widget.onPressed,
      child: SizedBox(
        width: widget.width,
        height: widget.height,
        child: Opacity(
          opacity: enabled ? 1 : 0.4,
          child: RetroBevel(
            fill: _down || widget.active
                ? const Color(0xFF34373D)
                : winampChassis,
            sunken: _down || widget.active,
            child: Center(child: widget.child),
          ),
        ),
      ),
    );
    final tooltip = widget.tooltip;
    if (tooltip != null) button = Tooltip(message: tooltip, child: button);
    return button;
  }
}

/// Les glyphes gravés sur les boutons de transport. Dessinés au trait plutôt
/// qu'empruntés à Material : les icônes arrondies d'aujourd'hui trahissent
/// tout de suite le châssis.
enum RetroGlyphKind { previous, play, pause, stop, next, close }

class RetroGlyph extends StatelessWidget {
  const RetroGlyph(this.kind, {super.key, this.size = 12, this.color});

  final RetroGlyphKind kind;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: Size(size * 1.3, size),
    painter: _GlyphPainter(kind, color ?? winampInk),
  );
}

class _GlyphPainter extends CustomPainter {
  const _GlyphPainter(this.kind, this.color);

  final RetroGlyphKind kind;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final h = size.height;
    final w = size.width;

    Path triangle(double left, double width, {bool pointsRight = true}) {
      final path = Path();
      if (pointsRight) {
        path
          ..moveTo(left, 0)
          ..lineTo(left + width, h / 2)
          ..lineTo(left, h);
      } else {
        path
          ..moveTo(left + width, 0)
          ..lineTo(left, h / 2)
          ..lineTo(left + width, h);
      }
      return path..close();
    }

    switch (kind) {
      case RetroGlyphKind.play:
        canvas.drawPath(triangle((w - h * 0.85) / 2, h * 0.85), paint);
      case RetroGlyphKind.pause:
        final bar = w * 0.24;
        canvas
          ..drawRect(Rect.fromLTWH(w * 0.2, 0, bar, h), paint)
          ..drawRect(Rect.fromLTWH(w * 0.56, 0, bar, h), paint);
      case RetroGlyphKind.stop:
        canvas.drawRect(Rect.fromLTWH((w - h) / 2, 0, h, h), paint);
      case RetroGlyphKind.previous:
        final wing = w * 0.36;
        canvas
          ..drawRect(Rect.fromLTWH(0, 0, w * 0.14, h), paint)
          ..drawPath(triangle(w * 0.18, wing, pointsRight: false), paint)
          ..drawPath(triangle(w * 0.58, wing, pointsRight: false), paint);
      case RetroGlyphKind.next:
        final wing = w * 0.36;
        canvas
          ..drawPath(triangle(w * 0.06, wing), paint)
          ..drawPath(triangle(w * 0.46, wing), paint)
          ..drawRect(Rect.fromLTWH(w * 0.86, 0, w * 0.14, h), paint);
      case RetroGlyphKind.close:
        final stroke = Paint()
          ..color = color
          ..strokeWidth = 1.6;
        canvas
          ..drawLine(Offset(w * 0.2, 0), Offset(w * 0.8, h), stroke)
          ..drawLine(Offset(w * 0.8, 0), Offset(w * 0.2, h), stroke);
    }
  }

  @override
  bool shouldRepaint(_GlyphPainter oldDelegate) =>
      oldDelegate.kind != kind || oldDelegate.color != color;
}

/// La glissière de position du lecteur : une rainure creuse et un bloc
/// biseauté qui coulisse dedans. Le geste (taper, glisser) reste à l'écran
/// qui l'affiche — ici, on ne fait que peindre.
class RetroSeekBar extends StatelessWidget {
  const RetroSeekBar({super.key, required this.progress, this.height = 22});

  final double progress;
  final double height;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: height,
    width: double.infinity,
    child: CustomPaint(painter: _SeekPainter(progress.clamp(0.0, 1.0))),
  );
}

class _SeekPainter extends CustomPainter {
  const _SeekPainter(this.progress);

  final double progress;

  static const _thumbWidth = 13.0;

  @override
  void paint(Canvas canvas, Size size) {
    // La rainure : creuse, à peine plus haute que le trait.
    final groove = Rect.fromLTWH(0, (size.height - 9) / 2, size.width, 9);
    paintRetroBevel(canvas, groove, fill: winampBevelDark, sunken: true);
    final left = (size.width - _thumbWidth) * progress;
    paintRetroBevel(
      canvas,
      Rect.fromLTWH(left, 0, _thumbWidth, size.height),
      fill: winampChassis,
    );
  }

  @override
  bool shouldRepaint(_SeekPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

/// Le curseur des glissières de 1999 : un petit bloc biseauté qui coulisse
/// dans une rainure, pas une bille qui flotte.
class RetroSliderThumb extends SliderComponentShape {
  const RetroSliderThumb();

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) => const Size(13, 22);

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    paintRetroBevel(
      context.canvas,
      Rect.fromCenter(center: center, width: 13, height: 22),
      fill: winampChassis,
    );
  }
}

/// Les glissières du châssis : rainure creuse à angles vifs, bloc biseauté.
const retroSliderTheme = SliderThemeData(
  trackHeight: 8,
  trackShape: RectangularSliderTrackShape(),
  thumbShape: RetroSliderThumb(),
  overlayShape: RoundSliderOverlayShape(overlayRadius: 16),
  inactiveTrackColor: winampBevelDark,
);
