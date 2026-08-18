import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/profiles_repository.dart';
import '../../data/resources_repository.dart';
import '../../data/retrieval_repository.dart';
import '../../models/activity.dart';

/// The budget the ideas list is filtered against, in centavos, for the party.
///
/// A separate provider rather than widget state so the list rebuilds from one
/// source and the screen keeps no copy of the number. ₱200 to start, because
/// it is the budget the whole product was scoped around (`CLAUDE.md`), not
/// because it is a safe-looking default.
final ideasBudgetProvider = StateProvider<int>((ref) => 200 * 100);

/// Activities that fit the budget and the gear the user actually owns,
/// ordered with the user's interests first.
///
/// Watches [myResourceIdsProvider], so changing what you own on the resource
/// picker re-filters this list without anything having to invalidate it by
/// hand, and [currentProfileProvider], so saving preferences re-orders it the
/// same way.
///
/// **Interests change the order and never the contents.** The list length is
/// identical whether the user has expressed none or all of them — that rule is
/// enforced in `retrieve_activities` and asserted in `ideas_test.dart`.
final ideasProvider = FutureProvider<List<Activity>>((ref) async {
  final budget = ref.watch(ideasBudgetProvider);
  final owned = await ref.watch(myResourceIdsProvider.future);
  final profile = await ref.watch(currentProfileProvider.future);

  return ref.watch(retrievalRepositoryProvider).activitiesWithin(
        budgetPhpCents: budget,
        ownedResourceIds: owned,
        interestSlugs: {
          for (final interest in profile?.interests ?? const {}) interest.slug,
        },
      );
});

/// How many activities exist in total, ignoring both filters.
///
/// Exists so an empty or short list can say *why* it is short — "5 of 16 fit"
/// is information, "5 results" is not. `02-design-system.md` §5 forbids a bare
/// empty state, and this is what makes a non-bare one possible without
/// guessing.
final ideasTotalProvider = FutureProvider<int>((ref) async {
  final all = await ref.watch(retrievalRepositoryProvider).activitiesWithin(
        // Deliberately unfiltered: a budget nothing exceeds, and every resource
        // the catalogue knows about, so the count is the whole catalogue rather
        // than a second filtered view.
        budgetPhpCents: 1 << 30,
        ownedResourceIds:
            (await ref.watch(resourceCatalogProvider.future)).map((r) => r.id).toSet(),
      );

  return all.length;
});
