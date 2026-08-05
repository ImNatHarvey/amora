import 'package:flutter/material.dart';

import '../../models/simple_plan.dart';
import '../../theme/app_tokens.dart';
import '../../util/format.dart';
import '../../util/manila_time.dart';
import '../plan_request/plan_parts.dart';

/// The plan as a document you can read while walking around.
///
/// `02-design-system.md` §9: the conversation stops at the itinerary. This is
/// something to keep and follow, not a transcript to scroll back through.
///
/// Numbers here match the map's markers exactly — same number, same colour —
/// because that link is the only thing tying a pin to a price.
class PlanTimeline extends StatelessWidget {
  const PlanTimeline({
    required this.plan,
    this.onStopTap,
    super.key,
  });

  final SimplePlan plan;

  /// Opens place detail. Null in contexts where there is nowhere to go.
  final void Function(PlanStop stop)? onStopTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.tokens;
    final plannedFor = toManila(plan.plannedForUtc);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < plan.stops.length; i += 1) ...[
          if (i < plan.legs.length) LegLine(leg: plan.legs[i]),
          StopTile(
            stop: plan.stops[i],
            plannedFor: plannedFor,
            partySize: plan.partySize,
            onTap: onStopTap == null ? null : () => onStopTap!(plan.stops[i]),
          ),
        ],
        SizedBox(height: tokens.md),
        const Divider(),
        TotalsBlock(totals: plan.totals),
      ],
    );
  }
}

/// One stop: the numbered circle, the name, the facts, and the model's note.
///
/// The whole row is the touch target, not just the name — 48 dp minimum, no
/// exceptions (`02-design-system.md` §5).
class StopTile extends StatelessWidget {
  const StopTile({
    required this.stop,
    required this.plannedFor,
    required this.partySize,
    this.onTap,
    super.key,
  });

  final PlanStop stop;
  final DateTime plannedFor;
  final int partySize;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.tokens;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(tokens.radiusMedium),
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: tokens.sm),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _StopNumber(number: stop.seq),
            SizedBox(width: tokens.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(stop.place.name, style: theme.textTheme.bodyLarge),
                  Text(
                    // The shared builder, so this row and the plain one in
                    // plan_parts cannot drift on how money is worded.
                    stopFacts(stop, plannedFor, partySize),
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                  if (stop.startTimeUtc != null)
                    Text(
                      formatManila(toManila(stop.startTimeUtc!)),
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  if (stop.note != null) ...[
                    SizedBox(height: tokens.xs),
                    Text(
                      // The model's one sentence. Italic so it reads as
                      // commentary rather than as another retrieved fact.
                      stop.note!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontStyle: FontStyle.italic,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (onTap != null)
              Icon(
                Icons.chevron_right,
                color: theme.colorScheme.onSurfaceVariant,
              ),
          ],
        ),
      ),
    );
  }
}

class _StopNumber extends StatelessWidget {
  const _StopNumber({required this.number});

  final int number;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SizedBox(
      width: 32,
      height: 32,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.colorScheme.primary,
          shape: BoxShape.circle,
        ),
        child: Center(
          child: Text(
            '$number',
            style: theme.textTheme.labelMedium
                ?.copyWith(color: theme.colorScheme.onPrimary),
          ),
        ),
      ),
    );
  }
}

/// The cost breakdown, as its own block under the timeline.
///
/// Over budget carries an icon **and** a colour, never colour alone: red-green
/// colourblindness affects roughly one man in twelve and no hue fixes that
/// (`02-design-system.md` §2).
class PlanCostSummary extends StatelessWidget {
  const PlanCostSummary({
    required this.totals,
    required this.budgetPhpCents,
    super.key,
  });

  final PlanTotals totals;
  final int budgetPhpCents;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.tokens;
    final overBudget = totals.totalPhpCents > budgetPhpCents;

    if (!overBudget) return const SizedBox.shrink();

    return Padding(
      padding: EdgeInsets.only(top: tokens.sm),
      child: Row(
        children: [
          Icon(
            tokens.costOverBudgetIcon,
            size: 18,
            color: tokens.costOverBudget,
          ),
          SizedBox(width: tokens.xs),
          Expanded(
            child: Text(
              'Over your budget of '
              '${pesos(budgetPhpCents, zeroIsFree: false)}.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: tokens.costOverBudget),
            ),
          ),
        ],
      ),
    );
  }
}
