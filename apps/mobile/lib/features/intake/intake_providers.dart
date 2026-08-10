import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/intake_repository.dart';
import '../../data/profiles_repository.dart';
import '../../models/intake.dart';

/// One line in the thread.
///
/// Not a persisted type: §5 defines no messages table and the schema discipline
/// is one phase's tables per phase. The thread is what the user is looking at
/// right now, not a record — and a conversation nobody can scroll back to
/// yesterday is the honest shape for something whose output is a saved plan,
/// not a transcript (`02-design-system.md` §9).
class IntakeMessage {
  const IntakeMessage.fromUser(this.text)
      : isUser = true,
        rejectedFields = const [];

  const IntakeMessage.fromAmora(this.text, {this.rejectedFields = const []})
      : isUser = false;

  final String text;
  final bool isUser;

  /// Fields the server had to drop, so the reply can say why it is asking
  /// again rather than just asking again.
  final List<String> rejectedFields;
}

/// The conversation: what has been said, and what it has resolved to.
class IntakeController extends AsyncNotifier<IntakeState> {
  @override
  Future<IntakeState> build() async => const IntakeState();

  /// Sends free text for extraction. **The only path that costs a model call.**
  Future<void> say(String utterance) async {
    final text = utterance.trim();
    if (text.isEmpty) return;

    final before = state.valueOrNull ?? const IntakeState();
    final withUser = before.copyWith(
      messages: [...before.messages, IntakeMessage.fromUser(text)],
    );
    // The user's line lands immediately and a real in-flight flag goes up.
    // There is no simulated pause: §9 forbids typing-indicator theatre, and a
    // fake delay spends frames on mid-range Android to feel slower than it is.
    state = AsyncValue.data(withUser.copyWith(busy: true));

    final result = await AsyncValue.guard(() async {
      final profile = await ref.read(currentProfileProvider.future);
      final extraction = await ref.read(intakeRepositoryProvider).extract(
            utterance: text,
            city: profile?.city ?? 'Bocaue',
          );

      // Merged, not replaced. A second message refines the first — "actually
      // make it 300" must not discard the time already established.
      final merged = withUser.constraints.copyWith(
        budgetPhpCents: extraction.constraints.budgetPhpCents,
        plannedForUtc: extraction.constraints.plannedForUtc,
        originArea: extraction.constraints.originArea,
        occasion: extraction.constraints.occasion,
      );

      return withUser.copyWith(
        busy: false,
        constraints: merged,
        lastCacheHit: extraction.cacheHit,
        messages: [
          ...withUser.messages,
          IntakeMessage.fromAmora(
            _reply(merged, extraction.rejected),
            rejectedFields: extraction.rejected,
          ),
        ],
      );
    });

    // The conversation always has data — the thread — so a failure is a field
    // on the state rather than an `AsyncError`.
    //
    // Carrying it as AsyncError.copyWithPrevious instead left `busy` true in
    // the retained value, so the progress bar never came down and the screen
    // never settled. Keeping the thread authoritative removes that whole class
    // of question: there is one place the screen reads `busy` from, and it is
    // always the value this method last wrote.
    state = AsyncValue.data(
      result.hasError
          ? withUser.copyWith(busy: false, error: '${result.error}')
          : (result.valueOrNull ?? withUser.copyWith(busy: false)),
    );
  }

  /// Sets one constraint directly, with **no model call**.
  ///
  /// This is the chip path, and it is the common one: a chip already holds a
  /// structured value, so correcting it skips §7 step 0 entirely. It is also
  /// what a starter chip does, which is why the friendliest opening is also the
  /// cheapest.
  void setConstraint(IntakeConstraints next) {
    final before = state.valueOrNull ?? const IntakeState();
    state = AsyncValue.data(before.copyWith(constraints: next));
  }

  void reset() => state = const AsyncValue.data(IntakeState());

  /// What Amora says back.
  ///
  /// It reports what was understood and asks for exactly what is missing. It
  /// never volunteers a place — there are none in scope here, and inventing one
  /// is the thing invariant 1 exists to forbid.
  static String _reply(IntakeConstraints c, List<String> rejected) {
    final missing = c.missing;
    if (missing.isEmpty) return 'Got it — here is what I have.';

    // Naming what was dropped is the difference between "Starting where?" and
    // an apparently arbitrary repeat of a question the user thinks they just
    // answered.
    final couldNotPlace = rejected.contains('origin_area')
        ? 'I could not place that one. '
        : '';

    final asks = missing.map((f) => f.prompt.toLowerCase()).join(' ');
    return '$couldNotPlace${asks[0].toUpperCase()}${asks.substring(1)}';
  }
}

/// Everything the intake screen renders.
class IntakeState {
  const IntakeState({
    this.messages = const [],
    this.constraints = const IntakeConstraints(),
    this.busy = false,
    this.lastCacheHit = false,
    this.error,
  });

  final List<IntakeMessage> messages;
  final IntakeConstraints constraints;

  /// A real in-flight state, shown as real progress. Never a simulated pause.
  final bool busy;

  /// Whether the last extraction was answered from `intake_cache`. Surfaced
  /// during Phase 3b acceptance, where hit-versus-miss is the measurement.
  final bool lastCacheHit;

  /// What went wrong on the last turn, if anything.
  ///
  /// The thread survives it: losing what the user typed on top of an error
  /// would be gratuitous, and the failure that actually happens here is a
  /// missing API key, whose message says how to fix it.
  final String? error;

  bool get isEmpty => messages.isEmpty;

  /// [error] is cleared unless passed, because it describes the **last turn**
  /// rather than the conversation. A `??` fallback would make one failure stick
  /// to every message after it.
  IntakeState copyWith({
    List<IntakeMessage>? messages,
    IntakeConstraints? constraints,
    bool? busy,
    bool? lastCacheHit,
    String? error,
  }) =>
      IntakeState(
        messages: messages ?? this.messages,
        constraints: constraints ?? this.constraints,
        busy: busy ?? this.busy,
        lastCacheHit: lastCacheHit ?? this.lastCacheHit,
        error: error,
      );
}

final intakeControllerProvider =
    AsyncNotifierProvider<IntakeController, IntakeState>(IntakeController.new);
