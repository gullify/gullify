import 'package:flutter/material.dart';

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
  rose(Color(0xFFEC4899), 'Rose'),
  violet(Color(0xFF7C6BF5), 'Violet'),
  ocean(Color(0xFF0EA5E9), 'Océan');

  const GullifyAccent(this.color, this.label);

  final Color color;
  final String label;
}

/// Réglages de rendu propres à la structure de verre, lus par les widgets
/// (mini-lecteur, barre de navigation, en-têtes) pour l'effet.
class GullifySurfaces extends ThemeExtension<GullifySurfaces> {
  const GullifySurfaces({
    this.frosted = true,
    this.barColor,
    this.background,
    this.accentBlob,
  });

  /// Surfaces givrées : flou réel (BackdropFilter) sous les barres.
  final bool frosted;

  /// Couleur translucide des barres.
  final Color? barColor;

  /// Dégradé de fond global (les scaffolds sont transparents).
  final Gradient? background;

  /// Halo d'accent diffus en haut de l'écran.
  final Color? accentBlob;

  @override
  GullifySurfaces copyWith({
    bool? frosted,
    Color? barColor,
    Gradient? background,
    Color? accentBlob,
  }) =>
      GullifySurfaces(
        frosted: frosted ?? this.frosted,
        barColor: barColor ?? this.barColor,
        background: background ?? this.background,
        accentBlob: accentBlob ?? this.accentBlob,
      );

  @override
  GullifySurfaces lerp(GullifySurfaces? other, double t) => this;
}

ThemeData _base(ColorScheme scheme, GullifySurfaces surfaces) => ThemeData(
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
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
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
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      cardTheme: CardThemeData(
        color: surfaces.barColor,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(
            color: scheme.brightness == Brightness.light
                ? const Color(0xB3FFFFFF)
                : const Color(0x26FFFFFF),
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

ThemeData gullifyThemeFor(GullifyAccent accent, {required bool dark}) =>
    dark ? _darkGlass(accent.color) : _lightGlass(accent.color);
