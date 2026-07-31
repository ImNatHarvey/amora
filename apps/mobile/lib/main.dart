import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/router.dart';
import 'app/startup.dart';
import 'data/profiles_repository.dart';
import 'theme/app_theme.dart';

void main() {
  // Startup work is not awaited here on purpose — see [appStartupProvider].
  runApp(const ProviderScope(child: AmoraApp()));
}

class AmoraApp extends ConsumerWidget {
  const AmoraApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final startup = ref.watch(appStartupProvider);

    // The router is built only once startup has data. Constructing it reaches
    // Supabase.instance through the auth repository, which throws until
    // Supabase.initialize has run — so the router cannot be created eagerly and
    // gated from the inside.
    return switch (startup) {
      AsyncError(:final error) => _Shell(
          child: StartupFailure(
            message: '$error',
            onRetry: () => ref.invalidate(appStartupProvider),
          ),
        ),
      AsyncData() => const _RoutedApp(),
      _ => const _Shell(child: StartupSplash()),
    };
  }
}

/// The routed app, built only once the profile has resolved.
///
/// The router's redirect is synchronous and reads the profile straight from the
/// provider, so that value has to exist before the router does. Waiting here
/// also avoids flashing the home screen before onboarding takes over.
class _RoutedApp extends ConsumerWidget {
  const _RoutedApp();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(currentProfileProvider);

    // Resolves immediately to null when signed out, so this is only a real wait
    // for a returning user.
    if (profile.isLoading) return const _Shell(child: StartupSplash());

    return MaterialApp.router(
      title: 'Amora',
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.system,
      routerConfig: ref.watch(routerProvider),
    );
  }
}

/// A themed [MaterialApp] for the states that exist before routing does, so the
/// splash and the failure screen still get Amora's colours and type.
class _Shell extends StatelessWidget {
  const _Shell({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Amora',
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.system,
      home: child,
    );
  }
}
