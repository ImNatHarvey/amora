import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

/// Amora's own design tokens, carried on [ThemeData] as a [ThemeExtension].
///
/// A `ThemeExtension` is Flutter's supported way to attach custom values to the
/// theme, so widgets read them through `Theme.of(context)` exactly like built-in
/// Material tokens. Two things fall out of that: there are no global constants
/// to import, and the colour tokens swap automatically between light and dark
/// because they are resolved from the active [ColorScheme].
///
/// Read them through the [AmoraThemeX.tokens] getter:
///
/// ```dart
/// final tokens = Theme.of(context).tokens;
/// Padding(padding: EdgeInsets.all(tokens.md), child: child);
/// ```
///
/// See `docs/02-design-system.md` §4 (spacing and shape) and §2 (budget colour
/// semantics).
@immutable
class AmoraTokens extends ThemeExtension<AmoraTokens> {
  const AmoraTokens({
    required this.xs,
    required this.sm,
    required this.md,
    required this.lg,
    required this.xl,
    required this.xxl,
    required this.radiusSmall,
    required this.radiusMedium,
    required this.radiusLarge,
    required this.costFree,
    required this.costNormal,
    required this.costOverBudget,
    this.costOverBudgetIcon = Icons.error_outline,
  });

  /// Builds the tokens for [colorScheme].
  ///
  /// The spacing and radius values are fixed by the design system; only the
  /// budget colours vary with the scheme, and each maps to a Material role
  /// rather than a raw colour so light and dark stay consistent for free.
  factory AmoraTokens.fromColorScheme(ColorScheme colorScheme) {
    return AmoraTokens(
      // 4pt base scale.
      xs: 4,
      sm: 8,
      md: 16,
      lg: 24,
      xl: 32,
      xxl: 48,
      radiusSmall: 8,
      radiusMedium: 12,
      radiusLarge: 20,
      // Free is good news, so it gets an accent role and is never muted.
      costFree: colorScheme.tertiary,
      costNormal: colorScheme.onSurface,
      costOverBudget: colorScheme.error,
    );
  }

  // --- Spacing (design system §4) -------------------------------------------
  // Screen edge padding: md. Between cards: sm. Between sections: lg.
  // Inside a card: md.

  /// 4 — tight pairings, such as an icon and its label.
  final double xs;

  /// 8 — gap between cards in a list.
  final double sm;

  /// 16 — screen edge padding, and padding inside a card.
  final double md;

  /// 24 — gap between sections.
  final double lg;

  /// 32
  final double xl;

  /// 48
  final double xxl;

  // --- Radius (design system §4) --------------------------------------------
  // A "full" radius is deliberately absent: in Material that is a StadiumBorder
  // or CircleBorder (FAB, avatars, mode pills), not a number.

  /// 8 — chips, text fields.
  final double radiusSmall;

  /// 12 — cards, list tiles.
  final double radiusMedium;

  /// 20 — bottom sheets, dialogs.
  final double radiusLarge;

  // --- Budget colour semantics (design system §2) ---------------------------
  // Money means the same thing everywhere in the app. Partner and sponsored
  // places get no colour treatment at all — a small text label only — so they
  // are deliberately absent here.

  /// Free / ₱0. Treated as good news, never greyed out or shrunk.
  final Color costFree;

  /// A normal, affordable cost.
  final Color costNormal;

  /// A cost that exceeds the user's stated budget.
  final Color costOverBudget;

  /// The icon that must accompany [costOverBudget] wherever it is used.
  ///
  /// A token rather than a convention, because "over budget" is the one piece
  /// of money meaning in this app that a user cannot afford to miss, and colour
  /// alone cannot carry it: red-green colourblindness affects roughly one man
  /// in twelve, and no choice of hue fixes that. The dark scheme's error colour
  /// was separated from `primary` in the same change (`app_theme.dart`), but
  /// separation is what makes the colour *legible*, not what makes it
  /// *sufficient*.
  ///
  /// Required by `docs/02-design-system.md` §2. Nothing renders an over-budget
  /// total yet — Phase 4 does — so this exists to be there before the first
  /// screen needs it rather than to be retrofitted across several afterwards.
  final IconData costOverBudgetIcon;

  @override
  AmoraTokens copyWith({
    double? xs,
    double? sm,
    double? md,
    double? lg,
    double? xl,
    double? xxl,
    double? radiusSmall,
    double? radiusMedium,
    double? radiusLarge,
    Color? costFree,
    Color? costNormal,
    Color? costOverBudget,
    IconData? costOverBudgetIcon,
  }) {
    return AmoraTokens(
      xs: xs ?? this.xs,
      sm: sm ?? this.sm,
      md: md ?? this.md,
      lg: lg ?? this.lg,
      xl: xl ?? this.xl,
      xxl: xxl ?? this.xxl,
      radiusSmall: radiusSmall ?? this.radiusSmall,
      radiusMedium: radiusMedium ?? this.radiusMedium,
      radiusLarge: radiusLarge ?? this.radiusLarge,
      costFree: costFree ?? this.costFree,
      costNormal: costNormal ?? this.costNormal,
      costOverBudget: costOverBudget ?? this.costOverBudget,
      costOverBudgetIcon: costOverBudgetIcon ?? this.costOverBudgetIcon,
    );
  }

  /// Interpolates between two token sets. Flutter calls this when animating a
  /// theme change, such as the switch between light and dark.
  @override
  AmoraTokens lerp(covariant AmoraTokens? other, double t) {
    if (other == null) return this;
    return AmoraTokens(
      xs: lerpDouble(xs, other.xs, t)!,
      sm: lerpDouble(sm, other.sm, t)!,
      md: lerpDouble(md, other.md, t)!,
      lg: lerpDouble(lg, other.lg, t)!,
      xl: lerpDouble(xl, other.xl, t)!,
      xxl: lerpDouble(xxl, other.xxl, t)!,
      radiusSmall: lerpDouble(radiusSmall, other.radiusSmall, t)!,
      radiusMedium: lerpDouble(radiusMedium, other.radiusMedium, t)!,
      radiusLarge: lerpDouble(radiusLarge, other.radiusLarge, t)!,
      costFree: Color.lerp(costFree, other.costFree, t)!,
      costNormal: Color.lerp(costNormal, other.costNormal, t)!,
      costOverBudget: Color.lerp(costOverBudget, other.costOverBudget, t)!,
      // An icon has no midpoint. Snapping at the halfway mark is what Flutter's
      // own non-interpolatable theme values do.
      costOverBudgetIcon: t < 0.5 ? costOverBudgetIcon : other.costOverBudgetIcon,
    );
  }
}

/// Convenience access to [AmoraTokens], so call sites read
/// `Theme.of(context).tokens.md` instead of the full `extension<T>()` lookup.
extension AmoraThemeX on ThemeData {
  AmoraTokens get tokens => extension<AmoraTokens>()!;
}
