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
/// Idée #85 : Maxime a dessiné le skin plutôt que de le décrire — « chrome &
/// LCD ». Les teintes ci-dessous sont SES jetons, repris tels quels ; le
/// chrome n'est plus un aplat mais un dégradé, et le lettrage devient bitmap
/// (Silkscreen gravé dans le châssis, VT323 derrière les vitres).
///
/// Ce fichier ne connaît pas le thème : il ne peint que du châssis, avec ses
/// propres teintes. C'est theme.dart qui vient y chercher sa palette (sens
/// unique : rien ici n'importe theme.dart).

/// Le chrome du châssis : un dégradé haut-clair / bas-sombre, jamais un
/// aplat — c'est lui qui donne la tôle emboutie (jetons de l'idée #85).
const winampChromeTop = Color(0xFF4B4B5A);
const winampChromeBottom = Color(0xFF2C2C36);

/// La teinte moyenne du chrome, pour tout ce qui ne peut pas porter de
/// dégradé (curseurs peints, plaques minuscules).
const winampChassis = Color(0xFF3C3C48);

/// Les quatre teintes des arêtes : le trait de lumière et le trait d'ombre,
/// puis leurs seconds traits (c'est la paire qui fait le relief, idée #83).
const winampBevelLight = Color(0xFF757589);
const winampBevelHighlight = Color(0xFFA0A0B6);
const winampBevelDark = Color(0xFF14141A);
const winampBevelShade = Color(0xFF26262F);

/// L'encre claire des glyphes et des étiquettes gravées dans le châssis.
const winampInk = Color(0xFFC9C9D8);

/// L'ambre des accents secondaires : ce que le vert ne doit pas dire.
const winampAmber = Color(0xFFFFD23F);

/// Les plaques plates (rangées de liste, cases d'action) : plus sombres que
/// le chrome, sans relief — elles reçoivent, elles ne dépassent pas.
const winampPanel = Color(0xFF22222A);
const winampPanelAlt = Color(0xFF1C1C23);

/// Le phosphore de l'afficheur, son vert éteint, et le noir verdâtre sur
/// lequel ils vivent (jetons de l'idée #85). Le vert franc de l'idée #83 a
/// perdu deux crans de saturation : sur une vitre, un vert pur bave.
const winampGreen = Color(0xFF22E04A);
const winampGreenDim = Color(0xFF157A2B);
const winampLcd = Color(0xFF05170A);

/// Le dégradé du chrome, celui des boutons et des barres.
const winampChrome = LinearGradient(
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
  colors: [winampChromeTop, winampChromeBottom],
);

/// Le même, enfoncé : la lumière ne vient plus du haut.
const winampChromePressed = LinearGradient(
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
  colors: [Color(0xFF272730), Color(0xFF35353F)],
);

/// Le lettrage GRAVÉ du châssis : bitmap, minuscule, très espacé. Tout ce
/// qui est peint sur la tôle (libellés de boutons, titres de section, nom de
/// l'écran) le porte ; ce qui vit derrière une vitre prend le VT323 de
/// retro_lcd.dart.
TextStyle retroLabelStyle({
  double size = 9,
  Color color = winampInk,
  FontWeight weight = FontWeight.w400,
  double letterSpacing = 1.2,
}) => TextStyle(
  fontFamily: 'Silkscreen',
  fontFamilyFallback: const ['monospace'],
  fontSize: size,
  fontWeight: weight,
  letterSpacing: letterSpacing,
  color: color,
  height: 1.3,
);

/// Le lettrage de l'AFFICHEUR : VT323, la chasse fixe des terminaux à tube
/// (idée #85). Le `monospace` générique d'Android avait la bonne chasse mais
/// pas le bon dessin — ses lettres sont celles de 2024, arrondies et
/// antialiassées ; VT323 a les angles carrés d'un caractère tramé.
TextStyle lcdTextStyle({
  double size = 16,
  FontWeight weight = FontWeight.w400,
  Color color = winampGreen,
}) => TextStyle(
  fontFamily: 'VT323',
  fontFamilyFallback: const ['monospace', 'Roboto Mono'],
  fontSize: size,
  fontWeight: weight,
  letterSpacing: 0.6,
  color: color,
  height: 1.15,
);

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

/// La barre de titre du châssis (idée #85) : une réglette de chrome, la
/// sortie gravée à gauche, les hachures au milieu, le nom de l'écran en
/// phosphore à droite et le petit tenon carré au bout. C'est l'élément qu'on
/// reconnaît en premier — plus encore que le vert.
class RetroTitleBar extends StatelessWidget implements PreferredSizeWidget {
  const RetroTitleBar({
    super.key,
    required this.title,
    this.onTitleTap,
    this.onClose,
    this.leadingLabel,
  });

  final String title;

  /// Le nom gravé reste cliquable quand il mène quelque part (l'album du
  /// titre en cours, idée #64) : l'habillage ne retire pas de chemin.
  final VoidCallback? onTitleTap;
  final VoidCallback? onClose;

  /// Ce que dit la sortie, à gauche : « RETOUR » par défaut.
  final String? leadingLabel;

  @override
  Size get preferredSize => const Size.fromHeight(30);

  @override
  Widget build(BuildContext context) => SafeArea(
    bottom: false,
    child: SizedBox(
      height: 30,
      child: RetroBevel(
        gradient: winampChrome,
        padding: const EdgeInsets.symmetric(horizontal: 5),
        child: Row(
          children: [
            if (onClose != null) ...[
              GestureDetector(
                onTap: onClose,
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.only(right: 8),
                  // Silkscreen n'a que du latin : les jolies flèches du
                  // design y feraient des tofus. Un chevron ASCII, c'est
                  // d'époque de toute façon.
                  child: Text(
                    '< ${leadingLabel ?? 'RETOUR'}',
                    style: retroLabelStyle(size: 8, letterSpacing: 1.5),
                  ),
                ),
              ),
            ],
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
                    textAlign: TextAlign.right,
                    overflow: TextOverflow.ellipsis,
                    style: retroLabelStyle(
                      size: 9,
                      color: winampGreen,
                      letterSpacing: 1.4,
                    ),
                  ),
                ),
              ),
            ),
            const RetroStud(),
          ],
        ),
      ),
    ),
  );
}

/// La réglette qui coiffe chaque onglet (idée #85) : le nom de l'app gravé à
/// gauche, les hachures au milieu, le nom de l'écran en phosphore à droite.
/// Elle ne fait rien — c'est un bandeau de façade, comme sur le meuble d'une
/// chaîne hi-fi, et c'est ce qui donne à chaque écran l'air d'un module du
/// même appareil plutôt que d'une page.
class RetroScreenBar extends StatelessWidget {
  const RetroScreenBar({super.key, required this.screen});

  final String screen;

  static const height = 26.0;

  @override
  Widget build(BuildContext context) => SafeArea(
    bottom: false,
    child: SizedBox(
      height: height,
      child: RetroBevel(
        gradient: winampChrome,
        padding: const EdgeInsets.symmetric(horizontal: 5),
        child: Row(
          children: [
            Text('GULLIFY', style: retroLabelStyle(size: 8)),
            const SizedBox(width: 8),
            const Expanded(child: _TitleHatching()),
            const SizedBox(width: 8),
            Flexible(
              flex: 5,
              child: Text(
                screen.toUpperCase(),
                maxLines: 1,
                textAlign: TextAlign.right,
                overflow: TextOverflow.ellipsis,
                style: retroLabelStyle(size: 8, color: winampGreen),
              ),
            ),
            const RetroStud(),
          ],
        ),
      ),
    ),
  );
}

/// Le tenon du coin : un carré de chrome de 12 px, purement décoratif. Il ne
/// fait rien — c'est exactement pour ça qu'il date l'objet.
class RetroStud extends StatelessWidget {
  const RetroStud({super.key, this.size = 12});

  final double size;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: 6),
    child: SizedBox(
      width: size,
      height: size,
      child: const RetroBevel(gradient: winampChrome, child: SizedBox.expand()),
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
            // Le chrome se retourne quand la plaque s'enfonce : la lumière
            // passe en bas, le dégradé avec elle (idée #85).
            gradient: _down || widget.active
                ? winampChromePressed
                : winampChrome,
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

/// Une vitre : le creux noir verdâtre sur lequel le phosphore s'écrit. Champ
/// de recherche, bandeau de file, ligne de titre du mini-lecteur — tout ce
/// qui « affiche » passe derrière (idée #85).
class RetroLcdPanel extends StatelessWidget {
  const RetroLcdPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => RetroBevel(
    sunken: true,
    fill: winampLcd,
    padding: padding,
    child: child,
  );
}

/// Une plaque PLATE : pas de biseau, juste un fond sombre et un liseré. Les
/// cases secondaires du design (idée #85) sont peintes comme ça — le relief
/// est réservé à ce qui se presse vraiment.
class RetroPlate extends StatelessWidget {
  const RetroPlate({
    super.key,
    required this.child,
    this.fill = winampPanel,
    this.padding = EdgeInsets.zero,
  });

  final Widget child;
  final Color fill;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: fill,
      border: Border.all(color: winampBevelShade),
    ),
    child: Padding(padding: padding, child: child),
  );
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
