import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../data/auth_repository.dart';
import '../../data/profiles_repository.dart';
import '../../data/resources_repository.dart';
import '../../theme/app_tokens.dart';

/// Phase 0 placeholder for the app's entry screen.
///
/// The real home — budget input and generated plans — arrives in later phases.
/// For now it confirms who is signed in and what they own, which is what makes
/// the Phase 1 reinstall test readable without opening the database.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final tokens = theme.tokens;

    final profile = ref.watch(currentProfileProvider);
    final myResources = ref.watch(myResourceIdsProvider);

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.all(tokens.md),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                switch (profile) {
                  AsyncData(:final value?) when value.displayName != null =>
                    'Hello, ${value.displayName}',
                  _ => 'Amora',
                },
                style: theme.textTheme.headlineSmall,
              ),
              SizedBox(height: tokens.sm),
              myResources.when(
                loading: () => Text(
                  'Loading what you own…',
                  style: theme.textTheme.bodyLarge,
                ),
                error: (_, _) => Text(
                  'Could not load what you own.',
                  style: theme.textTheme.bodyLarge
                      ?.copyWith(color: theme.colorScheme.error),
                ),
                data: (ids) => Text(
                  ids.isEmpty
                      ? 'You have not listed anything you own yet.'
                      : 'You own ${ids.length} '
                          '${ids.length == 1 ? 'thing' : 'things'} we can plan around.',
                  style: theme.textTheme.bodyLarge,
                ),
              ),
              SizedBox(height: tokens.lg),
              // Ideas leads, because it is the one that works today: it needs
              // no curated place, only the activities and the gear list, both
              // of which are real. "Plan something" needs the catalogue.
              FilledButton(
                onPressed: () => context.push(Routes.ideas),
                child: const Text('Find something to do'),
              ),
              SizedBox(height: tokens.sm),
              OutlinedButton(
                onPressed: () => context.push(Routes.plan),
                child: const Text('Plan something'),
              ),
              SizedBox(height: tokens.sm),
              OutlinedButton(
                onPressed: () => context.push(Routes.devTokens),
                child: const Text('View design tokens'),
              ),
              SizedBox(height: tokens.sm),
              // Temporary: without it the only way back to signed-out is a
              // reinstall. Moves to a settings screen in a later phase.
              TextButton(
                onPressed: () => ref.read(authRepositoryProvider).signOut(),
                child: const Text('Sign out'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
