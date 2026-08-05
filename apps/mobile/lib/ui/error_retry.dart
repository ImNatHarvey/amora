import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';

/// A failed load, stated plainly, with the one action that helps.
///
/// Shared because `AsyncValue.error` is handled the same way on every screen
/// (`docs/00-architecture.md` §4) and because the design system requires an
/// error state to offer an action rather than just an apology
/// (`docs/02-design-system.md` §5, §8).
///
/// The message is shown as-is. Every error reaching a widget has already passed
/// through `RepositoryException`, whose whole job is to make the text safe and
/// worth reading — so replacing it with something generic here would discard
/// the only useful part. "GEMINI_API_KEY is not set" is fixable;
/// "Something went wrong" is not.
///
/// First occupant of `lib/ui/`, which holds presentation shared across
/// features. Phase 4 fills it properly with the map, the timeline and the cost
/// breakdown.
class ErrorRetry extends StatelessWidget {
  const ErrorRetry({required this.message, required this.onRetry, super.key});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          message,
          style: theme.textTheme.bodyMedium
              ?.copyWith(color: theme.colorScheme.error),
        ),
        SizedBox(height: theme.tokens.sm),
        OutlinedButton(onPressed: onRetry, child: const Text('Try again')),
      ],
    );
  }
}
