import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/intake.dart';
import 'repository_exception.dart';
import 'supabase_client_provider.dart';

/// Turning a sentence into constraints — §7 step 0.
///
/// The second and last route to Gemini, and like [PlanGenerationRepository] it
/// does not look like one: nothing above this layer knows a model is involved,
/// which is what makes D8's "swapping the model is a config change" true rather
/// than aspirational.
///
/// **This is the only place free text leaves the device**, and it goes nowhere
/// else afterwards. What comes back is the constraint record; the sentence
/// itself is never stored, never hashed into `plan_cache`, and never logged
/// server-side. That separation is the entire reason a conversational intake is
/// affordable on a free tier (§7 step 2, §9).
class IntakeRepository {
  const IntakeRepository(this._client);

  final SupabaseClient _client;

  static const functionName = 'extract-intake';

  /// Reads [utterance] into constraints.
  ///
  /// Never call this for a tapped chip. A chip is already a structured value,
  /// so it skips extraction entirely — which is what makes the friendliest path
  /// also the cheapest (§7 step 0).
  Future<IntakeExtraction> extract({
    required String utterance,
    required String city,
  }) {
    return guard(
      () async {
        final response = await _client.functions.invoke(
          functionName,
          body: {'utterance': utterance, 'city': city},
        );

        final data = response.data as Map<String, dynamic>;

        // The server's sentence beats a generic one: "GEMINI_API_KEY is not
        // set" is a fixable message and "Could not read that" is not.
        if (data['error'] != null) {
          throw RepositoryException(data['error'].toString());
        }

        return IntakeExtraction(
          constraints: IntakeConstraints.fromMap(
            data['constraints'] as Map<String, dynamic>,
          ),
          cacheHit: data['cache_hit'] as bool? ?? false,
          rejected: [
            for (final field in (data['rejected'] as List? ?? const []))
              field as String,
          ],
        );
      },
      fallback: 'Could not read that.',
    );
  }
}

/// What one extraction produced.
class IntakeExtraction {
  const IntakeExtraction({
    required this.constraints,
    required this.cacheHit,
    this.rejected = const [],
  });

  final IntakeConstraints constraints;

  /// True when a previous phrasing of the same thing answered this, at no model
  /// cost. Surfaced rather than hidden for the same reason `plan_cache`'s hit
  /// is: during acceptance the difference between a hit and a miss is exactly
  /// what is being measured.
  final bool cacheHit;

  /// Fields the server dropped because they were not usable — a barangay we do
  /// not cover, a date that did not parse, a business name where an area
  /// belongs.
  ///
  /// **Not an error.** Each one is already null in [constraints] and will be
  /// asked about as an unfilled chip. Carried so the UI can say *why* it is
  /// asking, which is the difference between "Starting where?" and "I could not
  /// place that — starting where?".
  final List<String> rejected;
}

final intakeRepositoryProvider = Provider<IntakeRepository>(
  (ref) => IntakeRepository(ref.watch(supabaseClientProvider)),
);
