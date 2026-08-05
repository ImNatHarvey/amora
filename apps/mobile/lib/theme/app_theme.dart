import 'package:flutter/material.dart';

import 'app_tokens.dart';

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

  /// The dark scheme's error family, moved off Material's default red.
  ///
  /// `ColorScheme.fromSeed` derives `error` from a fixed red hue, and in the
  /// dark scheme it lightens to `#FFB4AB` — which lands next to this seed's
  /// `primary` at `#FFB1C6`, about 27/255 apart on one channel. Two roles that
  /// must never be confused became neighbours, and Phase 4 renders money in
  /// colour where an over-budget total has to be unmistakable.
  ///
  /// These are the Material tonal steps (80 / 20 / 30 / 90) of an orange-red
  /// hue rather than hand-picked colours, so the family still behaves like a
  /// Material palette. The fix is a *hue* separation, not a lightness one: at
  /// tone 80 both roles are equally light by construction, so the thing that
  /// tells them apart is that error now runs green-over-blue (`G182 B143`)
  /// where primary runs blue-over-green (`G177 B198`). The old red sat almost
  /// neutral between them, which is why it read as a decorative accent.
  ///
  /// **Light mode is deliberately untouched.** There `primary #8C4A5F` and
  /// `error #BA1A1A` are already far apart, and changing a working scheme to
  /// match a broken one is churn. A user only ever sees one mode.
  ///
  /// Colour is still not enough on its own — it fails for red-green colourblind
  /// users regardless of hue — which is why [AmoraTokens.costOverBudgetIcon]
  /// exists and why `docs/02-design-system.md` §2 requires it.
  static const Color _darkError = Color(0xFFFFB68F);
  static const Color _darkOnError = Color(0xFF562200);
  static const Color _darkErrorContainer = Color(0xFF723300);
  static const Color _darkOnErrorContainer = Color(0xFFFFDBCA);

  static ThemeData _themeFrom(Brightness brightness) {
    var colorScheme = ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: brightness,
    );

    if (brightness == Brightness.dark) {
      colorScheme = colorScheme.copyWith(
        error: _darkError,
        onError: _darkOnError,
        errorContainer: _darkErrorContainer,
        onErrorContainer: _darkOnErrorContainer,
      );
    }

    // No `fontFamily`: the MVP uses the system font (design system §3).
    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      // Amora's own spacing, radius and budget-colour tokens, read at call
      // sites as `Theme.of(context).tokens`.
      extensions: [AmoraTokens.fromColorScheme(colorScheme)],
    );
  }
}
