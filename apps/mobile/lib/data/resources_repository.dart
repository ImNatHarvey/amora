import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/resource.dart';
import 'auth_repository.dart';
import 'repository_exception.dart';
import 'supabase_client_provider.dart';

/// The shared resource catalogue, and which of it a user owns.
class ResourcesRepository {
  const ResourcesRepository(this._client);

  final SupabaseClient _client;

  /// Every resource in the catalogue, grouped-friendly order.
  ///
  /// World-readable by `resource_catalog_read`, so this works signed out too.
  Future<List<Resource>> fetchCatalog() {
    return guard(
      () async {
        final rows = await _client
            .from('resource_catalog')
            .select()
            .order('category')
            .order('name');

        return rows.map(Resource.fromMap).toList();
      },
      fallback: 'Could not load the list of things you might own.',
    );
  }

  /// The resource ids the signed-in user owns.
  Future<Set<String>> fetchMine() {
    return guard(
      () async {
        final userId = _client.auth.currentUser?.id;
        if (userId == null) return <String>{};

        final rows = await _client
            .from('user_resources')
            .select('resource_id')
            .eq('user_id', userId);

        return rows.map((row) => row['resource_id'] as String).toSet();
      },
      fallback: 'Could not load what you own.',
    );
  }

  /// Makes the user's owned set exactly [resourceIds].
  ///
  /// Writes only the difference rather than deleting and reinserting
  /// everything, so re-saving an unchanged selection touches no rows and the
  /// `created_at` of existing choices survives.
  Future<void> replaceMine(Set<String> resourceIds) {
    return guard(
      () async {
        final userId = _client.auth.currentUser?.id;
        if (userId == null) {
          throw const RepositoryException('You are not signed in.');
        }

        final current = await fetchMine();
        final toAdd = resourceIds.difference(current);
        final toRemove = current.difference(resourceIds);

        if (toRemove.isNotEmpty) {
          await _client
              .from('user_resources')
              .delete()
              .eq('user_id', userId)
              .inFilter('resource_id', toRemove.toList());
        }

        if (toAdd.isNotEmpty) {
          await _client.from('user_resources').insert([
            for (final resourceId in toAdd)
              {'user_id': userId, 'resource_id': resourceId},
          ]);
        }
      },
      fallback: 'Could not save what you own.',
    );
  }
}

final resourcesRepositoryProvider = Provider<ResourcesRepository>(
  (ref) => ResourcesRepository(ref.watch(supabaseClientProvider)),
);

/// The full catalogue. Rarely changes, so it is fetched once per session.
final resourceCatalogProvider = FutureProvider<List<Resource>>(
  (ref) => ref.watch(resourcesRepositoryProvider).fetchCatalog(),
);

/// The signed-in user's owned resource ids.
final myResourceIdsProvider = FutureProvider<Set<String>>((ref) async {
  ref.watch(authStateChangesProvider);
  return ref.watch(resourcesRepositoryProvider).fetchMine();
});
