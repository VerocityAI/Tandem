import 'package:flutter/material.dart';

import 'package:tandem/core/branding/branding.g.dart';

ThemeData buildLightTheme() => _build(
      brightness: Brightness.light,
      accent: Branding.accentLight,
      accentHover: Branding.accentLightHover,
      background: Branding.bgLight,
      surface: const Color(0xFFFFFFFF),
      text: const Color(0xFF242424),
      textMuted: const Color(0xFF5C5C5C),
      border: const Color(0xFFDEDEDE),
    );

ThemeData buildDarkTheme() => _build(
      brightness: Brightness.dark,
      accent: Branding.accentDark,
      accentHover: Branding.accentDarkHover,
      background: Branding.bgDark,
      surface: const Color(0xFF292929),
      text: const Color(0xFFDEDEDE),
      textMuted: const Color(0xFF919191),
      border: const Color(0xFF474747),
    );

ThemeData _build({
  required Brightness brightness,
  required Color accent,
  required Color accentHover,
  required Color background,
  required Color surface,
  required Color text,
  required Color textMuted,
  required Color border,
}) {
  final colorScheme = ColorScheme(
    brightness: brightness,
    primary: accent,
    onPrimary:
        brightness == Brightness.light ? Colors.white : const Color(0xFF1A1A1A),
    secondary: accent,
    onSecondary:
        brightness == Brightness.light ? Colors.white : const Color(0xFF1A1A1A),
    error: const Color(0xFFDC2626),
    onError: Colors.white,
    surface: surface,
    onSurface: text,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: background,
    fontFamily: 'Segoe UI',
    textTheme: TextTheme(
      headlineLarge: TextStyle(
        color: text,
        fontSize: 32,
        fontWeight: FontWeight.w600,
      ),
      headlineMedium: TextStyle(
        color: text,
        fontSize: 24,
        fontWeight: FontWeight.w600,
      ),
      titleLarge: TextStyle(
        color: text,
        fontSize: 18,
        fontWeight: FontWeight.w600,
      ),
      bodyLarge: TextStyle(color: text, fontSize: 16),
      bodyMedium: TextStyle(color: text, fontSize: 14),
      labelMedium: TextStyle(color: textMuted, fontSize: 12),
    ),
    dividerColor: border,
    cardTheme: CardThemeData(
      color: surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: border),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: accent,
        foregroundColor: brightness == Brightness.light
            ? Colors.white
            : const Color(0xFF1A1A1A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: text,
        side: BorderSide(color: border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      ),
    ),
  );
}
