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
    this.onReorder,
    this.onRemove,
    this.onRetime,
    super.key,
  });

  final SimplePlan plan;

  /// Opens place detail. Null in contexts where there is nowhere to go.
  final void Function(PlanStop stop)? onStopTap;

  /// Supplied only where the plan is editable. When all three are null the
  /// timeline renders exactly as it did before Phase 5, which is what keeps the
  /// read-only copy on the request screen untouched.
  final void Function(int oldIndex, int newIndex)? onReorder;
  final void Function(PlanStop stop)? onRemove;
  final void Function(PlanStop stop)? onRetime;

  bool get _editable =>
      onReorder != null || onRemove != null || onRetime != null;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.tokens;
    final plannedFor = toManila(plan.plannedForUtc);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_editable)
          _ReorderableStops(
            plan: plan,
            plannedFor: plannedFor,
            onStopTap: onStopTap,
            onReorder: onReorder,
            onRemove: onRemove,
            onRetime: onRetime,
          )
        else
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

/// The stops, draggable.
///
/// Each row carries the leg *into* its stop, which is how `plan_legs` is shaped
/// — `legs[i]` arrives at `stops[i]`. While a row is mid-drag the leg travelling
/// with it is briefly wrong, and that is accepted rather than worked around:
/// the server recomputes every leg on drop and the whole timeline redraws from
/// the response, so the only alternative would be predicting fares on the
/// device, which is invariant 3.
class _ReorderableStops extends StatelessWidget {
  const _ReorderableStops({
    required this.plan,
    required this.plannedFor,
    this.onStopTap,
    this.onReorder,
    this.onRemove,
    this.onRetime,
  });

  final SimplePlan plan;
  final DateTime plannedFor;
  final void Function(PlanStop stop)? onStopTap;
  final void Function(int oldIndex, int newIndex)? onReorder;
  final void Function(PlanStop stop)? onRemove;
  final void Function(PlanStop stop)? onRetime;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.tokens;

    return ReorderableListView.builder(
      // It lives inside the detail screen's ListView, so it must not scroll or
      // claim unbounded height of its own.
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      buildDefaultDragHandles: false,
      itemCount: plan.stops.length,
      // `onReorderItem`, not the deprecated `onReorder`: it hands back a
      // newIndex already adjusted for the item having been lifted out. The old
      // callback required the caller to subtract one when dragging downwards,
      // and doing both would rotate the list by one on every downward drag.
      onReorderItem: onReorder ?? (_, _) {},
      itemBuilder: (context, i) {
        final stop = plan.stops[i];
        return Column(
          // Keyed on the place, not the index: an index key would make Flutter
          // reuse the wrong row's state the moment the list is reordered.
          key: ValueKey(stop.place.id),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (i < plan.legs.length) LegLine(leg: plan.legs[i]),
            Row(
              children: [
                if (onReorder != null)
                  ReorderableDragStartListener(
                    index: i,
                    child: Padding(
                      padding: EdgeInsets.only(right: tokens.xs),
                      child: Icon(
                        Icons.drag_handle,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                Expanded(
                  child: StopTile(
                    stop: stop,
                    plannedFor: plannedFor,
                    partySize: plan.partySize,
                    onTap: onStopTap == null ? null : () => onStopTap!(stop),
                  ),
                ),
                if (onRetime != null)
                  IconButton(
                    icon: const Icon(Icons.schedule),
                    tooltip: 'Set a time for ${stop.place.name}',
                    onPressed: () => onRetime!(stop),
                  ),
                if (onRemove != null)
                  IconButton(
                    icon: const Icon(Icons.close),
                    // Named for what it removes. "Remove" alone tells a screen
                    // reader nothing about which of five rows it is on.
                    tooltip: 'Remove ${stop.place.name}',
                    onPressed: () => onRemove!(stop),
                  ),
              ],
            ),
          ],
        );
      },
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
                      // Time only. The date is stated once in the heading, and
                      // repeating it on every row buries the part that differs.
                      formatManilaTime(toManila(stop.startTimeUtc!)),
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

    // §6 sanctions animating "a total recalculating", and this is that moment:
    // the warning appears because an edit you just made pushed the plan over.
    // Snapping in reads as though it had always been there. Sliding it in says
    // the edit did it.
    //
    // Reduced motion renders the end state immediately, per §6 — a zero
    // duration, not a shorter one and not a blank space.
    return AnimatedSwitcher(
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 200),
      transitionBuilder: (child, animation) => SizeTransition(
        sizeFactor: animation,
        // Grows downward from the timeline rather than from its own middle, so
        // nothing above it moves.
        alignment: Alignment.topCenter,
        child: FadeTransition(opacity: animation, child: child),
      ),
      child: !overBudget
          ? const SizedBox.shrink(key: ValueKey('within-budget'))
          : Padding(
              key: const ValueKey('over-budget'),
              padding: EdgeInsets.only(top: tokens.sm),
              child: Row(
                children: [
                  Icon(
                    tokens.costOverBudgetIcon,
                    size: tokens.iconInline,
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
            ),
    );
  }
}
