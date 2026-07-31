import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../data/auth_repository.dart';
import '../../theme/app_tokens.dart';
import 'auth_form.dart';

class SignUpScreen extends ConsumerWidget {
  const SignUpScreen({super.key});

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
            Text('Create your account', style: theme.textTheme.headlineSmall),
            SizedBox(height: tokens.sm),
            Text(
              'Amora is free, and stays free.',
              style: theme.textTheme.bodyLarge,
            ),
            SizedBox(height: tokens.xl),
            AuthForm(
              submitLabel: 'Create account',
              // The on_auth_user_created trigger writes the profile row, so by
              // the time the session lands the router can read it.
              onSubmit: (email, password) => ref
                  .read(authRepositoryProvider)
                  .signUp(email: email, password: password),
            ),
            SizedBox(height: tokens.lg),
            TextButton(
              onPressed: () => context.go(Routes.signIn),
              child: const Text('Already have an account? Sign in'),
            ),
          ],
        ),
      ),
    );
  }
}
