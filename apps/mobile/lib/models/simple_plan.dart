import 'activity.dart';
import 'place.dart';

/// A barangay a plan can start from, with a coordinate to measure against.
///
/// The coordinate is the centroid of the curated places in that barangay, so it
/// comes from real rows rather than anyone's memory. Barangays with no curated
/// places cannot be origins yet — see `public.origin_areas`.
class OriginArea {
  const OriginArea({
    required this.area,
    required this.lat,
    required this.lng,
    required this.placeCount,
  });

  factory OriginArea.fromMap(Map<String, dynamic> map) => OriginArea(
        area: map['area'] as String,
        lat: (map['lat'] as num).toDouble(),
        lng: (map['lng'] as num).toDouble(),
        placeCount: map['place_count'] as int,
      );

  final String area;
  final double lat;
  final double lng;

  /// How many curated places back this centroid. Low counts mean a rough
  /// centre, which is worth knowing while the catalogue is small.
  final int placeCount;
}

/// One stop on a plan: a place, plus where it falls in the sequence.
class PlanStop {
  const PlanStop({
    required this.seq,
    required this.place,
    required this.distanceFromOriginM,
  });

  factory PlanStop.fromMap(Map<String, dynamic> map) => PlanStop(
        seq: map['seq'] as int,
        place: Place.fromMap(map),
        distanceFromOriginM: map['distance_m'] as int,
      );

  final int seq;
  final Place place;

  /// Straight-line from the plan's origin, not from the previous stop, and not
  /// road distance. [PlanLeg.distanceM] is the stop-to-stop figure.
  final int distanceFromOriginM;
}

/// The journey between two consecutive points on a plan.
class PlanLeg {
  const PlanLeg({
    required this.seq,
    required this.fromName,
    required this.toName,
    required this.distanceM,
    required this.fareKnown,
    this.mode,
    this.farePhpCents,
  });

  factory PlanLeg.fromMap(Map<String, dynamic> map) => PlanLeg(
        seq: map['seq'] as int,
        fromName: map['from_name'] as String,
        toName: map['to_name'] as String,
        mode: map['mode'] as String?,
        distanceM: map['distance_m'] as int,
        farePhpCents: map['fare_php_cents'] as int?,
        fareKnown: map['fare_known'] as bool,
      );

  final int seq;
  final String fromName;
  final String toName;

  /// `walk`, `tricycle`, `jeepney`, `bus`. Null exactly when [fareKnown] is
  /// false — we do not know how someone gets there, so we do not say.
  final String? mode;
  final int distanceM;
  final int? farePhpCents;

  /// False when no fare has been recorded for this barangay pair. The fare is
  /// then left out of the totals rather than estimated: no API knows what a
  /// tricycle between two barangays costs, and inventing one would poison the
  /// only data that makes Amora worth using (docs D5).
  final bool fareKnown;
}

/// What a plan costs, and how much of that we can actually vouch for.
class PlanTotals {
  const PlanTotals({
    required this.placesPhpCents,
    required this.faresPhpCents,
    required this.totalPhpCents,
    required this.unpricedLegs,
    required this.isComplete,
  });

  factory PlanTotals.fromMap(Map<String, dynamic> map) => PlanTotals(
        placesPhpCents: map['places_php_cents'] as int,
        faresPhpCents: map['fares_php_cents'] as int,
        totalPhpCents: map['total_php_cents'] as int,
        unpricedLegs: map['unpriced_legs'] as int,
        isComplete: map['is_complete'] as bool,
      );

  /// Sum of each stop's cheapest realistic cost.
  final int placesPhpCents;

  /// Sum of the fares we have actually recorded.
  final int faresPhpCents;

  /// [placesPhpCents] + [faresPhpCents].
  final int totalPhpCents;

  /// How many legs had no recorded fare.
  final int unpricedLegs;

  /// True when every leg was priced. When false, [totalPhpCents] is a floor and
  /// the UI must say so — presenting a short total as a whole one is the kind
  /// of quiet lie this whole architecture exists to prevent.
  final bool isComplete;
}

/// The output of the Phase 2 non-AI plan builder.
///
/// Named `SimplePlan`, not `Plan`, on purpose. `plans` is a Phase 3 table with
/// its own identity, ownership and lifecycle; this is a transient computed
/// result that is never persisted. Naming it `Plan` now would quietly claim a
/// name that belongs to something else and invite the two to be conflated.
class SimplePlan {
  const SimplePlan({
    required this.plannedForUtc,
    required this.budgetPhpCents,
    required this.originArea,
    required this.stops,
    required this.legs,
    required this.totals,
    required this.candidateActivities,
    this.radiusM,
  });

  factory SimplePlan.fromMap(Map<String, dynamic> map) {
    final origin = map['origin'] as Map<String, dynamic>;
    return SimplePlan(
      plannedForUtc: DateTime.parse(map['planned_for'] as String).toUtc(),
      budgetPhpCents: map['budget_php_cents'] as int,
      originArea: origin['area'] as String,
      radiusM: map['radius_m'] as int?,
      stops: [
        for (final stop in map['stops'] as List)
          PlanStop.fromMap(stop as Map<String, dynamic>),
      ],
      legs: [
        for (final leg in map['legs'] as List)
          PlanLeg.fromMap(leg as Map<String, dynamic>),
      ],
      totals: PlanTotals.fromMap(map['totals'] as Map<String, dynamic>),
      candidateActivities: [
        for (final activity in map['candidate_activities'] as List)
          Activity.fromMap(activity as Map<String, dynamic>),
      ],
    );
  }

  final DateTime plannedForUtc;
  final int budgetPhpCents;
  final String originArea;

  /// 3000 or 5000 — which radius retrieval settled on (docs §9). Null when
  /// nothing at all came back, so the UI can distinguish "nothing within 5 km"
  /// from "nothing matched your budget".
  final int? radiusM;

  final List<PlanStop> stops;

  /// One per stop: origin to stop 1, then stop to stop. Always the same length
  /// as [stops].
  final List<PlanLeg> legs;
  final PlanTotals totals;

  /// Activities the user has the gear for, within budget. Phase 2 does not
  /// attach these to stops — pairing an activity with a place is the judgement
  /// call Gemini makes in Phase 3. They are surfaced so the resource filter is
  /// visibly working before any of that exists.
  final List<Activity> candidateActivities;

  bool get isEmpty => stops.isEmpty;
}
