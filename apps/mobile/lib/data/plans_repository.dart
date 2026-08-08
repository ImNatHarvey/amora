import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/saved_plan.dart';
import 'repository_exception.dart';
import 'supabase_client_provider.dart';

/// Saved plans: writing one, listing them, reading one back.
///
/// Every method is a single RPC. Saving in particular is one call rather than
/// three inserts, because `plan_legs` references `plan_items.id` — three round
/// trips from a phone on mobile data is three chances to leave half a plan
/// behind (`save_plan`, Phase 4 migration).
///
/// **There are no ownership checks here.** RLS decides who can read and write
/// what, in Postgres, and a second implementation in Dart could only ever
/// disagree with it — which is CLAUDE.md invariant 6.
class PlansRepository {
  const PlansRepository(this._client);

  final SupabaseClient _client;

  /// Writes a plan and returns its id.
  ///
  /// [payload] is exactly what `build_simple_plan` or the generate-plan Edge
  /// Function returned. The server takes the place ids, their order and the
  /// model's notes from it and **recomputes every peso, distance and fare**
  /// itself (invariant 3) — so this method is not passing money to be stored,
  /// it is passing a shape to be re-costed.
  Future<String> save({
    required Map<String, dynamic> payload,
    String? title,
  }) {
    return guard(
      () async {
        final id = await _client.rpc<String>(
          'save_plan',
          params: {'p_payload': payload, 'p_title': title},
        );
        return id;
      },
      fallback: 'Could not save this plan.',
    );
  }

  /// The signed-in user's plans, newest first.
  ///
  /// A list view needs a title, a date and a total — not every stop — so this
  /// reads the `plans` rows directly rather than calling `read_plan` once per
  /// plan, which would be one round trip per row for data nothing shows yet.
  Future<List<PlanSummary>> listMine() {
    return guard(
      () async {
        final rows = await _client
            .from('plans')
            .select('id, title, planned_for, budget_php_cents, status, '
                'generated_by_model, origin_area, created_at')
            .order('planned_for', ascending: false);

        return rows.map(PlanSummary.fromMap).toList();
      },
      fallback: 'Could not load your plans.',
    );
  }

  /// Applies an edit and returns the **recomputed** plan.
  ///
  /// [stops] is the whole new ordered list, not a delta. Order is the one thing
  /// the client is authoritative about — it is a preference, not a fact — while
  /// every peso, distance and fare is derived server-side from `places` and
  /// `transit_fares` by the same `write_plan_stops` that `save_plan` uses. A
  /// delta API would need four code paths that each recompute legs correctly,
  /// which is four chances to get it wrong against one.
  ///
  /// Returns the new plan rather than an id so an edit costs one round trip
  /// instead of a write followed by a read — and so this screen can never
  /// render a total it worked out for itself.
  ///
  /// [targetPlaceId] is what makes the edit log answer invariant 7's question.
  Future<SavedPlan> edit({
    required String planId,
    required PlanEditType type,
    required List<Map<String, dynamic>> stops,
    String? targetPlaceId,
  }) {
    return guard(
      () async {
        final payload = await _client.rpc<Map<String, dynamic>>(
          'edit_plan',
          params: {
            'p_plan_id': planId,
            'p_edit_type': type.wireName,
            'p_stops': stops,
            'p_target_place_id': targetPlaceId,
          },
        );
        return SavedPlan.fromMap(payload);
      },
      fallback: 'Could not change this plan.',
    );
  }

  /// Adds a stop of the user's own and returns its place id.
  ///
  /// The row lands quarantined — `source='user'`,
  /// `verification_tier='user_submitted'` — and is excluded from retrieval for
  /// **everyone, including its submitter** (invariant 5). Those three columns
  /// are set by `add_user_place` in Postgres, never sent from here, so nothing
  /// this method could get wrong can widen what the shared catalogue contains.
  Future<String> addUserPlace({
    required String name,
    required String category,
    required String barangay,
    required double lat,
    required double lng,
    int priceMinPhpCents = 0,
    int? priceMaxPhpCents,
  }) {
    return guard(
      () async {
        return await _client.rpc<String>(
          'add_user_place',
          params: {
            'p_name': name,
            'p_category': category,
            'p_barangay': barangay,
            'p_lat': lat,
            'p_lng': lng,
            'p_price_min_php_cents': priceMinPhpCents,
            'p_price_max_php_cents': priceMaxPhpCents,
          },
        );
      },
      fallback: 'Could not add that stop.',
    );
  }

  /// One plan, in the same shape the composers return.
  ///
  /// Null when it does not exist **or** is not this user's — RLS makes those
  /// the same answer on purpose, and a client has no business telling them
  /// apart.
  Future<SavedPlan?> byId(String id) {
    return guard(
      () async {
        final payload = await _client.rpc<Map<String, dynamic>?>(
          'read_plan',
          params: {'p_plan_id': id},
        );
        if (payload == null) return null;
        return SavedPlan.fromMap(payload);
      },
      fallback: 'Could not open that plan.',
    );
  }
}

/// The four things a user can do to a saved plan.
///
/// An enum rather than a string because these are the exact values
/// `plan_edits.edit_type` accepts — Postgres rejects anything else, and a typo
/// in Dart should not be how that gets discovered.
enum PlanEditType {
  add('add'),
  remove('remove'),
  reorder('reorder'),
  retime('retime');

  const PlanEditType(this.wireName);

  /// What Postgres stores. Kept explicit rather than using `name`, so renaming
  /// a Dart constant cannot silently change a database value.
  final String wireName;
}

/// A row in the plans list. Deliberately thinner than [SavedPlan].
class PlanSummary {
  const PlanSummary({
    required this.id,
    required this.plannedForUtc,
    required this.budgetPhpCents,
    required this.status,
    this.title,
    this.originArea,
    this.generatedByModel,
  });

  factory PlanSummary.fromMap(Map<String, dynamic> map) => PlanSummary(
        id: map['id'] as String,
        title: map['title'] as String?,
        plannedForUtc: DateTime.parse(map['planned_for'] as String).toUtc(),
        budgetPhpCents: map['budget_php_cents'] as int,
        status: map['status'] as String? ?? 'draft',
        originArea: map['origin_area'] as String?,
        generatedByModel: map['generated_by_model'] as String?,
      );

  final String id;
  final String? title;
  final DateTime plannedForUtc;
  final int budgetPhpCents;
  final String status;
  final String? originArea;
  final String? generatedByModel;
}

final plansRepositoryProvider = Provider<PlansRepository>(
  (ref) => PlansRepository(ref.watch(supabaseClientProvider)),
);
