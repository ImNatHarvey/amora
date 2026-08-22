import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../models/memory.dart';
import '../../models/simple_plan.dart';
import '../../theme/app_tokens.dart';
import '../../ui/error_retry.dart';
import '../../util/format.dart';
import '../../util/manila_time.dart';
import '../memory/complete_plan_sheet.dart';
import '../memory/memory_providers.dart';
import '../memory/report_closure_dialog.dart';
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

            // Completion is the one state change that closes this screen's
            // editing off. Every edit affordance below is gated on it, and so is
            // the server: `edit_plan` refuses a completed plan, because its
            // place_reports describe the stop list it has and 6b will read them.
            final done = savedPlan.status == 'completed';
            final memory = ref.watch(memoryForPlanProvider(planId));

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
                // Pins stop being draggable once the plan is done, like
                // every other edit affordance on this screen.
                PlanMap(plan: plan, adjustable: !done),
                SizedBox(height: tokens.md),
                PlanTimeline(
                  plan: plan,
                  onStopTap: (stop) =>
                      context.push('${Routes.place}/${stop.place.id}'),
                  // All three null once the plan is done, which is what makes
                  // PlanTimeline render its read-only form — the same form the
                  // request screen has always used. No new mode was needed.
                  onReorder: done
                      ? null
                      : (oldIndex, newIndex) => ref
                          .read(savedPlanProvider(planId).notifier)
                          .reorder(oldIndex, newIndex),
                  onRemove: done
                      ? null
                      : (stop) => _removeWithUndo(context, ref, stop, plan),
                  onRetime:
                      done ? null : (stop) => _retime(context, ref, stop, plan),
                ),
                SizedBox(height: tokens.sm),
                if (!done)
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
                if (done)
                  _CompletedBlock(memory: memory)
                else
                  _StillToGoBlock(planId: planId, plan: plan),
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

/// The two things you can do to a plan you have not finished yet.
///
/// Marking it done is the primary action; reporting a closure is the one that
/// must not need it. §10.5's asymmetry made concrete in two buttons: the couple
/// who found a locked door will never press the first, and theirs is the report
/// worth the most.
class _StillToGoBlock extends ConsumerWidget {
  const _StillToGoBlock({required this.planId, required this.plan});

  final String planId;
  final SimplePlan plan;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = Theme.of(context).tokens;

    return Padding(
      padding: EdgeInsets.only(top: tokens.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FilledButton.icon(
            icon: const Icon(Icons.check),
            label: const Text('We did this'),
            onPressed: plan.stops.isEmpty
                // A plan with no stops has nothing to report and no evening to
                // remember. Disabled rather than hidden, so the action stays
                // where the user learned it is.
                ? null
                : () => showCompletePlanSheet(
                      context: context,
                      planId: planId,
                      plan: plan,
                    ),
          ),
          ReportClosureButton(
            onPressed: () => showReportClosureDialog(
              context: context,
              ref: ref,
              planId: planId,
              plan: plan,
            ),
          ),
        ],
      ),
    );
  }
}

/// What was recorded, once the outing is over.
///
/// [memory] is null while the timeline query has not loaded — the plan's own
/// status already says it is complete, so the screen states that much and fills
/// the rest in when it arrives. Waiting on a spinner here would hide a finished
/// plan behind a loading state for data that only decorates it.
class _CompletedBlock extends StatelessWidget {
  const _CompletedBlock({required this.memory});

  final Memory? memory;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.tokens;
    final spend = memory?.actualSpendPhpCents;

    return Padding(
      padding: EdgeInsets.only(top: tokens.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(),
          SizedBox(height: tokens.sm),
          Row(
            children: [
              Icon(Icons.check_circle, color: theme.colorScheme.primary),
              SizedBox(width: tokens.sm),
              Text('You did this', style: theme.textTheme.titleMedium),
            ],
          ),
          if (spend != null) ...[
            SizedBox(height: tokens.sm),
            Text(
              // The estimate is still on screen above, so this is the honest
              // comparison the whole phase exists to make possible.
              'It actually cost ${pesos(spend)}.',
              style: theme.textTheme.bodyLarge,
            ),
          ],
          if (memory?.caption != null) ...[
            SizedBox(height: tokens.xs),
            Text(memory!.caption!, style: theme.textTheme.bodyMedium),
          ],
          SizedBox(height: tokens.xs),
          Text(
            'This plan is no longer editable — what you reported describes the '
            'stops it has.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
