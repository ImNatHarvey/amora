import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/data/auth_repository.dart';
import 'package:mobile/data/profiles_repository.dart';
import 'package:mobile/features/preferences/preferences_screen.dart';
import 'package:mobile/models/preferences.dart';
import 'package:mobile/models/profile.dart';
import 'package:mobile/theme/app_theme.dart';

import 'fakes.dart';

Future<FakeProfilesRepository> _pump(
  WidgetTester tester, {
  Profile? profile,
}) async {
  // Three sections do not fit an 800 px test viewport, and a ListView does not
  // build what is off-screen — so the budget chips simply would not exist to
  // tap. Raise the viewport rather than scrolling: a scroll drags across the
  // chips and starts a gesture instead. Same fix and same reason as
  // add_stop_test.dart.
  tester.view.physicalSize = const Size(1080, 3200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final profiles = FakeProfilesRepository(
    profile: profile ??
        const Profile(id: 'u1', displayName: 'Nat', city: 'Bocaue'),
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(FakeAuthRepository(userId: 'u1')),
        profilesRepositoryProvider.overrideWithValue(profiles),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        home: const PreferencesScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return profiles;
}

void main() {
  testWidgets('companion type offers only partner', (tester) async {
    // D1 and CLAUDE.md's not-building list. The column permits five values so
    // that widening the persona is not a migration (§11), but offering them
    // here would BE shipping friends and families, whatever retrieval does with
    // the value. This test is the thing standing between "storage is ready" and
    // "the feature shipped by accident".
    await _pump(tester);

    expect(find.text('My partner'), findsOneWidget);
    expect(find.text('Friends'), findsNothing);
    expect(find.text('Family'), findsNothing);
    expect(find.text('Just me'), findsNothing);
    expect(find.text('A group'), findsNothing);
  });

  testWidgets('every interest maps to a real activity category', (tester) async {
    // The resource catalogue had 18 of 30 rows that no activity required, so
    // they could not change a single result. An interest that matched no
    // `activities.category` would be the same dead control with a nicer label.
    //
    // Asserted against the category vocabulary rather than a count, so adding
    // an interest fails loudly unless the category exists to rank against.
    const categories = {
      'outdoor', 'food', 'cooking', 'diy', 'fitness', 'music', 'indoor',
    };

    for (final interest in Interest.values) {
      expect(
        categories,
        contains(interest.slug),
        reason: '${interest.name} ranks against nothing',
      );
    }
  });

  testWidgets('saving sends exactly what was selected', (tester) async {
    final profiles = await _pump(tester);

    await tester.tap(find.text('My partner'));
    await tester.tap(find.text('Music'));
    await tester.tap(find.text('Outdoors and nature'));
    await tester.tap(find.text('₱500'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(profiles.preferenceWrites, hasLength(1));
    final written = profiles.preferenceWrites.single;
    expect(written.companionType, CompanionType.partner);
    expect(written.interests, {Interest.music, Interest.outdoor});
    expect(written.usualBudgetPhpCents, 50000);
  });

  testWidgets('everything is un-answerable', (tester) async {
    // Clearing has to be expressible or the first tap is permanent. Null and
    // empty are what "no preference" means in the columns, so the screen has to
    // be able to produce them.
    final profiles = await _pump(
      tester,
      profile: const Profile(
        id: 'u1',
        city: 'Bocaue',
        companionType: CompanionType.partner,
        interests: {Interest.music},
        usualBudgetPhpCents: 50000,
      ),
    );

    await tester.tap(find.text('My partner'));
    await tester.tap(find.text('Music'));
    await tester.tap(find.text('₱500'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final written = profiles.preferenceWrites.single;
    expect(written.companionType, isNull);
    expect(written.interests, isEmpty);
    expect(written.usualBudgetPhpCents, isNull);
  });

  testWidgets('a saved profile comes back selected', (tester) async {
    await _pump(
      tester,
      profile: const Profile(
        id: 'u1',
        city: 'Bocaue',
        interests: {Interest.diy, Interest.food},
        usualBudgetPhpCents: 20000,
      ),
    );

    ChoiceChip budgetChip(String label) =>
        tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, label));
    FilterChip interestChip(String label) =>
        tester.widget<FilterChip>(find.widgetWithText(FilterChip, label));

    expect(interestChip('Arts and crafts').selected, isTrue);
    expect(interestChip('Food and coffee').selected, isTrue);
    expect(interestChip('Music').selected, isFalse);
    expect(budgetChip('₱200').selected, isTrue);
    expect(budgetChip('₱500').selected, isFalse);
  });

  testWidgets('₱0 is offered and reads as free', (tester) async {
    // §9: a free date is a real budget, not the absence of one. And §2: ₱0 is
    // "free" wherever it is the price of something, which a date is.
    await _pump(tester);

    expect(find.widgetWithText(ChoiceChip, 'free'), findsOneWidget);
  });

  testWidgets('a failed save is shown and does not clear the form',
      (tester) async {
    final profiles = await _pump(tester);
    profiles.failNextWrite = true;

    await tester.tap(find.text('Music'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('Could not save your preferences.'), findsOneWidget);
    // The selection survives, so a retry does not mean re-answering.
    expect(
      tester
          .widget<FilterChip>(find.widgetWithText(FilterChip, 'Music'))
          .selected,
      isTrue,
    );
  });
}
