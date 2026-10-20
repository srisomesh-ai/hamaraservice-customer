import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Brand palette. Screens should prefer `Theme.of(context).colorScheme`;
/// these constants are for status colours and the few brand accents that
/// have no Material role.
class AppColors {
  static const brand     = Color(0xFFE8651A); // orange — secondary
  static const brand2    = Color(0xFFC9510F);
  static const brandSoft = Color(0xFFFFF3EB);
  static const teal      = Color(0xFF1B6B7A); // primary
  static const teal2     = Color(0xFF134F5C);
  static const tealSoft  = Color(0xFFE6F4F6);
  static const ink       = Color(0xFF1A1C1E);
  static const ink2      = Color(0xFF3F484A);
  static const muted     = Color(0xFF6F797A);
  static const line      = Color(0xFFDDE4E5);
  static const bg        = Color(0xFFF6F9FA);
  static const white     = Color(0xFFFFFFFF);
  static const green     = Color(0xFF1E8E4E);
  static const greenSoft = Color(0xFFE6F4EA);
  static const yellow    = Color(0xFFB26A00);
  static const yellowSoft= Color(0xFFFFF4E0);
  static const red       = Color(0xFFC62828);
  static const redSoft   = Color(0xFFFDECEC);
}

/// Standard spacing (Material 4-dp grid).
class Gap {
  static const double page = 16;
}

class AppTheme {
  static const SystemUiOverlayStyle overlay = SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
    statusBarBrightness: Brightness.light,
    systemNavigationBarColor: Colors.white,
    systemNavigationBarIconBrightness: Brightness.dark,
  );

  static ColorScheme get scheme => ColorScheme.fromSeed(
        seedColor: AppColors.teal,
        primary: AppColors.teal,
        onPrimary: Colors.white,
        primaryContainer: const Color(0xFFCDEBF0),
        onPrimaryContainer: const Color(0xFF00363F),
        secondary: AppColors.brand,
        onSecondary: Colors.white,
        secondaryContainer: const Color(0xFFFFDBCA),
        onSecondaryContainer: const Color(0xFF341000),
        surface: Colors.white,
        background: AppColors.bg,
        error: AppColors.red,
      );

  static ThemeData get theme {
    final cs = scheme;
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: cs,
      fontFamily: 'Roboto',
      visualDensity: VisualDensity.standard,
    );
    final text = base.textTheme.apply(
      bodyColor: AppColors.ink,
      displayColor: AppColors.ink,
    );
    final shape12 = RoundedRectangleBorder(borderRadius: BorderRadius.circular(12));
    return base.copyWith(
      scaffoldBackgroundColor: AppColors.bg,
      textTheme: text.copyWith(
        titleLarge: text.titleLarge?.copyWith(fontWeight: FontWeight.w600),
        titleMedium: text.titleMedium?.copyWith(fontWeight: FontWeight.w600),
        titleSmall: text.titleSmall?.copyWith(fontWeight: FontWeight.w600),
        labelLarge: text.labelLarge?.copyWith(fontWeight: FontWeight.w600),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        foregroundColor: AppColors.ink,
        elevation: 0,
        scrolledUnderElevation: 2,
        shadowColor: Colors.black26,
        centerTitle: false,
        systemOverlayStyle: overlay,
        titleTextStyle: text.titleLarge?.copyWith(
            fontWeight: FontWeight.w600, color: AppColors.ink),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        height: 72,
        indicatorColor: cs.primaryContainer,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: MaterialStateProperty.resolveWith((s) =>
            text.labelMedium?.copyWith(
              fontWeight: s.contains(MaterialState.selected)
                  ? FontWeight.w700
                  : FontWeight.w500,
              color: s.contains(MaterialState.selected)
                  ? AppColors.teal2
                  : AppColors.muted,
            )),
        iconTheme: MaterialStateProperty.resolveWith((s) => IconThemeData(
              color: s.contains(MaterialState.selected)
                  ? AppColors.teal2
                  : AppColors.muted,
            )),
      ),
      cardTheme: CardTheme(
        color: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.line),
        ),
      ),
      listTileTheme: const ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(horizontal: 16),
        iconColor: AppColors.ink2,
      ),
      dividerTheme: const DividerThemeData(color: AppColors.line, space: 1, thickness: 1),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(64, 52),
          shape: shape12,
          textStyle: text.labelLarge?.copyWith(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(64, 52),
          shape: shape12,
          side: const BorderSide(color: AppColors.line),
          textStyle: text.labelLarge?.copyWith(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.teal,
          foregroundColor: Colors.white,
          minimumSize: const Size(64, 52),
          shape: shape12,
          elevation: 0,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          textStyle: text.labelLarge?.copyWith(fontWeight: FontWeight.w600),
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: Colors.white,
        selectedColor: cs.primaryContainer,
        side: const BorderSide(color: AppColors.line),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        labelStyle: text.labelLarge?.copyWith(color: AppColors.ink2),
        secondaryLabelStyle: text.labelLarge?.copyWith(color: cs.onPrimaryContainer),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          visualDensity: VisualDensity.standard,
          textStyle: MaterialStatePropertyAll(
              text.labelLarge?.copyWith(fontWeight: FontWeight.w600)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
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
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFF263238),
        contentTextStyle: text.bodyMedium?.copyWith(color: Colors.white),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      dialogTheme: DialogTheme(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        showDragHandle: true,
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(color: AppColors.teal),
    );
  }
}

class AppConstants {
  static const firebaseDbUrl =
      'https://hamaraservice-s009-default-rtdb.asia-southeast1.firebasedatabase.app';
  static const appName = 'HamaraService';
  static const website = 'https://hamaraservice.com';
  static const contactEmail = 'info@hamaraservice.com';
}

/// SnackBar helper used across screens (replaces custom toasts).
void showSnack(BuildContext context, String message,
    {bool error = false, bool success = false}) {
  final m = ScaffoldMessenger.maybeOf(context);
  if (m == null) return;
  m.hideCurrentSnackBar();
  m.showSnackBar(SnackBar(
    content: Row(children: [
      Icon(
          error
              ? Icons.error_outline_rounded
              : success
                  ? Icons.check_circle_outline_rounded
                  : Icons.info_outline_rounded,
          color: error
              ? const Color(0xFFFFB4AB)
              : success
                  ? const Color(0xFF8CE0A8)
                  : Colors.white70,
          size: 20),
      const SizedBox(width: 12),
      Expanded(child: Text(message)),
    ]),
  ));
}
