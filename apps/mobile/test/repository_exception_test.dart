import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/data/repository_exception.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// `guard` decides what every error in the app says, and had no test at all
/// until the post-Phase-6 review — which is how a whole missing exception clause
/// survived three phases.
///
/// The gap it hid: `functions_client.invoke` **throws** on any non-2xx instead of
/// returning the body, so every sentence the Edge Functions carefully compose was
/// being replaced by "Check your connection and try again." Both Edge Functions'
/// `UpstreamError` work, and both repositories' `data['error']` checks, were inert
/// for the entire time they had existed.
///
/// The `FunctionException` cases below are the regression tests for that. The
/// three older types are here too, and they are the more important half: they are
/// what proves the fix was **additive** rather than a reshuffle of the error
/// paths that already worked.

/// Runs [guard] over something that throws [error], and returns the message a
/// user would see.
Future<String> messageFor(Object error, {String fallback = 'Could not.'}) async {
  try {
    await guard<void>(() async => throw error, fallback: fallback);
  } on RepositoryException catch (e) {
    return e.message;
  }
  return 'NOTHING THROWN';
}

void main() {
  group('FunctionException — the clause that was missing', () {
    test('surfaces the server\'s own sentence', () async {
      // The single most actionable message in the product. It used to become
      // advice about wifi.
      const setup = 'GEMINI_API_KEY is not set on this project. Add it with: '
          'supabase secrets set GEMINI_API_KEY=...';

      final message = await messageFor(
        FunctionException(status: 503, details: {'error': setup}),
        fallback: 'Could not generate a plan.',
      );

      expect(message, setup);
    });

    test('the body wins over the status, which is the bug this caught',
        () async {
      // Written first as "429/503 read as 'wait'", which passed — and broke the
      // case above, because the missing-key message is served as a **503**. The
      // status is the coarser signal and has to come second, or the one error
      // carrying a fixable instruction becomes the one you cannot act on.
      //
      // Both functions already word 429 for a person, so surfacing their
      // sentence is both simpler and better than substituting one here.
      final message = await messageFor(
        FunctionException(
          status: 429,
          details: {
            'error': 'Too many requests to the model just now. The free tier '
                'allows 5 per minute; try again shortly.',
          },
        ),
      );

      expect(message, contains('try again shortly'));
      expect(message.toLowerCase(), isNot(contains('connection')));
    });

    test('a transient status with no body reads as "wait", not as a fault',
        () async {
      // 429 is ORDINARY here — 5 requests per minute per model. When there is
      // nothing to quote (a gateway 503 that never reached our code), the
      // wording still has to say "wait" rather than "something went wrong",
      // which would invite the retry loop that makes the limit worse.
      for (final status in [429, 503]) {
        final message = await messageFor(
          FunctionException(status: status, details: null),
        );
        expect(message, contains('Wait about a minute'), reason: '$status');
        expect(message.toLowerCase(), isNot(contains('connection')));
      }
    });

    test('a non-Map body is not mistaken for a message', () async {
      // `details` is a plain String when the response was not JSON.
      final message = await messageFor(
        FunctionException(status: 500, details: 'The model is busy right now.'),
        fallback: 'Could not generate a plan.',
      );

      expect(message, 'Could not generate a plan.');
    });

    test('falls back when the body carries nothing readable', () async {
      // A 500 with a bare string body, or an empty one. There is nothing to
      // surface, so the operation's own words are the best available.
      expect(
        await messageFor(
          FunctionException(status: 500, details: null),
          fallback: 'Could not read that.',
        ),
        'Could not read that.',
      );
      expect(
        await messageFor(
          FunctionException(status: 500, details: {'unexpected': 'shape'}),
          fallback: 'Could not read that.',
        ),
        'Could not read that.',
      );
    });

    test('an empty error string is not treated as a message', () async {
      // Otherwise the user gets a blank alert, which is worse than a generic one.
      expect(
        await messageFor(
          FunctionException(status: 400, details: {'error': '   '}),
          fallback: 'Could not read that.',
        ),
        'Could not read that.',
      );
    });

    test('does not leak a reason phrase to the user', () async {
      // "Internal Server Error" is not something anyone can act on. The status
      // stays on `cause` for logging.
      final message = await messageFor(
        FunctionException(
          status: 500,
          details: null,
          reasonPhrase: 'Internal Server Error',
        ),
        fallback: 'Could not generate a plan.',
      );

      expect(message, 'Could not generate a plan.');
    });
  });

  group('the three types that already worked — unchanged', () {
    test('auth errors keep their specific wording', () async {
      expect(
        await messageFor(AuthException('whatever', code: 'invalid_credentials')),
        'That email and password do not match.',
      );
      expect(
        await messageFor(AuthException('whatever', code: 'weak_password')),
        'That password is too short. Use at least 6 characters.',
      );
    });

    test('an unrecognised auth code does not pass GoTrue\'s text through',
        () async {
      // GoTrue sometimes returns a raw JSON blob as its message. Showing that
      // to a user defeats the point of this class.
      final message = await messageFor(
        AuthException('{"code":419,"msg":"something internal"}', code: 'nope'),
      );

      expect(message, 'Something went wrong. Please try again.');
      expect(message, isNot(contains('msg')));
    });

    test('postgrest codes keep their mapping', () async {
      expect(
        await messageFor(PostgrestException(message: 'dup', code: '23505')),
        'That already exists.',
      );
      expect(
        await messageFor(PostgrestException(message: 'rls', code: '42501')),
        'You do not have access to that.',
      );
      expect(
        await messageFor(
          PostgrestException(message: 'odd', code: '99999'),
          fallback: 'Could not save your profile.',
        ),
        'Could not save your profile.',
      );
    });

    test('a RepositoryException passes through untouched', () async {
      // Repositories throw this themselves — `uploadPhoto` does when there is no
      // signed-in user. Re-wrapping it would replace a specific message with a
      // generic one.
      expect(
        await messageFor(const RepositoryException('Sign in again to save a photo.')),
        'Sign in again to save a photo.',
      );
    });

    test('anything else is treated as connectivity', () async {
      // The MVP assumes online (§4), so this is a retry prompt rather than an
      // offline mode. This is the branch FunctionException used to fall into.
      expect(
        await messageFor(
          StateError('socket closed'),
          fallback: 'Could not load your plans.',
        ),
        'Could not load your plans. Check your connection and try again.',
      );
    });
  });

  test('a successful action returns its value and throws nothing', () async {
    expect(
      await guard<int>(() async => 42, fallback: 'unused'),
      42,
    );
  });
}
