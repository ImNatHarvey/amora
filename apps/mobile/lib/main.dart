import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/router.dart';
import 'app/startup.dart';
import 'theme/app_theme.dart';

void main() {
  // Startup work is not awaited here on purpose — see [appStartupProvider].
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
      builder: (context, child) => AppStartupGate(child: child!),
    );
  }
}
