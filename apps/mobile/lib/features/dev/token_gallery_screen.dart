import 'package:flutter/material.dart';

import '../../theme/app_tokens.dart';

/// A developer-facing catalogue of every design token.
///
/// This is a verification tool, not product surface. `docs/02-design-system.md`
/// §8 requires every screen to be checked in light and dark and at larger text
/// scales; this screen makes that a glance instead of a hunt, for this phase and
/// each one after it.
class TokenGalleryScreen extends StatelessWidget {
  const TokenGalleryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.tokens;
    final colors = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Design tokens')),
      body: ListView(
        padding: EdgeInsets.all(tokens.md),
        children: [
          _Section(
            title: 'Colour roles',
            child: Wrap(
              spacing: tokens.sm,
              runSpacing: tokens.sm,
              children: [
                _Swatch('primary', colors.primary, colors.onPrimary),
                _Swatch(
                  'primaryContainer',
                  colors.primaryContainer,
                  colors.onPrimaryContainer,
                ),
                _Swatch('secondary', colors.secondary, colors.onSecondary),
                _Swatch('tertiary', colors.tertiary, colors.onTertiary),
                _Swatch('error', colors.error, colors.onError),
                _Swatch('surface', colors.surface, colors.onSurface),
                _Swatch(
                  'surfaceContainerHighest',
                  colors.surfaceContainerHighest,
                  colors.onSurface,
                ),
                _Swatch(
                  'outline',
                  colors.outline,
                  colors.surface,
                ),
              ],
            ),
          ),

          // The §2 table, rendered. Free must never look muted next to a paid
          // amount — that is the whole point of checking it here.
          _Section(
            title: 'Budget semantics',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _CostRow('Free / ₱0', 'Free', tokens.costFree),
                _CostRow('Normal cost', '₱180', tokens.costNormal),
                _CostRow(
                  'Over budget',
                  '₱1,250',
                  tokens.costOverBudget,
                  icon: tokens.costOverBudgetIcon,
                ),
                SizedBox(height: tokens.sm),
                // The check this row exists for: in dark mode `primary` and
                // `error` used to be neighbours, so an over-budget total read
                // as a decorative accent. Put them side by side and the
                // separation is either obvious or it is not.
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'primary vs error',
                        style: theme.textTheme.bodyLarge,
                      ),
                    ),
                    Text(
                      '₱1,250',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(color: colors.primary),
                    ),
                    SizedBox(width: tokens.sm),
                    Text(
                      '₱1,250',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(color: colors.error),
                    ),
                  ],
                ),
              ],
            ),
          ),

          _Section(
            title: 'Type scale',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Screen title', style: theme.textTheme.headlineSmall),
                Text('Section header', style: theme.textTheme.titleMedium),
                Text('Body text', style: theme.textTheme.bodyLarge),
                Text(
                  'Supporting caption',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: colors.onSurfaceVariant),
                ),
              ],
            ),
          ),

          _Section(
            title: 'Spacing',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Bar('xs', tokens.xs),
                _Bar('sm', tokens.sm),
                _Bar('md', tokens.md),
                _Bar('lg', tokens.lg),
                _Bar('xl', tokens.xl),
                _Bar('xxl', tokens.xxl),
              ],
            ),
          ),

          _Section(
            title: 'Radius',
            child: Wrap(
              spacing: tokens.sm,
              runSpacing: tokens.sm,
              children: [
                _RadiusBox('small', tokens.radiusSmall),
                _RadiusBox('medium', tokens.radiusMedium),
                _RadiusBox('large', tokens.radiusLarge),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.tokens;

    return Padding(
      padding: EdgeInsets.only(bottom: tokens.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.titleMedium),
          SizedBox(height: tokens.sm),
          child,
        ],
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch(this.label, this.color, this.onColor);

  final String label;
  final Color color;
  final Color onColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.tokens;

    return Container(
      width: 150,
      padding: EdgeInsets.all(tokens.sm),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(tokens.radiusSmall),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Text(
        label,
        style: theme.textTheme.bodyMedium?.copyWith(color: onColor),
      ),
    );
  }
}

class _CostRow extends StatelessWidget {
  const _CostRow(this.label, this.amount, this.color, {this.icon});

  final String label;
  final String amount;
  final Color color;

  /// Present only for over budget, which must never rely on colour alone.
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.tokens;

    return Padding(
      padding: EdgeInsets.only(bottom: tokens.xs),
      child: Row(
        children: [
          Expanded(child: Text(label, style: theme.textTheme.bodyLarge)),
          if (icon != null) ...[
            Icon(icon, size: 18, color: color),
            SizedBox(width: tokens.xs),
          ],
          Text(
            amount,
            style: theme.textTheme.titleMedium?.copyWith(color: color),
          ),
        ],
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar(this.label, this.value);

  final String label;
  final double value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.tokens;

    return Padding(
      padding: EdgeInsets.only(bottom: tokens.xs),
      child: Row(
        children: [
          SizedBox(
            width: 88,
            child: Text(
              '$label  ${value.toInt()}',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
          Container(
            width: value,
            height: 16,
            color: theme.colorScheme.primary,
          ),
        ],
      ),
    );
  }
}

class _RadiusBox extends StatelessWidget {
  const _RadiusBox(this.label, this.radius);

  final String label;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: 96,
      height: 64,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(radius),
      ),
      child: Text(
        '$label  ${radius.toInt()}',
        style: theme.textTheme.bodyMedium,
      ),
    );
  }
}
