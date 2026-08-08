import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/data/resources_repository.dart';
import 'package:mobile/data/retrieval_repository.dart';
import 'package:mobile/features/ideas/diy_tutorial.dart';
import 'package:mobile/features/ideas/ideas_screen.dart';
import 'package:mobile/models/activity.dart';
import 'package:mobile/theme/app_theme.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';

import 'fakes.dart';

const _free = Activity(
  id: 'a1',
  slug: 'sunset-watching',
  title: 'Sunset watching',
  category: 'outdoor',
  minBudgetPhpCents: 0,
  maxBudgetPhpCents: 0,
  durationMinutes: 60,
);

const _paid = Activity(
  id: 'a2',
  slug: 'cook-a-meal-together',
  title: 'Cook a meal together',
  category: 'cooking',
  minBudgetPhpCents: 15000,
  maxBudgetPhpCents: 50000,
  durationMinutes: 90,
  isDiy: true,
);

/// A DIY activity whose link is not a YouTube video. Deliberately not a YouTube
/// URL: the embed path builds a platform webview, which `flutter test` has no
/// implementation for, so the link-only branch is the one a widget test can
/// actually reach. The embed branch is covered by `tutorialRenderFor` below and
/// verified for real on device.
const _paidWithLink = Activity(
  id: 'a3',
  slug: 'scrapbook-making',
  title: 'Scrapbook making',
  category: 'diy',
  minBudgetPhpCents: 10000,
  durationMinutes: 60,
  isDiy: true,
  tutorialUrl: 'https://example.com/how-to-scrapbook',
);

Future<FakeRetrievalRepository> _pump(
  WidgetTester tester, {
  List<Activity> activities = const [],
  Object? error,
}) async {
  final retrieval = FakeRetrievalRepository(error: error)
    ..activities = activities;

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        retrievalRepositoryProvider.overrideWithValue(retrieval),
        resourcesRepositoryProvider
            .overrideWithValue(FakeResourcesRepository(owned: {'r1'})),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        home: const IdeasScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return retrieval;
}

void main() {
  testWidgets('lists what fits, and says so', (tester) async {
    await _pump(tester, activities: const [_free, _paid]);

    expect(find.text('Sunset watching'), findsOneWidget);
    expect(find.text('Cook a meal together'), findsOneWidget);
    expect(find.textContaining('2 ideas for ₱200'), findsOneWidget);
  });

  testWidgets('the party budget is halved before it reaches the server',
      (tester) async {
    // The one piece of arithmetic on this path. Activity budgets are per
    // person; the number the user typed is for two. Getting this wrong would
    // silently show a couple twice the ideas they can afford — and it has to
    // match what build_simple_plan does with the same figure.
    final retrieval = await _pump(tester, activities: const [_free]);

    expect(retrieval.activityBudgetsPhpCents.first, 200 * 100 ~/ 2);
  });

  testWidgets('a free activity takes no per-head qualifier', (tester) async {
    await _pump(tester, activities: const [_free]);

    // "free each" is absurd, and so is "₱0 for two". Assert the whole fact
    // line rather than a substring — "free" also appears in the budget field's
    // helper text, which is a different sentence doing a different job.
    expect(find.text('outdoor · 1h · free'), findsOneWidget);
    expect(find.textContaining('free each'), findsNothing);
    expect(find.textContaining('for two'), findsNothing);
  });

  testWidgets('a priced activity shows per person and for two', (tester) async {
    await _pump(tester, activities: const [_paid]);

    // Both figures, because either alone reads as a contradiction beside a
    // budget the user entered for the pair.
    expect(find.textContaining('₱150–₱500 each'), findsOneWidget);
    expect(find.textContaining('₱300 for two'), findsOneWidget);
  });

  testWidgets('finding nothing explains itself rather than saying "none"',
      (tester) async {
    await _pump(tester);

    expect(find.text('Nothing fits yet.'), findsOneWidget);
    // Design system §5: never a bare empty state — it must offer an action.
    expect(find.textContaining('add what you own'), findsOneWidget);
  });

  testWidgets('a zero budget blames the gear, not the money', (tester) async {
    await _pump(tester);
    await tester.enterText(find.byType(TextField), '0');
    await tester.pumpAndSettle();

    expect(find.textContaining('needs something you have not listed'),
        findsOneWidget);
    // "under free" would be nonsense: ₱0 here is a constraint echoed back, not
    // the price of anything.
    expect(find.textContaining('under free'), findsNothing);
  });

  testWidgets('a failed load offers a retry', (tester) async {
    await _pump(tester, error: Exception('no network'));

    expect(find.text('Try again'), findsOneWidget);
  });

  testWidgets('changing the budget re-queries', (tester) async {
    final retrieval = await _pump(tester, activities: const [_free]);

    await tester.enterText(find.byType(TextField), '50');
    await tester.pumpAndSettle();

    expect(retrieval.activityBudgetsPhpCents, contains(50 * 100 ~/ 2));
  });

  // --- DIY tutorials -------------------------------------------------------
  //
  // `tutorial_url` is null on all five DIY rows in the database, so the case
  // that actually ships is the one where nothing renders. Testing only the
  // happy path here would leave the shipping path uncovered.

  testWidgets('a DIY activity with no tutorial renders no tutorial',
      (tester) async {
    await _pump(tester, activities: const [_paid]);

    expect(find.text('Cook a meal together'), findsOneWidget);
    // An absent row, never a blank label — the rule place detail already
    // follows for a missing phone number.
    expect(find.text('Watch the tutorial'), findsNothing);
    expect(find.byType(YoutubePlayer), findsNothing);
  });

  testWidgets('a non-embeddable tutorial still offers to open externally',
      (tester) async {
    await _pump(tester, activities: const [_paidWithLink]);

    expect(find.text('Watch the tutorial'), findsOneWidget);
    expect(find.byType(YoutubePlayer), findsNothing);
  });

  testWidgets('a non-DIY activity never shows a tutorial', (tester) async {
    await _pump(tester, activities: const [_free]);

    expect(find.text('Watch the tutorial'), findsNothing);
  });

  group('tutorialRenderFor', () {
    test('nothing collected renders nothing', () {
      expect(tutorialRenderFor(null), TutorialRender.none);
      expect(tutorialRenderFor(''), TutorialRender.none);
      // The CSV importer writes an empty cell as an empty string, not null, so
      // whitespace has to land in the same bucket or the blank rows we ship
      // today would each grow a dead button.
      expect(tutorialRenderFor('   '), TutorialRender.none);
    });

    test('the YouTube URL shapes a person actually pastes all embed', () {
      for (final url in const [
        'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
        'https://youtube.com/watch?v=dQw4w9WgXcQ',
        'https://m.youtube.com/watch?v=dQw4w9WgXcQ',
        'https://youtu.be/dQw4w9WgXcQ',
        'https://www.youtube.com/shorts/dQw4w9WgXcQ',
        'https://www.youtube.com/embed/dQw4w9WgXcQ',
      ]) {
        expect(tutorialRenderFor(url), TutorialRender.embed, reason: url);
      }
    });

    test('anything else is a link, not a failure', () {
      // Both directions matter. A Facebook video is the likeliest non-YouTube
      // tutorial in Bocaue and must still be openable; classifying it as `none`
      // would silently drop a link somebody collected.
      expect(
        tutorialRenderFor('https://www.facebook.com/watch/?v=12345'),
        TutorialRender.linkOnly,
      );
      expect(
        tutorialRenderFor('https://vimeo.com/123456789'),
        TutorialRender.linkOnly,
      );
      expect(tutorialRenderFor('not a url at all'), TutorialRender.linkOnly);
    });
  });
}
