import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/data/plans_repository.dart';
import 'package:mobile/features/plan/plan_providers.dart';
import 'package:mobile/features/plan/plan_timeline.dart';
import 'package:mobile/models/saved_plan.dart';
import 'package:mobile/theme/app_theme.dart';
import 'package:mobile/util/manila_time.dart';

import 'fakes.dart';

/// Phase 5 editing.
///
/// **Nothing here asserts a total.** Every peso is recomputed by
/// `write_plan_stops` in Postgres and verified there against `places` and
/// `transit_fares` (invariant 3). What a widget test can honestly check is the
/// *stop list the screen sends* — which is the only input the client controls,
/// and the only place a client-side bug can change the answer.

Map<String, dynamic> _stop(
  String id,
  String name,
  int seq, {
  String? note,
  String? activityId,
  String? startTime,
  int? durationMinutes,
}) =>
    {
      'seq': seq,
      'place_id': id,
      'slug': 'test-$id',
      'name': name,
      'category': 'cafe',
      'barangay': 'Poblacion',
      'lat': 14.7955 + seq / 1000,
      'lng': 120.9273,
      'opening_hours': null,
      'price_min_php_cents': 10000,
      'price_max_php_cents': 20000,
      'party_price_php_cents': 20000,
      'distance_m': 100 * seq,
      'note': note,
      'activity_id': activityId,
      'start_time': startTime,
      'duration_minutes': durationMinutes,
    };

const _names = {'p1': 'First', 'p2': 'Second', 'p3': 'Third'};

Map<String, dynamic> _payload({
  List<String> stops = const ['p1', 'p2', 'p3'],
}) =>
    {
      'plan_id': 'plan-1',
      'title': 'Saturday',
      'status': 'draft',
      'planned_for': '2026-08-08T10:00:00+00:00',
      'budget_php_cents': 100000,
      'party_size': 2,
      'origin': {'area': 'Poblacion', 'lat': 14.7966, 'lng': 120.9268},
      'stops': [
        for (var i = 0; i < stops.length; i += 1)
          _stop(stops[i], _names[stops[i]]!, i + 1),
      ],
      'legs': const [],
      'totals': {
        'places_php_cents': 60000,
        'fares_php_cents': 0,
        'total_php_cents': 60000,
        'unpriced_legs': 0,
        'is_complete': true,
      },
      'candidate_activities': <dynamic>[],
    };

/// Drives the notifier directly. The reorder arithmetic is the part that can be
/// wrong without any test noticing, so it is reached without a drag gesture.
Future<PlanEditor> _editor(FakePlansRepository repo) async {
  final container = ProviderContainer(
    overrides: [plansRepositoryProvider.overrideWithValue(repo)],
  );
  addTearDown(container.dispose);

  await container.read(savedPlanProvider('plan-1').future);
  return container.read(savedPlanProvider('plan-1').notifier);
}

void main() {
  group('reorder', () {
    // The timeline uses `onReorderItem`, which hands back an index already
    // adjusted for the lifted item. Adjusting again — as the deprecated
    // `onReorder` required — rotates the list by one on every downward drag,
    // and a plan whose stops quietly shuffle is worse than one that cannot be
    // edited at all. Both directions are asserted because an off-by-one shows
    // up in only one of them.
    test('dragging the first stop to the end', () async {
      final repo = FakePlansRepository(plan: SavedPlan.fromMap(_payload()));
      final editor = await _editor(repo);

      await editor.reorder(0, 2);

      expect(repo.edits.single.type, PlanEditType.reorder);
      expect(repo.edits.single.placeIds, ['p2', 'p3', 'p1']);
    });

    test('dragging the last stop to the front', () async {
      final repo = FakePlansRepository(plan: SavedPlan.fromMap(_payload()));
      final editor = await _editor(repo);

      await editor.reorder(2, 0);

      expect(repo.edits.single.placeIds, ['p3', 'p1', 'p2']);
    });

    test('a drag that lands where it started asks the server nothing',
        () async {
      final repo = FakePlansRepository(plan: SavedPlan.fromMap(_payload()));
      final editor = await _editor(repo);

      await editor.reorder(1, 1);

      expect(repo.edits, isEmpty);
    });

    test('the moved stop is what gets logged', () async {
      // Invariant 7's telemetry groups by place, so naming the wrong one is a
      // silent corruption of the only signal this table exists to carry.
      final repo = FakePlansRepository(plan: SavedPlan.fromMap(_payload()));
      final editor = await _editor(repo);

      await editor.reorder(0, 2);

      expect(repo.edits.single.target, 'p1');
    });
  });

  group('remove and restore', () {
    test('removing sends the remaining stops and names the one removed',
        () async {
      final repo = FakePlansRepository(plan: SavedPlan.fromMap(_payload()));
      final editor = await _editor(repo);
      final second = SavedPlan.fromMap(_payload()).plan.stops[1];

      await editor.removeStop(second);

      expect(repo.edits.single.type, PlanEditType.remove);
      expect(repo.edits.single.placeIds, ['p1', 'p3']);
      expect(repo.edits.single.target, 'p2');
    });

    test('restoring puts the stop back at its old index', () async {
      // Editing is always live, so an accidental ✕ has no "Done" to reconsider
      // before. Undo is the only thing standing between a mistap and a lost
      // stop.
      //
      // The plan here is the state *after* a removal — which is what undo
      // actually operates on. Starting from the three-stop plan would insert
      // p2 beside itself and the test would pass on a duplicate.
      final repo = FakePlansRepository(
        plan: SavedPlan.fromMap(_payload(stops: const ['p1', 'p3'])),
      );
      final editor = await _editor(repo);
      final second = SavedPlan.fromMap(_payload()).plan.stops[1];

      await editor.restoreStop(second, 1);

      expect(repo.edits.single.type, PlanEditType.add);
      expect(repo.edits.single.placeIds, ['p1', 'p2', 'p3']);
      expect(repo.edits.single.target, 'p2');
    });
  });

  test('an edit carries the model\'s note and activity pairing forward',
      () async {
    // The single highest-value assertion in this file. `note` and `activity_id`
    // are the only things the model authors (invariant 1 forbids it authoring
    // anything else), and they survive an edit only because _stopPayload copies
    // them. If that regressed, every reorder would silently strip them: the
    // plan would still render, still cost correctly, and quietly be worth less.
    // Nothing else here would fail.
    final repo = FakePlansRepository(
      plan: SavedPlan.fromMap({
        ..._payload(),
        'stops': [
          _stop('p1', 'First', 1,
              note: 'Quiet enough to talk.', activityId: 'act-1'),
          _stop('p2', 'Second', 2),
        ],
      }),
    );
    final editor = await _editor(repo);

    await editor.reorder(0, 1);

    final moved = repo.edits.single.stops
        .firstWhere((s) => s['place_id'] == 'p1');
    expect(moved['note'], 'Quiet enough to talk.');
    expect(moved['activity_id'], 'act-1');
  });

  group('retime', () {
    // The plan is 2026-08-08T10:00Z, which is 18:00 Manila the same day.
    final planned = DateTime.utc(2026, 8, 8, 10);

    test('a Manila wall-clock time is stored as the right UTC instant',
        () async {
      // The eight-hour bug, asserted by arithmetic rather than by eye. Skipping
      // manilaToUtc turns an evening into a morning and the plan still renders
      // perfectly plausibly, so nothing but a number catches it.
      final repo = FakePlansRepository(plan: SavedPlan.fromMap(_payload()));
      final editor = await _editor(repo);
      final stop = SavedPlan.fromMap(_payload()).plan.stops[1];

      // 19:30 Manila on the plan's day.
      final manila = toManila(planned);
      final startUtc = manilaToUtc(
        DateTime(manila.year, manila.month, manila.day, 19, 30),
      );

      await editor.retime(stop, startTimeUtc: startUtc, durationMinutes: 90);

      final sent =
          repo.edits.single.stops.firstWhere((s) => s['place_id'] == 'p2');
      // 19:30 Manila is 11:30 UTC the same day.
      expect(sent['start_time'], DateTime.utc(2026, 8, 8, 11, 30).toIso8601String());
      expect(sent['duration_minutes'], '90');
      expect(repo.edits.single.type, PlanEditType.retime);
    });

    test('retiming touches one stop and moves nothing', () async {
      // Order is what determines every distance and fare. A retime that
      // reordered would change the total while claiming to change a clock.
      final repo = FakePlansRepository(plan: SavedPlan.fromMap(_payload()));
      final editor = await _editor(repo);
      final stop = SavedPlan.fromMap(_payload()).plan.stops[1];

      await editor.retime(
        stop,
        startTimeUtc: DateTime.utc(2026, 8, 8, 11, 30),
        durationMinutes: 60,
      );

      expect(repo.edits.single.placeIds, ['p1', 'p2', 'p3']);
      // The untouched stops carry no timing keys at all.
      final other =
          repo.edits.single.stops.firstWhere((s) => s['place_id'] == 'p1');
      expect(other.containsKey('start_time'), isFalse);
    });

    test('clearing a time removes the key rather than sending null', () async {
      // Somebody who does not know how long they will stay must be able to say
      // so. write_plan_stops reads `->> 'duration_minutes'`, so an absent key
      // and a null both land as NULL — but sending the old value back because
      // the map was mutated rather than rebuilt would silently refuse the
      // clear.
      final repo = FakePlansRepository(
        plan: SavedPlan.fromMap({
          ..._payload(),
          'stops': [
            _stop('p1', 'First', 1,
                startTime: '2026-08-08T11:30:00.000Z', durationMinutes: 60),
          ],
        }),
      );
      final editor = await _editor(repo);
      final stop = SavedPlan.fromMap({
        ..._payload(),
        'stops': [
          _stop('p1', 'First', 1,
              startTime: '2026-08-08T11:30:00.000Z', durationMinutes: 60),
        ],
      }).plan.stops.first;

      await editor.retime(stop, startTimeUtc: null, durationMinutes: null);

      final sent = repo.edits.single.stops.single;
      expect(sent.containsKey('start_time'), isFalse);
      expect(sent.containsKey('duration_minutes'), isFalse);
    });
  });

  testWidgets('a read-only timeline offers no way to edit', (tester) async {
    // The request screen renders the same widget. If handles or ✕ buttons
    // leaked into it, a plan that has not been saved would appear editable and
    // every edit would fail — there is no plan id to edit.
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: PlanTimeline(plan: SavedPlan.fromMap(_payload()).plan),
        ),
      ),
    );

    expect(find.byIcon(Icons.drag_handle), findsNothing);
    expect(find.byIcon(Icons.close), findsNothing);
    expect(find.text('First'), findsOneWidget);
  });

  testWidgets('an editable timeline shows a handle and a remove per stop',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: SingleChildScrollView(
            child: PlanTimeline(
              plan: SavedPlan.fromMap(_payload()).plan,
              onReorder: (_, _) {},
              onRemove: (_) {},
              onRetime: (_) {},
            ),
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.drag_handle), findsNWidgets(3));
    expect(find.byIcon(Icons.close), findsNWidgets(3));
    expect(find.byIcon(Icons.schedule), findsNWidgets(3));
  });
}
