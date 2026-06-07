// ignore_for_file: duplicate_import
import 'package:flutter/material.dart' show ThemeData, ColorScheme, Color, AppBarTheme, ElevatedButtonThemeData, ElevatedButton, RoundedRectangleBorder, BorderRadius, InputDecorationTheme, OutlineInputBorder, BorderSide, EdgeInsets, Size, TextStyle, FontWeight, Colors;

class AppColors {
  static const brand     = Color(0xFFE8651A);
  static const brand2    = Color(0xFFC9510F);
  static const brandSoft = Color(0xFFFFF3EB);
  static const teal      = Color(0xFF1B6B7A);
  static const teal2     = Color(0xFF134F5C);
  static const tealSoft  = Color(0xFFE6F4F6);
  static const ink       = Color(0xFF1A1A2E);
  static const ink2      = Color(0xFF2D3748);
  static const muted     = Color(0xFF718096);
  static const line      = Color(0xFFE2E8F0);
  static const bg        = Color(0xFFF0F7F9);
  static const white     = Color(0xFFFFFFFF);
  static const green     = Color(0xFF2ECC71);
  static const greenSoft = Color(0xFFE8F8F0);
  static const yellow    = Color(0xFFF59E0B);
  static const red       = Color(0xFFE53E3E);
}

class AppTheme {
  static ThemeData get theme => ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.brand,
      primary: AppColors.brand,
      secondary: AppColors.teal,
      surface: AppColors.white,
    ),
    scaffoldBackgroundColor: AppColors.bg,
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.teal,
      foregroundColor: AppColors.white,
      elevation: 0,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.brand,
        foregroundColor: AppColors.white,
        minimumSize: const Size(double.infinity, 52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        elevation: 0,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.teal, width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    ),
  );
}

class AppConstants {
  static const firebaseDbUrl =
      'https://hamaraservice-s009-default-rtdb.asia-southeast1.firebasedatabase.app';
  static const appName = 'HamaraService';
}      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.teal, width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      hintStyle: GoogleFonts.sora(color: AppColors.muted, fontSize: 14),
    ),
    cardTheme: CardTheme(
      color: AppColors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.line),
      ),
      margin: EdgeInsets.zero,
    ),
  );
}

class AppConstants {
  static const firebaseDbUrl =
      'https://hamaraservice-s009-default-rtdb.asia-southeast1.firebasedatabase.app';
  static const appName = 'HamaraService';
  static const supportPhone = '+919999999999';
}
