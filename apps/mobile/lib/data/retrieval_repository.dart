import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/activity.dart';
import '../models/party.dart';
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

  /// The barangays a user-added stop may sit in.
  ///
  /// Wider than [originAreas], deliberately. An origin needs a coordinate and
  /// the only honest one is the centroid of curated places, so a barangay with
  /// none cannot be an origin. A new place has no such problem — the user taps
  /// its coordinate on a map, so it brings its own. Using [originAreas] here
  /// would reject Duhat, Wakas and Batia, which `transit_fares` knows routes to
  /// and which are exactly where a missing stop is most worth adding.
  /// [KnownArea.hasFares] is carried rather than discarded because it changes
  /// what the user should be told: a barangay with no recorded fare produces a
  /// permanently unpriced leg, and that is worth saying *before* they pick it
  /// rather than leaving them to wonder why the total came back hedged.
  Future<List<KnownArea>> knownAreas(String city) {
    return guard(
      () async {
        final rows = await _client.rpc<List<dynamic>>(
          'known_areas',
          params: {'p_city': city},
        );

        return rows
            .map((row) => KnownArea.fromMap(row as Map<String, dynamic>))
            .toList();
      },
      fallback: 'Could not load the areas we cover.',
    );
  }

  /// How many people the plan is for — see [Party.size], which is the only
  /// place this number is written down.
  static const partySize = Party.size;

  /// Activities the party can afford and already owns the gear for.
  ///
  /// The same `retrieve_activities` call `build_simple_plan` makes internally,
  /// exposed on its own because it is the one half of retrieval that does not
  /// need a single curated place to be useful. Activities carry no location by
  /// design — the place supplies the where — so this answers "what could we
  /// do" while the catalogue is still being built.
  ///
  /// [budgetPhpCents] is the whole party's budget, as everywhere else in the
  /// app. Activity budgets are stored per person, so the division happens here
  /// rather than in the user's head — and it matches what `build_simple_plan`
  /// already does with the same number, so the two surfaces cannot disagree
  /// about what ₱200 buys.
  Future<List<Activity>> activitiesWithin({
    required int budgetPhpCents,
    required Set<String> ownedResourceIds,
  }) {
    return guard(
      () async {
        final rows = await _client.rpc<List<dynamic>>(
          'retrieve_activities',
          params: {
            'p_budget_php_cents': budgetPhpCents ~/ partySize,
            'p_owned_resource_ids': ownedResourceIds.toList(),
          },
        );

        return rows
            .map((row) => Activity.fromMap(row as Map<String, dynamic>))
            .toList();
      },
      fallback: 'Could not load ideas.',
    );
  }

  /// Builds a plan. One round trip: the server retrieves, composes and costs.
  ///
  /// [plannedForUtc] must be UTC — the server converts to Manila wall clock to
  /// decide what is open. [budgetPhpCents] is what the whole party can spend,
  /// not what each person can.
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
            'p_party_size': partySize,
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
