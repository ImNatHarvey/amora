import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/profiles_repository.dart';
import '../../data/repository_exception.dart';
import '../../data/resources_repository.dart';
import '../../models/resource.dart';
import '../../theme/app_tokens.dart';
import 'resource_icons.dart';
import '../../ui/button_spinner.dart';

/// "What do you already have?" — the inventory Phase 2 filters activities
/// against.
///
/// Finishing with nothing selected is a real answer, so Done is always enabled.
/// Completion is recorded on the profile rather than inferred from the row
/// count, which is what `profiles.onboarded_at` exists for.
class ResourcePickerScreen extends ConsumerStatefulWidget {
  const ResourcePickerScreen({super.key});

  @override
  ConsumerState<ResourcePickerScreen> createState() =>
      _ResourcePickerScreenState();
}

class _ResourcePickerScreenState extends ConsumerState<ResourcePickerScreen> {
  /// Null until the saved selection has loaded, so returning to this screen
  /// shows what was chosen before rather than an empty grid.
  Set<String>? _selected;

  bool _saving = false;
  String? _error;

  Future<void> _finish() async {
    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      await ref
          .read(resourcesRepositoryProvider)
          .replaceMine(_selected ?? <String>{});
      await ref.read(profilesRepositoryProvider).markOnboarded();

      ref.invalidate(myResourceIdsProvider);
      // The router gates on onboarded_at, so it needs the fresh profile.
      ref.invalidate(currentProfileProvider);
    } on RepositoryException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final catalog = ref.watch(resourceCatalogProvider);
    final mine = ref.watch(myResourceIdsProvider);

    // Seed the local selection once, from whatever is already saved.
    if (_selected == null && mine.hasValue) {
      _selected = {...mine.requireValue};
    }

    return Scaffold(
      body: SafeArea(
        child: catalog.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => _PickerError(
            message: error is RepositoryException
                ? error.message
                : 'Could not load the list.',
            onRetry: () => ref.invalidate(resourceCatalogProvider),
          ),
          data: (resources) => _PickerBody(
            resources: resources,
            selected: _selected ?? const <String>{},
            saving: _saving,
            error: _error,
            onToggle: (id) => setState(() {
              final next = {..._selected ?? <String>{}};
              next.contains(id) ? next.remove(id) : next.add(id);
              _selected = next;
            }),
            onFinish: _saving ? null : _finish,
          ),
        ),
      ),
    );
  }
}

class _PickerBody extends StatelessWidget {
  const _PickerBody({
    required this.resources,
    required this.selected,
    required this.saving,
    required this.error,
    required this.onToggle,
    required this.onFinish,
  });

  final List<Resource> resources;
  final Set<String> selected;
  final bool saving;
  final String? error;
  final ValueChanged<String> onToggle;
  final VoidCallback? onFinish;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.tokens;

    // The catalogue arrives ordered by category, so grouping preserves it.
    final byCategory = <String?, List<Resource>>{};
    for (final resource in resources) {
      byCategory.putIfAbsent(resource.category, () => []).add(resource);
    }

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: EdgeInsets.all(tokens.md),
            children: [
              SizedBox(height: tokens.lg),
              Text(
                'What do you already have?',
                style: theme.textTheme.headlineSmall,
              ),
              SizedBox(height: tokens.sm),
              Text(
                'We only suggest plans you can actually pull off. Skip anything '
                'you are not sure about — you can change this later.',
                style: theme.textTheme.bodyLarge,
              ),
              SizedBox(height: tokens.lg),
              for (final entry in byCategory.entries) ...[
                Text(
                  resourceCategoryLabel(entry.key),
                  style: theme.textTheme.titleMedium,
                ),
                SizedBox(height: tokens.sm),
                Wrap(
                  spacing: tokens.sm,
                  runSpacing: tokens.sm,
                  children: [
                    for (final resource in entry.value)
                      FilterChip(
                        label: Text(resource.name),
                        avatar: Icon(resourceIcon(resource.icon)),
                        selected: selected.contains(resource.id),
                        onSelected:
                            saving ? null : (_) => onToggle(resource.id),
                      ),
                  ],
                ),
                SizedBox(height: tokens.lg),
              ],
            ],
          ),
        ),
        // Kept out of the scroll view so Done is always reachable.
        Padding(
          padding: EdgeInsets.all(tokens.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (error case final message?) ...[
                Text(
                  message,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: theme.colorScheme.error),
                ),
                SizedBox(height: tokens.sm),
              ],
              Text(
                selected.isEmpty
                    ? 'Nothing selected'
                    : '${selected.length} selected',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              SizedBox(height: tokens.sm),
              FilledButton(
                onPressed: onFinish,
                child: saving
                    ? const ButtonSpinner()
                    : const Text('Done'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PickerError extends StatelessWidget {
  const _PickerError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.tokens;

    return Center(
      child: Padding(
        padding: EdgeInsets.all(tokens.md),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(message, style: theme.textTheme.bodyLarge),
            SizedBox(height: tokens.md),
            FilledButton(onPressed: onRetry, child: const Text('Try again')),
          ],
        ),
      ),
    );
  }
}
