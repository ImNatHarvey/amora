import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/plan/plan_timeline.dart';
import 'package:mobile/models/simple_plan.dart';
import 'package:mobile/theme/app_theme.dart';
import 'package:mobile/theme/app_tokens.dart';

/// The timeline and cost summary.
///
/// The map is deliberately not tested here: tiles need a network, and a widget
/// test that stubs them would be testing the stub. It is a device check.
Map<String, dynamic> _payload({
  int placePrice = 6000,
  bool fareKnown = true,
  String mode = 'walk',
  String? note,
}) =>
    {
      'planned_for': '2026-08-08T10:00:00+00:00',
      'budget_php_cents': 60000,
      'party_size': 2,
      'radius_m': 3000,
      'origin': {'area': 'Poblacion', 'lat': 14.7966, 'lng': 120.9268},
      'stops': [
        {
          'seq': 1,
          'place_id': 'p1',
          'slug': 'test-milk-tea-corner',
          'name': 'Milk Tea Corner',
          'category': 'cafe',
          'barangay': 'Poblacion',
          'lat': 14.7955,
          'lng': 120.9273,
          'opening_hours': null,
          'price_min_php_cents': placePrice,
          'price_max_php_cents': placePrice == 0 ? 0 : placePrice * 2,
          'party_price_php_cents': placePrice * 2,
          'distance_m': 132,
          'note': note,
        },
      ],
      'legs': [
        {
          'seq': 1,
          'from_name': 'Poblacion',
          'to_name': 'Milk Tea Corner',
          'mode': mode,
          'distance_m': 132,
          'fare_php_cents': fareKnown ? 3000 : null,
          'fare_known': fareKnown,
        },
      ],
      'totals': {
        'places_php_cents': placePrice * 2,
        'fares_php_cents': fareKnown ? 3000 : 0,
        'total_php_cents': placePrice * 2 + (fareKnown ? 3000 : 0),
        'unpriced_legs': fareKnown ? 0 : 1,
        'is_complete': fareKnown,
      },
      'candidate_activities': <dynamic>[],
    };

Future<void> _pump(WidgetTester tester, Widget child) => tester.pumpWidget(
      MaterialApp(theme: AppTheme.light, home: Scaffold(body: child)),
    );

void main() {
  testWidgets('the timeline draws stops, legs and totals', (tester) async {
    final plan = SimplePlan.fromMap(_payload());
    await _pump(tester, PlanTimeline(plan: plan));

    expect(find.text('Milk Tea Corner'), findsOneWidget);
    // Per-person price carries "each" beside a party total, or the two read as
    // a contradiction.
    expect(find.textContaining('₱60–₱120 each'), findsOneWidget);
    expect(find.textContaining('walk'), findsOneWidget);
    expect(find.textContaining('Total'), findsOneWidget);
  });

  testWidgets('the stop number is present, because the map repeats it',
      (tester) async {
    // Same number, same colour, always (design system §5). If this stops being
    // rendered the map's pins point at nothing.
    await _pump(tester, PlanTimeline(plan: SimplePlan.fromMap(_payload())));

    expect(find.text('1'), findsOneWidget);
  });

  testWidgets('an unpriced leg says so rather than reading as free',
      (tester) async {
    final plan = SimplePlan.fromMap(_payload(fareKnown: false));
    await _pump(tester, PlanTimeline(plan: plan));

    expect(find.textContaining('fare not recorded'), findsOneWidget);
    // The total is a floor, and the screen has to admit it.
    expect(find.textContaining('At least'), findsOneWidget);
  });

  testWidgets('a free stop takes no per-head qualifier', (tester) async {
    final plan = SimplePlan.fromMap(_payload(placePrice: 0));
    await _pump(tester, PlanTimeline(plan: plan));

    expect(find.textContaining('free each'), findsNothing);
  });

  testWidgets("the model's note renders under its stop", (tester) async {
    final plan = SimplePlan.fromMap(_payload(note: 'Quiet enough to talk.'));
    await _pump(tester, PlanTimeline(plan: plan));

    expect(find.text('Quiet enough to talk.'), findsOneWidget);
  });

  testWidgets('a stop is tappable only when there is somewhere to go',
      (tester) async {
    final plan = SimplePlan.fromMap(_payload());

    await _pump(tester, PlanTimeline(plan: plan));
    expect(find.byIcon(Icons.chevron_right), findsNothing);

    var tapped = 0;
    await _pump(tester, PlanTimeline(plan: plan, onStopTap: (_) => tapped += 1));
    expect(find.byIcon(Icons.chevron_right), findsOneWidget);

    await tester.tap(find.text('Milk Tea Corner'));
    expect(tapped, 1);
  });

  group('cost summary', () {
    testWidgets('says nothing when the plan fits', (tester) async {
      await _pump(
        tester,
        const PlanCostSummary(
          totals: PlanTotals(
            placesPhpCents: 12000,
            faresPhpCents: 0,
            totalPhpCents: 12000,
            unpricedLegs: 0,
            isComplete: true,
          ),
          budgetPhpCents: 60000,
        ),
      );

      expect(find.textContaining('Over your budget'), findsNothing);
    });

    testWidgets('over budget carries an icon as well as a colour',
        (tester) async {
      // Colour alone fails for red-green colourblind users at any hue, which is
      // why the icon is part of the token set rather than a nicety.
      await _pump(
        tester,
        const PlanCostSummary(
          totals: PlanTotals(
            placesPhpCents: 80000,
            faresPhpCents: 0,
            totalPhpCents: 80000,
            unpricedLegs: 0,
            isComplete: true,
          ),
          budgetPhpCents: 60000,
        ),
      );

      expect(find.textContaining('Over your budget of ₱600'), findsOneWidget);
      expect(
        find.byIcon(AppTheme.light.tokens.costOverBudgetIcon),
        findsOneWidget,
      );
    });

    /// The summary at [totalPhpCents], against a budget of ₱600.
    ///
    /// Pumped twice with different totals, because AnimatedSwitcher does not
    /// animate its first child — and the real moment this fires is an edit
    /// pushing an already-visible plan over, not a screen opening over.
    Future<void> pumpTotal(
      WidgetTester tester,
      int totalPhpCents, {
      required bool disableAnimations,
    }) => tester.pumpWidget(
          MediaQuery(
            data: MediaQueryData(disableAnimations: disableAnimations),
            child: MaterialApp(
              theme: AppTheme.light,
              home: Scaffold(
                body: PlanCostSummary(
                  totals: PlanTotals(
                    placesPhpCents: totalPhpCents,
                    faresPhpCents: 0,
                    totalPhpCents: totalPhpCents,
                    unpricedLegs: 0,
                    isComplete: true,
                  ),
                  budgetPhpCents: 60000,
                ),
              ),
            ),
          ),
        );

    // Both directions, for the reason the splash test gives: "renders at once"
    // passes against a build that never animates, and "grows from nothing"
    // passes against one that ignores the accessibility setting. Neither half
    // is worth anything alone.

    testWidgets('grows in when an edit pushes the plan over', (tester) async {
      await pumpTotal(tester, 12000, disableAnimations: false);
      expect(find.textContaining('Over your budget'), findsNothing);

      await pumpTotal(tester, 80000, disableAnimations: false);
      await tester.pump();

      // Mid-transition: in the tree, not yet at full height.
      final growing =
          tester.getSize(find.byType(PlanCostSummary)).height;

      await tester.pumpAndSettle();
      final settled =
          tester.getSize(find.byType(PlanCostSummary)).height;

      expect(settled, greaterThan(0));
      expect(growing, lessThan(settled));
    });

    testWidgets('reduced motion renders the end state at once', (tester) async {
      // §6: the end state immediately — not a shorter animation, not a blank
      // space. One pump, no settling.
      await pumpTotal(tester, 12000, disableAnimations: true);
      await pumpTotal(tester, 80000, disableAnimations: true);
      await tester.pump();

      expect(find.textContaining('Over your budget of ₱600'), findsOneWidget);
      expect(
        tester.getSize(find.byType(PlanCostSummary)).height,
        greaterThan(0),
      );
    });
  });

  test('a leg reports itself as a list of segments', () {
    // §12.3: a day trip is a bus, then an MRT ride, then a jeep. Widgets read
    // `segments` so that arriving stays additive.
    final plan = SimplePlan.fromMap(_payload());

    expect(plan.legs.single.segments, hasLength(1));
    expect(plan.legs.single.segments.single.mode, 'walk');
  });

  test('the origin coordinate survives parsing, because the map needs it', () {
    // It used to be dropped by fromMap. The first leg starts at the origin
    // rather than at a stop, so without this the map loses the leg the user
    // actually begins with.
    final plan = SimplePlan.fromMap(_payload());

    expect(plan.originLat, 14.7966);
    expect(plan.originLng, 120.9268);
  });
}
