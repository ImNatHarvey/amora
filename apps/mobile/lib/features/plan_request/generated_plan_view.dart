import 'package:flutter/material.dart';

import '../../models/plan.dart';
import '../../theme/app_tokens.dart';
import '../../util/format.dart';
import '../../util/manila_time.dart';
import '../plan/save_plan_button.dart';
import 'plan_parts.dart';
import 'plan_request_providers.dart';

/// The generated plans, rendered as plainly as the Phase 2 output beside them.
///
/// No cards, no colour, no motion — Phase 4 designs this. Styling it now would
/// make a model's answer look better than the crude builder's for reasons that
/// have nothing to do with the answer.
class GeneratedPlanView extends StatelessWidget {
  const GeneratedPlanView({required this.timed, super.key});

  final TimedPlanSet timed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.tokens;
    final set = timed.plans;

    if (set.isEmpty) {
      return Padding(
        padding: EdgeInsets.only(top: tokens.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('The model found nothing.', style: theme.textTheme.titleMedium),
            SizedBox(height: tokens.sm),
            Text(
              'Every plan it produced was rejected, or no place was open and '
              'affordable to build one from.',
              style: theme.textTheme.bodyMedium,
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(height: tokens.md),
        Text(
          '${set.plans.length} generated '
          '${set.plans.length == 1 ? 'plan' : 'plans'}',
          style: theme.textTheme.titleMedium,
        ),
        SizedBox(height: tokens.xs),
        Text(
          // The cache state belongs beside the timing or the two readings look
          // like one measurement contradicting itself. A hit skips retrieval
          // and the model entirely.
          '${set.cacheHit ? 'from cache' : set.generatedByModel ?? 'generated'}'
          ' · ${timed.elapsed.inMilliseconds} ms',
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        SizedBox(height: tokens.md),
        for (final plan in set.plans) ...[
          _PlanBlock(plan: plan),
          SizedBox(height: tokens.md),
        ],
      ],
    );
  }
}

class _PlanBlock extends StatelessWidget {
  const _PlanBlock({required this.plan});

  final GeneratedPlan plan;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.tokens;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(plan.title, style: theme.textTheme.bodyLarge),
        SizedBox(height: tokens.xs),
        for (var i = 0; i < plan.stops.length; i += 1) ...[
          if (i < plan.legs.length) LegLine(leg: plan.legs[i]),
          StopLine(
            stop: plan.stops[i],
            plannedFor: toManila(plan.plannedForUtc),
            partySize: plan.partySize,
          ),
          // The model's own sentence. Indented under its stop so it reads as
          // commentary rather than as another retrieved fact.
          if (plan.stops[i].note != null)
            Padding(
              padding: EdgeInsets.only(left: tokens.md, bottom: tokens.sm),
              child: Text(
                plan.stops[i].note!,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
        ],
        TotalsBlock(totals: plan.totals),
        SavePlanButton(payload: plan.sourcePayload, title: plan.title),
        if (plan.overBudget) ...[
          SizedBox(height: tokens.xs),
          // Colour and an icon, never colour alone (docs 02 §2). The server
          // reports over budget rather than trimming stops to fit, so this is
          // the honest answer being shown honestly.
          Row(
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
                  '${pesos(plan.budgetPhpCents, zeroIsFree: false)}.',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: tokens.costOverBudget),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
