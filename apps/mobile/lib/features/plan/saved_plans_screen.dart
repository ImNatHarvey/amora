import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../data/plans_repository.dart';
import '../../theme/app_tokens.dart';
import '../../ui/error_retry.dart';
import '../../util/format.dart';
import '../../util/manila_time.dart';
import 'plan_providers.dart';

/// Plans this user has saved, newest first.
class SavedPlansScreen extends ConsumerWidget {
  const SavedPlansScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final tokens = theme.tokens;
    final plans = ref.watch(savedPlansProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Your plans')),
      body: SafeArea(
        child: plans.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Padding(
            padding: EdgeInsets.all(tokens.md),
            child: ErrorRetry(
              message: '$error',
              onRetry: () => ref.invalidate(savedPlansProvider),
            ),
          ),
          data: (list) => list.isEmpty
              ? const _EmptyState()
              : ListView.separated(
                  padding: EdgeInsets.all(tokens.md),
                  itemCount: list.length,
                  separatorBuilder: (_, _) => SizedBox(height: tokens.sm),
                  itemBuilder: (context, i) => _PlanCard(summary: list[i]),
                ),
        ),
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({required this.summary});

  final PlanSummary summary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.tokens;
    final plannedFor = toManila(summary.plannedForUtc);

    return InkWell(
      onTap: () => context.push('${Routes.plan}/${summary.id}'),
      borderRadius: BorderRadius.circular(tokens.radiusMedium),
      child: Container(
        padding: EdgeInsets.all(tokens.md),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(tokens.radiusMedium),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              // A plan with no title is named by when it is for, which is what
              // the user would have called it anyway.
              summary.title ?? 'Plan for ${formatManila(plannedFor)}',
              style: theme.textTheme.bodyLarge,
            ),
            SizedBox(height: tokens.xs),
            Text(
              [
                formatManila(plannedFor),
                if (summary.originArea != null) 'from ${summary.originArea}',
                // The budget, not the total: the list is for choosing between
                // plans, and the total needs every leg loaded to be honest.
                'budget ${pesos(summary.budgetPhpCents, zeroIsFree: false)}',
              ].join(' · '),
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

/// Never a bare "no plans" — `02-design-system.md` §5 requires an explanation
/// and an action.
class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.tokens;

    return Padding(
      padding: EdgeInsets.all(tokens.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Nothing saved yet.', style: theme.textTheme.titleMedium),
          SizedBox(height: tokens.sm),
          Text(
            'Build a plan and save it, and it will wait here for you to walk '
            'around with.',
            style: theme.textTheme.bodyMedium,
          ),
          SizedBox(height: tokens.md),
          FilledButton(
            onPressed: () => context.push(Routes.planRequest),
            child: const Text('Plan something'),
          ),
        ],
      ),
    );
  }
}
