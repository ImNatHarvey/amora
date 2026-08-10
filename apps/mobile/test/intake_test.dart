import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/data/intake_repository.dart';
import 'package:mobile/data/profiles_repository.dart';
import 'package:mobile/data/retrieval_repository.dart';
import 'package:mobile/features/intake/intake_screen.dart';
import 'package:mobile/models/intake.dart';
import 'package:mobile/models/profile.dart';
import 'package:mobile/theme/app_theme.dart';

import 'fakes.dart';

/// Phase 3b — the conversation.
///
/// **Nothing here tests extraction itself.** That is a model call, guarded by
/// `extraction_test.ts` (which proves nothing unsafe gets through) and measured
/// by `acceptance.mjs` (which proves the model behaves). What a widget test can
/// honestly check is the thing those cannot: that the **chip path never calls
/// the model at all**, which is the entire cost argument for §7 step 0.

Future<FakeIntakeRepository> _pump(
  WidgetTester tester, {
  IntakeConstraints? returns,
  Object? error,
}) async {
  final intake = FakeIntakeRepository(returns: returns, error: error);

  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        intakeRepositoryProvider.overrideWithValue(intake),
        retrievalRepositoryProvider.overrideWithValue(FakeRetrievalRepository()),
        profilesRepositoryProvider.overrideWithValue(
          FakeProfilesRepository(
            profile: const Profile(id: 'u1', displayName: 'Nat', city: 'Bocaue'),
          ),
        ),
      ],
      child: MaterialApp(theme: AppTheme.light, home: const IntakeScreen()),
    ),
  );
  await tester.pumpAndSettle();
  return intake;
}

void main() {
  testWidgets('the empty thread offers something to press', (tester) async {
    // §9's empty-state rule: never a blank thread with nothing to press.
    await _pump(tester);

    expect(find.text('Tonight'), findsOneWidget);
    expect(find.text('This weekend'), findsOneWidget);
    expect(find.text('Under ₱200'), findsOneWidget);
  });

  testWidgets('a starter chip costs no model call', (tester) async {
    // This is the cost argument for the whole phase. A tapped chip is already
    // a structured value, so it must skip extraction entirely — if it ever
    // started calling the model, the conversation would stop being affordable
    // and nothing would look different on screen.
    final intake = await _pump(tester);

    await tester.tap(find.text('Under ₱200'));
    await tester.pumpAndSettle();

    expect(intake.calls, isEmpty);
  });

  testWidgets('a tapped starter visibly does something', (tester) async {
    // Regression: the chips row was gated on "budget is set OR there are
    // messages", so tapping "Tonight" set a value that nothing rendered and the
    // starter screen stayed up. The tap read as a no-op.
    await _pump(tester);

    await tester.tap(find.text('Tonight'));
    await tester.pumpAndSettle();

    // Starters gone, chips in their place.
    expect(find.text('This weekend'), findsNothing);
    expect(find.text('How much?'), findsOneWidget);
    expect(find.text('Starting where?'), findsOneWidget);
  });

  testWidgets('an unresolved constraint asks rather than defaulting',
      (tester) async {
    // §9: a constraint the model could not determine appears as an unfilled
    // chip prompting for it, never as a silent default. A wrong assumption the
    // user can see costs a tap; a hidden one costs their evening.
    await _pump(tester);

    await tester.tap(find.text('Under ₱200'));
    await tester.pumpAndSettle();

    expect(find.text('When?'), findsOneWidget);
    expect(find.text('Starting where?'), findsOneWidget);
    // ₱200 is shown back, so the reading is visible rather than assumed.
    expect(find.text('₱200'), findsOneWidget);
  });

  testWidgets('typing calls extraction exactly once', (tester) async {
    final intake = await _pump(
      tester,
      returns: const IntakeConstraints(budgetPhpCents: 30000),
    );

    await tester.enterText(find.byType(TextField), 'we have 300 tonight');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pumpAndSettle();

    expect(intake.calls, ['we have 300 tonight']);
    expect(find.text('we have 300 tonight'), findsOneWidget);
    expect(find.text('₱300'), findsOneWidget);
  });

  testWidgets('correcting a chip after typing does not re-extract',
      (tester) async {
    // "Correcting a chip re-plans" is an acceptance criterion, and the cost
    // control depends on it not re-reading language to do so.
    final intake = await _pump(
      tester,
      returns: const IntakeConstraints(budgetPhpCents: 30000),
    );

    await tester.enterText(find.byType(TextField), 'we have 300 tonight');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pumpAndSettle();
    expect(intake.calls.length, 1);

    await tester.tap(find.text('₱300'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '450');
    await tester.tap(find.text('Set'));
    await tester.pumpAndSettle();

    // Still one call: the correction went straight to the structured record.
    expect(intake.calls.length, 1);
    expect(find.text('₱450'), findsOneWidget);
  });

  testWidgets('a failed extraction keeps the thread and offers a retry',
      (tester) async {
    // The failure that matters is a missing API key, and the server's sentence
    // says how to fix it. Losing what the user typed on top of that would be
    // gratuitous.
    await _pump(tester, error: Exception('GEMINI_API_KEY is not set'));

    await tester.enterText(find.byType(TextField), 'under 200 tonight');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pumpAndSettle();

    expect(find.textContaining('GEMINI_API_KEY'), findsOneWidget);
    expect(find.text('under 200 tonight'), findsOneWidget);
  });

  testWidgets('the form stays reachable as the fallback', (tester) async {
    // It is the fallback when extraction fails and the only way to exercise
    // retrieval with no model in the loop, so it must not become dev-only.
    await _pump(tester);

    expect(find.text('Use the form'), findsOneWidget);
  });
}
