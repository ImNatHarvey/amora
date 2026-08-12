import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/memories_repository.dart';
import '../../models/memory.dart';
import '../plan/plan_providers.dart';

/// The signed-in user's memories, newest first.
final memoriesProvider = FutureProvider<List<Memory>>(
  (ref) => ref.watch(memoriesRepositoryProvider).listMine(),
);

/// A signed URL for one stored photo.
///
/// Keyed by object path, so two cards showing the same photo share one signing
/// round trip. The URL expires; the **path** is what the image cache keys on —
/// see `MemoriesRepository.signedPhotoUrl`.
final memoryPhotoUrlProvider = FutureProvider.family<String, String>(
  (ref, path) => ref.watch(memoriesRepositoryProvider).signedPhotoUrl(path),
);

/// Completes a plan, then makes every screen that showed it stale.
///
/// An [AsyncNotifier] rather than a bare call so the sheet gets its three states
/// from `AsyncValue` instead of inventing a loading flag — the same reason
/// `SavePlanController` is one.
///
/// **The invalidations are the interesting part.** A completion changes the plan
/// itself (its status becomes `completed`, which is what removes the edit
/// affordances), the saved-plans list, and the memory timeline. Missing any one
/// leaves a screen asserting something that is no longer true — most visibly a
/// plan still offering a drag handle for a stop whose price has already been
/// reported.
class CompletePlanController extends AsyncNotifier<Memory?> {
  @override
  Future<Memory?> build() async => null;

  Future<Memory?> complete({
    required String planId,
    required List<Map<String, dynamic>> stopSpends,
    required List<Map<String, dynamic>> legFares,
    int? rating,
    String? caption,
    String? photoPath,
  }) async {
    state = const AsyncValue.loading();

    final result = await AsyncValue.guard(
      () => ref.read(memoriesRepositoryProvider).complete(
            planId: planId,
            stopSpends: stopSpends,
            legFares: legFares,
            rating: rating,
            caption: caption,
            photoPath: photoPath,
          ),
    );
    state = result;

    if (result.hasValue) {
      ref.invalidate(savedPlanProvider(planId));
      ref.invalidate(savedPlansProvider);
      ref.invalidate(memoriesProvider);
    }

    return result.valueOrNull;
  }
}

final completePlanControllerProvider =
    AsyncNotifierProvider<CompletePlanController, Memory?>(
  CompletePlanController.new,
);

/// The memory belonging to one plan, if it has been completed.
///
/// Reads the list rather than querying by plan id: a user has few memories, the
/// list is already loaded wherever this is asked, and one source of truth means
/// a completion cannot leave the timeline and the plan screen disagreeing about
/// whether an outing happened.
final memoryForPlanProvider = Provider.family<Memory?, String>((ref, planId) {
  final memories = ref.watch(memoriesProvider).valueOrNull;
  if (memories == null) return null;
  for (final memory in memories) {
    if (memory.planId == planId) return memory;
  }
  return null;
});
