import 'simple_plan.dart';

/// A plan that has been written to the database and read back.
///
/// It **contains** a [SimplePlan] rather than extending or re-parsing one,
/// because `public.read_plan` deliberately returns the same jsonb shape the two
/// composers return. That is what lets one renderer draw a fresh plan and a
/// saved one and guarantees they cannot disagree about a fare — there is one
/// shape and one set of costing rules, not two kept in step by hand.
///
/// Composition also keeps [SimplePlan]'s own doc comment honest: it really is
/// the transient computed result, never persisted. The persisted thing is this,
/// and it is a different type because it has an identity, a title and a
/// lifecycle that the transient one does not.
class SavedPlan {
  const SavedPlan({
    required this.id,
    required this.status,
    required this.plan,
    this.title,
    this.generatedByModel,
  });

  factory SavedPlan.fromMap(Map<String, dynamic> map) => SavedPlan(
        id: map['plan_id'] as String,
        title: map['title'] as String?,
        status: map['status'] as String? ?? 'draft',
        generatedByModel: map['generated_by_model'] as String?,
        plan: SimplePlan.fromMap(map),
      );

  final String id;

  /// What the user called it, or the model's title. Null is fine — the screen
  /// falls back to the date rather than inventing a name.
  final String? title;

  /// `draft` | `active` | `completed`. Phase 6 moves plans through these; today
  /// everything saves as a draft.
  final String status;

  /// Which model composed it, or null when the Phase 2 builder did. Recorded
  /// because D8 makes the model a config choice, and a plan that cannot say
  /// which model produced it cannot be audited after a swap.
  final String? generatedByModel;

  /// The stops, legs and totals — the same types the request screen renders.
  final SimplePlan plan;
}
