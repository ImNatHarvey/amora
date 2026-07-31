import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/main.dart';
import 'package:mobile/theme/app_tokens.dart';

void main() {
  testWidgets('boots to the home route', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: AmoraApp()));
    await tester.pumpAndSettle();

    expect(find.text('Amora'), findsOneWidget);
    expect(find.text('View design tokens'), findsOneWidget);
  });

  testWidgets('navigates to the token gallery and back', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: AmoraApp()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('View design tokens'));
    await tester.pumpAndSettle();
    expect(find.text('Design tokens'), findsOneWidget);

    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.text('View design tokens'), findsOneWidget);
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
