import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// 경륜 앱 테마 - 경마 Plus 스타일 (다크, 골드/노란 액센트)
class AppTheme {
  static const Color _primary = Color(0xFF22C55E);
  static const Color _accent = Color(0xFFFBBF24);
  static const Color _surfaceDark = Color(0xFF0D1117);
  static const Color _cardDark = Color(0xFF161B22);
  static const Color _cardLight = Color(0xFFF6F8FA);

  static ThemeData get light {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: ColorScheme.light(
        primary: _primary,
        onPrimary: Colors.white,
        secondary: _accent,
        surface: Colors.white,
        onSurface: const Color(0xFF1F2937),
        surfaceContainerHighest: _cardLight,
      ),
      scaffoldBackgroundColor: const Color(0xFFF0F4F8),
      appBarTheme: AppBarTheme(
        elevation: 0,
        centerTitle: true,
        backgroundColor: _primary,
        foregroundColor: Colors.white,
        titleTextStyle: GoogleFonts.notoSansKr(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 2,
        shadowColor: Colors.black12,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        color: Colors.white,
      ),
      textTheme: GoogleFonts.notoSansKrTextTheme().copyWith(
        headlineMedium: GoogleFonts.notoSansKr(
          fontWeight: FontWeight.w700,
          color: const Color(0xFF1F2937),
        ),
        titleMedium: GoogleFonts.notoSansKr(
          fontWeight: FontWeight.w600,
          color: const Color(0xFF374151),
        ),
        bodyMedium: GoogleFonts.notoSansKr(
          color: const Color(0xFF6B7280),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: _primary,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: GoogleFonts.notoSansKr(
            fontWeight: FontWeight.w600,
            fontSize: 15,
          ),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: _primary.withValues(alpha: 0.15),
        labelStyle: GoogleFonts.notoSansKr(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: _primary,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }

  static ThemeData get dark {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: ColorScheme.dark(
        primary: _primary,
        onPrimary: Colors.white,
        secondary: _accent,
        surface: _surfaceDark,
        onSurface: Colors.white,
        surfaceContainerHighest: _cardDark,
      ),
      scaffoldBackgroundColor: _surfaceDark,
      appBarTheme: AppBarTheme(
        elevation: 0,
        centerTitle: true,
        backgroundColor: _surfaceDark,
        foregroundColor: Colors.white,
        titleTextStyle: GoogleFonts.notoSansKr(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFF30363D), width: 1),
        ),
        color: _cardDark,
      ),
      textTheme: GoogleFonts.notoSansKrTextTheme(ThemeData.dark().textTheme).copyWith(
        headlineMedium: GoogleFonts.notoSansKr(
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
        titleMedium: GoogleFonts.notoSansKr(
          fontWeight: FontWeight.w600,
          color: const Color(0xFFE6EDF3),
        ),
        bodyMedium: GoogleFonts.notoSansKr(
          color: const Color(0xFF8B949E),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: _primary,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: GoogleFonts.notoSansKr(
            fontWeight: FontWeight.w600,
            fontSize: 15,
          ),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: _primary.withValues(alpha: 0.2),
        labelStyle: GoogleFonts.notoSansKr(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: _primary,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }
}
