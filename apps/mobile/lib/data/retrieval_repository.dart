import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/simple_plan.dart';
import 'repository_exception.dart';
import 'supabase_client_provider.dart';

/// Retrieval: turning a budget, a place to start and a time into a costed plan.
///
/// Every filter, distance, fare and total is computed by Postgres functions —
/// `public.retrieve_candidates`, `public.fare_for`, `public.build_simple_plan`.
/// This class does no arithmetic on money, which is CLAUDE.md invariant 3, and
/// it is why there is no `PlacesRepository` beside it: retrieval is one call
/// returning one composed answer, not a set of tables to query and join on the
/// device.
///
/// The same functions back Phase 3's Edge Function, so what the app renders and
/// what the model is given are the same rows by construction, not by agreement.
class RetrievalRepository {
  const RetrievalRepository(this._client);

  final SupabaseClient _client;

  /// The barangays a plan can start from, with a coordinate for each.
  Future<List<OriginArea>> originAreas(String city) {
    return guard(
      () async {
        final rows = await _client.rpc<List<dynamic>>(
          'origin_areas',
          params: {'p_city': city},
        );

        return rows
            .map((row) => OriginArea.fromMap(row as Map<String, dynamic>))
            .toList();
      },
      fallback: 'Could not load the areas we cover.',
    );
  }

  /// Builds a plan. One round trip: the server retrieves, composes and costs.
  ///
  /// [plannedForUtc] must be UTC — the server converts to Manila wall clock to
  /// decide what is open.
  Future<SimplePlan> buildSimplePlan({
    required String city,
    required int budgetPhpCents,
    required DateTime plannedForUtc,
    required OriginArea origin,
    required Set<String> ownedResourceIds,
  }) {
    return guard(
      () async {
        final payload = await _client.rpc<Map<String, dynamic>>(
          'build_simple_plan',
          params: {
            'p_city': city,
            'p_budget_php_cents': budgetPhpCents,
            'p_at': plannedForUtc.toUtc().toIso8601String(),
            'p_origin_area': origin.area,
            'p_origin_lat': origin.lat,
            'p_origin_lng': origin.lng,
            'p_owned_resource_ids': ownedResourceIds.toList(),
          },
        );

        return SimplePlan.fromMap(payload);
      },
      fallback: 'Could not build a plan.',
    );
  }
}

final retrievalRepositoryProvider = Provider<RetrievalRepository>(
  (ref) => RetrievalRepository(ref.watch(supabaseClientProvider)),
);
