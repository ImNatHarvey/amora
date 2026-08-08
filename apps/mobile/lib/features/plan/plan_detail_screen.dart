import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../models/simple_plan.dart';
import '../../theme/app_tokens.dart';
import '../../ui/error_retry.dart';
import '../../util/format.dart';
import '../../util/manila_time.dart';
import 'plan_map.dart';
import 'plan_providers.dart';
import 'plan_timeline.dart';
import 'retime_sheet.dart';

/// A saved plan: map, timeline, cost.
///
/// The document half of the product. `02-design-system.md` §9: intake is a
/// chat, the plan is not — this is something to keep and walk around with,
/// which is why it opens on a map rather than on a message thread.
class PlanDetailScreen extends ConsumerWidget {
  const PlanDetailScreen({required this.planId, super.key});

  final String planId;

  /// Asks when a stop starts, then writes it.
  ///
  /// A dismissed sheet returns null and must change nothing — distinct from a
  /// record whose fields are null, which is the user clearing a time they had
  /// set. Collapsing the two would make "cancel" quietly erase a timing.
  Future<void> _retime(
    BuildContext context,
    WidgetRef ref,
    PlanStop stop,
    SimplePlan plan,
  ) async {
    final editor = ref.read(savedPlanProvider(planId).notifier);
    final choice = await showRetimeSheet(
      context: context,
      stop: stop,
      planDateUtc: plan.plannedForUtc,
    );
    if (choice == null) return;

    await editor.retime(
      stop,
      startTimeUtc: choice.startTimeUtc,
      durationMinutes: choice.durationMinutes,
    );
  }

  /// Removes a stop, and offers to put it back.
  ///
  /// Editing here is always live — there is no "Done" to reconsider before —
  /// so a mistapped ✕ would otherwise destroy a stop with no way back. Undo is
  /// cheap because the removed stop is still in hand and `edit_plan` takes a
  /// whole stop list, so restoring is one more ordinary edit rather than a
  /// special rollback path.
  Future<void> _removeWithUndo(
    BuildContext context,
    WidgetRef ref,
    PlanStop stop,
    SimplePlan plan,
  ) async {
    final index = plan.stops.indexWhere((s) => s.place.id == stop.place.id);
    final messenger = ScaffoldMessenger.of(context);
    final editor = ref.read(savedPlanProvider(planId).notifier);

    await editor.removeStop(stop);

    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text('Removed ${stop.place.name}'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () => editor.restoreStop(stop, index),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final tokens = theme.tokens;
    final saved = ref.watch(savedPlanProvider(planId));

    return Scaffold(
      appBar: AppBar(title: const Text('Plan')),
      body: SafeArea(
        child: saved.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Padding(
            padding: EdgeInsets.all(tokens.md),
            child: ErrorRetry(
              message: '$error',
              onRetry: () => ref.invalidate(savedPlanProvider(planId)),
            ),
          ),
          data: (savedPlan) {
            if (savedPlan == null) {
              // Not found and not yours are the same answer on purpose — see
              // read_plan. Saying "you do not have access" would confirm the
              // plan exists, which is not this screen's to disclose.
              return Padding(
                padding: EdgeInsets.all(tokens.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('That plan is not here.',
                        style: theme.textTheme.titleMedium),
                    SizedBox(height: tokens.sm),
                    Text(
                      'It may have been deleted.',
                      style: theme.textTheme.bodyMedium,
                    ),
                    SizedBox(height: tokens.md),
                    OutlinedButton(
                      onPressed: () => context.go(Routes.plans),
                      child: const Text('Back to your plans'),
                    ),
                  ],
                ),
              );
            }

            final plan = savedPlan.plan;
            final plannedFor = toManila(plan.plannedForUtc);

            return ListView(
              padding: EdgeInsets.all(tokens.md),
              children: [
                Text(
                  savedPlan.title ?? 'Plan for ${formatManila(plannedFor)}',
                  style: theme.textTheme.headlineSmall,
                ),
                SizedBox(height: tokens.xs),
                Text(
                  '${formatManila(plannedFor)} · from ${plan.originArea}'
                  ' · budget ${pesos(plan.budgetPhpCents, zeroIsFree: false)}',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
                SizedBox(height: tokens.md),
                PlanMap(plan: plan),
                SizedBox(height: tokens.md),
                PlanTimeline(
                  plan: plan,
                  onStopTap: (stop) =>
                      context.push('${Routes.place}/${stop.place.id}'),
                  onReorder: (oldIndex, newIndex) => ref
                      .read(savedPlanProvider(planId).notifier)
                      .reorder(oldIndex, newIndex),
                  onRemove: (stop) => _removeWithUndo(context, ref, stop, plan),
                  onRetime: (stop) => _retime(context, ref, stop, plan),
                ),
                SizedBox(height: tokens.sm),
                OutlinedButton.icon(
                  icon: const Icon(Icons.add),
                  label: const Text('Add a stop'),
                  onPressed: () =>
                      context.push('${Routes.plan}/$planId/add-stop'),
                ),
                PlanCostSummary(
                  totals: plan.totals,
                  budgetPhpCents: plan.budgetPhpCents,
                ),
                if (savedPlan.generatedByModel != null) ...[
                  SizedBox(height: tokens.lg),
                  Text(
                    'Composed by ${savedPlan.generatedByModel}. Places, prices '
                    'and fares come from the local database, not the model.',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}
