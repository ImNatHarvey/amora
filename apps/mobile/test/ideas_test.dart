import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/data/resources_repository.dart';
import 'package:mobile/data/retrieval_repository.dart';
import 'package:mobile/features/ideas/ideas_screen.dart';
import 'package:mobile/models/activity.dart';
import 'package:mobile/theme/app_theme.dart';

import 'fakes.dart';

const _free = Activity(
  id: 'a1',
  slug: 'sunset-watching',
  title: 'Sunset watching',
  category: 'outdoor',
  minBudgetPhpCents: 0,
  maxBudgetPhpCents: 0,
  durationMinutes: 60,
);

const _paid = Activity(
  id: 'a2',
  slug: 'cook-a-meal-together',
  title: 'Cook a meal together',
  category: 'cooking',
  minBudgetPhpCents: 15000,
  maxBudgetPhpCents: 50000,
  durationMinutes: 90,
  isDiy: true,
);

Future<FakeRetrievalRepository> _pump(
  WidgetTester tester, {
  List<Activity> activities = const [],
  Object? error,
}) async {
  final retrieval = FakeRetrievalRepository(error: error)
    ..activities = activities;

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        retrievalRepositoryProvider.overrideWithValue(retrieval),
        resourcesRepositoryProvider
            .overrideWithValue(FakeResourcesRepository(owned: {'r1'})),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        home: const IdeasScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return retrieval;
}

void main() {
  testWidgets('lists what fits, and says so', (tester) async {
    await _pump(tester, activities: const [_free, _paid]);

    expect(find.text('Sunset watching'), findsOneWidget);
    expect(find.text('Cook a meal together'), findsOneWidget);
    expect(find.textContaining('2 ideas for ₱200'), findsOneWidget);
  });

  testWidgets('the party budget is halved before it reaches the server',
      (tester) async {
    // The one piece of arithmetic on this path. Activity budgets are per
    // person; the number the user typed is for two. Getting this wrong would
    // silently show a couple twice the ideas they can afford — and it has to
    // match what build_simple_plan does with the same figure.
    final retrieval = await _pump(tester, activities: const [_free]);

    expect(retrieval.activityBudgetsPhpCents.first, 200 * 100 ~/ 2);
  });

  testWidgets('a free activity takes no per-head qualifier', (tester) async {
    await _pump(tester, activities: const [_free]);

    // "free each" is absurd, and so is "₱0 for two". Assert the whole fact
    // line rather than a substring — "free" also appears in the budget field's
    // helper text, which is a different sentence doing a different job.
    expect(find.text('outdoor · 1h · free'), findsOneWidget);
    expect(find.textContaining('free each'), findsNothing);
    expect(find.textContaining('for two'), findsNothing);
  });

  testWidgets('a priced activity shows per person and for two', (tester) async {
    await _pump(tester, activities: const [_paid]);

    // Both figures, because either alone reads as a contradiction beside a
    // budget the user entered for the pair.
    expect(find.textContaining('₱150–₱500 each'), findsOneWidget);
    expect(find.textContaining('₱300 for two'), findsOneWidget);
  });

  testWidgets('finding nothing explains itself rather than saying "none"',
      (tester) async {
    await _pump(tester);

    expect(find.text('Nothing fits yet.'), findsOneWidget);
    // Design system §5: never a bare empty state — it must offer an action.
    expect(find.textContaining('add what you own'), findsOneWidget);
  });

  testWidgets('a zero budget blames the gear, not the money', (tester) async {
    await _pump(tester);
    await tester.enterText(find.byType(TextField), '0');
    await tester.pumpAndSettle();

    expect(find.textContaining('needs something you have not listed'),
        findsOneWidget);
    // "under free" would be nonsense: ₱0 here is a constraint echoed back, not
    // the price of anything.
    expect(find.textContaining('under free'), findsNothing);
  });

  testWidgets('a failed load offers a retry', (tester) async {
    await _pump(tester, error: Exception('no network'));

    expect(find.text('Try again'), findsOneWidget);
  });

  testWidgets('changing the budget re-queries', (tester) async {
    final retrieval = await _pump(tester, activities: const [_free]);

    await tester.enterText(find.byType(TextField), '50');
    await tester.pumpAndSettle();

    expect(retrieval.activityBudgetsPhpCents, contains(50 * 100 ~/ 2));
  });
}
