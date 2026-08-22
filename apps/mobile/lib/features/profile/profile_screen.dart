import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../data/auth_repository.dart';
import '../../data/profiles_repository.dart';
import '../../data/resources_repository.dart';
import '../../models/profile.dart';
import '../../theme/app_tokens.dart';
import '../../util/format.dart';

/// Who you are, what you own, and how you usually plan.
///
/// Absorbs what the old home screen carried that was not planning — the
/// greeting, the owned-resource count, preferences, the token gallery and sign
/// out. Home itself is gone: its button column was the navigation, and the
/// navigation is now the bar.
///
/// Nothing here is required. A user who never opens this tab gets the same app,
/// which is why the summary reads as information rather than as unfinished
/// setup — no completion meter, no "3 of 5 done".
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final tokens = theme.tokens;

    final profile = ref.watch(currentProfileProvider);
    final myResources = ref.watch(myResourceIdsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: SafeArea(
        child: ListView(
          padding: EdgeInsets.all(tokens.md),
          children: [
            Text(
              switch (profile) {
                AsyncData(:final value?) when value.displayName != null =>
                  value.displayName!,
                _ => 'Amora',
              },
              style: theme.textTheme.headlineSmall,
            ),
            SizedBox(height: tokens.xs),
            Text(
              switch (profile) {
                AsyncData(:final value?) when value.hasCity =>
                  '${value.city}, Bulacan',
                _ => 'Bocaue, Bulacan',
              },
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            SizedBox(height: tokens.lg),

            // --- How you usually plan ---------------------------------------
            Card(
              child: Padding(
                padding: EdgeInsets.all(tokens.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('How you usually plan',
                        style: theme.textTheme.titleMedium),
                    SizedBox(height: tokens.xs),
                    Text(
                      _preferenceSummary(profile.valueOrNull),
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                    SizedBox(height: tokens.sm),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: FilledButton.tonal(
                        onPressed: () => context.push(Routes.preferences),
                        child: Text(
                          profile.valueOrNull?.hasPreferences ?? false
                              ? 'Edit'
                              : 'Set your preferences',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SizedBox(height: tokens.sm),

            // --- What you own -----------------------------------------------
            Card(
              child: Padding(
                padding: EdgeInsets.all(tokens.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('What you own', style: theme.textTheme.titleMedium),
                    SizedBox(height: tokens.xs),
                    myResources.when(
                      loading: () => Text('Loading…',
                          style: theme.textTheme.bodyMedium),
                      error: (_, _) => Text(
                        'Could not load what you own.',
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(color: theme.colorScheme.error),
                      ),
                      data: (ids) => Text(
                        ids.isEmpty
                            ? 'Nothing listed yet. We only suggest plans you '
                                'can actually pull off, so this is worth doing.'
                            : '${ids.length} '
                                '${ids.length == 1 ? 'thing' : 'things'} we can '
                                'plan around.',
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ),
                    SizedBox(height: tokens.sm),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: FilledButton.tonal(
                        onPressed: () => context.push(Routes.onboardingResources),
                        child: const Text('Change'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SizedBox(height: tokens.lg),

            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.palette_outlined),
              title: const Text('Design tokens'),
              subtitle: const Text('A verification surface, not a setting'),
              onTap: () => context.push(Routes.devTokens),
            ),
            const Divider(),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.logout, color: theme.colorScheme.error),
              title: Text(
                'Sign out',
                style: TextStyle(color: theme.colorScheme.error),
              ),
              onTap: () => ref.read(authRepositoryProvider).signOut(),
            ),
          ],
        ),
      ),
    );
  }
}

/// One line describing what has been expressed, or an invitation if nothing has.
///
/// A sentence rather than a chip row, because this is a summary of another
/// screen and repeating its controls here would give two places to change the
/// same value.
String _preferenceSummary(Profile? profile) {
  if (profile == null || !profile.hasPreferences) {
    return 'Nothing set. Amora works fine without this — it only changes the '
        'order things appear in.';
  }

  final parts = <String>[
    if (profile.companionType case final companion?) companion.label,
    if (profile.interests.isNotEmpty)
      profile.interests.length == 1
          ? profile.interests.single.label
          : '${profile.interests.length} interests',
    if (profile.usualBudgetPhpCents case final cents?)
      'usually ${pesos(cents)}',
  ];

  return parts.join(' · ');
}
