import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../data/auth_repository.dart';
import '../../theme/app_tokens.dart';
import '../../theme/brand_mark.dart';
import 'auth_form.dart';

class SignInScreen extends ConsumerWidget {
  const SignInScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final tokens = theme.tokens;

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: EdgeInsets.all(tokens.md),
          children: [
            SizedBox(height: tokens.xxl),
            const BrandMark(art: BrandArt.logo, size: 64),
            SizedBox(height: tokens.lg),
            Text('Welcome back', style: theme.textTheme.headlineSmall),
            SizedBox(height: tokens.sm),
            Text(
              'Sign in to pick up where you left off.',
              style: theme.textTheme.bodyLarge,
            ),
            SizedBox(height: tokens.xl),
            AuthForm(
              submitLabel: 'Sign in',
              // No navigation on success: the router's redirect moves us as
              // soon as the session appears.
              onSubmit: (email, password) => ref
                  .read(authRepositoryProvider)
                  .signIn(email: email, password: password),
            ),
            SizedBox(height: tokens.lg),
            TextButton(
              onPressed: () => context.go(Routes.signUp),
              child: const Text('No account yet? Create one'),
            ),
          ],
        ),
      ),
    );
  }
}
