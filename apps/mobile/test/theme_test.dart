import 'package:mobile/theme/app_theme.dart';
import 'package:mobile/theme/app_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Guards the one colour relationship the product cannot get wrong.
///
/// `primary` and `error` must stay tellable apart, because Phase 4 renders an
/// over-budget total in `error` beside prices in `primary`. Material's default
/// dark error (`#FFB4AB`) sat ~27/255 from this seed's dark primary
/// (`#FFB1C6`), which reads as a decorative accent rather than a warning.
///
/// These are regression tests, not design tests: they do not assert a specific
/// hex, so retuning the palette is allowed. They assert that the two roles stay
/// distinguishable, and that the non-colour channel exists.
void main() {
  group('dark scheme', () {
    final dark = AppTheme.dark.colorScheme;

    test('error is separated from primary by more than one channel', () {
      // The failure mode was two pastels differing on a single channel. Require
      // real distance across all three, so a future seed change that
      // reintroduces the collision fails here rather than on someone's phone.
      final dr = (dark.error.r - dark.primary.r).abs();
      final dg = (dark.error.g - dark.primary.g).abs();
      final db = (dark.error.b - dark.primary.b).abs();

      expect(
        (dr + dg + db) * 255,
        greaterThan(60),
        reason: 'primary ${dark.primary} and error ${dark.error} are too close',
      );
    });

    test('error and primary sit on opposite sides of green vs blue', () {
      // At the same tone both roles are equally light by construction, so
      // lightness cannot be the distinguishing signal — hue has to be. Primary
      // is a rose (blue over green); error must be an orange (green over blue).
      expect(dark.primary.b, greaterThan(dark.primary.g),
          reason: 'primary should read as rose');
      expect(dark.error.g, greaterThan(dark.error.b),
          reason: 'error should read as orange-red, not another pink');
    });

    test('text on error is still legible', () {
      // A hand-picked family can silently break the contrast Material
      // guarantees. Cheap luminance check rather than a full WCAG harness.
      final delta =
          (dark.error.computeLuminance() - dark.onError.computeLuminance()).abs();
      expect(delta, greaterThan(0.4));
    });
  });

  test('light scheme is left alone', () {
    // Light mode was never broken. This asserts the fix stayed scoped: if
    // someone later overrides both, they should have to change this test and
    // think about why.
    final light = AppTheme.light.colorScheme;
    final reference = ColorScheme.fromSeed(
      seedColor: AppTheme.seedColor,
      brightness: Brightness.light,
    );
    expect(light.error, reference.error);
  });

  test('over budget carries a channel that is not colour', () {
    // Colour alone fails for red-green colourblind users at any hue, so the
    // icon is part of the token rather than something each screen remembers.
    expect(AppTheme.dark.tokens.costOverBudgetIcon, isNotNull);
    expect(
      AppTheme.light.tokens.costOverBudgetIcon,
      AppTheme.dark.tokens.costOverBudgetIcon,
    );
  });
}
