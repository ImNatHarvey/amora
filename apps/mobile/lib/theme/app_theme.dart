import 'package:flutter/material.dart';

/// Amora's Material 3 theme.
///
/// The whole colour system is derived at runtime from a single seed by
/// [ColorScheme.fromSeed], which runs the same Material 3 tonal-palette
/// algorithm the Material Theme Builder uses. Changing the brand colour means
/// changing [seedColor] and nothing else.
///
/// See `docs/02-design-system.md` §2 (colour) and §3 (typography).
abstract final class AppTheme {
  /// Deep rose. See `docs/02-design-system.md` §2 for the rationale.
  static const Color seedColor = Color(0xFFB4436C);

  static ThemeData get light => _themeFrom(Brightness.light);

  static ThemeData get dark => _themeFrom(Brightness.dark);

  static ThemeData _themeFrom(Brightness brightness) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: brightness,
    );

    // No `fontFamily`: the MVP uses the system font (design system §3).
    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
    );
  }
}
