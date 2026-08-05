import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/plan_generation_repository.dart';
import '../../data/profiles_repository.dart';
import '../../data/resources_repository.dart';
import '../../data/retrieval_repository.dart';
import '../../models/plan.dart';
import '../../models/simple_plan.dart';

/// The barangays the signed-in user can start a plan from.
///
/// Keyed off the profile's city rather than a constant, so the day a second
/// municipality has curated places this needs no change.
final originAreasProvider = FutureProvider<List<OriginArea>>((ref) async {
  final profile = await ref.watch(currentProfileProvider.future);
  final city = profile?.city;
  if (city == null || city.isEmpty) return const [];

  return ref.watch(retrievalRepositoryProvider).originAreas(city);
});

/// A plan, plus how long the round trip took.
///
/// Phase 2's acceptance criterion is a latency one, so the measurement is part
/// of the result rather than something to go looking for in a log. It is shown
/// on screen because a number nobody sees is a number nobody checks.
class TimedPlan {
  const TimedPlan({required this.plan, required this.elapsed});

  final SimplePlan plan;

  /// Wall-clock time for the whole call as the device experienced it: server
  /// execution plus the round trip to Tokyo. The server half is the part the
  /// 400 ms criterion is about — see `docs/00-architecture.md` §8.
  final Duration elapsed;
}

/// Holds the most recent plan the user asked for.
///
/// An [AsyncNotifier] rather than a `FutureProvider.family` keyed on the form
/// values: a plan is produced when someone presses a button, not whenever a
/// parameter changes, and a family would need every field of the request to
/// have value equality to avoid quietly recomputing or quietly not.
///
/// `null` means nothing has been requested yet, which is a different screen
/// state from "requested and found nothing".
class PlanController extends AsyncNotifier<TimedPlan?> {
  @override
  Future<TimedPlan?> build() async => null;

  Future<void> submit({
    required int budgetPhpCents,
    required DateTime plannedForUtc,
    required OriginArea origin,
  }) async {
    state = const AsyncValue.loading();

    state = await AsyncValue.guard(() async {
      final profile = await ref.read(currentProfileProvider.future);
      final owned = await ref.read(myResourceIdsProvider.future);

      final stopwatch = Stopwatch()..start();
      final plan = await ref.read(retrievalRepositoryProvider).buildSimplePlan(
            city: profile?.city ?? '',
            budgetPhpCents: budgetPhpCents,
            plannedForUtc: plannedForUtc,
            origin: origin,
            ownedResourceIds: owned,
          );
      stopwatch.stop();

      return TimedPlan(plan: plan, elapsed: stopwatch.elapsed);
    });
  }
}

final planControllerProvider =
    AsyncNotifierProvider<PlanController, TimedPlan?>(PlanController.new);

/// A generated plan set, plus how long the round trip took.
class TimedPlanSet {
  const TimedPlanSet({required this.plans, required this.elapsed});

  final GeneratedPlanSet plans;

  /// End to end from the device: Tokyo round trip, retrieval, the Gemini call
  /// and validation. A cache hit skips the middle two, which is why
  /// [GeneratedPlanSet.cacheHit] is shown beside this number — otherwise the
  /// two readings look like the same measurement disagreeing with itself.
  final Duration elapsed;
}

/// Holds the most recent generated plan set.
///
/// Deliberately a sibling of [PlanController] rather than a mode inside it.
/// Phase 2's builder is not a fallback for Phase 3 and Phase 3 is not an
/// upgrade of Phase 2 — one is the crude nearest-first composer that proves
/// retrieval works, the other is the model. Keeping them side by side is what
/// makes "did the model actually improve on nearest-first" a question you can
/// answer by looking at one screen.
class GenerationController extends AsyncNotifier<TimedPlanSet?> {
  @override
  Future<TimedPlanSet?> build() async => null;

  Future<void> generate({
    required int budgetPhpCents,
    required DateTime plannedForUtc,
    required OriginArea origin,
  }) async {
    state = const AsyncValue.loading();

    state = await AsyncValue.guard(() async {
      final profile = await ref.read(currentProfileProvider.future);
      final owned = await ref.read(myResourceIdsProvider.future);

      final stopwatch = Stopwatch()..start();
      final plans = await ref.read(planGenerationRepositoryProvider).generate(
            city: profile?.city ?? '',
            budgetPhpCents: budgetPhpCents,
            plannedForUtc: plannedForUtc,
            origin: origin,
            ownedResourceIds: owned,
          );
      stopwatch.stop();

      return TimedPlanSet(plans: plans, elapsed: stopwatch.elapsed);
    });
  }
}

final generationControllerProvider =
    AsyncNotifierProvider<GenerationController, TimedPlanSet?>(
  GenerationController.new,
);
