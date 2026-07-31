import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/app/startup.dart';
import 'package:mobile/main.dart';
import 'package:mobile/theme/app_tokens.dart';

/// The app with startup already finished, so UI tests exercise screens rather
/// than Supabase initialisation.
Widget _bootedApp() => ProviderScope(
      overrides: [appStartupProvider.overrideWith((ref) async {})],
      child: const AmoraApp(),
    );

void main() {
  testWidgets('boots to the home route', (tester) async {
    await tester.pumpWidget(_bootedApp());
    await tester.pumpAndSettle();

    expect(find.text('Amora'), findsOneWidget);
    expect(find.text('View design tokens'), findsOneWidget);
  });

  testWidgets('navigates to the token gallery and back', (tester) async {
    await tester.pumpWidget(_bootedApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('View design tokens'));
    await tester.pumpAndSettle();
    expect(find.text('Design tokens'), findsOneWidget);

    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.text('View design tokens'), findsOneWidget);
  });

  testWidgets('shows a splash while startup is still running', (tester) async {
    // A future that never completes, standing in for a slow cold start.
    final pending = Completer<void>();
    addTearDown(() => pending.complete());

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appStartupProvider.overrideWith((ref) => pending.future)],
        child: const AmoraApp(),
      ),
    );
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('View design tokens'), findsNothing);
  });

  testWidgets('offers a retry when startup fails', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appStartupProvider.overrideWith(
            (ref) => Future<void>.error(Exception('Missing SUPABASE_URL')),
          ),
        ],
        child: const AmoraApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Amora could not start'), findsOneWidget);
    expect(find.textContaining('Missing SUPABASE_URL'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
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
