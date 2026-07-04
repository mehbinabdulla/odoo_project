import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  // Primary brand (Nothing Red)
  static const Color primary = Color(0xFFEA3E36);
  static const Color primaryLight = Color(0xFFFF6D66);
  static const Color primaryDark = Color(0xFFC02A24);
  static const Color primarySurface = Color(0xFF2A0A08);

  // Accents
  static const Color accent = Color(0xFF333333);
  static const Color accentOrange = Color(0xFFFF7043);
  static const Color accentYellow = Color(0xFFFFB300);
  static const Color accentBlue = Color(0xFF29B6F6);
  static const Color accentPink = Color(0xFFEC407A);

  // Dark theme
  static const Color darkBg = Color(0xFF000000);
  static const Color darkSurface = Color(0xFF000000);
  static const Color darkCard = Color(0xFF141414);
  static const Color darkCardElevated = Color(0xFF1F1F1F);
  static const Color darkBorder = Color(0xFF262626);
  static const Color darkTextPrimary = Color(0xFFFFFFFF);
  static const Color darkTextSecondary = Color(0xFFAAAAAA);
  static const Color darkTextMuted = Color(0xFF666666);

  // Light theme
  static const Color lightBg = Color(0xFFF4F4F4);
  static const Color lightSurface = Color(0xFFF4F4F4);
  static const Color lightCard = Color(0xFFEBEBEB);
  static const Color lightCardElevated = Color(0xFFFFFFFF);
  static const Color lightBorder = Color(0xFFDBDBDB);
  static const Color lightTextPrimary = Color(0xFF000000);
  static const Color lightTextSecondary = Color(0xFF555555);
  static const Color lightTextMuted = Color(0xFF888888);

  // Status colors
  static const Color statusDone = Color(0xFF00C853);
  static const Color statusInProgress = Color(0xFF29B6F6);
  static const Color statusBlocked = Color(0xFFEA3E36);
  static const Color statusTodo = Color(0xFFBDBDBD);
  static const Color statusReview = Color(0xFFFFB300);

  // Gradient pairs
  static const List<Color> gradientPurple = [Color(0xFFEA3E36), Color(0xFFFF6D66)];
  static const List<Color> gradientTeal = [Color(0xFF333333), Color(0xFF555555)];
  static const List<Color> gradientOrange = [Color(0xFFFF7043), Color(0xFFFFB300)];
  static const List<Color> gradientPink = [Color(0xFFEC407A), Color(0xFFAB47BC)];
  static const List<Color> gradientGreen = [Color(0xFF00C853), Color(0xFFB9F6CA)];
  static const List<Color> gradientRed = [Color(0xFFEA3E36), Color(0xFFFF8A80)];
}

class AppTheme {
  static TextTheme _buildTextTheme(Color primary, Color secondary, Color muted) {
    return TextTheme(
      displayLarge: GoogleFonts.poppins(
        fontSize: 57, fontWeight: FontWeight.w700, color: primary,
      ),
      displayMedium: GoogleFonts.poppins(
        fontSize: 45, fontWeight: FontWeight.w700, color: primary,
      ),
      displaySmall: GoogleFonts.poppins(
        fontSize: 36, fontWeight: FontWeight.w600, color: primary,
      ),
      headlineLarge: GoogleFonts.poppins(
        fontSize: 32, fontWeight: FontWeight.w700, color: primary,
      ),
      headlineMedium: GoogleFonts.poppins(
        fontSize: 28, fontWeight: FontWeight.w600, color: primary,
      ),
      headlineSmall: GoogleFonts.poppins(
        fontSize: 24, fontWeight: FontWeight.w600, color: primary,
      ),
      titleLarge: GoogleFonts.poppins(
        fontSize: 22, fontWeight: FontWeight.w600, color: primary,
      ),
      titleMedium: GoogleFonts.poppins(
        fontSize: 16, fontWeight: FontWeight.w600, color: primary,
      ),
      titleSmall: GoogleFonts.poppins(
        fontSize: 14, fontWeight: FontWeight.w500, color: primary,
      ),
      bodyLarge: GoogleFonts.poppins(
        fontSize: 16, fontWeight: FontWeight.w400, color: secondary,
      ),
      bodyMedium: GoogleFonts.poppins(
        fontSize: 14, fontWeight: FontWeight.w400, color: secondary,
      ),
      bodySmall: GoogleFonts.poppins(
        fontSize: 12, fontWeight: FontWeight.w400, color: muted,
      ),
      labelLarge: GoogleFonts.poppins(
        fontSize: 14, fontWeight: FontWeight.w600, letterSpacing: 0.5,
      ),
      labelMedium: GoogleFonts.poppins(
        fontSize: 12, fontWeight: FontWeight.w500, letterSpacing: 0.5,
      ),
      labelSmall: GoogleFonts.poppins(
        fontSize: 11, fontWeight: FontWeight.w500, letterSpacing: 0.5,
      ),
    );
  }

  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: AppColors.darkBg,
      colorScheme: const ColorScheme.dark(
        primary: AppColors.primary,
        primaryContainer: AppColors.primaryDark,
        secondary: AppColors.accent,
        secondaryContainer: Color(0xFF003929),
        surface: AppColors.darkSurface,
        error: AppColors.statusBlocked,
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onSurface: AppColors.darkTextPrimary,
        onError: Colors.white,
        outline: AppColors.darkBorder,
        surfaceContainerHighest: AppColors.darkCard,
        surfaceContainerLow: AppColors.darkCardElevated,
      ),
      textTheme: _buildTextTheme(
        AppColors.darkTextPrimary,
        AppColors.darkTextSecondary,
        AppColors.darkTextMuted,
      ),
      cardTheme: CardThemeData(
        color: AppColors.darkCard,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide.none,
        ),
        margin: EdgeInsets.zero,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.darkBg,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: GoogleFonts.dmSerifDisplay(
          fontSize: 32,
          color: AppColors.darkTextPrimary,
        ),
        iconTheme: const IconThemeData(color: AppColors.darkTextPrimary),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.darkSurface,
        indicatorColor: AppColors.primary.withValues(alpha: 0.2),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return GoogleFonts.poppins(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AppColors.primary,
            );
          }
          return GoogleFonts.poppins(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: AppColors.darkTextMuted,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const IconThemeData(color: AppColors.primary, size: 24);
          }
          return const IconThemeData(color: AppColors.darkTextMuted, size: 24);
        }),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.darkCard,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.darkBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.darkBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.statusBlocked, width: 1.5),
        ),
        labelStyle: GoogleFonts.poppins(color: AppColors.darkTextSecondary),
        hintStyle: GoogleFonts.poppins(color: AppColors.darkTextMuted),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primary,
          side: const BorderSide(color: AppColors.primary),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.darkCardElevated,
        selectedColor: AppColors.darkTextPrimary,
        labelStyle: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.darkTextSecondary),
        secondaryLabelStyle: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.darkBg),
        side: BorderSide.none,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.darkBorder,
        thickness: 1,
        space: 1,
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 4,
        shape: CircleBorder(),
      ),
    );
  }

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: AppColors.lightBg,
      colorScheme: const ColorScheme.light(
        primary: AppColors.primary,
        primaryContainer: AppColors.primarySurface,
        secondary: AppColors.accent,
        secondaryContainer: Color(0xFFB2F2E6),
        surface: AppColors.lightSurface,
        error: AppColors.statusBlocked,
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onSurface: AppColors.lightTextPrimary,
        onError: Colors.white,
        outline: AppColors.lightBorder,
        surfaceContainerHighest: AppColors.lightCard,
        surfaceContainerLow: Color(0xFFF8F8FF),
      ),
      textTheme: _buildTextTheme(
        AppColors.lightTextPrimary,
        AppColors.lightTextSecondary,
        AppColors.lightTextMuted,
      ),
      cardTheme: CardThemeData(
        color: AppColors.lightCard,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide.none,
        ),
        margin: EdgeInsets.zero,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.lightBg,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: GoogleFonts.dmSerifDisplay(
          fontSize: 32,
          color: AppColors.lightTextPrimary,
        ),
        iconTheme: const IconThemeData(color: AppColors.lightTextPrimary),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.lightSurface,
        indicatorColor: AppColors.primary.withValues(alpha: 0.12),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return GoogleFonts.poppins(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AppColors.primary,
            );
          }
          return GoogleFonts.poppins(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: AppColors.lightTextMuted,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const IconThemeData(color: AppColors.primary, size: 24);
          }
          return const IconThemeData(color: AppColors.lightTextMuted, size: 24);
        }),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.lightCard,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.lightBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.lightBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.statusBlocked, width: 1.5),
        ),
        labelStyle: GoogleFonts.poppins(color: AppColors.lightTextSecondary),
        hintStyle: GoogleFonts.poppins(color: AppColors.lightTextMuted),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primary,
          side: const BorderSide(color: AppColors.primary),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.lightCard,
        selectedColor: AppColors.lightTextPrimary,
        labelStyle: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.lightTextSecondary),
        secondaryLabelStyle: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.lightBg),
        side: BorderSide.none,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.lightBorder,
        thickness: 1,
        space: 1,
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 4,
        shape: CircleBorder(),
      ),
    );
  }
}
