import 'package:flutter/material.dart';

/// Needly's shared visual language, mapped to Flutter's Material 3 components.
abstract final class AppTheme {
  static const Color _lightSurface = Color(0xFFF8F9FF);
  static const Color _lightText = Color(0xFF131C26);
  static const Color _lightSecondaryText = Color(0xFF5C6470);
  static const Color _lightOutline = Color(0xFFE6E2DE);
  static const Color _lightPrimary = Color(0xFF7B5800);
  static const Color _lightPrimaryContainer = Color(0xFFF5B82E);
  static const Color _lightSecondary = Color(0xFF006C45);

  static const Color _darkSurface = Color(0xFF16140D);
  static const Color _darkText = Color(0xFFECE9DF);
  static const Color _darkSecondaryText = Color(0xFFCFC6B5);
  static const Color _darkOutline = Color(0xFF4C463A);
  static const Color _darkPrimary = Color(0xFFF5B82E);
  static const Color _darkPrimaryContainer = Color(0xFF5D4200);
  static const Color _darkSecondary = Color(0xFF69DCA1);

  static final ThemeData light = _buildTheme(
    colorScheme: const ColorScheme(
      brightness: Brightness.light,
      primary: _lightPrimary,
      onPrimary: Colors.white,
      primaryContainer: _lightPrimaryContainer,
      onPrimaryContainer: Color(0xFF684A00),
      secondary: _lightSecondary,
      onSecondary: Colors.white,
      secondaryContainer: Color(0xFF86F9BC),
      onSecondaryContainer: Color(0xFF00734A),
      tertiary: Color(0xFF815600),
      onTertiary: Colors.white,
      tertiaryContainer: Color(0xFFFDB436),
      onTertiaryContainer: Color(0xFF6D4800),
      error: Color(0xFFBA1A1A),
      onError: Colors.white,
      errorContainer: Color(0xFFFFDAD6),
      onErrorContainer: Color(0xFF93000A),
      surface: _lightSurface,
      onSurface: _lightText,
      onSurfaceVariant: Color(0xFF504534),
      outline: Color(0xFF827561),
      outlineVariant: Color(0xFFD4C4AD),
      shadow: Colors.black,
      scrim: Colors.black,
      inverseSurface: Color(0xFF28313C),
      onInverseSurface: Color(0xFFE9F1FF),
      inversePrimary: Color(0xFFFABC33),
      surfaceTint: _lightPrimary,
    ),
  );

  static final ThemeData dark = _buildTheme(
    colorScheme: const ColorScheme(
      brightness: Brightness.dark,
      primary: _darkPrimary,
      onPrimary: Color(0xFF3F2B00),
      primaryContainer: _darkPrimaryContainer,
      onPrimaryContainer: Color(0xFFFFDFA3),
      secondary: _darkSecondary,
      onSecondary: Color(0xFF00391F),
      secondaryContainer: Color(0xFF005233),
      onSecondaryContainer: Color(0xFF86F9BC),
      tertiary: Color(0xFFFFBA49),
      onTertiary: Color(0xFF452A00),
      tertiaryContainer: Color(0xFF614000),
      onTertiaryContainer: Color(0xFFFFDDB1),
      error: Color(0xFFFFB4AB),
      onError: Color(0xFF690005),
      errorContainer: Color(0xFF93000A),
      onErrorContainer: Color(0xFFFFDAD6),
      surface: _darkSurface,
      onSurface: _darkText,
      onSurfaceVariant: _darkSecondaryText,
      outline: Color(0xFF98917F),
      outlineVariant: _darkOutline,
      shadow: Colors.black,
      scrim: Colors.black,
      inverseSurface: Color(0xFF28313C),
      onInverseSurface: Color(0xFFE9F1FF),
      inversePrimary: _lightPrimary,
      surfaceTint: _darkPrimary,
    ),
  );

  static ThemeData _buildTheme({required ColorScheme colorScheme}) {
    final isLight = colorScheme.brightness == Brightness.light;
    final surface = isLight ? _lightSurface : _darkSurface;
    final inputSurface = isLight ? Colors.white : const Color(0xFF0D0C06);
    final outline = isLight ? _lightOutline : _darkOutline;
    final secondaryText = isLight ? _lightSecondaryText : _darkSecondaryText;

    final baseTextTheme = ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
    ).textTheme;
    final textTheme = baseTextTheme.copyWith(
      displayLarge: const TextStyle(
        fontSize: 32,
        height: 1.25,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.64,
      ),
      headlineLarge: const TextStyle(
        fontSize: 28,
        height: 1.22,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.28,
      ),
      headlineMedium: const TextStyle(
        fontSize: 24,
        height: 1.25,
        fontWeight: FontWeight.w700,
      ),
      titleLarge: const TextStyle(
        fontSize: 20,
        height: 1.3,
        fontWeight: FontWeight.w600,
      ),
      titleMedium: const TextStyle(
        fontSize: 17,
        height: 1.4,
        fontWeight: FontWeight.w500,
      ),
      bodyLarge: const TextStyle(fontSize: 17, height: 1.42),
      bodyMedium: const TextStyle(fontSize: 16, height: 1.38),
      bodySmall: const TextStyle(fontSize: 14, height: 1.43),
      labelLarge: const TextStyle(
        fontSize: 15,
        height: 1.35,
        fontWeight: FontWeight.w600,
      ),
      labelMedium: const TextStyle(
        fontSize: 12,
        height: 1.33,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.24,
      ),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: colorScheme.brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: surface,
      fontFamily: 'Inter',
      textTheme: textTheme.apply(fontFamily: 'Inter'),
      appBarTheme: AppBarTheme(
        backgroundColor: surface,
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        toolbarHeight: 60,
        titleTextStyle: textTheme.titleLarge?.copyWith(
          color: colorScheme.onSurface,
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: inputSurface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        labelStyle: TextStyle(color: colorScheme.onSurface),
        hintStyle: TextStyle(color: secondaryText),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colorScheme.primaryContainer, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colorScheme.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colorScheme.error, width: 2),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 56),
          padding: const EdgeInsets.symmetric(horizontal: 24),
          backgroundColor: colorScheme.primaryContainer,
          foregroundColor: colorScheme.onPrimaryContainer,
          disabledBackgroundColor: colorScheme.primaryContainer.withValues(
            alpha: 0.5,
          ),
          disabledForegroundColor: colorScheme.onPrimaryContainer.withValues(
            alpha: 0.6,
          ),
          textStyle: textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(48, 48),
          foregroundColor: colorScheme.onSurface,
          side: BorderSide(color: colorScheme.outline),
          textStyle: textTheme.labelLarge,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: colorScheme.primary,
          textStyle: textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      cardTheme: CardThemeData(
        color: inputSurface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: outline),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: inputSurface,
        selectedColor: colorScheme.primaryContainer,
        side: BorderSide(color: outline),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        labelStyle: textTheme.labelMedium?.copyWith(
          color: colorScheme.onSurface,
        ),
        secondaryLabelStyle: textTheme.labelMedium?.copyWith(
          color: colorScheme.onPrimaryContainer,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: inputSurface,
        indicatorColor: colorScheme.primaryContainer.withValues(alpha: 0.48),
        elevation: 0,
        labelTextStyle: WidgetStatePropertyAll(
          textTheme.labelMedium?.copyWith(color: colorScheme.onSurface),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: colorScheme.primaryContainer,
        foregroundColor: colorScheme.onPrimaryContainer,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      dividerTheme: DividerThemeData(color: outline, thickness: 1, space: 1),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: colorScheme.inverseSurface,
        contentTextStyle: TextStyle(color: colorScheme.onInverseSurface),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: inputSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: inputSurface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: colorScheme.secondary,
      ),
    );
  }
}
