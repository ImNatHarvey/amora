import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/plans_repository.dart';
import '../../models/saved_plan.dart';

/// The signed-in user's saved plans, newest first.
final savedPlansProvider = FutureProvider<List<PlanSummary>>(
  (ref) => ref.watch(plansRepositoryProvider).listMine(),
);

/// One saved plan.
///
/// Null when it does not exist or is not this user's — RLS makes those the same
/// answer deliberately, and the screen treats them the same way for the same
/// reason: a client that could tell them apart would be able to enumerate other
/// people's plans.
final savedPlanProvider = FutureProvider.family<SavedPlan?, String>(
  (ref, id) => ref.watch(plansRepositoryProvider).byId(id),
);

/// Saves a plan and hands back its id.
///
/// An [AsyncNotifier] rather than a bare call so the button can show progress
/// and a failure can be retried without the screen inventing its own loading
/// flag — `AsyncValue` already carries all three states.
class SavePlanController extends AsyncNotifier<String?> {
  @override
  Future<String?> build() async => null;

  Future<String?> save({
    required Map<String, dynamic> payload,
    String? title,
  }) async {
    state = const AsyncValue.loading();

    final result = await AsyncValue.guard(
      () => ref.read(plansRepositoryProvider).save(payload: payload, title: title),
    );
    state = result;

    // The list is now stale by definition.
    if (result.hasValue) ref.invalidate(savedPlansProvider);

    return result.valueOrNull;
  }
}

final savePlanControllerProvider =
    AsyncNotifierProvider<SavePlanController, String?>(SavePlanController.new);
