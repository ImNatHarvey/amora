import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/data/profiles_repository.dart';
import 'package:mobile/data/resources_repository.dart';
import 'package:mobile/data/retrieval_repository.dart';
import 'package:mobile/features/plan_request/plan_request_screen.dart';
import 'package:mobile/models/intake.dart';
import 'package:mobile/models/profile.dart';
import 'package:mobile/theme/app_theme.dart';
import 'package:mobile/models/simple_plan.dart';
import 'package:mobile/util/manila_time.dart';

import 'fakes.dart';

/// The handoff from the conversation to the form.
///
/// Found on the device, not here: tapping "Plan it" after answering all three
/// questions opened the form on its own defaults — ₱200 because that is the
/// hardcoded controller text, the alphabetically-first barangay because the
/// dropdown fell back to `list.first`, and the next half hour because that is
/// `_defaultTime()`. Every answer the user had just given was discarded, which
/// is the entire intake (`docs/00-architecture.md` D10).
///
/// It was invisible to every existing test because each one pumped the form
/// directly, which is exactly the case that still works.
void main() {
  /// The screen reads the profile and the owned resources as well as the area
  /// list, so all three need overriding or it reaches a real Supabase client.
  List<Override> overrides({List<OriginArea>? areas}) => [
        profilesRepositoryProvider.overrideWithValue(
          FakeProfilesRepository(
            profile: Profile(
              id: 'user-1',
              displayName: 'Nat',
              city: 'Bocaue',
              onboardedAt: DateTime.utc(2026),
            ),
          ),
        ),
        resourcesRepositoryProvider.overrideWithValue(
          FakeResourcesRepository(owned: const {}),
        ),
        retrievalRepositoryProvider.overrideWithValue(
          FakeRetrievalRepository(areas: areas),
        ),
      ];

  Widget host(Widget child) => ProviderScope(
        overrides: overrides(),
        child: MaterialApp(theme: AppTheme.light, home: child),
      );

  group('constraints reach the form', () {
    testWidgets('budget, origin and time all survive the handoff',
        (tester) async {
      tester.view.physicalSize = const Size(1000, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      // Deliberately none of the defaults: not ₱200, not the first area, and a
      // time nobody's clock would round to.
      final when = DateTime(2026, 8, 22, 19);
      await tester.pumpWidget(
        host(
          PlanRequestScreen(
            constraints: IntakeConstraints(
              budgetPhpCents: 45000,
              originArea: 'Turo',
              plannedForUtc: manilaToUtc(when),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('450'), findsOneWidget);
      expect(find.textContaining('Turo'), findsOneWidget);
      expect(find.textContaining(formatManila(when)), findsOneWidget);

      // The one that actually broke: the alphabetically-first area must not be
      // showing when the conversation named a different one.
      expect(find.textContaining('Poblacion'), findsNothing);
    });

    testWidgets('opened cold, the form keeps its own defaults', (tester) async {
      // The paired positive. Without it, a screen that rendered nothing at all
      // would satisfy the "Poblacion is absent" assertion above, and a form
      // that had simply lost its fallbacks would look fixed.
      tester.view.physicalSize = const Size(1000, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(host(const PlanRequestScreen()));
      await tester.pumpAndSettle();

      expect(find.text('200'), findsOneWidget);
      // First area in the fake list, which is what a cold form should show.
      expect(find.textContaining('Poblacion'), findsOneWidget);
    });

    testWidgets('an area the server does not offer falls back, not crashes',
        (tester) async {
      tester.view.physicalSize = const Size(1000, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        host(
          const PlanRequestScreen(
            constraints: IntakeConstraints(originArea: 'Nowhere At All'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Poblacion'), findsOneWidget);
    });
  });

  testWidgets('one place reads as "place", not "1 places"', (tester) async {
    tester.view.physicalSize = const Size(1000, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides(
          areas: const [
            OriginArea(
              area: 'Antipona',
              lat: 14.806,
              lng: 120.9335,
              placeCount: 1,
            ),
            OriginArea(
              area: 'Turo',
              lat: 14.8065,
              lng: 120.9418,
              placeCount: 2,
            ),
          ],
        ),
        child: MaterialApp(
          theme: AppTheme.light,
          home: const PlanRequestScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('(1 place)'), findsOneWidget);
    expect(find.textContaining('(1 places)'), findsNothing);
  });
}
