import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'repository_exception.dart';
import 'supabase_client_provider.dart';

/// Everything the app does with accounts.
///
/// Phase 1 is email and password only. Google is deferred — see
/// `docs/00-architecture.md` §8 for the setup it needs.
class AuthRepository {
  const AuthRepository(this._client);

  final SupabaseClient _client;

  /// The signed-in session, or null. Read synchronously by the router.
  Session? get currentSession => _client.auth.currentSession;

  String? get currentUserId => _client.auth.currentUser?.id;

  /// Emits on sign in, sign out, and token refresh.
  Stream<AuthState> get onAuthStateChange => _client.auth.onAuthStateChange;

  /// Creates an account.
  ///
  /// With email confirmation disabled this also signs the user in, and the
  /// `on_auth_user_created` trigger has already made their profile row by the
  /// time this returns. With confirmation enabled the session stays null until
  /// they click the link.
  Future<void> signUp({required String email, required String password}) {
    return guard(
      () async => _client.auth.signUp(email: email.trim(), password: password),
      fallback: 'Could not create your account.',
    );
  }

  Future<void> signIn({required String email, required String password}) {
    return guard(
      () async => _client.auth
          .signInWithPassword(email: email.trim(), password: password),
      fallback: 'Could not sign you in.',
    );
  }

  Future<void> signOut() {
    return guard(
      () async => _client.auth.signOut(),
      fallback: 'Could not sign you out.',
    );
  }
}

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepository(ref.watch(supabaseClientProvider)),
);

/// Auth events as a stream, so the router and any screen can react to sign in
/// and sign out without polling.
final authStateChangesProvider = StreamProvider<AuthState>(
  (ref) => ref.watch(authRepositoryProvider).onAuthStateChange,
);
