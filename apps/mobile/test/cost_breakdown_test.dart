import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/plan_request/plan_parts.dart';
import 'package:mobile/models/simple_plan.dart';
import 'package:mobile/theme/app_theme.dart';

/// Gate C — the price breakdown, tested where the rule lives.
///
/// `costBreakdownLine` decides how every plan's money reads, on three screens,
/// and is a pure function precisely so it can be checked without a render tree.
///
/// The parsing tests are written in **both directions**, which is this repo's
/// standing rule for anything that decides money: a `fromMap` that always
/// returned null lines would pass a one-sided test, and so would one that
/// invented an empty `CostLines` for a payload that has none. Those two states
/// mean different things — "this plan has no breakdown" versus "this plan's
/// breakdown is all zeroes" — and the UI renders them differently.
void main() {
  PlanTotals totalsWith({
    int places = 0,
    int fares = 0,
    int activities = 0,
    int total = 0,
    bool complete = true,
    CostLines? lines,
  }) =>
      PlanTotals(
        placesPhpCents: places,
        faresPhpCents: fares,
        activitiesPhpCents: activities,
        totalPhpCents: total,
        unpricedLegs: complete ? 0 : 1,
        isComplete: complete,
        lines: lines,
      );

  group('PlanTotals.fromMap', () {
    test('reads the five lines and the activities total', () {
      final totals = PlanTotals.fromMap(const {
        'places_php_cents': 36000,
        'fares_php_cents': 3000,
        'activities_php_cents': 20000,
        'total_php_cents': 59000,
        'unpriced_legs': 0,
        'is_complete': true,
        'lines': {
          'fares': 3000,
          'food': 36000,
          'materials': 20000,
          'activities': 0,
          'gifts': 0,
        },
      });

      expect(totals.activitiesPhpCents, 20000);
      expect(totals.lines, isNotNull);
      expect(totals.lines!.faresPhpCents, 3000);
      expect(totals.lines!.foodPhpCents, 36000);
      expect(totals.lines!.materialsPhpCents, 20000);
      expect(totals.lines!.activitiesPhpCents, 0);
      expect(totals.lines!.giftsPhpCents, 0);
    });

    test('the five lines sum to the total, which is the whole property', () {
      final totals = PlanTotals.fromMap(const {
        'places_php_cents': 90000,
        'fares_php_cents': 3000,
        'activities_php_cents': 10000,
        'total_php_cents': 103000,
        'unpriced_legs': 0,
        'is_complete': true,
        'lines': {
          'fares': 3000,
          'food': 30000,
          'materials': 10000,
          'activities': 0,
          'gifts': 60000,
        },
      });

      final lines = totals.lines!;
      final sum = lines.faresPhpCents +
          lines.foodPhpCents +
          lines.materialsPhpCents +
          lines.activitiesPhpCents +
          lines.giftsPhpCents;

      expect(sum, totals.totalPhpCents);
    });

    test('a payload from before the breakdown existed parses with null lines',
        () {
      // A `plan_cache` entry written by an older function. It stays valid until
      // places_version() moves, so this is a live shape, not a historical one.
      final totals = PlanTotals.fromMap(const {
        'places_php_cents': 30000,
        'fares_php_cents': 0,
        'total_php_cents': 30000,
        'unpriced_legs': 0,
        'is_complete': true,
      });

      expect(totals.lines, isNull);
      expect(totals.activitiesPhpCents, 0);
      expect(totals.totalPhpCents, 30000);
    });
  });

  group('costBreakdownLine', () {
    test('shows every line that is something', () {
      final line = costBreakdownLine(totalsWith(
        total: 113000,
        lines: const CostLines(
          faresPhpCents: 3000,
          foodPhpCents: 30000,
          materialsPhpCents: 20000,
          activitiesPhpCents: 10000,
          giftsPhpCents: 50000,
        ),
      ));

      expect(line, 'fares ₱30 · food ₱300 · materials ₱200 · '
          'activities ₱100 · gifts ₱500');
    });

    test('hides the four category lines when they are zero', () {
      final line = costBreakdownLine(totalsWith(
        total: 33000,
        lines: const CostLines(
          faresPhpCents: 3000,
          foodPhpCents: 30000,
          materialsPhpCents: 0,
          activitiesPhpCents: 0,
          giftsPhpCents: 0,
        ),
      ));

      expect(line, 'fares ₱30 · food ₱300');
      expect(line, isNot(contains('materials')));
      expect(line, isNot(contains('gifts')));
    });

    test('keeps fares at ₱0, because every outing involves getting there', () {
      final line = costBreakdownLine(totalsWith(
        total: 30000,
        lines: const CostLines(
          faresPhpCents: 0,
          foodPhpCents: 30000,
          materialsPhpCents: 0,
          activitiesPhpCents: 0,
          giftsPhpCents: 0,
        ),
      ));

      expect(line, 'fares ₱0 · food ₱300');
    });

    test('never says free — ₱0 here is an addend, not a price', () {
      // docs/02-design-system.md §2: "Total free" is right, "fares free" is not.
      final line = costBreakdownLine(totalsWith(
        lines: const CostLines(
          faresPhpCents: 0,
          foodPhpCents: 0,
          materialsPhpCents: 0,
          activitiesPhpCents: 0,
          giftsPhpCents: 0,
        ),
      ));

      expect(line, 'fares ₱0');
      expect(line, isNot(contains('free')));
    });

    test('falls back to the old summary when a payload has no lines', () {
      final line = costBreakdownLine(
          totalsWith(places: 30000, fares: 2500, total: 32500));

      expect(line, 'places ₱300 · fares ₱25');
    });
  });

  // The rule above is worth nothing if no widget calls it. This repo has twice
  // shipped correct server work that no screen could reach — `tutorial_url`
  // went four phases without a renderer, and `edit_plan` accepted a retime that
  // nothing in Flutter ever invoked. One widget test closes that gap for all
  // three call sites, since TotalsBlock is the only renderer.
  testWidgets('TotalsBlock renders the breakdown, not just the total',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: TotalsBlock(
          totals: totalsWith(
            total: 53000,
            lines: const CostLines(
              faresPhpCents: 3000,
              foodPhpCents: 30000,
              materialsPhpCents: 20000,
              activitiesPhpCents: 0,
              giftsPhpCents: 0,
            ),
          ),
        ),
      ),
    ));

    expect(find.text('Total ₱530'), findsOneWidget);
    expect(find.text('fares ₱30 · food ₱300 · materials ₱200'), findsOneWidget);
  });
}
