import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/data/auth_repository.dart';
import 'package:mobile/data/profiles_repository.dart';
import 'package:mobile/data/resources_repository.dart';
import 'package:mobile/features/profile/profile_screen.dart';
import 'package:mobile/models/preferences.dart';
import 'package:mobile/models/profile.dart';
import 'package:mobile/theme/app_theme.dart';

import 'fakes.dart';

Future<FakeAuthRepository> _pump(
  WidgetTester tester, {
  Profile? profile,
  Set<String> owned = const {'r1'},
}) async {
  // Two cards plus the two list tiles overflow an 800 px test viewport, and a
  // ListView does not build what is off-screen — so Sign out did not exist to
  // tap. Third time this trap has been hit in this repo; the fix is always to
  // raise the viewport rather than to scroll.
  tester.view.physicalSize = const Size(1080, 3200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final auth = FakeAuthRepository(userId: 'u1');

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(auth),
        profilesRepositoryProvider.overrideWithValue(
          FakeProfilesRepository(
            profile: profile ??
                const Profile(id: 'u1', displayName: 'Nat', city: 'Bocaue'),
          ),
        ),
        resourcesRepositoryProvider
            .overrideWithValue(FakeResourcesRepository(owned: owned)),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        home: const ProfileScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return auth;
}

void main() {
  testWidgets('unset preferences read as optional, not as unfinished setup',
      (tester) async {
    // Nothing here gates anything, so the copy must not imply a task list. A
    // completion meter would make an optional screen feel required and push
    // people through it to make a badge go away.
    await _pump(tester);

    expect(find.textContaining('Amora works fine without this'), findsOneWidget);
    expect(find.text('Set your preferences'), findsOneWidget);
    expect(find.text('Edit'), findsNothing);
  });

  testWidgets('set preferences are summarised in one line', (tester) async {
    await _pump(
      tester,
      profile: const Profile(
        id: 'u1',
        displayName: 'Nat',
        city: 'Bocaue',
        companionType: CompanionType.partner,
        interests: {Interest.music, Interest.outdoor},
        usualBudgetPhpCents: 50000,
      ),
    );

    expect(find.text('My partner · 2 interests · usually ₱500'), findsOneWidget);
    // The button changes verb once there is something to change.
    expect(find.text('Edit'), findsOneWidget);
    expect(find.text('Set your preferences'), findsNothing);
  });

  testWidgets('a single interest is named rather than counted', (tester) async {
    // "1 interests" is the kind of thing that ships because nobody set exactly
    // one.
    await _pump(
      tester,
      profile: const Profile(
        id: 'u1',
        city: 'Bocaue',
        interests: {Interest.music},
      ),
    );

    expect(find.text('Music'), findsOneWidget);
    expect(find.textContaining('1 interests'), findsNothing);
  });

  testWidgets('a free usual budget reads as free', (tester) async {
    // §2: ₱0 is "free" wherever it is the price of something, and a date is.
    await _pump(
      tester,
      profile: const Profile(
        id: 'u1',
        city: 'Bocaue',
        usualBudgetPhpCents: 0,
      ),
    );

    expect(find.text('usually free'), findsOneWidget);
  });

  testWidgets('owning nothing says why it is worth fixing', (tester) async {
    // Design system §5: never a bare empty state. Zero resources is the one
    // that actually costs the user results, so it says so.
    await _pump(tester, owned: const {});

    expect(find.textContaining('can actually pull off'), findsOneWidget);
  });

  testWidgets('sign out is reachable', (tester) async {
    // It lived on the old home screen. Losing it in the move would have left a
    // reinstall as the only way back to signed-out.
    final auth = await _pump(tester);

    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();

    expect(auth.signOutCount, 1);
  });
}
