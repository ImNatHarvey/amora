import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/profile.dart';
import 'auth_repository.dart';
import 'repository_exception.dart';
import 'supabase_client_provider.dart';

/// Reads and writes the signed-in user's profile.
///
/// Every method is scoped to the current user by RLS, not by a filter in Dart —
/// `profiles_select_own` and `profiles_update_own` already restrict rows to
/// `auth.uid()`. The `.eq('id', ...)` calls below are for addressing the right
/// row, not for security.
class ProfilesRepository {
  const ProfilesRepository(this._client);

  final SupabaseClient _client;

  /// The current user's profile, or null when signed out.
  ///
  /// Returns null rather than throwing if the row is somehow absent, so the
  /// router can treat "no profile yet" as a state instead of an error.
  Future<Profile?> fetchMine() {
    return guard(
      () async {
        final userId = _client.auth.currentUser?.id;
        if (userId == null) return null;

        final row = await _client
            .from('profiles')
            .select()
            .eq('id', userId)
            .maybeSingle();

        return row == null ? null : Profile.fromMap(row);
      },
      fallback: 'Could not load your profile.',
    );
  }

  Future<void> updateProfile({String? displayName, String? city}) {
    return guard(
      () async {
        final userId = _client.auth.currentUser?.id;
        if (userId == null) {
          throw const RepositoryException('You are not signed in.');
        }

        // Only the fields actually passed are written, so a caller updating the
        // display name cannot blank the city by omission.
        await _client.from('profiles').update({
          'display_name': ?displayName?.trim(),
          'city': ?city,
        }).eq('id', userId);
      },
      fallback: 'Could not save your profile.',
    );
  }

  /// Records that the user finished the resource picker.
  ///
  /// Separate from [updateProfile] because it is a state transition, not an
  /// edit — onboarding completes once and never un-completes.
  Future<void> markOnboarded() {
    return guard(
      () async {
        final userId = _client.auth.currentUser?.id;
        if (userId == null) {
          throw const RepositoryException('You are not signed in.');
        }

        await _client
            .from('profiles')
            .update({'onboarded_at': DateTime.now().toUtc().toIso8601String()})
            .eq('id', userId);
      },
      fallback: 'Could not finish setting up your account.',
    );
  }
}

final profilesRepositoryProvider = Provider<ProfilesRepository>(
  (ref) => ProfilesRepository(ref.watch(supabaseClientProvider)),
);

/// The signed-in user's profile, refetched whenever auth changes.
///
/// The router reads this to decide whether onboarding is finished, so it must
/// invalidate on sign in and sign out — hence the watch on auth state.
final currentProfileProvider = FutureProvider<Profile?>((ref) async {
  ref.watch(authStateChangesProvider);
  return ref.watch(profilesRepositoryProvider).fetchMine();
});
