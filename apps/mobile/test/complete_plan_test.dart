import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/data/memories_repository.dart';
import 'package:mobile/data/plans_repository.dart';
import 'package:mobile/features/memory/memory_timeline_screen.dart';
import 'package:mobile/features/plan/plan_detail_screen.dart';
import 'package:mobile/models/memory.dart';
import 'package:mobile/models/saved_plan.dart';
import 'package:mobile/theme/app_theme.dart';
import 'package:mobile/util/format.dart';

import 'fakes.dart';

/// Phase 6 — completion, actuals and closures.
///
/// **Nothing here asserts a total, and nothing asserts a per-person figure.**
/// `complete_plan` divides each stop's party figure by `party_size` and derives
/// the plan's actual spend itself, both verified in SQL against `places` and
/// `transit_fares` (invariant 3, §9). What a widget test can honestly check is
/// what the sheet *sends*: which figures, under which seq, and on which paths it
/// sends nothing at all.
///
/// The last of those is the point of several tests below. A completion that
/// silently writes no reports looks identical on screen to one that writes them
/// all — the user sees the same "saved" either way — so the only place that
/// difference is visible is here.

Map<String, dynamic> _stop(String id, String name, int seq, int partyPrice) => {
      'seq': seq,
      'place_id': id,
      'slug': 'test-$id',
      'name': name,
      'category': 'cafe',
      'barangay': 'Poblacion',
      'lat': 14.7955 + seq / 1000,
      'lng': 120.9273,
      'opening_hours': null,
      'price_min_php_cents': partyPrice ~/ 2,
      'price_max_php_cents': null,
      'party_price_php_cents': partyPrice,
      'distance_m': 100 * seq,
      'note': null,
      'activity_id': null,
      'start_time': null,
      'duration_minutes': null,
    };

Map<String, dynamic> _leg(
  int seq,
  String from,
  String to, {
  int? fare,
}) =>
    {
      'seq': seq,
      'from_name': from,
      'to_name': to,
      'mode': fare == null ? null : 'tricycle',
      'distance_m': 1200,
      'fare_php_cents': fare,
      'fare_known': fare != null,
    };

Map<String, dynamic> _payload({String status = 'draft'}) => {
      'plan_id': 'plan-1',
      'title': 'Saturday',
      'status': status,
      'planned_for': '2026-08-15T11:00:00+00:00',
      'budget_php_cents': 100000,
      'party_size': 2,
      'origin': {'area': 'Poblacion', 'lat': 14.7966, 'lng': 120.9268},
      'stops': [
        // ₱360 and ₱400 for the party, so a correct send is unmistakable: the
        // per-person halves (18000, 20000) appear nowhere in these assertions,
        // which is what makes a double division visible.
        _stop('p1', 'Dessert Bar', 1, 36000),
        _stop('p2', 'Casual Diner', 2, 40000),
      ],
      'legs': [
        _leg(1, 'Poblacion', 'Dessert Bar', fare: 3000),
        // Deliberately unpriced: no fare recorded for this barangay pair.
        _leg(2, 'Dessert Bar', 'Casual Diner'),
      ],
      'totals': const {
        'places_php_cents': 76000,
        'fares_php_cents': 3000,
        'total_php_cents': 79000,
        'unpriced_legs': 1,
        'is_complete': false,
      },
      'candidate_activities': <dynamic>[],
    };

Widget _app(FakePlansRepository plans, FakeMemoriesRepository memories) {
  return ProviderScope(
    overrides: [
      plansRepositoryProvider.overrideWithValue(plans),
      memoriesRepositoryProvider.overrideWithValue(memories),
    ],
    child: MaterialApp(
      theme: AppTheme.light,
      home: const PlanDetailScreen(planId: 'plan-1'),
    ),
  );
}

/// A widget test viewport is 800 px tall and a `ListView` does not build what is
/// off-screen, so the completion sheet's lower half simply would not exist to
/// tap. Raised rather than scrolled: a scroll drags across the map and starts a
/// gesture instead of moving the list.
void _tallView(WidgetTester tester) {
  tester.view.physicalSize = const Size(1400, 4000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  group('completing a plan', () {
    testWidgets('sends every stop as a party figure, under a one-based seq',
        (tester) async {
      _tallView(tester);
      final plans = FakePlansRepository(plan: SavedPlan.fromMap(_payload()));
      final memories = FakeMemoriesRepository();

      await tester.pumpWidget(_app(plans, memories));
      await tester.pumpAndSettle();

      await tester.tap(find.text('We did this'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Save this outing'));
      await tester.pumpAndSettle();

      expect(memories.completions, hasLength(1));
      final sent = memories.completions.single;

      // Prefilled and submitted untouched: the estimate is confirmed, and it is
      // confirmed as the PARTY figure. 18000 here would mean the screen divided
      // a number the server also divides.
      expect(sent.stopSpends, [
        {'seq': 1, 'spent_php_cents': 36000},
        {'seq': 2, 'spent_php_cents': 40000},
      ]);
    });

    testWidgets('a corrected amount replaces the estimate', (tester) async {
      _tallView(tester);
      final plans = FakePlansRepository(plan: SavedPlan.fromMap(_payload()));
      final memories = FakeMemoriesRepository();

      await tester.pumpWidget(_app(plans, memories));
      await tester.pumpAndSettle();
      await tester.tap(find.text('We did this'));
      await tester.pumpAndSettle();

      // They actually spent ₱450 at the diner.
      await tester.enterText(find.byKey(const ValueKey('stop-spend-1')), '450');
      await tester.tap(find.text('Save this outing'));
      await tester.pumpAndSettle();

      expect(memories.completions.single.stopSpends, [
        {'seq': 1, 'spent_php_cents': 36000},
        {'seq': 2, 'spent_php_cents': 45000},
      ]);
    });

    testWidgets('a cleared amount is omitted, not sent as zero', (tester) async {
      _tallView(tester);
      final plans = FakePlansRepository(plan: SavedPlan.fromMap(_payload()));
      final memories = FakeMemoriesRepository();

      await tester.pumpWidget(_app(plans, memories));
      await tester.pumpAndSettle();
      await tester.tap(find.text('We did this'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const ValueKey('stop-spend-0')), '');
      await tester.tap(find.text('Save this outing'));
      await tester.pumpAndSettle();

      // Only stop 2. A `{'seq': 1, 'spent_php_cents': 0}` here would file the
      // café as free — the report would say ₱0 rather than saying nothing, and
      // 6b would take a median over it.
      expect(memories.completions.single.stopSpends, [
        {'seq': 2, 'spent_php_cents': 40000},
      ]);
    });

    testWidgets('an unpriced leg still offers a field, and what is typed is sent',
        (tester) async {
      _tallView(tester);
      final plans = FakePlansRepository(plan: SavedPlan.fromMap(_payload()));
      final memories = FakeMemoriesRepository();

      await tester.pumpWidget(_app(plans, memories));
      await tester.pumpAndSettle();
      await tester.tap(find.text('We did this'));
      await tester.pumpAndSettle();

      // The prompt exists at all — this is the fare no transit_fares row covers,
      // and the couple who just paid it is the only source there will ever be.
      expect(find.text('We had no fare for this — what did it cost?'),
          findsOneWidget);

      await tester.enterText(find.byKey(const ValueKey('leg-fare-1')), '25');
      await tester.tap(find.text('Save this outing'));
      await tester.pumpAndSettle();

      expect(memories.completions.single.legFares, [
        {'seq': 1, 'fare_php_cents': 3000},
        {'seq': 2, 'fare_php_cents': 2500},
      ]);
    });

    testWidgets('with no photo it still writes every report', (tester) async {
      _tallView(tester);
      final plans = FakePlansRepository(plan: SavedPlan.fromMap(_payload()));
      // photoToReturn stays null, as it must in a test with no camera.
      final memories = FakeMemoriesRepository();

      await tester.pumpWidget(_app(plans, memories));
      await tester.pumpAndSettle();
      await tester.tap(find.text('We did this'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save this outing'));
      await tester.pumpAndSettle();

      final sent = memories.completions.single;
      expect(sent.photoPath, isNull);
      expect(memories.uploadCount, 0);
      // The whole point: the correction loop does not depend on a photograph.
      expect(sent.stopSpends, hasLength(2));
    });

    testWidgets('a rating is only sent when given', (tester) async {
      _tallView(tester);
      final plans = FakePlansRepository(plan: SavedPlan.fromMap(_payload()));
      final memories = FakeMemoriesRepository();

      await tester.pumpWidget(_app(plans, memories));
      await tester.pumpAndSettle();
      await tester.tap(find.text('We did this'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save this outing'));
      await tester.pumpAndSettle();

      // Not 3. An unrated outing is not an average one, and defaulting would
      // fabricate the only subjective figure the app stores.
      expect(memories.completions.single.rating, isNull);
    });

    testWidgets('tapping the fourth star sends 4', (tester) async {
      _tallView(tester);
      final plans = FakePlansRepository(plan: SavedPlan.fromMap(_payload()));
      final memories = FakeMemoriesRepository();

      await tester.pumpWidget(_app(plans, memories));
      await tester.pumpAndSettle();
      await tester.tap(find.text('We did this'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('4 of 5'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save this outing'));
      await tester.pumpAndSettle();

      expect(memories.completions.single.rating, 4);
    });

    testWidgets('a failure keeps the sheet open with the figures intact',
        (tester) async {
      _tallView(tester);
      final plans = FakePlansRepository(plan: SavedPlan.fromMap(_payload()));
      final memories = FakeMemoriesRepository(error: Exception('server said no'));

      await tester.pumpWidget(_app(plans, memories));
      await tester.pumpAndSettle();
      await tester.tap(find.text('We did this'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('stop-spend-0')), '999');
      await tester.tap(find.text('Save this outing'));
      await tester.pumpAndSettle();

      // Still on the sheet, still holding what was typed. Closing on failure
      // would make the user re-enter an evening they already reported.
      expect(find.text('Save this outing'), findsOneWidget);
      expect(find.text('999'), findsOneWidget);
    });
  });

  group('a completed plan', () {
    testWidgets('offers no way to edit itself', (tester) async {
      _tallView(tester);
      final plans = FakePlansRepository(
        plan: SavedPlan.fromMap(_payload(status: 'completed')),
      );
      final memories = FakeMemoriesRepository();

      await tester.pumpWidget(_app(plans, memories));
      await tester.pumpAndSettle();

      // Every Phase 5 affordance gone: reorder, remove, retime, add. `edit_plan`
      // refuses a completed plan too — this is the UI half of one rule, and the
      // reason it is a rule is that reports describe the stop list they were
      // written against.
      expect(find.byIcon(Icons.drag_handle), findsNothing);
      expect(find.byIcon(Icons.close), findsNothing);
      expect(find.byIcon(Icons.schedule), findsNothing);
      expect(find.text('Add a stop'), findsNothing);
      expect(find.text('We did this'), findsNothing);
      expect(find.text('You did this'), findsOneWidget);
    });

    testWidgets('shows what it actually cost once the memory loads',
        (tester) async {
      _tallView(tester);
      final plans = FakePlansRepository(
        plan: SavedPlan.fromMap(_payload(status: 'completed')),
      );
      final memories = FakeMemoriesRepository(memories: [
        Memory(
          id: 'memory-1',
          planId: 'plan-1',
          createdAtUtc: DateTime.utc(2026, 8, 15),
          actualSpendPhpCents: 97501,
          caption: 'worth it',
        ),
      ]);

      await tester.pumpWidget(_app(plans, memories));
      await tester.pumpAndSettle();

      expect(find.text('It actually cost ₱975.01.'), findsOneWidget);
      expect(find.text('worth it'), findsOneWidget);
    });
  });

  group('reporting a closure', () {
    testWidgets('is reachable from a plan that has not been completed',
        (tester) async {
      _tallView(tester);
      final plans = FakePlansRepository(plan: SavedPlan.fromMap(_payload()));
      final memories = FakeMemoriesRepository();

      await tester.pumpWidget(_app(plans, memories));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Something was closed'));
      await tester.pumpAndSettle();
      // Scoped to the dialog: the stop's name is also on the timeline behind it,
      // and an unscoped finder matches both.
      await tester.tap(find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Dessert Bar'),
      ));
      await tester.pumpAndSettle();

      // §10.5's asymmetry, and the reason this test exists: the couple who found
      // a locked door abandons the plan, so this path must work without any
      // completion having happened.
      expect(memories.closures, hasLength(1));
      expect(memories.closures.single.placeId, 'p1');
      expect(memories.closures.single.planId, 'plan-1');
      expect(memories.completions, isEmpty);
    });

    testWidgets('is gone once the plan is completed', (tester) async {
      _tallView(tester);
      final plans = FakePlansRepository(
        plan: SavedPlan.fromMap(_payload(status: 'completed')),
      );

      await tester.pumpWidget(_app(plans, FakeMemoriesRepository()));
      await tester.pumpAndSettle();

      // They evidently got in, and the price reports are already filed.
      expect(find.text('Something was closed'), findsNothing);
    });
  });

  group('the memory timeline', () {
    testWidgets('explains itself when empty rather than saying "none"',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            memoriesRepositoryProvider
                .overrideWithValue(FakeMemoriesRepository()),
          ],
          child: MaterialApp(
            theme: AppTheme.light,
            home: const MemoryTimelineScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Nothing here yet'), findsOneWidget);
      expect(find.text('Your plans'), findsOneWidget);
    });

    testWidgets('renders a memory that has no photo', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            memoriesRepositoryProvider.overrideWithValue(
              FakeMemoriesRepository(memories: [
                Memory(
                  id: 'memory-1',
                  planId: 'plan-1',
                  createdAtUtc: DateTime.utc(2026, 8, 15),
                  planTitle: 'Saturday',
                  actualSpendPhpCents: 45000,
                  rating: 4,
                ),
              ]),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.light,
            home: const MemoryTimelineScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // The card must not depend on an image: most rows will have none, and a
      // photo-shaped hole is worse than no photo.
      expect(find.text('Saturday'), findsOneWidget);
      expect(find.text('Spent ₱450'), findsOneWidget);
    });
  });

  group('centavosFromPesoText', () {
    // Tested in both directions, like the constraint hash and the utterance
    // normaliser: a money parser can fail by rejecting what people type (a
    // figure silently lost) or by accepting what they did not mean (a wrong
    // figure filed as evidence). A suite checking only one direction passes
    // trivially if you make everything null.
    test('reads what people actually type', () {
      expect(centavosFromPesoText('400'), 40000);
      expect(centavosFromPesoText('400.50'), 40050);
      expect(centavosFromPesoText('₱400'), 40000);
      expect(centavosFromPesoText('1,200'), 120000);
      expect(centavosFromPesoText(' 250 '), 25000);
      // ₱0 is a real amount and a real answer — a free place (§9).
      expect(centavosFromPesoText('0'), 0);
    });

    test('refuses what is not an amount, and says so as null', () {
      expect(centavosFromPesoText(null), isNull);
      expect(centavosFromPesoText(''), isNull);
      expect(centavosFromPesoText('   '), isNull);
      expect(centavosFromPesoText('abc'), isNull);
      // Negative spending is not a thing.
      expect(centavosFromPesoText('-100'), isNull);
    });

    test('round-trips against pesos, which is the pair that has to agree', () {
      for (final cents in [0, 2500, 18000, 40050, 120000]) {
        expect(centavosFromPesoText(pesos(cents, zeroIsFree: false)), cents);
      }
    });
  });
}
