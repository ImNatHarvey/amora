import 'simple_plan.dart';

/// One plan as returned by the `generate-plan` Edge Function.
///
/// Separate from [SimplePlan] rather than a flag on it, because the two differ
/// in what they *are*, not just in how they were made: a generated plan has a
/// title the model wrote, a note per stop, and an over-budget verdict, and
/// Phase 2's builder has none of those because it can never exceed the budget
/// — it skips whatever does not fit.
///
/// It shares [PlanStop], [PlanLeg] and [PlanTotals] because both composers
/// return the same shape from Postgres, costed by the same functions. That is
/// deliberate (`docs/00-architecture.md` §4a): one set of numbers, whoever
/// composed them.
class GeneratedPlan {
  const GeneratedPlan({
    required this.title,
    required this.plannedForUtc,
    required this.budgetPhpCents,
    required this.originArea,
    required this.stops,
    required this.legs,
    required this.totals,
    required this.overBudget,
    this.partySize = 2,
    this.radiusM,
  });

  factory GeneratedPlan.fromMap(Map<String, dynamic> map) {
    final origin = map['origin'] as Map<String, dynamic>;
    return GeneratedPlan(
      // The server always sends one; the fallback is for a payload cached
      // before titles existed rather than for a model that forgot.
      title: map['title'] as String? ?? 'Plan',
      plannedForUtc: DateTime.parse(map['planned_for'] as String).toUtc(),
      budgetPhpCents: map['budget_php_cents'] as int,
      originArea: origin['area'] as String,
      partySize: map['party_size'] as int? ?? 2,
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
      overBudget: map['over_budget'] as bool? ?? false,
    );
  }

  /// Written by the model. It names the plan; it never states a fact.
  final String title;
  final DateTime plannedForUtc;

  /// What the whole party can spend, not what each person can.
  final int budgetPhpCents;
  final String originArea;
  final int partySize;
  final int? radiusM;

  final List<PlanStop> stops;
  final List<PlanLeg> legs;
  final PlanTotals totals;

  /// True when the costed total exceeds the budget.
  ///
  /// A real answer, not a failure. The server does not trim stops to fit —
  /// that would be the composer lying about what it found — so the UI has to
  /// show this, and per `docs/02-design-system.md` §2 it must carry an icon as
  /// well as a colour.
  final bool overBudget;

  bool get isEmpty => stops.isEmpty;
}

/// What one call to `generate-plan` produced.
class GeneratedPlanSet {
  const GeneratedPlanSet({
    required this.plans,
    required this.cacheHit,
    this.generatedByModel,
  });

  factory GeneratedPlanSet.fromMap(Map<String, dynamic> map) {
    return GeneratedPlanSet(
      plans: [
        for (final plan in (map['plans'] as List? ?? const []))
          GeneratedPlan.fromMap(plan as Map<String, dynamic>),
      ],
      generatedByModel: map['generated_by_model'] as String?,
      cacheHit: map['cache_hit'] as bool? ?? false,
    );
  }

  final List<GeneratedPlan> plans;

  /// Which model composed these, or null on a cache hit from an older payload.
  /// Recorded because D8 makes the model a config choice, and a plan that
  /// cannot say which model produced it cannot be audited after a swap.
  final String? generatedByModel;

  /// True when this came from `plan_cache` rather than a fresh model call.
  ///
  /// Surfaced rather than hidden: the cache is the primary cost control (§7
  /// step 2), and during Phase 3 acceptance the difference between a hit and a
  /// miss is exactly what is being checked.
  final bool cacheHit;

  bool get isEmpty => plans.isEmpty;
}
