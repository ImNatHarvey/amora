import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/app/startup.dart';
import 'package:mobile/data/auth_repository.dart';
import 'package:mobile/data/profiles_repository.dart';
import 'package:mobile/data/resources_repository.dart';
import 'package:mobile/data/supabase_client_provider.dart';
import 'package:mobile/main.dart';
import 'package:mobile/models/profile.dart';
import 'package:mobile/theme/app_theme.dart';
import 'package:mobile/theme/app_tokens.dart';

import 'fakes.dart';

/// The app wired to in-memory repositories, with startup already finished.
Widget _app({
  FakeAuthRepository? auth,
  FakeProfilesRepository? profiles,
  FakeResourcesRepository? resources,
}) {
  return ProviderScope(
    overrides: [
      appStartupProvider.overrideWith((ref) async {}),
      authRepositoryProvider.overrideWithValue(auth ?? FakeAuthRepository()),
      profilesRepositoryProvider
          .overrideWithValue(profiles ?? FakeProfilesRepository()),
      resourcesRepositoryProvider
          .overrideWithValue(resources ?? FakeResourcesRepository()),
    ],
    child: const AmoraApp(),
  );
}

const _signedOut = null;

Profile _profile({String? city, DateTime? onboardedAt}) => Profile(
      id: 'user-1',
      displayName: 'Nat',
      city: city,
      onboardedAt: onboardedAt,
    );

void main() {
  group('redirect ladder', () {
    testWidgets('signed out lands on sign in', (tester) async {
      await tester.pumpWidget(_app(auth: FakeAuthRepository(userId: _signedOut)));
      await tester.pumpAndSettle();

      expect(find.text('Welcome back'), findsOneWidget);
    });

    testWidgets('signed in without a city goes to profile setup',
        (tester) async {
      await tester.pumpWidget(
        _app(
          auth: FakeAuthRepository(userId: 'user-1'),
          profiles: FakeProfilesRepository(profile: _profile()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('What should we call you?'), findsOneWidget);
    });

    testWidgets('city set but not onboarded goes to the resource picker',
        (tester) async {
      await tester.pumpWidget(
        _app(
          auth: FakeAuthRepository(userId: 'user-1'),
          profiles: FakeProfilesRepository(profile: _profile(city: 'Bocaue')),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('What do you already have?'), findsOneWidget);
    });

    testWidgets('fully set up lands on home', (tester) async {
      await tester.pumpWidget(
        _app(
          auth: FakeAuthRepository(userId: 'user-1'),
          profiles: FakeProfilesRepository(
            profile: _profile(city: 'Bocaue', onboardedAt: DateTime.utc(2026)),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Hello, Nat'), findsOneWidget);
    });
  });

  group('resource picker', () {
    testWidgets('shows saved selection and toggles', (tester) async {
      await tester.pumpWidget(
        _app(
          auth: FakeAuthRepository(userId: 'user-1'),
          profiles: FakeProfilesRepository(profile: _profile(city: 'Bocaue')),
          resources: FakeResourcesRepository(owned: {'r1'}),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('1 selected'), findsOneWidget);

      await tester.tap(find.text('Board games'));
      await tester.pumpAndSettle();
      expect(find.text('2 selected'), findsOneWidget);

      await tester.tap(find.text('Picnic mat'));
      await tester.pumpAndSettle();
      expect(find.text('1 selected'), findsOneWidget);
    });

    testWidgets('finishing with nothing selected is allowed', (tester) async {
      final resources = FakeResourcesRepository(owned: {'r1'});
      final profiles = FakeProfilesRepository(profile: _profile(city: 'Bocaue'));

      await tester.pumpWidget(
        _app(
          auth: FakeAuthRepository(userId: 'user-1'),
          profiles: profiles,
          resources: resources,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Picnic mat')); // deselect the only one
      await tester.pumpAndSettle();
      expect(find.text('Nothing selected'), findsOneWidget);

      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();

      // Owning nothing is a real answer: it still completes onboarding.
      expect(resources.owned, isEmpty);
      expect(profiles.profile!.isOnboarded, isTrue);
    });
  });

  group('splash animation', () {
    // Written in both directions on purpose. A reduced-motion check that only
    // asserts "reaches opacity 1" passes against a build that never animates at
    // all, and one that only asserts "starts faded" passes against a build that
    // ignores the accessibility setting. Neither half is worth anything alone.

    Future<void> pumpSplash(
      WidgetTester tester, {
      required bool disableAnimations,
    }) async {
      await tester.pumpWidget(
        MediaQuery(
          data: MediaQueryData(disableAnimations: disableAnimations),
          child: MaterialApp(
            theme: AppTheme.light,
            home: const StartupSplash(),
          ),
        ),
      );
    }

    double firstFrameOpacity(WidgetTester tester) =>
        tester.widget<Opacity>(find.byType(Opacity)).opacity;

    testWidgets('animates in when motion is allowed', (tester) async {
      await pumpSplash(tester, disableAnimations: false);
      await tester.pump();

      expect(firstFrameOpacity(tester), lessThan(1));

      // And it finishes — an animation that starts and stalls is worse than
      // none, because the wordmark would sit permanently half-faded.
      //
      // A fixed pump rather than `pumpAndSettle`: the progress indicator is
      // indeterminate, so it never stops animating and settling never returns.
      // Same trap as the intake's LinearProgressIndicator, recorded in HANDOFF.
      await tester.pump(const Duration(milliseconds: 600));
      expect(firstFrameOpacity(tester), 1);
    });

    testWidgets('respects the OS reduced-motion setting', (tester) async {
      // §6. Jumping to the end state is not "no splash" — it is the same
      // screen, arrived at instantly.
      await pumpSplash(tester, disableAnimations: true);
      await tester.pump();

      expect(firstFrameOpacity(tester), 1);
    });

    testWidgets('the progress indicator does not wait on the animation',
        (tester) async {
      // It reports real work. If it faded in with the wordmark, a slow start
      // would show nothing at all during the frames that matter most.
      await pumpSplash(tester, disableAnimations: false);
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });
  });

  group('startup gate', () {
    testWidgets('shows a splash while startup is still running',
        (tester) async {
      final pending = Completer<void>();
      addTearDown(() => pending.complete());

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appStartupProvider.overrideWith((ref) => pending.future),
            authRepositoryProvider.overrideWithValue(FakeAuthRepository()),
            profilesRepositoryProvider
                .overrideWithValue(FakeProfilesRepository()),
            resourcesRepositoryProvider
                .overrideWithValue(FakeResourcesRepository()),
          ],
          child: const AmoraApp(),
        ),
      );
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    // Regression: the router used to be built eagerly as MaterialApp.router's
    // routerConfig, which resolves before its builder runs. That reached
    // Supabase.instance through the auth repository and threw on a real device
    // ("You must initialize the supabase instance first"), while passing every
    // test that overrode the repositories. Here the client throws if touched,
    // so building the router too early fails the test.
    testWidgets('does not build the router before startup finishes',
        (tester) async {
      final pending = Completer<void>();
      addTearDown(() => pending.complete());

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appStartupProvider.overrideWith((ref) => pending.future),
            supabaseClientProvider.overrideWith(
              (ref) => throw StateError('Supabase touched before init'),
            ),
          ],
          child: const AmoraApp(),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('offers a retry when startup fails', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appStartupProvider.overrideWith(
              (ref) => Future<void>.error(Exception('Missing SUPABASE_URL')),
            ),
            authRepositoryProvider.overrideWithValue(FakeAuthRepository()),
            profilesRepositoryProvider
                .overrideWithValue(FakeProfilesRepository()),
            resourcesRepositoryProvider
                .overrideWithValue(FakeResourcesRepository()),
          ],
          child: const AmoraApp(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Amora could not start'), findsOneWidget);
      expect(find.textContaining('Missing SUPABASE_URL'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
    });
  });

  testWidgets('exposes Amora tokens through the theme', (tester) async {
    late AmoraTokens tokens;

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          extensions: [
            AmoraTokens.fromColorScheme(
              ColorScheme.fromSeed(seedColor: const Color(0xFFB4436C)),
            ),
          ],
        ),
        home: Builder(
          builder: (context) {
            tokens = Theme.of(context).tokens;
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    // The 4pt scale from docs/02-design-system.md §4.
    expect(tokens.xs, 4);
    expect(tokens.sm, 8);
    expect(tokens.md, 16);
    expect(tokens.lg, 24);
    expect(tokens.xl, 32);
    expect(tokens.xxl, 48);
  });
}
