import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/supabase_client_provider.dart';
import '../theme/app_tokens.dart';

/// The one-time work the app must finish before any screen can talk to Supabase.
///
/// This is deliberately *not* awaited inside `main()`. Doing that held the first
/// frame until Supabase finished initialising — around 20 seconds on a cold
/// emulator — during which the device showed a blank system splash. As a
/// provider it runs while the themed UI is already on screen, and a failure
/// becomes retryable instead of fatal.
final appStartupProvider = FutureProvider<void>((ref) => initialiseSupabase());

/// Shown while [appStartupProvider] is still running.
///
/// Deliberately *not* placed inside `MaterialApp.router`'s `builder`: that
/// builder runs after `routerConfig` is evaluated, and building the router
/// touches `Supabase.instance` — which throws until initialisation finishes.
/// The gate has to sit above the router, so `AmoraApp` switches on the startup
/// state and only constructs the router once it has data.
class StartupSplash extends StatelessWidget {
  const StartupSplash({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.tokens;

    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('Amora', style: theme.textTheme.headlineSmall),
            SizedBox(height: tokens.lg),
            const CircularProgressIndicator(),
          ],
        ),
      ),
    );
  }
}

/// Startup failure is almost always a missing or incomplete `.env`, so the
/// message is shown verbatim rather than replaced with something friendlier.
class StartupFailure extends StatelessWidget {
  const StartupFailure({
    required this.message,
    required this.onRetry,
    super.key,
  });

  final String message;
  final VoidCallback onRetry;

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
              Text(
                'Amora could not start',
                style: theme.textTheme.headlineSmall,
              ),
              SizedBox(height: tokens.sm),
              Text(message, style: theme.textTheme.bodyLarge),
              SizedBox(height: tokens.lg),
              FilledButton(onPressed: onRetry, child: const Text('Try again')),
            ],
          ),
        ),
      ),
    );
  }
}
