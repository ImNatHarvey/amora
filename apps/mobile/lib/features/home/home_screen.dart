import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../theme/app_tokens.dart';

/// Phase 0 placeholder for the app's entry screen.
///
/// The real home — budget input and generated plans — arrives in later phases.
/// This exists so the router shell has somewhere to land and so "the app boots
/// on a real device" is something you can actually look at.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.tokens;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.all(tokens.md),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Amora', style: theme.textTheme.headlineSmall),
              SizedBox(height: tokens.sm),
              Text(
                'Foundation is in place. Plans arrive in a later phase.',
                style: theme.textTheme.bodyLarge,
              ),
              SizedBox(height: tokens.lg),
              FilledButton(
                // `push`, not `go`, so the gallery gets a back entry and the
                // Material back arrow behaves as expected.
                onPressed: () => context.push(Routes.devTokens),
                child: const Text('View design tokens'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
