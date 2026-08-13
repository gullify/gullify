import 'package:flutter/material.dart';

import 'widgets/retro_chrome.dart';

/// Identité Gullify : UNE structure « Liquid Glass » (verre translucide,
/// images en filigrane, mise en page constante). Seuls changent la COULEUR
/// d'accent choisie et la base claire/sombre — la personnalité vient de la
/// structure, pas de la couleur.

/// Accent indigo par défaut (celui du design de référence).
const glassAccent = Color(0xFF4A5FE8);

/// Ambre de marque (placeholder de pochette, icône de secours).
const gullifyAmber = Color(0xFFE3A94F);

/// Couleurs d'accent proposées. La structure reste identique quelle que
/// soit la teinte choisie.
enum GullifyAccent {
  indigo(Color(0xFF4A5FE8), 'Indigo'),
  ambre(Color(0xFFE0913A), 'Ambre'),
  emeraude(Color(0xFF10B981), 'Émeraude'),
  turquoise(Color(0xFF14B8A6), 'Turquoise'),
  ocean(Color(0xFF0EA5E9), 'Océan'),
  violet(Color(0xFF7C6BF5), 'Violet'),
  fuchsia(Color(0xFFC026D3), 'Fuchsia'),
  rose(Color(0xFFEC4899), 'Rose'),
  rubis(Color(0xFFE5484D), 'Rubis'),
  graphite(Color(0xFF64748B), 'Graphite');

  const GullifyAccent(this.color, this.label);

  final Color color;
  final String label;
}

/// L'habillage de l'app.
///
/// Le verre est l'identité de Gullify : une seule structure, seule la couleur
/// change (voir plus haut). Le rétro Winamp (idée #82) est un écart assumé,
/// rangé à part des accents — la nostalgie, « de temps en temps ». Il ne
/// change rien à la mise en page : mêmes écrans, mêmes gestes, seulement des
/// surfaces biseautées, un fond métal et un afficheur vert.
enum GullifySkin { glass, winamp }

/// Le vert de l'afficheur et le noir sur lequel il vit sont désormais rangés
/// avec le reste de la palette du châssis (retro_chrome.dart) : le design de
/// l'idée #85 les donne comme des jetons, à côté du chrome et de l'ambre.

/// Réglages de rendu propres à la structure de verre, lus par les widgets
/// (mini-lecteur, barre de navigation, en-têtes) pour l'effet.
class GullifySurfaces extends ThemeExtension<GullifySurfaces> {
  const GullifySurfaces({
    this.frosted = true,
    this.barColor,
    this.background,
    this.accentBlob,
    this.retro = false,
    this.bevelLight,
    this.bevelDark,
  });

  /// Surfaces givrées : flou réel (BackdropFilter) sous les barres.
  final bool frosted;

  /// Couleur translucide des barres.
  final Color? barColor;

  /// Dégradé de fond global (les scaffolds sont transparents).
  final Gradient? background;

  /// Halo d'accent diffus en haut de l'écran.
  final Color? accentBlob;

  /// Habillage rétro (idée #82) : surfaces opaques biseautées, angles à peine
  /// arrondis, afficheur vert. Les widgets communs (GlassBox, mini-lecteur)
  /// se peignent autrement quand il est levé — la mise en page, elle, ne
  /// bouge pas d'un pixel.
  final bool retro;

  /// Arêtes du biseau : la lumière en haut à gauche, l'ombre en bas à droite.
  final Color? bevelLight;
  final Color? bevelDark;

  @override
  GullifySurfaces copyWith({
    bool? frosted,
    Color? barColor,
    Gradient? background,
    Color? accentBlob,
    bool? retro,
    Color? bevelLight,
    Color? bevelDark,
  }) =>
      GullifySurfaces(
        frosted: frosted ?? this.frosted,
        barColor: barColor ?? this.barColor,
        background: background ?? this.background,
        accentBlob: accentBlob ?? this.accentBlob,
        retro: retro ?? this.retro,
        bevelLight: bevelLight ?? this.bevelLight,
        bevelDark: bevelDark ?? this.bevelDark,
      );

  @override
  GullifySurfaces lerp(GullifySurfaces? other, double t) => this;
}

/// [corner] arrondit les champs et les boutons, [cardCorner] les cartes.
/// Le verre est tout en pilules ; le rétro Winamp est presque carré.
ThemeData _base(
  ColorScheme scheme,
  GullifySurfaces surfaces, {
  double corner = 12,
  double cardCorner = 18,
}) =>
    ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      fontFamily: 'HankenGrotesk',
      // Scaffolds transparents : le dégradé global (main.dart) est visible
      // derrière tout, les barres de verre floutent le contenu dessous.
      scaffoldBackgroundColor: Colors.transparent,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
      ),
      textTheme: const TextTheme(
        headlineSmall:
            TextStyle(fontWeight: FontWeight.w800, letterSpacing: -0.6),
        titleLarge: TextStyle(fontWeight: FontWeight.w800, letterSpacing: -0.5),
        titleMedium: TextStyle(fontSize: 16.5, fontWeight: FontWeight.w700),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(corner),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(corner),
          borderSide: BorderSide(color: scheme.primary, width: 1.5),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          // Jamais Size.fromHeight : sa largeur infinie casse le layout des
          // boutons dans un Row.
          minimumSize: const Size(64, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(corner),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      // SnackBars flottantes : elles s'affichent au-dessus du dock/mini-
      // lecteur au lieu de passer derrière.
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
      ),
      cardTheme: CardThemeData(
        color: surfaces.barColor,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(cardCorner),
          side: BorderSide(
            color: switch (scheme.brightness) {
              // Rétro : l'arête claire du châssis, pas un liseré de verre.
              _ when surfaces.retro => winampBevelLight,
              Brightness.light => const Color(0xB3FFFFFF),
              Brightness.dark => const Color(0x26FFFFFF),
            },
          ),
        ),
      ),
      extensions: [surfaces],
    );

/// Base CLAIRE : dégradé perle, verre blanc, encre sombre.
ThemeData _lightGlass(Color accent) {
  final scheme = ColorScheme.fromSeed(seedColor: accent).copyWith(
    primary: accent,
    onPrimary: Colors.white,
    surface: const Color(0xFFF2F3F7),
    onSurface: const Color(0xFF191B21),
    onSurfaceVariant: const Color(0xFF6B7078),
    outline: const Color(0xFFA0A4AC),
    outlineVariant: const Color(0xFFD8DCE4),
    surfaceContainerHighest: const Color(0xCCFFFFFF),
  );
  return _base(
    scheme,
    GullifySurfaces(
      accentBlob: accent,
      barColor: const Color(0x8CFFFFFF),
      background: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFFF6F6F8), Color(0xFFECEEF4), Color(0xFFE6EAF1)],
      ),
    ),
  );
}

/// Base SOMBRE : verre nuit, même structure, teinté par l'accent.
ThemeData _darkGlass(Color accent) {
  final scheme = ColorScheme.fromSeed(
    seedColor: accent,
    brightness: Brightness.dark,
  ).copyWith(
    primary: accent,
    onPrimary: Colors.white,
    surface: const Color(0xFF14161C),
    onSurface: const Color(0xFFEDEFF3),
    onSurfaceVariant: const Color(0xFF9BA0AA),
    outline: const Color(0xFF565A63),
    outlineVariant: const Color(0xFF2A2D34),
    surfaceContainerHighest: const Color(0x14FFFFFF),
  );
  return _base(
    scheme,
    GullifySurfaces(
      accentBlob: accent,
      barColor: const Color(0xBF1A1D24),
      background: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF1A1C22), Color(0xFF111319), Color(0xFF171922)],
      ),
    ),
  );
}

/// Le thème rétro Winamp (idée #82) : le châssis gris métal des lecteurs de
/// 1999, ses biseaux, son afficheur vert sur noir.
///
/// Un seul thème, sombre : un Winamp clair n'a jamais existé, et c'est bien
/// tout l'intérêt. Il reste rangé à part des accents — on le met « de temps
/// en temps », il ne remplace pas l'identité de verre.
ThemeData _winamp() {
  final scheme = ColorScheme.fromSeed(
    seedColor: winampGreen,
    brightness: Brightness.dark,
  ).copyWith(
    primary: winampGreen,
    // Le vert de l'afficheur est trop lumineux pour porter du texte blanc :
    // sur les boutons pleins, l'encre est noire, comme sur un vrai LCD.
    onPrimary: const Color(0xFF05170A),
    // L'ambre du design (idée #85) : la seconde voix du châssis, celle des
    // actions qui ne sont pas la lecture.
    secondary: winampAmber,
    onSecondary: const Color(0xFF14141A),
    surface: const Color(0xFF2A2A33),
    onSurface: const Color(0xFFE6E6EF),
    onSurfaceVariant: const Color(0xFF9A9AAC),
    outline: winampBevelLight,
    outlineVariant: winampBevelShade,
    surfaceContainerHighest: winampChassis,
  );
  return _base(
    scheme,
    const GullifySurfaces(
      frosted: false,
      retro: true,
      // Panneaux opaques : le verre translucide n'a rien à faire ici.
      barColor: winampChassis,
      bevelLight: winampBevelLight,
      bevelDark: winampBevelDark,
      // Pas de halo d'accent : un châssis de 1999 ne brille pas.
      // Un gris à peine violacé, plus sombre que les plaques : sans cet
      // écart, les biseaux ne se détachent pas du fond (idée #83). Les
      // teintes viennent du design de l'idée #85.
      background: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFF1E1E25), Color(0xFF191920), Color(0xFF15151B)],
      ),
    ),
    corner: 0,
    cardCorner: 0,
  ).copyWith(
    sliderTheme: retroSliderTheme,
    // Tout champ de saisie devient une vitre : creux, fond noir verdâtre,
    // lettrage VT323 en phosphore (idée #85). C'est ce qui transforme la
    // recherche et les filtres en « afficheurs » sans toucher aux écrans.
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: winampLcd,
      hintStyle: lcdTextStyle(size: 17, color: winampGreenDim),
      labelStyle: lcdTextStyle(size: 17, color: winampGreenDim),
      prefixIconColor: winampGreenDim,
      suffixIconColor: winampGreenDim,
      border: const OutlineInputBorder(
        borderRadius: BorderRadius.zero,
        borderSide: BorderSide(color: winampBevelDark),
      ),
      enabledBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.zero,
        borderSide: BorderSide(color: winampBevelDark),
      ),
      focusedBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.zero,
        borderSide: BorderSide(color: winampGreenDim, width: 1.5),
      ),
    ),
    textSelectionTheme: const TextSelectionThemeData(
      cursorColor: winampGreen,
      selectionColor: Color(0x5522E04A),
      selectionHandleColor: winampGreen,
    ),
    // Les filtres (genres, années, onglets de bibliothèque) deviennent les
    // petits onglets de chrome du design : carrés, gravés, allumés en vert
    // quand ils sont choisis.
    chipTheme: ChipThemeData(
      backgroundColor: winampPanel,
      selectedColor: const Color(0xFF1A1F1C),
      side: const BorderSide(color: winampBevelShade),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.zero,
        side: BorderSide(color: winampBevelDark),
      ),
      labelStyle: retroLabelStyle(size: 8.5),
      secondaryLabelStyle: retroLabelStyle(size: 8.5, color: winampGreen),
      checkmarkColor: winampGreen,
      showCheckmark: false,
    ),
  );
}

ThemeData gullifyThemeFor(GullifyAccent accent, {required bool dark}) =>
    dark ? _darkGlass(accent.color) : _lightGlass(accent.color);

/// Le thème à appliquer : le verre teinté par l'accent, ou le rétro Winamp
/// (qui ignore accent et mode — il n'a qu'une seule tête).
ThemeData gullifyTheme(
  GullifySkin skin,
  GullifyAccent accent, {
  required bool dark,
}) => switch (skin) {
  GullifySkin.winamp => _winamp(),
  GullifySkin.glass => gullifyThemeFor(accent, dark: dark),
};
