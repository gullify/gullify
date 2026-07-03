import 'package:flutter/material.dart';

/// Gullify "audiophile" dark theme — amber accent on near-black surfaces,
/// matching the web client's audiophile theme (oklch(0.78 0.14 65)).
const gullifyAmber = Color(0xFFE3A94F);
const _surface = Color(0xFF121212);
const _surfaceContainer = Color(0xFF1C1B18);

// Liquid Glass Player (design de référence) : perle claire, verre blanc,
// encre #191B21, accent indigo diffusé en halo.
const glassInk = Color(0xFF191B21);
const glassAccent = Color(0xFF4A5FE8);

/// Styles visuels de l'app. `system` alterne Clair/Audiophile selon l'OS.
enum GullifyStyle { system, clair, audiophile, amoled, glass }

extension GullifyStyleInfo on GullifyStyle {
  String get label => switch (this) {
        GullifyStyle.system => 'Système',
        GullifyStyle.clair => 'Clair',
        GullifyStyle.audiophile => 'Audiophile',
        GullifyStyle.amoled => 'AMOLED',
        GullifyStyle.glass => 'Liquid Glass',
      };

  /// Couleurs d'aperçu (fond, surface, accent) pour le sélecteur.
  (Color, Color, Color) get preview => switch (this) {
        GullifyStyle.system => (Colors.white, _surface, gullifyAmber),
        GullifyStyle.clair =>
          (Colors.white, const Color(0xFFF3EDE2), const Color(0xFF7A5B1E)),
        GullifyStyle.audiophile => (_surface, _surfaceContainer, gullifyAmber),
        GullifyStyle.amoled =>
          (Colors.black, const Color(0xFF0A0A0A), gullifyAmber),
        GullifyStyle.glass =>
          (const Color(0xFFF2F3F7), Colors.white, glassAccent),
      };
}

/// Réglages de rendu propres au style, lus par les widgets (mini-player,
/// barre de navigation) pour l'effet verre.
class GullifySurfaces extends ThemeExtension<GullifySurfaces> {
  const GullifySurfaces({
    this.frosted = false,
    this.barColor,
    this.background,
    this.accentBlob,
  });

  /// Surfaces givrées : flou réel (BackdropFilter) sous les barres,
  /// barres flottantes, pochette floutée en fond du lecteur.
  final bool frosted;

  /// Couleur translucide des barres quand [frosted] est actif.
  final Color? barColor;

  /// Dégradé de fond global (les scaffolds sont alors transparents).
  final Gradient? background;

  /// Halo d'accent diffus en haut de l'écran (design Liquid Glass Player).
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

ThemeData _base(ColorScheme scheme, {GullifySurfaces? surfaces}) => ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      // Style « Liquid Glass Player » : scaffolds transparents, le dégradé
      // global (main.dart) est visible derrière tout, les barres de verre
      // floutent le contenu qui défile dessous.
      scaffoldBackgroundColor: Colors.transparent,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
      ),
      textTheme: const TextTheme(
        headlineSmall: TextStyle(
          fontWeight: FontWeight.w800,
          letterSpacing: -0.6,
        ),
        titleLarge: TextStyle(
          fontWeight: FontWeight.w800,
          letterSpacing: -0.5,
        ),
        titleMedium: TextStyle(
          fontSize: 16.5,
          fontWeight: FontWeight.w700,
        ),
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
          // Jamais Size.fromHeight ici : sa largeur infinie fait exploser le
          // layout des boutons placés dans un Row (l'arbre ne se peint plus).
          minimumSize: const Size(64, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      extensions: [surfaces ?? const GullifySurfaces()],
    );

/// Thème clair — dégradé perle du design Liquid Glass Player.
ThemeData gullifyLightTheme() => _base(
      ColorScheme.fromSeed(seedColor: gullifyAmber),
      surfaces: const GullifySurfaces(
        background: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFF6F6F8), Color(0xFFECEEF4), Color(0xFFE6EAF1)],
        ),
      ),
    );

/// Thème sombre « audiophile » historique.
ThemeData gullifyTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: gullifyAmber,
    brightness: Brightness.dark,
    surface: _surface,
  ).copyWith(
    primary: gullifyAmber,
    onPrimary: Colors.black,
    surfaceContainerHighest: _surfaceContainer,
  );
  return _base(
    scheme,
    surfaces: const GullifySurfaces(
      barColor: Color(0xC71C1B18),
      background: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF191511), Color(0xFF121212), Color(0xFF141210)],
      ),
    ),
  );
}

/// Noir pur (écrans OLED) — contraste maximal, accent ambre.
ThemeData gullifyAmoledTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: gullifyAmber,
    brightness: Brightness.dark,
    surface: Colors.black,
  ).copyWith(
    primary: gullifyAmber,
    onPrimary: Colors.black,
    surfaceContainerHighest: const Color(0xFF111111),
    outlineVariant: const Color(0xFF222222),
  );
  return _base(
    scheme,
    surfaces: const GullifySurfaces(
      barColor: Color(0xD90A0A0A),
      background: LinearGradient(
        colors: [Colors.black, Colors.black],
      ),
    ),
  ).copyWith(
    cardTheme: const CardThemeData(color: Color(0xFF0A0A0A)),
    dividerTheme: const DividerThemeData(color: Color(0xFF1A1A1A)),
  );
}

/// « Liquid Glass » — reproduction fidèle du design de référence :
/// dégradé perle, verre blanc, encre #191B21, gris #6B7078/#8A8F98,
/// accent indigo avec halo diffus en haut d'écran.
ThemeData gullifyGlassTheme() {
  final scheme = ColorScheme.fromSeed(seedColor: glassAccent).copyWith(
    primary: glassAccent,
    onPrimary: Colors.white,
    surface: const Color(0xFFF2F3F7),
    onSurface: glassInk,
    onSurfaceVariant: const Color(0xFF6B7078),
    outline: const Color(0xFFA0A4AC),
    outlineVariant: const Color(0xFFD8DCE4),
    surfaceContainerHighest: const Color(0xCCFFFFFF),
  );
  return _base(
    scheme,
    surfaces: const GullifySurfaces(
      frosted: true,
      accentBlob: glassAccent,
      background: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFFF6F6F8), Color(0xFFECEEF4), Color(0xFFE6EAF1)],
      ),
    ),
  ).copyWith(
    cardTheme: CardThemeData(
      color: const Color(0x8CFFFFFF),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: Color(0xB3FFFFFF)),
      ),
    ),
  );
}

ThemeData themeFor(GullifyStyle style, Brightness platformBrightness) =>
    switch (style) {
      GullifyStyle.system => platformBrightness == Brightness.dark
          ? gullifyTheme()
          : gullifyLightTheme(),
      GullifyStyle.clair => gullifyLightTheme(),
      GullifyStyle.audiophile => gullifyTheme(),
      GullifyStyle.amoled => gullifyAmoledTheme(),
      GullifyStyle.glass => gullifyGlassTheme(),
    };
