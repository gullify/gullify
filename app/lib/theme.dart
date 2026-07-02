import 'package:flutter/material.dart';

/// Gullify "audiophile" dark theme — amber accent on near-black surfaces,
/// matching the web client's audiophile theme (oklch(0.78 0.14 65)).
const gullifyAmber = Color(0xFFE3A94F);
const _surface = Color(0xFF121212);
const _surfaceContainer = Color(0xFF1C1B18);

/// Thème clair — même accent ambre, surfaces claires.
ThemeData gullifyLightTheme() {
  final scheme = ColorScheme.fromSeed(seedColor: gullifyAmber);

  return ThemeData(
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
        // Voir le commentaire du thème sombre : jamais Size.fromHeight ici.
        minimumSize: const Size(64, 48),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        textStyle: const TextStyle(fontWeight: FontWeight.w600),
      ),
    ),
  );
}

ThemeData gullifyTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: gullifyAmber,
    brightness: Brightness.dark,
    surface: _surface,
  ).copyWith(
    primary: gullifyAmber,
    surfaceContainerHighest: _surfaceContainer,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: _surface,
    appBarTheme: const AppBarTheme(
      backgroundColor: _surface,
      surfaceTintColor: Colors.transparent,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: _surfaceContainer,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: gullifyAmber, width: 1.5),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: gullifyAmber,
        foregroundColor: Colors.black,
        // Jamais Size.fromHeight ici : sa largeur infinie fait exploser le
        // layout des boutons placés dans un Row (l'arbre ne se peint plus).
        minimumSize: const Size(64, 48),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        textStyle: const TextStyle(fontWeight: FontWeight.w600),
      ),
    ),
  );
}
