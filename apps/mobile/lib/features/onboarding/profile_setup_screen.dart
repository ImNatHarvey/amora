import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/profiles_repository.dart';
import '../../data/repository_exception.dart';
import '../../theme/app_tokens.dart';

/// The city Amora currently covers.
///
/// Not an input. D1 scopes the MVP to one municipality, and offering a free
/// text field would invite cities that retrieval has no data for.
const _city = 'Bocaue';

class ProfileSetupScreen extends ConsumerStatefulWidget {
  const ProfileSetupScreen({super.key});

  @override
  ConsumerState<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends ConsumerState<ProfileSetupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();

  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      await ref.read(profilesRepositoryProvider).updateProfile(
            displayName: _nameController.text,
            city: _city,
          );
      // The router reads the profile, so it has to refetch before it can see
      // that the city is now set.
      ref.invalidate(currentProfileProvider);
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

    return Scaffold(
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: EdgeInsets.all(tokens.md),
            children: [
              SizedBox(height: tokens.xxl),
              Text('What should we call you?', style: theme.textTheme.headlineSmall),
              SizedBox(height: tokens.sm),
              Text(
                'Just a first name is fine.',
                style: theme.textTheme.bodyLarge,
              ),
              SizedBox(height: tokens.xl),
              TextFormField(
                controller: _nameController,
                enabled: !_saving,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => _saving ? null : _save(),
                decoration: const InputDecoration(
                  labelText: 'Name',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if ((value ?? '').trim().isEmpty) return 'Enter a name.';
                  return null;
                },
              ),
              SizedBox(height: tokens.lg),
              Card(
                elevation: 0,
                color: theme.colorScheme.surfaceContainerHighest,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(tokens.radiusMedium),
                ),
                child: Padding(
                  padding: EdgeInsets.all(tokens.md),
                  child: Row(
                    children: [
                      Icon(Icons.place_outlined, color: theme.colorScheme.primary),
                      SizedBox(width: tokens.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('$_city, Bulacan',
                                style: theme.textTheme.titleMedium),
                            Text(
                              'The only area Amora knows well, for now.',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (_error case final message?) ...[
                SizedBox(height: tokens.md),
                Text(
                  message,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: theme.colorScheme.error),
                ),
              ],
              SizedBox(height: tokens.lg),
              FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Continue'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
