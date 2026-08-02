import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/data/auth_repository.dart';
import 'package:mobile/data/profiles_repository.dart';
import 'package:mobile/data/resources_repository.dart';
import 'package:mobile/data/retrieval_repository.dart';
import 'package:mobile/features/plan_request/plan_request_screen.dart';
import 'package:mobile/models/activity.dart';
import 'package:mobile/models/place.dart';
import 'package:mobile/models/profile.dart';
import 'package:mobile/models/simple_plan.dart';
import 'package:mobile/theme/app_theme.dart';

import 'fakes.dart';

/// The plan screen alone, wired to in-memory repositories.
///
/// Mounted directly rather than through the router: the redirect ladder is
/// already covered in widget_test.dart, and going through it would make every
/// test here depend on onboarding state that has nothing to do with retrieval.
Widget _screen(FakeRetrievalRepository retrieval) {
  return ProviderScope(
    overrides: [
      authRepositoryProvider.overrideWithValue(
        FakeAuthRepository(userId: 'user-1'),
      ),
      profilesRepositoryProvider.overrideWithValue(
        FakeProfilesRepository(
          profile: Profile(
            id: 'user-1',
            displayName: 'Nat',
            city: 'Bocaue',
            onboardedAt: DateTime.utc(2026),
          ),
        ),
      ),
      resourcesRepositoryProvider.overrideWithValue(
        FakeResourcesRepository(owned: {'r1'}),
      ),
      retrievalRepositoryProvider.overrideWithValue(retrieval),
    ],
    child: MaterialApp(
      theme: AppTheme.light,
      home: const PlanRequestScreen(),
    ),
  );
}

Place _place({
  required String name,
  int priceMin = 0,
  int? priceMax,
  Map<String, dynamic>? hours,
}) {
  return Place(
    id: 'p-$name',
    slug: name.toLowerCase(),
    name: name,
    category: 'cafe',
    barangay: 'Poblacion',
    lat: 14.7967,
    lng: 120.9261,
    priceMinPhpCents: priceMin,
    priceMaxPhpCents: priceMax,
    openingHours: hours == null ? null : OpeningHours.fromMap(hours),
  );
}

SimplePlan _plan({
  required List<PlanStop> stops,
  required List<PlanLeg> legs,
  required PlanTotals totals,
  List<Activity> activities = const [],
}) {
  return SimplePlan(
    // A Friday, so the opening-hours fixtures below have a day to land on.
    plannedForUtc: DateTime.utc(2026, 8, 7, 10),
    budgetPhpCents: 20000,
    originArea: 'Poblacion',
    radiusM: 3000,
    stops: stops,
    legs: legs,
    totals: totals,
    candidateActivities: activities,
  );
}

void main() {
  group('opening hours', () {
    // Friday 2026-08-07, Manila.
    final friday = DateTime(2026, 8, 7, 18);

    test('reads back the range for that day', () {
      final hours = OpeningHours.fromMap({
        'fri': [
          ['09:00', '22:00'],
        ],
      });
      expect(hours.describe(friday), '09:00–22:00');
    });

    test('all-day reads as words, not 00:00-24:00', () {
      final hours = OpeningHours.fromMap({
        'fri': [
          ['00:00', '24:00'],
        ],
      });
      expect(hours.describe(friday), 'open 24 hours');
    });

    test('a range wrapping past midnight belongs to the day it opens', () {
      final hours = OpeningHours.fromMap({
        'fri': [
          ['18:00', '02:00'],
        ],
      });

      // Recorded against Friday, so Friday is where it shows...
      expect(hours.describe(friday), '18:00–02:00');
      // ...and Saturday has nothing of its own, even though the bar is open
      // into Saturday morning. `public.is_open_at` owns that question; this
      // type only reports what was written down.
      expect(hours.describe(friday.add(const Duration(days: 1))), isNull);
    });

    test('a day that was never mentioned is closed', () {
      final hours = OpeningHours.fromMap({
        'mon': [
          ['09:00', '17:00'],
        ],
      });
      expect(hours.describe(friday), isNull);
    });
  });

  group('plan screen', () {
    testWidgets('starts with nothing and does not call the server',
        (tester) async {
      final retrieval = FakeRetrievalRepository();
      await tester.pumpWidget(_screen(retrieval));
      await tester.pumpAndSettle();

      expect(find.textContaining('No plan yet'), findsOneWidget);
      expect(retrieval.buildCount, 0);
    });

    testWidgets('renders stops, legs and a total', (tester) async {
      final retrieval = FakeRetrievalRepository(
        plan: _plan(
          stops: [
            PlanStop(
              seq: 1,
              place: _place(
                name: 'Town Plaza',
                hours: {
                  'fri': [
                    ['00:00', '24:00'],
                  ],
                },
              ),
              distanceFromOriginM: 72,
            ),
            PlanStop(
              seq: 2,
              place: _place(
                name: 'Corner Cafe',
                priceMin: 15000,
                priceMax: 35000,
                hours: {
                  'fri': [
                    ['09:00', '22:00'],
                  ],
                },
              ),
              distanceFromOriginM: 116,
            ),
          ],
          legs: const [
            PlanLeg(
              seq: 1,
              fromName: 'Poblacion',
              toName: 'Town Plaza',
              mode: 'walk',
              distanceM: 72,
              farePhpCents: 0,
              fareKnown: true,
            ),
            PlanLeg(
              seq: 2,
              fromName: 'Town Plaza',
              toName: 'Corner Cafe',
              mode: 'jeepney',
              distanceM: 1200,
              farePhpCents: 1500,
              fareKnown: true,
            ),
          ],
          totals: const PlanTotals(
            placesPhpCents: 15000,
            faresPhpCents: 1500,
            totalPhpCents: 16500,
            unpricedLegs: 0,
            isComplete: true,
          ),
        ),
      );

      await tester.pumpWidget(_screen(retrieval));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Build a plan'));
      await tester.pumpAndSettle();

      expect(find.text('2 stops from Poblacion'), findsOneWidget);
      expect(find.text('1. Town Plaza'), findsOneWidget);
      expect(find.text('2. Corner Cafe'), findsOneWidget);

      // Free is spelled out rather than shown as ₱0 (design system §2:
      // free is good news, never muted).
      expect(find.textContaining('free'), findsWidgets);
      expect(find.textContaining('₱150–₱350'), findsOneWidget);

      // Legs carry mode and fare.
      expect(find.textContaining('jeepney · ₱15'), findsOneWidget);
      expect(find.text('Total ₱165'), findsOneWidget);
    });

    testWidgets('an unpriced leg is named and left out of the total',
        (tester) async {
      final retrieval = FakeRetrievalRepository(
        plan: _plan(
          stops: [
            PlanStop(
              seq: 1,
              place: _place(name: 'Dessert Bar', priceMin: 18000),
              distanceFromOriginM: 2400,
            ),
          ],
          legs: const [
            // No fare recorded for this barangay pair. We never estimate one
            // (D5), so the leg is visibly incomplete instead of quietly wrong.
            PlanLeg(
              seq: 1,
              fromName: 'Poblacion',
              toName: 'Dessert Bar',
              distanceM: 2400,
              fareKnown: false,
            ),
          ],
          totals: const PlanTotals(
            placesPhpCents: 18000,
            faresPhpCents: 0,
            totalPhpCents: 18000,
            unpricedLegs: 1,
            isComplete: false,
          ),
        ),
      );

      await tester.pumpWidget(_screen(retrieval));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Build a plan'));
      await tester.pumpAndSettle();

      expect(find.textContaining('fare not recorded'), findsOneWidget);
      // "At least", never "Total" — the figure is a floor.
      expect(find.text('At least ₱180'), findsOneWidget);
      expect(find.text('Total ₱180'), findsNothing);
      expect(
        find.textContaining('1 leg has no recorded fare'),
        findsOneWidget,
      );
    });

    testWidgets('finding nothing is an empty state, not an error',
        (tester) async {
      // The fake's default plan has no stops.
      final retrieval = FakeRetrievalRepository();

      await tester.pumpWidget(_screen(retrieval));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Build a plan'));
      await tester.pumpAndSettle();

      expect(find.text('Nothing fits.'), findsOneWidget);
      expect(find.text('Try again'), findsNothing);
    });

    testWidgets('a failed build offers a retry', (tester) async {
      final retrieval = FakeRetrievalRepository(
        error: Exception('Could not build a plan.'),
      );

      await tester.pumpWidget(_screen(retrieval));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Build a plan'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Could not build a plan.'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
    });

    testWidgets('a non-numeric budget never reaches the server',
        (tester) async {
      final retrieval = FakeRetrievalRepository();
      await tester.pumpWidget(_screen(retrieval));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField), '');
      await tester.tap(find.text('Build a plan'));
      await tester.pumpAndSettle();

      expect(find.text('Enter a budget.'), findsOneWidget);
      expect(retrieval.buildCount, 0);
    });

    testWidgets('a zero budget is a real request, not a validation failure',
        (tester) async {
      final retrieval = FakeRetrievalRepository();
      await tester.pumpWidget(_screen(retrieval));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField), '0');
      await tester.tap(find.text('Build a plan'));
      await tester.pumpAndSettle();

      // docs §9: ₱0 is just budget = 0, never a separate lesser flow.
      expect(retrieval.buildCount, 1);
      expect(find.text('Enter a budget.'), findsNothing);
    });
  });
}
