import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/router.dart';
import 'data/supabase_client_provider.dart';
import 'theme/app_theme.dart';
import 'theme/app_tokens.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await initialiseSupabase();
  } catch (error) {
    // A misconfigured .env is a setup mistake, not a runtime failure to retry.
    // Show what is wrong instead of crashing to a blank screen.
    runApp(StartupErrorApp(message: '$error'));
    return;
  }

  runApp(const ProviderScope(child: AmoraApp()));
}

class AmoraApp extends StatelessWidget {
  const AmoraApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Amora',
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.system,
      routerConfig: router,
    );
  }
}

/// Shown when the app cannot start at all — currently only a missing or
/// incomplete `.env`.
class StartupErrorApp extends StatelessWidget {
  const StartupErrorApp({required this.message, super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Amora',
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.system,
      home: Builder(
        builder: (context) {
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
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
