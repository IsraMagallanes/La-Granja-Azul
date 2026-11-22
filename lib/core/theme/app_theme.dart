import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Tema único de la aplicación: claro, azul y blanco. No hay tema oscuro.
abstract final class AppTheme {
  static const double radius = 14;

  static ThemeData get light {
    final scheme =
        ColorScheme.fromSeed(
          seedColor: AppColors.blue,
          brightness: Brightness.light,
        ).copyWith(
          primary: AppColors.blue,
          onPrimary: AppColors.white,
          primaryContainer: AppColors.blueSoft,
          onPrimaryContainer: AppColors.blueDark,
          surface: AppColors.white,
          onSurface: AppColors.ink,
          onSurfaceVariant: AppColors.inkMuted,
          surfaceContainerLowest: AppColors.white,
          surfaceContainerLow: AppColors.blueMist,
          surfaceContainer: AppColors.blueMist,
          surfaceContainerHigh: AppColors.blueSoft,
          outline: AppColors.line,
          outlineVariant: AppColors.line,
        );
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radius),
    );
    OutlineInputBorder border(Color color, [double width = 1]) =>
        OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: color, width: width),
        );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.blueMist,
      textTheme: Typography.material2021().black.apply(
        bodyColor: AppColors.ink,
        displayColor: AppColors.ink,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.navy,
        foregroundColor: AppColors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
      ),
      tabBarTheme: const TabBarThemeData(
        labelColor: AppColors.blue,
        unselectedLabelColor: AppColors.inkMuted,
        indicatorColor: AppColors.blue,
        dividerColor: AppColors.line,
        labelStyle: TextStyle(fontWeight: FontWeight.w700),
      ),
      dataTableTheme: const DataTableThemeData(
        headingTextStyle: TextStyle(
          color: AppColors.inkMuted,
          fontWeight: FontWeight.w600,
          fontSize: 13,
        ),
        dividerThickness: 1,
      ),
      listTileTheme: const ListTileThemeData(
        iconColor: AppColors.blue,
        contentPadding: EdgeInsets.symmetric(horizontal: 16),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.blue,
        foregroundColor: AppColors.white,
      ),
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: AppColors.navy,
        contentTextStyle: TextStyle(color: AppColors.white),
        behavior: SnackBarBehavior.floating,
      ),
      cardTheme: CardThemeData(
        color: AppColors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius),
          side: const BorderSide(color: AppColors.line),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.white,
        border: border(AppColors.line),
        enabledBorder: border(AppColors.line),
        focusedBorder: border(AppColors.blue, 2),
        errorBorder: border(scheme.error),
        focusedErrorBorder: border(scheme.error, 2),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.blue,
          foregroundColor: AppColors.white,
          minimumSize: const Size(64, 48),
          shape: shape,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.blue,
          foregroundColor: AppColors.white,
          minimumSize: const Size(64, 48),
          shape: shape,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.blue,
          minimumSize: const Size(64, 48),
          side: const BorderSide(color: AppColors.blue),
          shape: shape,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: AppColors.blue),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.blueSoft,
        side: BorderSide.none,
        labelStyle: const TextStyle(
          color: AppColors.blueDark,
          fontWeight: FontWeight.w600,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.white,
        surfaceTintColor: Colors.transparent,
        shape: shape,
      ),
      dividerTheme: const DividerThemeData(color: AppColors.line, space: 1),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.blue,
      ),
    );
  }
}
