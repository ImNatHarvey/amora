import 'package:flutter/material.dart';

import '../../models/intake.dart';
import '../../theme/app_tokens.dart';
import '../../util/format.dart';
import '../../util/manila_time.dart';

/// The extracted constraints, each one tappable to correct.
///
/// `02-design-system.md` §9 calls this the most important new component in the
/// app, because it is what stops conversation becoming guesswork the user
/// cannot see. **The model's reading of a request is always shown, never
/// assumed.**
///
/// Two rules from that section are load-bearing rather than decorative:
///
///   * A chip must read as *editable* — a value the user can change, not a
///     pronouncement the system has made.
///   * A constraint the model could not determine appears as an **unfilled**
///     chip prompting for it, never as a silent default. A wrong assumption the
///     user can see and fix costs a tap; one hidden behind confident prose
///     costs their evening.
class ConstraintChips extends StatelessWidget {
  const ConstraintChips({
    required this.constraints,
    required this.onEdit,
    super.key,
  });

  final IntakeConstraints constraints;
  final void Function(IntakeField field) onEdit;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).tokens;

    return Wrap(
      spacing: tokens.sm,
      runSpacing: tokens.sm,
      children: [
        _Chip(
          field: IntakeField.budget,
          // ₱0 is a real budget and must read as one, so `zeroIsFree: false` —
          // here the figure is a constraint being echoed back, not the price of
          // anything, and "free" would name a category rather than an amount.
          value: constraints.budgetPhpCents == null
              ? null
              : pesos(constraints.budgetPhpCents!, zeroIsFree: false),
          onTap: () => onEdit(IntakeField.budget),
        ),
        _Chip(
          field: IntakeField.time,
          value: constraints.plannedForUtc == null
              ? null
              : formatManila(toManila(constraints.plannedForUtc!)),
          onTap: () => onEdit(IntakeField.time),
        ),
        _Chip(
          field: IntakeField.origin,
          value: constraints.originArea,
          onTap: () => onEdit(IntakeField.origin),
        ),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.field, required this.value, required this.onTap});

  final IntakeField field;

  /// Null renders the unfilled state — a question, not a default.
  final String? value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.tokens;
    final filled = value != null;

    return ActionChip(
      onPressed: onTap,
      // Small radius per §4's chip scale.
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(tokens.radiusSmall),
        side: BorderSide(
          color: filled
              ? theme.colorScheme.outlineVariant
              // An unfilled chip is something to act on, so it carries the
              // primary outline rather than fading into the surface. It is
              // asking a question, not reporting a value.
              : theme.colorScheme.primary,
        ),
      ),
      avatar: Icon(
        filled ? Icons.edit : Icons.add,
        size: 16,
        color: filled
            ? theme.colorScheme.onSurfaceVariant
            : theme.colorScheme.primary,
      ),
      label: Text(
        value ?? field.prompt,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: filled ? null : theme.colorScheme.primary,
        ),
      ),
    );
  }
}
