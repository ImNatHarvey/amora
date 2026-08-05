import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/party.dart';
import '../models/plan.dart';
import '../models/simple_plan.dart';
import 'repository_exception.dart';
import 'supabase_client_provider.dart';

/// The app's only route to Gemini, and it does not look like one.
///
/// From the widget's point of view this is a repository like any other
/// (`docs/00-architecture.md` §4, path B). Nothing above this layer knows a
/// model is involved, which is what makes D8's "swapping the model is a config
/// change" true rather than aspirational.
///
/// The Gemini key is not here and never will be — it lives in Edge Function
/// secrets (invariant 4). This class knows a function name.
class PlanGenerationRepository {
  const PlanGenerationRepository(this._client);

  final SupabaseClient _client;

  static const functionName = 'generate-plan';

  /// Asks the server for three costed plans.
  ///
  /// Everything that could be wrong about the result — an invented place, a
  /// bad total — has already been rejected server-side before this returns
  /// (invariants 2 and 3). There is deliberately no client-side validation to
  /// pair with it: a second implementation here could disagree with the first,
  /// and then neither would be authoritative.
  Future<GeneratedPlanSet> generate({
    required String city,
    required int budgetPhpCents,
    required DateTime plannedForUtc,
    required OriginArea origin,
    required Set<String> ownedResourceIds,
    String? occasion,
  }) {
    return guard(
      () async {
        final response = await _client.functions.invoke(
          functionName,
          body: {
            'city': city,
            'budget_php_cents': budgetPhpCents,
            'planned_for': plannedForUtc.toUtc().toIso8601String(),
            'origin_area': origin.area,
            'origin_lat': origin.lat,
            'origin_lng': origin.lng,
            'owned_resource_ids': ownedResourceIds.toList(),
            'party_size': partySize,
            // Null-aware map entry: omitted entirely when there is no
            // occasion, rather than sent as an explicit null the Edge Function
            // would have to defend against.
            'occasion': ?occasion,
          },
        );

        final data = response.data as Map<String, dynamic>;

        // The function reports its own failures in the body, and they are the
        // useful ones: a missing API key, or a model that produced nothing
        // valid twice. Surfacing the server's sentence beats replacing it with
        // a generic one — "GEMINI_API_KEY is not set" is a fixable message and
        // "Could not generate a plan" is not.
        if (data['error'] != null) {
          throw RepositoryException(data['error'].toString());
        }

        return GeneratedPlanSet.fromMap(data);
      },
      fallback: 'Could not generate a plan.',
    );
  }

  /// How many people the plan is for. [Party.size], the same number the
  /// retrieval path sends — if these two ever disagreed, the crude builder and
  /// the model would report different totals for the same plan.
  static const partySize = Party.size;
}

final planGenerationRepositoryProvider = Provider<PlanGenerationRepository>(
  (ref) => PlanGenerationRepository(ref.watch(supabaseClientProvider)),
);
