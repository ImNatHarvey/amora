import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/models/plan.dart';

/// Parsing tests for what `generate-plan` returns.
///
/// These are deliberately not "does the model produce good plans" tests — that
/// is Phase 3's acceptance run against the real API, and it cannot be faked
/// here. What is worth guarding in Dart is the contract: that the payload the
/// Edge Function returns maps onto the models the screen renders, including the
/// fields Phase 2's builder never sets.
Map<String, dynamic> _payload({
  bool overBudget = false,
  String? note = 'Quiet enough to actually talk.',
}) =>
    {
      'plans': [
        {
          'title': 'Slow evening by the river',
          'valid': true,
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
              'price_min_php_cents': 6000,
              'price_max_php_cents': 12000,
              'party_price_php_cents': 12000,
              'distance_m': 132,
              'activity_id': 'a1',
              'start_time': '2026-08-08T10:30:00+00:00',
              'duration_minutes': 60,
              'note': note,
            },
          ],
          'legs': [
            {
              'seq': 1,
              'from_name': 'Poblacion',
              'to_name': 'Milk Tea Corner',
              'mode': 'walk',
              'distance_m': 132,
              'fare_php_cents': 0,
              'fare_known': true,
            },
          ],
          'totals': {
            'places_php_cents': 12000,
            'fares_php_cents': 0,
            'total_php_cents': 12000,
            'unpriced_legs': 0,
            'is_complete': true,
          },
          'over_budget': overBudget,
        },
      ],
      'generated_by_model': 'gemini-2.5-flash',
      'cache_hit': false,
    };

void main() {
  test('parses a generated plan, including the fields Phase 2 never sets',
      () {
    final set = GeneratedPlanSet.fromMap(_payload());
    final plan = set.plans.single;
    final stop = plan.stops.single;

    expect(plan.title, 'Slow evening by the river');
    expect(set.generatedByModel, 'gemini-2.5-flash');
    expect(set.cacheHit, isFalse);

    // The four fields that only exist on a generated stop. They live on the
    // shared PlanStop, so a regression here is silent rather than a crash.
    expect(stop.activityId, 'a1');
    expect(stop.durationMinutes, 60);
    expect(stop.note, 'Quiet enough to actually talk.');
    expect(stop.startTimeUtc, DateTime.utc(2026, 8, 8, 10, 30));
  });

  test('the total is taken from the server, never recomputed', () {
    // Invariant 3. If anyone later "fixes" the client by summing stops here,
    // the two implementations can disagree and neither is authoritative. This
    // payload has a deliberately impossible total to catch exactly that: a
    // client that recomputes would report 12000 and be "right".
    final payload = _payload();
    (payload['plans'] as List).first['totals']['total_php_cents'] = 99999;

    final plan = GeneratedPlanSet.fromMap(payload).plans.single;

    expect(plan.totals.totalPhpCents, 99999);
  });

  test('over budget survives parsing', () {
    // A real answer, not a failure: the server does not trim stops to fit, so
    // the UI must be able to say so.
    final plan = GeneratedPlanSet.fromMap(_payload(overBudget: true)).plans.single;

    expect(plan.overBudget, isTrue);
  });

  test('a stop with no note is fine', () {
    // The model may omit it; the schema only requires place_id.
    final plan = GeneratedPlanSet.fromMap(_payload(note: null)).plans.single;

    expect(plan.stops.single.note, isNull);
  });

  test('an empty payload is empty, not an error', () {
    // "Nothing open that fits" comes back as a valid response with no plans.
    final set = GeneratedPlanSet.fromMap(
      {'plans': [], 'cache_hit': false},
    );

    expect(set.isEmpty, isTrue);
    expect(set.generatedByModel, isNull);
  });
}
