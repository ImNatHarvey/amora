import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/data/plans_repository.dart';
import 'package:mobile/data/profiles_repository.dart';
import 'package:mobile/data/retrieval_repository.dart';
import 'package:mobile/features/plan/add_stop_screen.dart';
import 'package:mobile/models/profile.dart';
import 'package:mobile/theme/app_theme.dart';

import 'fakes.dart';

/// Adding a stop of the user's own.
///
/// The map itself is not driven here — tiles need a network and a widget test
/// that stubbed them would be testing the stub, the same call `plan_detail_test`
/// makes. What is checked is everything around it: the validation that stops a
/// coordinate-less row being written, and that the barangay list comes from the
/// right function.
Future<(FakePlansRepository, FakeRetrievalRepository)> _pump(
  WidgetTester tester,
) async {
  final plans = FakePlansRepository();
  final retrieval = FakeRetrievalRepository();

  // The form is taller than a default 800 px test viewport, and a ListView does
  // not build what is off-screen — so the submit button would simply not exist
  // to tap. Taller viewport rather than scrolling, because scrolling would drag
  // across the map and start a gesture instead.
  tester.view.physicalSize = const Size(1080, 3200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        plansRepositoryProvider.overrideWithValue(plans),
        retrievalRepositoryProvider.overrideWithValue(retrieval),
        profilesRepositoryProvider.overrideWithValue(
          FakeProfilesRepository(
            profile: const Profile(
              id: 'u1',
              displayName: 'Nat',
              city: 'Bocaue',
            ),
          ),
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        home: const AddStopScreen(planId: 'plan-1'),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (plans, retrieval);
}

void main() {
  testWidgets('the barangay list comes from known_areas, not origin_areas',
      (tester) async {
    // These two are genuinely different functions and picking the wrong one is
    // invisible until somebody tries to add a stop in a barangay that has no
    // curated places — which is the case the feature exists for. The fakes
    // return deliberately different lists so this can be asserted at all.
    await _pump(tester);

    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();

    // Duhat has fares but no curated places: present in known_areas, absent
    // from origin_areas.
    expect(find.text('Duhat'), findsWidgets);
  });

  testWidgets('a stop with no pin is refused, and says why', (tester) async {
    // A place with no coordinate cannot have a distance, so every leg to it
    // would be meaningless. The server would reject it; this stops the user
    // discovering that after filling the whole form.
    final (plans, _) = await _pump(tester);

    await tester.enterText(find.byType(TextFormField).first, 'Aling Nena');
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Poblacion').last);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Add to this plan'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Tap the map'), findsWidgets);
    expect(plans.addedPlaces, isEmpty);
  });

  testWidgets('a nameless stop is refused', (tester) async {
    final (plans, _) = await _pump(tester);

    await tester.tap(find.text('Add to this plan'));
    await tester.pumpAndSettle();

    expect(find.text('A stop needs a name.'), findsOneWidget);
    expect(plans.addedPlaces, isEmpty);
  });

  testWidgets('a barangay with no recorded fare warns before it is chosen',
      (tester) async {
    // Wakas has no fares in the fake. Choosing it means every leg there will
    // report unpriced — a real gap that should stay visible, and one the user
    // should hear about while choosing rather than after the total comes back
    // hedged.
    await _pump(tester);

    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Wakas').last);
    await tester.pumpAndSettle();

    expect(find.textContaining('No fare recorded to Wakas'), findsOneWidget);
  });

  testWidgets('the quarantine is stated before anything is typed',
      (tester) async {
    // §12.5: a user entering their own café and being shown it back has a notes
    // app, not Amora. Saying so up front is what keeps the expectation honest.
    await _pump(tester);

    expect(find.textContaining('Only you will see this stop'), findsOneWidget);
  });
}
