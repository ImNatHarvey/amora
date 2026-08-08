import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/plans_repository.dart';
import '../../models/saved_plan.dart';
import '../../models/simple_plan.dart';

/// The signed-in user's saved plans, newest first.
final savedPlansProvider = FutureProvider<List<PlanSummary>>(
  (ref) => ref.watch(plansRepositoryProvider).listMine(),
);

/// One saved plan, and the edits that can be made to it.
///
/// Null when it does not exist or is not this user's — RLS makes those the same
/// answer deliberately, and the screen treats them the same way for the same
/// reason: a client that could tell them apart would be able to enumerate other
/// people's plans.
///
/// A notifier rather than a `FutureProvider` because editing is **always live**:
/// every change writes immediately, and `edit_plan` hands back the whole
/// recomputed plan. Setting [state] from that response is what keeps an edit to
/// one round trip — invalidating and refetching would be two, and would flash
/// a spinner over a plan the user is in the middle of arranging.
///
/// **No method here computes money.** Each builds a new ordered stop list and
/// asks Postgres what it now costs (invariant 3).
class PlanEditor extends FamilyAsyncNotifier<SavedPlan?, String> {
  @override
  Future<SavedPlan?> build(String planId) =>
      ref.watch(plansRepositoryProvider).byId(planId);

  /// The current stops as `edit_plan` wants them: place ids in order, carrying
  /// the timings that are the user's rather than the database's.
  List<Map<String, dynamic>> _stopPayload(List<PlanStop> stops) => [
        for (final stop in stops)
          {
            'place_id': stop.place.id,
            if (stop.activityId != null) 'activity_id': stop.activityId,
            if (stop.startTimeUtc != null)
              'start_time': stop.startTimeUtc!.toIso8601String(),
            if (stop.durationMinutes != null)
              'duration_minutes': '${stop.durationMinutes}',
            if (stop.note != null) 'note': stop.note,
          },
      ];

  /// The one place an edit is sent and the result taken up.
  ///
  /// Takes the payload rather than `List<PlanStop>` so that adding a place —
  /// which has an id and no stop to build from — goes through here too. It had
  /// its own copy of this body until the Phase 5 review: the same
  /// loading-with-previous, guard and invalidate, duplicated. That is the shape
  /// behind both bugs this repo has already shipped (party size in two files,
  /// `_pesos` in two screens), and worth removing before a third.
  Future<void> _send(
    PlanEditType type,
    List<Map<String, dynamic>> stops, {
    String? targetPlaceId,
  }) async {
    final planId = arg;
    final previous = state;
    // Keep the old plan on screen while the write is in flight. A spinner here
    // would blank a document the user is reading.
    state = const AsyncValue<SavedPlan?>.loading().copyWithPrevious(previous);

    state = await AsyncValue.guard(() async {
      return await ref.read(plansRepositoryProvider).edit(
            planId: planId,
            type: type,
            stops: stops,
            targetPlaceId: targetPlaceId,
          );
    });

    // Totals feed the list screen's summary.
    if (state.hasValue) ref.invalidate(savedPlansProvider);
  }

  Future<void> _apply(
    PlanEditType type,
    List<PlanStop> stops, {
    String? targetPlaceId,
  }) =>
      _send(type, _stopPayload(stops), targetPlaceId: targetPlaceId);

  Future<void> reorder(int oldIndex, int newIndex) async {
    final stops = [...?state.valueOrNull?.plan.stops];
    if (stops.isEmpty || oldIndex == newIndex) return;

    // [newIndex] arrives already adjusted for the lifted item, because the
    // timeline uses `onReorderItem` rather than the deprecated `onReorder`.
    // Subtracting one here as well — which the old callback required — would
    // rotate the list by one on every downward drag.
    final moved = stops.removeAt(oldIndex);
    stops.insert(newIndex, moved);

    await _apply(PlanEditType.reorder, stops, targetPlaceId: moved.place.id);
  }

  Future<void> removeStop(PlanStop stop) async {
    final stops = [...?state.valueOrNull?.plan.stops]
      ..removeWhere((s) => s.place.id == stop.place.id);
    await _apply(PlanEditType.remove, stops, targetPlaceId: stop.place.id);
  }

  /// Puts a removed stop back where it was.
  ///
  /// Logged as an `add`, because that is what it is to the database — and
  /// because a removal the user immediately reversed is a different signal from
  /// one they kept, which is the distinction invariant 7 exists to capture.
  Future<void> restoreStop(PlanStop stop, int atIndex) async {
    final stops = [...?state.valueOrNull?.plan.stops];
    stops.insert(atIndex.clamp(0, stops.length), stop);
    await _apply(PlanEditType.add, stops, targetPlaceId: stop.place.id);
  }

  /// Changes when one stop starts and how long it lasts, and nothing else.
  ///
  /// Both values are nullable and null is meaningful: it clears the timing
  /// rather than leaving it alone. Somebody who does not know how long they
  /// will stay has to be able to say so.
  ///
  /// The order is untouched, so `write_plan_stops` recomputes identical legs
  /// and every fare comes back unchanged. Retiming must not move anything.
  Future<void> retime(
    PlanStop stop, {
    required DateTime? startTimeUtc,
    required int? durationMinutes,
  }) async {
    final stops = [...?state.valueOrNull?.plan.stops];
    if (stops.isEmpty) return;

    final payload = _stopPayload(stops);
    final index = stops.indexWhere((s) => s.place.id == stop.place.id);
    if (index < 0) return;

    // Rebuilt rather than mutated in place, so a null genuinely removes the key
    // instead of leaving the previous value behind.
    payload[index] = {
      'place_id': stop.place.id,
      if (stop.activityId != null) 'activity_id': stop.activityId,
      if (startTimeUtc != null) 'start_time': startTimeUtc.toIso8601String(),
      if (durationMinutes != null) 'duration_minutes': '$durationMinutes',
      if (stop.note != null) 'note': stop.note,
    };

    await _send(PlanEditType.retime, payload, targetPlaceId: stop.place.id);
  }

  Future<void> addPlace(String placeId) async {
    final stops = [...?state.valueOrNull?.plan.stops];
    final payload = _stopPayload(stops)..add({'place_id': placeId});
    await _send(PlanEditType.add, payload, targetPlaceId: placeId);
  }
}

final savedPlanProvider =
    AsyncNotifierProvider.family<PlanEditor, SavedPlan?, String>(
  PlanEditor.new,
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
