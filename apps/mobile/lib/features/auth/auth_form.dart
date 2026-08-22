import 'package:flutter/material.dart';

import '../../data/repository_exception.dart';
import '../../theme/app_tokens.dart';
import '../../ui/button_spinner.dart';

/// The email and password form shared by sign in and sign up.
///
/// Owns its controllers, validation and submitting state so neither screen has
/// to repeat them. The caller supplies what "submit" means.
class AuthForm extends StatefulWidget {
  const AuthForm({
    required this.submitLabel,
    required this.onSubmit,
    super.key,
  });

  final String submitLabel;

  /// Throws a [RepositoryException] to have its message shown inline.
  final Future<void> Function(String email, String password) onSubmit;

  @override
  State<AuthForm> createState() => _AuthFormState();
}

class _AuthFormState extends State<AuthForm> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      await widget.onSubmit(_emailController.text, _passwordController.text);
    } on RepositoryException catch (error) {
      // The repository has already turned this into something readable.
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.tokens;

    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextFormField(
            controller: _emailController,
            enabled: !_submitting,
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: 'Email',
              border: OutlineInputBorder(),
            ),
            validator: (value) {
              final email = (value ?? '').trim();
              if (email.isEmpty) return 'Enter your email address.';
              if (!email.contains('@') || !email.contains('.')) {
                return 'That does not look like an email address.';
              }
              return null;
            },
          ),
          SizedBox(height: tokens.md),
          TextFormField(
            controller: _passwordController,
            enabled: !_submitting,
            obscureText: true,
            textInputAction: TextInputAction.done,
            onFieldSubmitted: (_) => _submitting ? null : _submit(),
            decoration: const InputDecoration(
              labelText: 'Password',
              border: OutlineInputBorder(),
            ),
            validator: (value) {
              // Matches the project's Supabase minimum.
              if ((value ?? '').length < 6) {
                return 'Use at least 6 characters.';
              }
              return null;
            },
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
            onPressed: _submitting ? null : _submit,
            child: _submitting
                ? const ButtonSpinner()
                : Text(widget.submitLabel),
          ),
        ],
      ),
    );
  }
}
