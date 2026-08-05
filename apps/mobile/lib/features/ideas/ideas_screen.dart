import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/retrieval_repository.dart';
import '../../models/activity.dart';
import '../../theme/app_tokens.dart';
import 'ideas_providers.dart';

/// "What could we do?" — the half of retrieval that needs no curated place.
///
/// Activities carry a budget and a gear requirement but no location, by design
/// (`docs/00-architecture.md` §5). That makes this surface honest while the
/// place catalogue is still being built: it answers *what*, and never pretends
/// to answer *where*. The moment places exist, the plan screen answers both and
/// this stays as the cheaper question.
class IdeasScreen extends ConsumerStatefulWidget {
  const IdeasScreen({super.key});

  @override
  ConsumerState<IdeasScreen> createState() => _IdeasScreenState();
}

class _IdeasScreenState extends ConsumerState<IdeasScreen> {
  late final TextEditingController _budgetController = TextEditingController(
    text: (ref.read(ideasBudgetProvider) ~/ 100).toString(),
  );

  @override
  void dispose() {
    _budgetController.dispose();
    super.dispose();
  }

  void _applyBudget(String raw) {
    final pesos = int.tryParse(raw.trim());
    if (pesos == null) return;
    // Pesos in the field, centavos everywhere else. One conversion, at the
    // boundary (CLAUDE.md conventions).
    ref.read(ideasBudgetProvider.notifier).state = pesos * 100;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.tokens;

    final ideas = ref.watch(ideasProvider);
    final budget = ref.watch(ideasBudgetProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Ideas')),
      body: SafeArea(
        child: ListView(
          padding: EdgeInsets.all(tokens.md),
          children: [
            // The budget input is the main event on its own surface
            // (`02-design-system.md` §5), not a field in a row of others.
            TextField(
              controller: _budgetController,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineSmall,
              onChanged: _applyBudget,
              decoration: const InputDecoration(
                labelText: 'Budget for the two of you',
                prefixText: '₱',
                border: OutlineInputBorder(),
                helperText: '0 is fine — free plans are still plans.',
              ),
            ),
            SizedBox(height: tokens.lg),
            ideas.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => _ErrorRetry(
                message: '$error',
                onRetry: () => ref.invalidate(ideasProvider),
              ),
              data: (list) => list.isEmpty
                  ? _EmptyState(budgetPhpCents: budget)
                  : _IdeasList(activities: list, budgetPhpCents: budget),
            ),
          ],
        ),
      ),
    );
  }
}

/// `₱180`, or `free` when zero is genuinely the price of something.
///
/// Same rule as the plan screen: "free" belongs where ₱0 is a price, not where
/// it is a constraint being echoed back (`02-design-system.md` §2).
String _pesos(int cents, {bool zeroIsFree = true}) {
  if (cents == 0) return zeroIsFree ? 'free' : '₱0';
  final pesos = cents ~/ 100;
  final remainder = cents % 100;
  return remainder == 0
      ? '₱$pesos'
      : '₱$pesos.${remainder.toString().padLeft(2, '0')}';
}

String _duration(int minutes) {
  if (minutes < 60) return '$minutes min';
  final hours = minutes ~/ 60;
  final rest = minutes % 60;
  return rest == 0 ? '${hours}h' : '${hours}h ${rest}m';
}

class _IdeasList extends ConsumerWidget {
  const _IdeasList({required this.activities, required this.budgetPhpCents});

  final List<Activity> activities;
  final int budgetPhpCents;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final tokens = theme.tokens;
    final total = ref.watch(ideasTotalProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          switch (total) {
            // "5 of 16" says the filter is working. A bare "5" says nothing,
            // and a short list with no explanation reads as a broken app.
            AsyncData(:final value) when value > activities.length =>
              '${activities.length} of $value fit '
                  '${_pesos(budgetPhpCents, zeroIsFree: false)} '
                  'and what you own',
            _ => '${activities.length} '
                '${activities.length == 1 ? 'idea' : 'ideas'} for '
                '${_pesos(budgetPhpCents, zeroIsFree: false)}',
          },
          style: theme.textTheme.titleMedium,
        ),
        SizedBox(height: tokens.md),
        for (final activity in activities) ...[
          _IdeaTile(activity: activity),
          SizedBox(height: tokens.sm),
        ],
      ],
    );
  }
}

class _IdeaTile extends StatelessWidget {
  const _IdeaTile({required this.activity});

  final Activity activity;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.tokens;

    // Activity budgets are per person, like every other price in the app. The
    // "each" qualifier is what stops it reading as a contradiction beside a
    // party budget — and a free activity takes no qualifier, because "free
    // each" is absurd.
    final max = activity.maxBudgetPhpCents;
    final range = max == null || max == activity.minBudgetPhpCents
        ? _pesos(activity.minBudgetPhpCents)
        : '${_pesos(activity.minBudgetPhpCents)}–${_pesos(max)}';
    final isFree = activity.minBudgetPhpCents == 0 && (max ?? 0) == 0;
    final price = isFree
        ? range
        : '$range each · ${_pesos(activity.minBudgetPhpCents * RetrievalRepository.partySize, zeroIsFree: false)} for two';

    final facts = [
      if (activity.category != null) activity.category!,
      if (activity.durationMinutes != null)
        _duration(activity.durationMinutes!),
      price,
    ].join(' · ');

    return Container(
      padding: EdgeInsets.all(tokens.md),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(tokens.radiusMedium),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(activity.title, style: theme.textTheme.bodyLarge),
              ),
              if (activity.isDiy)
                Padding(
                  padding: EdgeInsets.only(left: tokens.sm),
                  child: Text(
                    'DIY',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ),
            ],
          ),
          SizedBox(height: tokens.xs),
          Text(
            facts,
            style: theme.textTheme.bodySmall?.copyWith(
              // Free is good news and is never muted (`02-design-system.md` §2).
              color: activity.minBudgetPhpCents == 0
                  ? tokens.costFree
                  : theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// Never a bare "no results" — `02-design-system.md` §5.
class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.budgetPhpCents});

  final int budgetPhpCents;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Nothing fits yet.', style: theme.textTheme.titleMedium),
        SizedBox(height: theme.tokens.sm),
        Text(
          budgetPhpCents == 0
              // At ₱0 the budget is not the problem — every free activity in
              // the catalogue needs gear this user has not listed.
              ? 'Every free idea here needs something you have not listed yet. '
                  'Add what you own and they will appear.'
              : 'Nothing costs under '
                  '${_pesos(budgetPhpCents, zeroIsFree: false)} for two with '
                  'the gear you have listed. Try a higher budget, or add what '
                  'you own.',
          style: theme.textTheme.bodyMedium,
        ),
      ],
    );
  }
}

class _ErrorRetry extends StatelessWidget {
  const _ErrorRetry({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          message,
          style: theme.textTheme.bodyMedium
              ?.copyWith(color: theme.colorScheme.error),
        ),
        SizedBox(height: theme.tokens.sm),
        OutlinedButton(onPressed: onRetry, child: const Text('Try again')),
      ],
    );
  }
}
