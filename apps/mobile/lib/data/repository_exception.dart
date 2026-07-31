import 'package:supabase_flutter/supabase_flutter.dart';

/// The single error type every repository throws.
///
/// Supabase raises several unrelated exception types ([AuthException],
/// [PostgrestException], [FunctionException], plus raw socket errors). Letting
/// those reach the UI would mean every screen handling four shapes and leaking
/// backend vocabulary into user-facing text. Repositories catch them here and
/// rethrow this instead, so callers only ever handle one thing.
///
/// See `docs/00-architecture.md` §4.
class RepositoryException implements Exception {
  const RepositoryException(this.message, {this.cause});

  /// Safe to show to a user as-is.
  final String message;

  /// The original error, kept for logging. Never shown.
  final Object? cause;

  @override
  String toString() => 'RepositoryException: $message';
}

/// Runs [action], translating anything Supabase throws into a
/// [RepositoryException] with a message worth reading.
///
/// [fallback] describes the operation in plain words ('Could not save your
/// profile.') and is used whenever the underlying error has nothing useful to
/// say.
Future<T> guard<T>(Future<T> Function() action, {required String fallback}) async {
  try {
    return await action();
  } on AuthException catch (error) {
    throw RepositoryException(_authMessage(error), cause: error);
  } on PostgrestException catch (error) {
    throw RepositoryException(_postgrestMessage(error, fallback), cause: error);
  } on RepositoryException {
    rethrow;
  } catch (error) {
    // Most often no connectivity. The MVP assumes online (architecture §4), so
    // this is a retry prompt rather than an offline mode.
    throw RepositoryException(
      '$fallback Check your connection and try again.',
      cause: error,
    );
  }
}

String _authMessage(AuthException error) {
  final code = error.code ?? '';
  final message = switch (code) {
    'invalid_credentials' => 'That email and password do not match.',
    'user_already_exists' ||
    'email_exists' =>
      'That email already has an account. Try signing in instead.',
    'weak_password' => 'That password is too short. Use at least 6 characters.',
    'email_not_confirmed' =>
      'Confirm your email address first, then sign in.',
    'over_request_rate_limit' ||
    'over_email_send_rate_limit' =>
      'Too many attempts. Wait a minute and try again.',
    'validation_failed' => 'Enter a valid email address and password.',
    _ => null,
  };

  if (message != null) return message;

  // Unrecognised codes fall back to something plain rather than passing the
  // server's text through. GoTrue sometimes returns a raw JSON blob as its
  // message — showing that to a user defeats the point of this class. The
  // original is still on `cause` for logging.
  return 'Something went wrong. Please try again.';
}

String _postgrestMessage(PostgrestException error, String fallback) {
  // 23505 unique_violation, 23503 foreign_key_violation, 42501 RLS denial.
  return switch (error.code) {
    '23505' => 'That already exists.',
    '23503' => 'Something it depends on is missing. Try again.',
    '42501' => 'You do not have access to that.',
    _ => fallback,
  };
}
