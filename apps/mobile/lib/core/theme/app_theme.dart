import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:cohyve/core/branding/branding.g.dart';

ThemeData buildLightTheme() => _build(true);
ThemeData buildDarkTheme() => _build(false);

// Extended palette beyond the 6 basic branding constants.
// These match the branding.config.json gradient/colors section.
class BrandingExtended {
  BrandingExtended._();
  static const Color gradientStart = Color(0xFF8B5CF6); // Violet
  static const Color gradientMid = Color(0xFFEC4899);    // Pink
  static const Color gradientEnd = Color(0xFFF97316);    // Orange
  static const Color success = Color(0xFF10B981);
  static const Color warning = Color(0xFFF59E0B);
  static const Color danger = Color(0xFFEF4444);
  static const Color cardLight = Color(0xFFFFFFFF);
  static const Color cardDark = Color(0xFF1A1A2E);
  static const Color surfaceLight = Color(0xFFF5F5F7);
  static const Color surfaceDark = Color(0xFF16162A);
}

ThemeData _build(bool isLight) {
  final scaffoldBg = isLight ? Branding.bgLight : Branding.bgDark;
  final surface = isLight ? BrandingExtended.cardLight : BrandingExtended.cardDark;
  final surfaceContainer = isLight ? BrandingExtended.surfaceLight : BrandingExtended.surfaceDark;
  final textColor = isLight ? Color(0xFF1A1A1A) : Color(0xFFE8E8F0);
  final mutedBorder = isLight ? Color(0xFFE5E5EA) : Color(0xFF2A2A40);

  // Vibrant gradient palette inspired by Spotify Wrapped's bold energy.
  final gradientColors = isLight
      ? [BrandingExtended.gradientStart, BrandingExtended.gradientMid, BrandingExtended.gradientEnd]
      : [BrandingExtended.gradientEnd, BrandingExtended.gradientMid, BrandingExtended.gradientStart];

  final scheme = ColorScheme.fromSeed(
    seedColor: BrandingExtended.gradientStart,
    brightness: isLight ? Brightness.light : Brightness.dark,
  ).copyWith(
    primary: BrandingExtended.gradientStart,
    secondary: BrandingExtended.gradientMid,
    tertiary: BrandingExtended.gradientEnd,
    surface: surface,
    surfaceContainer: surfaceContainer,
  );

  // Bold typography — Space Grotesk for body, Inter for headings.
  final textTheme = TextTheme(
    displayLarge: GoogleFonts.inter(
      fontSize: 57, fontWeight: FontWeight.w800, letterSpacing: -1.5, color: textColor,
    ),
    displayMedium: GoogleFonts.inter(
      fontSize: 45, fontWeight: FontWeight.w700, letterSpacing: -0.5, color: textColor,
    ),
    displaySmall: GoogleFonts.inter(
      fontSize: 36, fontWeight: FontWeight.w600, color: textColor,
    ),
    headlineLarge: GoogleFonts.inter(
      fontSize: 32, fontWeight: FontWeight.w800, letterSpacing: -0.5, color: textColor,
    ),
    headlineMedium: GoogleFonts.inter(
      fontSize: 28, fontWeight: FontWeight.w700, letterSpacing: -0.3, color: textColor,
    ),
    headlineSmall: GoogleFonts.inter(
      fontSize: 22, fontWeight: FontWeight.w600, color: textColor,
    ),
    titleLarge: GoogleFonts.inter(
      fontSize: 18, fontWeight: FontWeight.w700, letterSpacing: -0.2, color: textColor,
    ),
    titleMedium: GoogleFonts.inter(
      fontSize: 15, fontWeight: FontWeight.w600, color: textColor,
    ),
    titleSmall: GoogleFonts.inter(
      fontSize: 13, fontWeight: FontWeight.w500, color: textColor,
    ),
    bodyLarge: GoogleFonts.spaceGrotesk(
      fontSize: 16, height: 1.5, color: textColor,
    ),
    bodyMedium: GoogleFonts.spaceGrotesk(
      fontSize: 14, height: 1.45, color: textColor,
    ),
    bodySmall: GoogleFonts.spaceGrotesk(
      fontSize: 12, height: 1.4, color: textColor.withValues(alpha: isLight ? 0.6 : 0.5),
    ),
    labelLarge: GoogleFonts.spaceGrotesk(
      fontSize: 14, fontWeight: FontWeight.w700, color: textColor,
    ),
    labelMedium: GoogleFonts.spaceGrotesk(
      fontSize: 12, fontWeight: FontWeight.w600, color: textColor,
    ),
    labelSmall: GoogleFonts.spaceGrotesk(
      fontSize: 11, fontWeight: FontWeight.w500, color: textColor,
    ),
  );

  // Vibrant gradient for primary buttons
  final primaryGradient = LinearGradient(
    colors: gradientColors,
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: isLight ? Brightness.light : Brightness.dark,
    colorScheme: scheme,
    scaffoldBackgroundColor: scaffoldBg,
    textTheme: textTheme,
    visualDensity: VisualDensity.adaptivePlatformDensity,
    splashFactory: InkSparkle.splashFactory,

    // App bar — clean, minimal elevation
    appBarTheme: AppBarTheme(
      backgroundColor: scaffoldBg,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0.5,
      centerTitle: false,
      titleTextStyle: textTheme.titleLarge,
      iconTheme: IconThemeData(color: textColor),
    ),

    // Cards with subtle gradient border effect
    cardTheme: CardThemeData(
      color: scheme.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: mutedBorder, width: 1),
      ),
    ),

    // Bottom navigation — gradient indicator
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: scheme.surface,
      indicatorColor: scheme.primary,
      elevation: 3,
      height: 68,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      labelTextStyle: WidgetStatePropertyAll(
        textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w700),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          color: states.contains(WidgetState.selected)
              ? scheme.primary
              : scheme.onSurfaceVariant,
        ),
      ),
    ),

    // Chips with gradient accent on selected
    chipTheme: ChipThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      side: BorderSide(color: mutedBorder),
      backgroundColor: scheme.surfaceContainer,
      selectedColor: scheme.primary,
      labelStyle: textTheme.labelMedium,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    ),

    // Input fields — gradient focus border
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: isLight ? Colors.white : const Color(0xFF1A1A2E),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: mutedBorder),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: mutedBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: scheme.primary, width: 1.6),
      ),
    ),

    // Primary buttons — gradient filled
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        textStyle: textTheme.labelLarge,
        foregroundColor: Colors.white,
        backgroundColor: scheme.primary,
        elevation: 0,
      ),
    ),

    // Outline buttons — subtle
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: scheme.primary,
        side: BorderSide(color: mutedBorder),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
      ),
    ),

    // Text buttons — primary color
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: scheme.primary),
    ),

    // FAB — gradient background
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: scheme.primary,
      foregroundColor: scheme.onPrimary,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),

    // List tiles — rounded
    listTileTheme: ListTileThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),

    // Dividers
    dividerTheme: DividerThemeData(
      color: mutedBorder,
      thickness: 1,
      space: 1,
    ),

    // Snack bars — gradient
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      backgroundColor: scheme.primary,
      contentTextStyle: textTheme.bodyMedium?.copyWith(color: Colors.white),
    ),
  );
}
