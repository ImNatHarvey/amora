import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/data/intake_repository.dart';
import 'package:mobile/data/profiles_repository.dart';
import 'package:mobile/data/retrieval_repository.dart';
import 'package:mobile/features/intake/intake_screen.dart';
import 'package:mobile/features/plan_request/plan_parts.dart';
import 'package:mobile/models/profile.dart';
import 'package:mobile/models/simple_plan.dart';
import 'package:mobile/theme/app_theme.dart';

import 'fakes.dart';

/// 1.3× font scale, on a phone-sized viewport.
///
/// The device pass runs at 1.3× because that is where this app breaks, and
/// every widget test in this suite runs at 1.0× on a viewport up to 2400
/// logical pixels tall — which is taller than any phone and is why nothing here
/// has ever caught an overflow. Three have been found on the device instead.
///
/// A `RenderFlex overflowed` is an exception, and an exception fails the test,
/// so these need no assertion beyond pumping. The viewport is deliberately
/// modest: a Galaxy S25 Ultra flatters the layout (`00-architecture.md` §3),
/// and the point is to catch what a smaller phone would show.
void main() {
  /// A small-but-real phone: 400×720 logical, which is close to the narrow end
  /// of what Android ships, rather than the flagship this project tests on.
  void useSmallPhoneAt13x(WidgetTester tester) {
    tester.view.physicalSize = const Size(400, 720);
    tester.view.devicePixelRatio = 1.0;
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  }

  group('the price breakdown', () {
    testWidgets('a five-line breakdown wraps rather than overflowing',
        (tester) async {
      useSmallPhoneAt13x(tester);

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: TotalsBlock(
              totals: const PlanTotals(
                placesPhpCents: 110000,
                faresPhpCents: 3000,
                activitiesPhpCents: 20000,
                totalPhpCents: 133000,
                unpricedLegs: 0,
                isComplete: true,
                // Every line populated, which is the longest string this can
                // produce: roughly 60 characters before scaling.
                lines: CostLines(
                  faresPhpCents: 3000,
                  foodPhpCents: 30000,
                  materialsPhpCents: 20000,
                  activitiesPhpCents: 30000,
                  giftsPhpCents: 50000,
                ),
              ),
            ),
          ),
        ),
      ));

      expect(find.textContaining('gifts ₱500'), findsOneWidget);
    });

    testWidgets('the unpriced-leg warning survives 1.3× too', (tester) async {
      useSmallPhoneAt13x(tester);

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: TotalsBlock(
              totals: const PlanTotals(
                placesPhpCents: 30000,
                faresPhpCents: 0,
                totalPhpCents: 30000,
                unpricedLegs: 2,
                isComplete: false,
                lines: CostLines(
                  faresPhpCents: 0,
                  foodPhpCents: 30000,
                  materialsPhpCents: 0,
                  activitiesPhpCents: 0,
                  giftsPhpCents: 0,
                ),
              ),
            ),
          ),
        ),
      ));

      expect(find.textContaining('At least ₱300'), findsOneWidget);
      expect(find.textContaining('no recorded'), findsOneWidget);
    });
  });

  group('the budget sheet', () {
    /// The sheet whose whole job is to be usable with the keyboard up.
    ///
    /// `autofocus: true` means the keyboard is up the moment it opens, so the
    /// content has to fit in what is left. A widget test has no real keyboard,
    /// so the inset is injected — otherwise this passes for the wrong reason.
    /// The inset is raised **after** the sheet is open, through the view rather
    /// than a wrapping MediaQuery.
    ///
    /// Injecting it around the whole app instead squashes the intake screen
    /// too, which a real keyboard never does — the first attempt at this test
    /// failed by never reaching the sheet at all. The keyboard appears because
    /// the sheet's field takes focus, so the inset has to arrive in that order
    /// or the test is measuring a layout the user never sees.
    Future<void> pumpSheet(WidgetTester tester, double keyboardInset) async {
      useSmallPhoneAt13x(tester);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            intakeRepositoryProvider.overrideWithValue(FakeIntakeRepository()),
            retrievalRepositoryProvider
                .overrideWithValue(FakeRetrievalRepository()),
            profilesRepositoryProvider.overrideWithValue(
              FakeProfilesRepository(
                profile: const Profile(
                    id: 'u1', displayName: 'Nat', city: 'Bocaue'),
              ),
            ),
          ],
          child: MaterialApp(theme: AppTheme.light, home: const IntakeScreen()),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Something this weekend'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('How much?'));
      await tester.pumpAndSettle();

      if (keyboardInset > 0) {
        tester.view.viewInsets = FakeViewPadding(bottom: keyboardInset);
        await tester.pumpAndSettle();
      }
    }

    testWidgets('fits with the keyboard up at 1.3×', (tester) async {
      // ~300 logical pixels is an ordinary Android keyboard. With the sheet's
      // displaySmall amount field, a two-line helper, five preset chips and two
      // buttons, this is the combination the device pass was told to watch.
      await pumpSheet(tester, 300);

      expect(find.text('For the whole date, not each.'), findsOneWidget);
      expect(find.text('Set'), findsOneWidget);
    });

    testWidgets('fits with no keyboard at 1.3×', (tester) async {
      await pumpSheet(tester, 0);

      expect(find.text('Set'), findsOneWidget);
    });
  });
}
