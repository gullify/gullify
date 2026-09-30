import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Les graphiques de l'écran « Statistiques » (idée #120).
///
/// Ils étaient bâtis en `Container` empilés : une piste grise, une barre en
/// dégradé, et des étiquettes dans un `Row` d'`Expanded` qui débordaient dès
/// qu'un libellé était long. Ils se peignent maintenant au tracé, et suivent
/// les règles d'un graphique lisible :
///
///  * UNE série → UNE teinte (l'accent de l'app), pas d'arc-en-ciel et pas de
///    légende : le titre de la carte dit déjà ce qui est tracé.
///  * marques fines : barres de 24 px au plus, à tête arrondie de 4 et pied
///    carré sur la ligne de base ; courbe de 2 px ; lavis d'aire à ~10 %.
///  * grille en retrait : des filets d'un cheveu, pleins (jamais pointillés),
///    et des graduations qui tombent sur des chiffres ronds.
///  * étiquettes CHOISIES — l'extrême et le point touché, jamais un nombre
///    sur chaque barre —, toujours à l'encre de l'app et non à la couleur de
///    la série.
///  * de quoi lire n'importe quelle valeur au doigt : on touche (ou on glisse
///    le long) du graphique, la valeur s'écrit dans l'en-tête de la carte.

/// Gouttière de gauche : la place des graduations de l'axe des ordonnées.
const double kStatsGutter = 30;

/// Hauteur du tracé, puis de la bande des étiquettes du bas. Les deux sont
/// dans la même toile : un cadre trop court rognait l'axe.
const double kStatsPlotHeight = 124;
const double kStatsAxisBand = 18;

/// Arrondit le haut de l'axe au chiffre rond au-dessus (1, 2, 5 × 10ⁿ) : une
/// graduation se lit « 50 », pas « 37 ».
int niceCeil(int value) {
  if (value <= 5) return math.max(1, value);
  final decade = math.pow(10, (math.log(value) / math.ln10).floor()).toDouble();
  for (final step in const [1.0, 2.0, 5.0, 10.0]) {
    final candidate = step * decade;
    if (candidate >= value) return candidate.round();
  }
  return (10 * decade).round();
}

/// La couleur de la série : l'accent de l'app, ramené dans la bande de clarté
/// où une marque se détache de sa surface.
///
/// En sombre, l'accent brut est souvent trop foncé pour se lire sur une carte
/// de nuit — le vert de la marque (#2C6774) n'y tient que 2,3:1, sous le
/// plancher de 3:1. Éclairci, il passe à 5,3:1 sans changer de teinte : c'est
/// bien le même vert, monté d'un cran. En clair, l'opération inverse retient
/// les accents très pâles. Le mode sombre a ainsi SES pas, et non un simple
/// retournement de ceux du clair.
Color statsSeriesColor(ColorScheme scheme) {
  final hsl = HSLColor.fromColor(scheme.primary);
  return hsl
      .withLightness(
        scheme.brightness == Brightness.dark
            ? math.max(hsl.lightness, 0.52)
            : math.min(hsl.lightness, 0.55),
      )
      .toColor();
}

/// Les encres et les filets partagés par les graphiques.
class _Chrome {
  /// `font` vient du thème : sous le rétro Winamp, les étiquettes s'écrivent
  /// dans le lettrage bitmap du châssis comme le reste de l'écran.
  _Chrome(ColorScheme scheme, this.font)
      : muted = scheme.onSurfaceVariant,
        grid = scheme.onSurface.withValues(alpha: 0.07),
        baseline = scheme.onSurface.withValues(alpha: 0.16),
        surface = scheme.surface;

  final String? font;

  /// Encre des étiquettes et des graduations.
  final Color muted;

  /// Filets horizontaux, et la ligne de base, un cran plus marquée.
  final Color grid;
  final Color baseline;

  /// Couleur derrière les marques : c'est elle qui fait l'anneau du point
  /// touché, là où il chevauche la courbe.
  final Color surface;
}

/// Mesure un texte à l'encre du graphique, prêt à être posé par son coin
/// haut-gauche.
TextPainter _label(String text, _Chrome chrome, {double size = 10}) {
  final painter = TextPainter(
    text: TextSpan(
      text: text,
      style: TextStyle(
        color: chrome.muted,
        fontSize: size,
        fontWeight: FontWeight.w600,
        fontFamily: chrome.font,
      ),
    ),
    textDirection: TextDirection.ltr,
  );
  painter.layout();
  return painter;
}

/// Trace la grille, les graduations et la ligne de base, et rend la fonction
/// qui place une valeur en ordonnée.
double Function(num) _paintFrame(
  Canvas canvas,
  Size size,
  _Chrome chrome,
  int top,
) {
  final bottom = kStatsPlotHeight;
  double y(num value) => bottom - (value / top) * bottom;

  final grid = Paint()
    ..color = chrome.grid
    ..strokeWidth = 1;
  // Le haut, le milieu (quand il tombe juste) et la base. Trois filets
  // suffisent à donner l'échelle ; au-delà, la grille couvre les données.
  final ticks = <int>[top, if (top.isEven && top > 2) top ~/ 2, 0];
  for (final tick in ticks) {
    final ty = y(tick);
    canvas.drawLine(
      Offset(kStatsGutter, ty),
      Offset(size.width, ty),
      tick == 0
          ? (Paint()
            ..color = chrome.baseline
            ..strokeWidth = 1)
          : grid,
    );
    final text = _label('$tick', chrome);
    text.paint(
      canvas,
      Offset(kStatsGutter - 6 - text.width, ty - text.height / 2),
    );
  }
  return y;
}

/// Trace les étiquettes de l'axe des abscisses, une case par valeur.
void _paintAxis(
  Canvas canvas,
  Size size,
  _Chrome chrome,
  List<String> labels,
  bool Function(int) shows,
) {
  final slot = (size.width - kStatsGutter) / labels.length;
  for (final (i, label) in labels.indexed) {
    if (!shows(i)) continue;
    final text = _label(label, chrome, size: 9.5);
    // Centrée sur sa case, puis ramenée dans la toile : la première et la
    // dernière étiquette débordaient de la carte.
    final center = kStatsGutter + slot * (i + 0.5);
    final x = (center - text.width / 2)
        .clamp(kStatsGutter, math.max(kStatsGutter, size.width - text.width))
        .toDouble();
    text.paint(canvas, Offset(x, kStatsPlotHeight + 5));
  }
}

/// Position, en abscisse, du centre de la case `i`.
double _slotCenter(double width, int count, int i) =>
    kStatsGutter + (width - kStatsGutter) / count * (i + 0.5);

/// Une courbe d'aire : l'activité au fil du temps, une seule série.
///
/// La courbe est lissée par des quadratiques passant par les milieux de
/// segments : le tracé reste dans l'enveloppe des points, donc il ne plonge
/// jamais sous zéro comme le ferait une spline trop libre.
class StatsTrendChart extends StatelessWidget {
  const StatsTrendChart({
    super.key,
    required this.data,
    required this.labels,
    required this.selected,
    required this.onSelected,
    required this.showsLabel,
  });

  final List<int> data;
  final List<String> labels;
  final int? selected;

  /// `null` quand on retouche le point déjà choisi : la valeur se retire.
  final ValueChanged<int?> onSelected;

  /// Quelles étiquettes d'abscisse s'écrivent.
  final bool Function(int) showsLabel;

  int _indexAt(double dx, double width) {
    final slot = (width - kStatsGutter) / data.length;
    return ((dx - kStatsGutter) / slot).floor().clamp(0, data.length - 1);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final chrome = _Chrome(scheme, theme.textTheme.labelSmall?.fontFamily);
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        void pick(double dx, {bool toggle = false}) {
          // Une série vide n'est pas affichée, mais la boîte, elle, reste
          // touchable : mieux vaut ne rien choisir que sortir de la liste.
          if (data.isEmpty) return;
          final i = _indexAt(dx, width);
          onSelected(toggle && selected == i ? null : i);
        }

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) => pick(d.localPosition.dx, toggle: true),
          onHorizontalDragUpdate: (d) => pick(d.localPosition.dx),
          // Largeur imposée : sans elle, un `CustomPaint` sans enfant se
          // réduit à zéro de large dès que la contrainte est lâche — et le
          // graphique disparaissait.
          child: SizedBox(
            width: width,
            height: kStatsPlotHeight + kStatsAxisBand,
            child: CustomPaint(
              painter: _TrendPainter(
                data: data,
                labels: labels,
                selected: selected,
                showsLabel: showsLabel,
                accent: statsSeriesColor(scheme),
                chrome: chrome,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _TrendPainter extends CustomPainter {
  _TrendPainter({
    required this.data,
    required this.labels,
    required this.selected,
    required this.showsLabel,
    required this.accent,
    required this.chrome,
  });

  final List<int> data;
  final List<String> labels;
  final int? selected;
  final bool Function(int) showsLabel;
  final Color accent;
  final _Chrome chrome;

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;
    final top = niceCeil(data.reduce(math.max));
    final y = _paintFrame(canvas, size, chrome, top);

    final points = [
      for (final (i, v) in data.indexed)
        Offset(_slotCenter(size.width, data.length, i), y(v)),
    ];

    final line = Path()..moveTo(points.first.dx, points.first.dy);
    for (var i = 1; i < points.length; i++) {
      final previous = points[i - 1];
      final mid = (previous + points[i]) / 2;
      line.quadraticBezierTo(previous.dx, previous.dy, mid.dx, mid.dy);
    }
    line.lineTo(points.last.dx, points.last.dy);

    // Le lavis sous la courbe : un voile, pas un aplat.
    final area = Path.from(line)
      ..lineTo(points.last.dx, kStatsPlotHeight)
      ..lineTo(points.first.dx, kStatsPlotHeight)
      ..close();
    canvas.drawPath(
      area,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            accent.withValues(alpha: 0.22),
            accent.withValues(alpha: 0.02),
          ],
        ).createShader(Rect.fromLTWH(0, 0, size.width, kStatsPlotHeight)),
    );
    canvas.drawPath(
      line,
      Paint()
        ..color = accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    // Le dernier point : il dit où la série s'arrête, donc aujourd'hui.
    canvas.drawCircle(points.last, 3.5, Paint()..color = accent);

    // Étiquette de l'extrême — une seule, choisie : le sommet de la série.
    final peak = data.indexOf(data.reduce(math.max));
    if (data[peak] > 0 && selected != peak) {
      _valueAt(canvas, size, points[peak], '${data[peak]}');
    }

    final at = selected;
    if (at != null && at < points.length) {
      canvas.drawLine(
        Offset(points[at].dx, 0),
        Offset(points[at].dx, kStatsPlotHeight),
        Paint()
          ..color = accent.withValues(alpha: 0.35)
          ..strokeWidth = 1,
      );
      // Anneau à la couleur du fond : le point reste lisible là où il
      // chevauche la courbe.
      canvas.drawCircle(points[at], 6, Paint()..color = chrome.surface);
      canvas.drawCircle(points[at], 4.5, Paint()..color = accent);
      _valueAt(canvas, size, points[at], '${data[at]}');
    }

    _paintAxis(canvas, size, chrome, labels, showsLabel);
  }

  /// Écrit une valeur juste au-dessus de son point, sans sortir de la toile.
  void _valueAt(Canvas canvas, Size size, Offset point, String value) {
    final text = _label(value, chrome);
    final x = (point.dx - text.width / 2)
        .clamp(kStatsGutter, math.max(kStatsGutter, size.width - text.width))
        .toDouble();
    final ty = math.max(0.0, point.dy - text.height - 7);
    text.paint(canvas, Offset(x, ty));
  }

  @override
  bool shouldRepaint(_TrendPainter old) =>
      old.selected != selected ||
      old.data != data ||
      old.accent != accent ||
      old.chrome.muted != chrome.muted;
}

/// Un histogramme : une case par tranche (l'heure, le jour), une seule série.
///
/// Quand une barre est choisie, les autres reculent d'un ton : c'est la barre
/// dont on lit la valeur qui doit ressortir, pas tout le graphique.
class StatsBarChart extends StatelessWidget {
  const StatsBarChart({
    super.key,
    required this.data,
    required this.labels,
    required this.selected,
    required this.onSelected,
    required this.showsLabel,
  });

  final List<int> data;
  final List<String> labels;
  final int? selected;
  final ValueChanged<int?> onSelected;
  final bool Function(int) showsLabel;

  int _indexAt(double dx, double width) {
    final slot = (width - kStatsGutter) / data.length;
    return ((dx - kStatsGutter) / slot).floor().clamp(0, data.length - 1);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final chrome = _Chrome(scheme, theme.textTheme.labelSmall?.fontFamily);
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        void pick(double dx, {bool toggle = false}) {
          // Une série vide n'est pas affichée, mais la boîte, elle, reste
          // touchable : mieux vaut ne rien choisir que sortir de la liste.
          if (data.isEmpty) return;
          final i = _indexAt(dx, width);
          onSelected(toggle && selected == i ? null : i);
        }

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) => pick(d.localPosition.dx, toggle: true),
          onHorizontalDragUpdate: (d) => pick(d.localPosition.dx),
          // Largeur imposée : sans elle, un `CustomPaint` sans enfant se
          // réduit à zéro de large dès que la contrainte est lâche — et le
          // graphique disparaissait.
          child: SizedBox(
            width: width,
            height: kStatsPlotHeight + kStatsAxisBand,
            child: CustomPaint(
              painter: _BarPainter(
                data: data,
                labels: labels,
                selected: selected,
                showsLabel: showsLabel,
                accent: statsSeriesColor(scheme),
                chrome: chrome,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _BarPainter extends CustomPainter {
  _BarPainter({
    required this.data,
    required this.labels,
    required this.selected,
    required this.showsLabel,
    required this.accent,
    required this.chrome,
  });

  final List<int> data;
  final List<String> labels;
  final int? selected;
  final bool Function(int) showsLabel;
  final Color accent;
  final _Chrome chrome;

  /// Épaisseur maximale d'une barre : au-delà, le reste de la case est de
  /// l'air. Deux pixels sont toujours laissés au fond entre deux voisines —
  /// c'est le fond qui sépare les marques, pas un cadre dessiné autour.
  static const _maxBarWidth = 24.0;
  static const _gap = 2.0;

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;
    final top = niceCeil(data.reduce(math.max));
    final y = _paintFrame(canvas, size, chrome, top);
    final slot = (size.width - kStatsGutter) / data.length;
    final barWidth = math.max(2.0, math.min(_maxBarWidth, slot - _gap));
    final peak = data.indexOf(data.reduce(math.max));

    for (final (i, value) in data.indexed) {
      if (value <= 0) continue;
      final center = _slotCenter(size.width, data.length, i);
      final rect = Rect.fromLTRB(
        center - barWidth / 2,
        y(value),
        center + barWidth / 2,
        kStatsPlotHeight,
      );
      // Tête arrondie, pied carré : la barre pousse depuis la ligne de base.
      final shape = RRect.fromRectAndCorners(
        rect,
        topLeft: const Radius.circular(4),
        topRight: const Radius.circular(4),
      );
      final dimmed = selected != null && selected != i;
      canvas.drawRRect(
        shape,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: dimmed
                ? [
                    accent.withValues(alpha: 0.40),
                    accent.withValues(alpha: 0.26),
                  ]
                : [accent, accent.withValues(alpha: 0.72)],
          ).createShader(rect),
      );

      // Une valeur sur la tête, et seulement là où elle a un sens : le
      // sommet de la série, et la barre que l'on vient de toucher.
      if (i != peak && selected != i) continue;
      final text = _label('$value', chrome);
      if (text.width > slot) continue;
      text.paint(
        canvas,
        Offset(
          (center - text.width / 2)
              .clamp(
                kStatsGutter,
                math.max(kStatsGutter, size.width - text.width),
              )
              .toDouble(),
          math.max(0.0, rect.top - text.height - 3),
        ),
      );
    }

    _paintAxis(canvas, size, chrome, labels, showsLabel);
  }

  @override
  bool shouldRepaint(_BarPainter old) =>
      old.selected != selected ||
      old.data != data ||
      old.accent != accent ||
      old.chrome.muted != chrome.muted;
}

/// La palette des parts : sept teintes d'IDENTITÉ, dans un ordre FIXE, une
/// variante par mode clair/sombre.
///
/// Le serveur envoie, lui, dix couleurs recyclées sur quatorze genres — deux
/// genres finissaient donc de la même couleur, et rien ne garantissait qu'on
/// distingue deux voisines. Celles-ci sont vérifiées : bande de clarté,
/// plancher de saturation, écart entre voisines y compris sous daltonisme
/// (protanopie, deutéranopie), contraste sur la surface. En clair, quatre
/// teintes passent sous 3:1 — d'où la légende chiffrée sous la barre, qui
/// rend chaque valeur lisible sans dépendre de la couleur.
///
/// La queue de la liste n'a PAS droit à une teinte de plus : elle se replie
/// sur « Autres », en gris — une huitième couleur inventée ne se distingue
/// plus de la septième.
class StatsShare {
  const StatsShare({
    required this.label,
    required this.value,
    required this.slot,
  });

  final String label;
  final int value;

  /// Rang dans la palette, ou `null` pour « Autres » (le gris).
  final int? slot;

  static const _light = [
    Color(0xFF2A78D6),
    Color(0xFFEB6834),
    Color(0xFF1BAF7A),
    Color(0xFFEDA100),
    Color(0xFFE87BA4),
    Color(0xFF008300),
  ];

  static const _dark = [
    Color(0xFF3987E5),
    Color(0xFFD95926),
    Color(0xFF199E70),
    Color(0xFFC98500),
    Color(0xFFD55181),
    Color(0xFF008300),
  ];

  /// Le gris de la queue : volontairement sans teinte, pour qu'« Autres » ne
  /// passe jamais pour un genre de plus.
  static const _other = Color(0xFF898781);

  /// Nombre de genres nommés avant que la queue ne se replie sur « Autres ».
  static const maxSlots = 6;

  Color color(Brightness brightness) {
    final index = slot;
    if (index == null) return _other;
    final palette = brightness == Brightness.dark ? _dark : _light;
    return palette[index % palette.length];
  }
}

/// Une barre de parts : le tout coupé en tranches, les plus grosses d'abord.
///
/// Les tranches sont séparées par deux pixels de fond — jamais par un trait
/// tracé autour —, et seules les deux extrémités de la barre sont arrondies :
/// c'est bien UN tout que l'on découpe.
class StatsShareBar extends StatelessWidget {
  const StatsShareBar({super.key, required this.shares, this.height = 14});

  final List<StatsShare> shares;
  final double height;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).colorScheme.brightness;
    return SizedBox(
      height: height,
      child: CustomPaint(
        // La largeur demandée est infinie, donc ramenée à celle de la carte :
        // un `CustomPaint` sans enfant ni taille se peindrait dans du vide.
        size: Size(double.infinity, height),
        painter: _SharePainter(
          values: [for (final s in shares) s.value],
          colors: [for (final s in shares) s.color(brightness)],
        ),
      ),
    );
  }
}

class _SharePainter extends CustomPainter {
  _SharePainter({required this.values, required this.colors});

  final List<int> values;
  final List<Color> colors;

  static const _gap = 2.0;

  @override
  void paint(Canvas canvas, Size size) {
    final total = values.fold(0, (sum, v) => sum + v);
    if (total <= 0) return;
    canvas.save();
    // Tout se peint dans une gélule : les bouts de la barre sont arrondis,
    // les coupes intérieures restent droites.
    canvas.clipRRect(
      RRect.fromRectAndRadius(
        Offset.zero & size,
        Radius.circular(size.height / 2),
      ),
    );
    var x = 0.0;
    for (final (i, value) in values.indexed) {
      final width = size.width * value / total;
      final last = i == values.length - 1;
      // Une part minuscule garde tout de même un pixel visible.
      final right = math.max(x + 1, x + width - (last ? 0 : _gap));
      canvas.drawRect(
        Rect.fromLTRB(x, 0, right, size.height),
        Paint()..color = colors[i],
      );
      x += width;
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_SharePainter old) =>
      old.values != values || old.colors != colors;
}
