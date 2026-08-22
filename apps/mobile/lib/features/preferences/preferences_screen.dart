import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/profiles_repository.dart';
import '../../data/repository_exception.dart';
import '../../models/preferences.dart';
import '../../models/profile.dart';
import '../../theme/app_tokens.dart';
import '../../ui/error_retry.dart';
import '../../util/format.dart';

/// "How do you usually plan?" — the three preferences that shape retrieval.
///
/// Everything here is **optional and correctable**. A user who never opens this
/// screen gets the same app, which is why nothing gates on it and why Save is
/// always enabled: clearing every answer is a real answer.
///
/// Three rules that are not cosmetic:
///
///   * **Interests rank, never filter** (`retrieve_activities`). Ticking
///     nothing must return the same activities as ticking everything, or the
///     picker becomes a way to hide the catalogue by accident.
///   * **The usual budget is a default, never a cap.** It prefills the intake
///     chip; the budget sheet still takes any number.
///   * **Companion type offers one value.** The column permits five
///     (§11), but everything past "my partner" is persona expansion, which D1
///     and `CLAUDE.md`'s not-building list defer.
class PreferencesScreen extends ConsumerWidget {
  const PreferencesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(currentProfileProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('How you usually plan')),
      body: SafeArea(
        child: profile.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Center(
            child: ErrorRetry(
              message: error is RepositoryException
                  ? error.message
                  : 'Could not load your preferences.',
              onRetry: () => ref.invalidate(currentProfileProvider),
            ),
          ),
          // A signed-in user always has a profile row (the trigger writes it),
          // so null here is the same "should be impossible" the router handles.
          // Treated as an empty form rather than an error: the worst outcome is
          // that a save creates the answers.
          data: (value) => _PreferencesForm(profile: value),
        ),
      ),
    );
  }
}

class _PreferencesForm extends ConsumerStatefulWidget {
  const _PreferencesForm({required this.profile});

  final Profile? profile;

  @override
  ConsumerState<_PreferencesForm> createState() => _PreferencesFormState();
}

class _PreferencesFormState extends ConsumerState<_PreferencesForm> {
  late CompanionType? _companion = widget.profile?.companionType;
  late final Set<Interest> _interests = {...?widget.profile?.interests};
  late int? _budget = widget.profile?.usualBudgetPhpCents;

  bool _saving = false;
  String? _error;

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      await ref.read(profilesRepositoryProvider).updatePreferences(
            companionType: _companion,
            interests: _interests,
            usualBudgetPhpCents: _budget,
          );

      // Ideas ranks on interests and the intake chip prefills from the budget,
      // so both need the fresh profile rather than the one they started with.
      ref.invalidate(currentProfileProvider);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Saved')),
        );
      }
    } on RepositoryException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.tokens;

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: EdgeInsets.all(tokens.md),
            children: [
              _Section(
                title: 'Who are you planning with?',
                subtitle: 'Amora is built for couples right now.',
                child: Wrap(
                  spacing: tokens.sm,
                  runSpacing: tokens.sm,
                  children: [
                    for (final companion in CompanionType.offered)
                      ChoiceChip(
                        label: Text(companion.label),
                        selected: _companion == companion,
                        // Selecting the chosen one again clears it. Every
                        // answer here has to be un-answerable.
                        onSelected: _saving
                            ? null
                            : (_) => setState(() => _companion =
                                _companion == companion ? null : companion),
                      ),
                  ],
                ),
              ),
              _Section(
                title: 'What do you two enjoy?',
                subtitle:
                    'This moves things up the list. It never hides anything — '
                    'you will still see everything you can afford.',
                child: Wrap(
                  spacing: tokens.sm,
                  runSpacing: tokens.sm,
                  children: [
                    for (final interest in Interest.values)
                      FilterChip(
                        label: Text(interest.label),
                        selected: _interests.contains(interest),
                        onSelected: _saving
                            ? null
                            : (_) => setState(() {
                                  _interests.contains(interest)
                                      ? _interests.remove(interest)
                                      : _interests.add(interest);
                                }),
                      ),
                  ],
                ),
              ),
              _Section(
                title: 'What do you usually spend?',
                subtitle:
                    'For the whole date, not each. We use it to fill in the '
                    'budget for you — you can always change it.',
                child: Wrap(
                  spacing: tokens.sm,
                  runSpacing: tokens.sm,
                  children: [
                    for (final cents in usualBudgetOptionsPhpCents)
                      ChoiceChip(
                        // `zeroIsFree` on purpose: here ₱0 is the price of a
                        // date, which is exactly where "free" belongs (§2).
                        label: Text(pesos(cents, zeroIsFree: true)),
                        selected: _budget == cents,
                        onSelected: _saving
                            ? null
                            : (_) => setState(
                                () => _budget = _budget == cents ? null : cents),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        // Outside the scroll view so Save is always reachable, matching the
        // resource picker.
        Padding(
          padding: EdgeInsets.all(tokens.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_error case final message?) ...[
                Text(
                  message,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: theme.colorScheme.error),
                ),
                SizedBox(height: tokens.sm),
              ],
              FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Save'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.tokens;

    return Padding(
      padding: EdgeInsets.only(bottom: tokens.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.titleMedium),
          SizedBox(height: tokens.xs),
          Text(
            subtitle,
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          SizedBox(height: tokens.sm),
          child,
        ],
      ),
    );
  }
}
