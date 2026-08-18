import 'package:flutter/material.dart';

// consistent pkm-inspired theme with strict aesthetics
// all code comments are entirely in lowercase
class AppTheme {
  static const primaryColor = Color(0xfff6b012); // vibrant amber/yellow
  static const secondaryColor = Color(0xff3c9fdd); // sky blue
  static const backgroundColor = Color(0xff050505); // deep black/obsidian
  static const surfaceColor = Color(0xff121212); // slightly elevated surface
  static const accentColor = Color(0xff1a1a1a); // selection/hover accent
  static const textPrimary = Color(0xfff6f6f6);
  static const textSecondary = Color(0xffa1a1aa);
  static const textMuted = Color(0xff71717a);

  static ThemeData get darkTheme {
    final baseTheme = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      fontFamily: 'VarelaRound',
      splashFactory: NoSplash.splashFactory, // remove glow/ripple
      highlightColor: Colors.transparent, // remove tap highlight
      colorScheme: const ColorScheme.dark(
        primary: primaryColor,
        secondary: secondaryColor,
        surface: backgroundColor,
        onSurface: textPrimary,
        surfaceContainer: surfaceColor,
      ),
      scaffoldBackgroundColor: backgroundColor,
      cardTheme: CardThemeData(
        color: surfaceColor,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: backgroundColor,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w500,
          fontFamily: 'VarelaRound',
        ),
      ),
      navigationRailTheme: const NavigationRailThemeData(
        backgroundColor: backgroundColor,
        indicatorColor: Colors.transparent,
        useIndicator: false,
        selectedIconTheme: IconThemeData(color: primaryColor),
        unselectedIconTheme: IconThemeData(color: textSecondary),
        selectedLabelTextStyle: TextStyle(color: primaryColor, fontSize: 12, fontFamily: 'VarelaRound'),
        unselectedLabelTextStyle: TextStyle(color: textSecondary, fontSize: 12, fontFamily: 'VarelaRound'),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: backgroundColor,
        selectedItemColor: primaryColor,
        unselectedItemColor: textSecondary,
        elevation: 0,
        showSelectedLabels: true,
        showUnselectedLabels: true,
        type: BottomNavigationBarType.fixed,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          splashFactory: NoSplash.splashFactory,
          elevation: 0,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          splashFactory: NoSplash.splashFactory,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          splashFactory: NoSplash.splashFactory,
        ),
      ),
    );

    return baseTheme.copyWith(
      textTheme: baseTheme.textTheme.apply(
        fontFamily: 'VarelaRound',
        bodyColor: textPrimary,
        displayColor: textPrimary,
      ).copyWith(
        displayLarge: const TextStyle(color: textPrimary, fontFamily: 'VarelaRound'),
        titleLarge: const TextStyle(color: textPrimary, fontWeight: FontWeight.w500, fontFamily: 'VarelaRound'),
        titleMedium: const TextStyle(color: textPrimary, fontFamily: 'VarelaRound'),
        titleSmall: const TextStyle(color: textSecondary, fontFamily: 'VarelaRound'),
        bodyLarge: const TextStyle(color: textPrimary, fontFamily: 'VarelaRound'),
        bodyMedium: const TextStyle(color: textSecondary, fontFamily: 'VarelaRound'),
        labelSmall: const TextStyle(color: textMuted, fontFamily: 'VarelaRound'),
      ),
    );
  }
}
