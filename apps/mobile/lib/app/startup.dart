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

/// Shows the app once [appStartupProvider] succeeds, and a legible failure if
/// it doesn't.
///
/// Wraps every route via `MaterialApp.router`'s `builder`, so the theme,
/// navigation and status bar are correct from the first frame regardless of
/// how long startup takes.
class AppStartupGate extends ConsumerWidget {
  const AppStartupGate({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref.watch(appStartupProvider).when(
          data: (_) => child,
          loading: () => const _StartupSplash(),
          error: (error, _) => _StartupFailure(
            message: '$error',
            onRetry: () => ref.invalidate(appStartupProvider),
          ),
        );
  }
}

class _StartupSplash extends StatelessWidget {
  const _StartupSplash();

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
class _StartupFailure extends StatelessWidget {
  const _StartupFailure({required this.message, required this.onRetry});

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
