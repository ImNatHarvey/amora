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
  } on FunctionException catch (error) {
    throw RepositoryException(_functionMessage(error, fallback), cause: error);
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

/// An Edge Function's own words, when it had any.
///
/// **This clause was missing until the post-Phase-6 review, and its absence was
/// expensive out of all proportion to its size.** `functions_client.invoke`
/// *throws* on any non-2xx rather than returning the body, so every deliberate
/// message either function composes — a missing API key, a rate limit, a model
/// that produced nothing valid twice — fell through to the generic `catch` below
/// and reached the user as "Check your connection and try again."
///
/// Three pieces of existing work were quietly inert because of it:
///
///   * Both repositories' `if (data['error'] != null)` checks, which can only
///     fire on an error inside a **200** — something neither function emits.
///   * The `UpstreamError` class in both Edge Functions, whose entire purpose is
///     to pass 429 through instead of flattening it to 500. The acceptance
///     harnesses saw the difference because they use raw `fetch`; the app never
///     could.
///   * This file's own doc comment, which has always listed [FunctionException]
///     among the types it handles.
///
/// The most actionable sentence in the whole product — "GEMINI_API_KEY is not
/// set on this project. Add it with: supabase secrets set…" — was being replaced
/// with advice to check the wifi.
String _functionMessage(FunctionException error, String fallback) {
  // The server's sentence first, whatever the status. The function knows what
  // went wrong and this layer does not, and both functions already word their
  // failures for a person: the rate limit says "try again shortly", the busy
  // model says "this is temporary".
  //
  // **Status-first was wrong, and a test caught it.** Checking for 429/503
  // before reading the body meant the missing-key message — which is served as a
  // 503 — was replaced by "too many requests", turning the one error with a
  // fixable instruction in it into the one error you cannot act on. The status
  // is the coarser signal; it belongs after.
  final details = error.details;
  if (details is Map && details['error'] != null) {
    final message = details['error'].toString().trim();
    if (message.isNotEmpty) return message;
  }

  // A transient status with no readable body. 429 and 503 are ORDINARY on this
  // tier rather than faults — the free Gemini quota is 5 requests per minute per
  // model (measured, see HANDOFF.md), so a couple planning two dates in quick
  // succession will meet it. Wording it as a failure invites the retry loop that
  // makes the rate limit worse.
  if (error.status == 429 || error.status == 503) {
    return 'Too many requests just now. Wait about a minute and try again.';
  }

  // Anything else with nothing to say. Deliberately not passing `reasonPhrase`
  // through — "Internal Server Error" tells a user nothing they can act on, and
  // the status is already on `cause` for logging.
  return fallback;
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
