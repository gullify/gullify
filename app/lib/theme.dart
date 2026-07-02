import 'package:flutter/material.dart';

/// Gullify "audiophile" dark theme — amber accent on near-black surfaces,
/// matching the web client's audiophile theme (oklch(0.78 0.14 65)).
const gullifyAmber = Color(0xFFE3A94F);
const _surface = Color(0xFF121212);
const _surfaceContainer = Color(0xFF1C1B18);

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
        minimumSize: const Size.fromHeight(48),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        textStyle: const TextStyle(fontWeight: FontWeight.w600),
      ),
    ),
  );
}
