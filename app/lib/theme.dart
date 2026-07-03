import 'package:flutter/material.dart';

/// Gullify "audiophile" dark theme — amber accent on near-black surfaces,
/// matching the web client's audiophile theme (oklch(0.78 0.14 65)).
const gullifyAmber = Color(0xFFE3A94F);
const _surface = Color(0xFF121212);
const _surfaceContainer = Color(0xFF1C1B18);

// Liquid Glass — bleu nuit profond, accent glacier, surfaces translucides.
const _glassBg = Color(0xFF0A0F1A);
const _glassAccent = Color(0xFF8AD4F0);

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
          (_glassBg, const Color(0x1FFFFFFF), _glassAccent),
      };
}

/// Réglages de rendu propres au style, lus par les widgets (mini-player,
/// barre de navigation) pour l'effet verre.
class GullifySurfaces extends ThemeExtension<GullifySurfaces> {
  const GullifySurfaces({this.frosted = false, this.barColor});

  /// Surfaces givrées : flou réel (BackdropFilter) sous les barres.
  final bool frosted;

  /// Couleur translucide des barres quand [frosted] est actif.
  final Color? barColor;

  @override
  GullifySurfaces copyWith({bool? frosted, Color? barColor}) =>
      GullifySurfaces(
        frosted: frosted ?? this.frosted,
        barColor: barColor ?? this.barColor,
      );

  @override
  GullifySurfaces lerp(GullifySurfaces? other, double t) => this;
}

ThemeData _base(ColorScheme scheme, {GullifySurfaces? surfaces}) => ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      appBarTheme: const AppBarTheme(surfaceTintColor: Colors.transparent),
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

/// Thème clair — même accent ambre, surfaces claires.
ThemeData gullifyLightTheme() =>
    _base(ColorScheme.fromSeed(seedColor: gullifyAmber));

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
  return _base(scheme).copyWith(
    scaffoldBackgroundColor: _surface,
    appBarTheme: const AppBarTheme(
      backgroundColor: _surface,
      surfaceTintColor: Colors.transparent,
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
  return _base(scheme).copyWith(
    scaffoldBackgroundColor: Colors.black,
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.black,
      surfaceTintColor: Colors.transparent,
    ),
    cardTheme: const CardThemeData(color: Color(0xFF0A0A0A)),
    dividerTheme: const DividerThemeData(color: Color(0xFF1A1A1A)),
  );
}

/// « Liquid Glass » — bleu nuit, accent glacier, barres givrées translucides
/// (les widgets appliquent un vrai flou via [GullifySurfaces.frosted]).
ThemeData gullifyGlassTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: _glassAccent,
    brightness: Brightness.dark,
    surface: _glassBg,
  ).copyWith(
    primary: _glassAccent,
    onPrimary: const Color(0xFF06222E),
    surfaceContainerHighest: const Color(0x14FFFFFF),
    outlineVariant: const Color(0x1FFFFFFF),
  );
  return _base(
    scheme,
    surfaces: const GullifySurfaces(
      frosted: true,
      barColor: Color(0xB30D1524),
    ),
  ).copyWith(
    scaffoldBackgroundColor: _glassBg,
    appBarTheme: const AppBarTheme(
      backgroundColor: Color(0xB30D1524),
      surfaceTintColor: Colors.transparent,
    ),
    cardTheme: CardThemeData(
      color: const Color(0x14FFFFFF),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0x1FFFFFFF)),
      ),
    ),
    navigationBarTheme: const NavigationBarThemeData(
      backgroundColor: Colors.transparent,
      elevation: 0,
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
