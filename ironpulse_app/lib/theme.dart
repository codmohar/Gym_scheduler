import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  static const Color background = Color(0xFF0F131D);
  static const Color surfaceLowest = Color(0xFF0A0E18);
  static const Color surface = Color(0xFF171B26);
  static const Color surfaceHigh = Color(0xFF262A35);
  static const Color surfaceHighest = Color(0xFF313540);
  
  static const Color primary = Color(0xFFFFC174);
  static const Color primaryContainer = Color(0xFFF59E0B);
  static const Color onPrimary = Color(0xFF472A00);
  
  static const Color secondary = Color(0xFF4EDEA3);
  static const Color secondaryContainer = Color(0xFF00A572);
  static const Color onSecondary = Color(0xFF003824);
  
  static const Color tertiary = Color(0xFF8ED5FF);
  static const Color tertiaryContainer = Color(0xFF38BDF8);
  static const Color onTertiary = Color(0xFF00354A);
  
  static const Color textMain = Color(0xFFDFE2F1);
  static const Color textMuted = Color(0xFF9CA3AF);
  static const Color error = Color(0xFFFFB4AB);

  static ThemeData get darkTheme {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: background,
      colorScheme: const ColorScheme.dark(
        surface: surface,
        primary: primaryContainer,
        secondary: secondary,
        error: error,
        onSurface: textMain,
      ),
      textTheme: GoogleFonts.interTextTheme(
        ThemeData.dark().textTheme.apply(
          bodyColor: textMain,
          displayColor: textMain,
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: background,
        elevation: 0,
        centerTitle: false,
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: surfaceLowest,
        selectedItemColor: primaryContainer,
        unselectedItemColor: textMuted,
        type: BottomNavigationBarType.fixed,
        elevation: 10,
      ),
    );
  }
}
