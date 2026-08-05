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
