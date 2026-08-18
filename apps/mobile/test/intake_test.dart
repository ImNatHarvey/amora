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

    expect(find.text('Tonight, under ₱200'), findsOneWidget);
    expect(find.text('Something this weekend'), findsOneWidget);
    expect(find.text('Something free tonight'), findsOneWidget);
  });

  testWidgets('no starter is numbered or ordered', (tester) async {
    // The copy must read like something a person would type. A leading ordinal
    // turns a suggestion into step one of a form, which is the shape D10
    // decided against — and it is the kind of regression that only ever
    // arrives as "just a label tweak".
    await _pump(tester);

    for (final chip in tester.widgetList<ActionChip>(find.byType(ActionChip))) {
      final label = ((chip.label as Text).data)!;
      expect(
        RegExp(r'^\s*(\d+[.)]|[-•*])\s').hasMatch(label),
        isFalse,
        reason: 'starter chip "$label" is numbered or bulleted',
      );
    }
  });

  testWidgets('the free opener sets a real ₱0 budget', (tester) async {
    // §9: ₱0 is a budget, not the absence of one. Nothing on the empty state
    // said so before, and "we have no money" is the most common way this app
    // will be opened.
    await _pump(tester);

    await tester.tap(find.text('Something free tonight'));
    await tester.pumpAndSettle();

    // Echoed back as an amount, not as the word "free" — here the figure is a
    // constraint, not the price of anything.
    expect(find.text('₱0'), findsOneWidget);
  });

  testWidgets('a starter chip costs no model call', (tester) async {
    // This is the cost argument for the whole phase. A tapped chip is already
    // a structured value, so it must skip extraction entirely — if it ever
    // started calling the model, the conversation would stop being affordable
    // and nothing would look different on screen.
    final intake = await _pump(tester);

    await tester.tap(find.text('Tonight, under ₱200'));
    await tester.pumpAndSettle();

    expect(intake.calls, isEmpty);
  });

  testWidgets('a tapped starter visibly does something', (tester) async {
    // Regression: the chips row was gated on "budget is set OR there are
    // messages", so tapping "Tonight" set a value that nothing rendered and the
    // starter screen stayed up. The tap read as a no-op.
    await _pump(tester);

    await tester.tap(find.text('Something this weekend'));
    await tester.pumpAndSettle();

    // Starters gone, chips in their place.
    expect(find.text('Tonight, under ₱200'), findsNothing);
    expect(find.text('How much?'), findsOneWidget);
    expect(find.text('Starting where?'), findsOneWidget);
  });

  testWidgets('an unresolved constraint asks rather than defaulting',
      (tester) async {
    // §9: a constraint the model could not determine appears as an unfilled
    // chip prompting for it, never as a silent default. A wrong assumption the
    // user can see costs a tap; a hidden one costs their evening.
    await _pump(tester);

    await tester.tap(find.text('Tonight, under ₱200'));
    await tester.pumpAndSettle();

    // The opener fills budget and time; origin it cannot know, so it asks.
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

  testWidgets('a budget preset fills the field rather than submitting',
      (tester) async {
    // Presets are shortcuts, not the only path. If a preset submitted on tap,
    // "₱500 but actually 550" would mean reopening the sheet — which is the
    // behaviour that makes preset-only budget pickers annoying.
    await _pump(tester);

    await tester.tap(find.text('Tonight, under ₱200'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('₱200'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ChoiceChip, '₱500'));
    await tester.pumpAndSettle();

    // Still open, and the amount is now editable text rather than a committed
    // value.
    expect(find.byType(ChoiceChip), findsWidgets);
    expect(
      tester.widget<TextField>(find.byType(TextField).last).controller!.text,
      '500',
    );

    // And it can still be overtyped before committing.
    await tester.enterText(find.byType(TextField).last, '550');
    await tester.tap(find.text('Set'));
    await tester.pumpAndSettle();

    expect(find.text('₱550'), findsOneWidget);
  });

  testWidgets('free is a preset, and the sheet says the budget is not per head',
      (tester) async {
    // The inversion this guards against shipped twice: prices are per person,
    // the budget is the whole outing (§9). The sentence is on the surface where
    // the number is typed, not only in the docs.
    await _pump(tester);

    await tester.tap(find.text('Something this weekend'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('How much?'));
    await tester.pumpAndSettle();

    expect(find.text('For the whole date, not each.'), findsOneWidget);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Free'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Set'));
    await tester.pumpAndSettle();

    expect(find.text('₱0'), findsOneWidget);
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
