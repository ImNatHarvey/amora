import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../theme/app_tokens.dart';
import 'plan_providers.dart';

/// Saves a plan and opens it.
///
/// One widget for both composers, because `build_simple_plan` and
/// `cost_generated_plan` return the same payload shape and `save_plan` accepts
/// either. A second save path would be a second chance to disagree about what a
/// plan is.
///
/// Saving is explicit rather than automatic. A plan the user did not ask to keep
/// is clutter in a list they have to maintain, and Phase 5 lets them edit what
/// they saved — which only makes sense if saving meant something.
class SavePlanButton extends ConsumerWidget {
  const SavePlanButton({
    required this.payload,
    this.title,
    super.key,
  });

  /// What the server returned. Null when a plan came from somewhere that did
  /// not keep it, in which case there is nothing honest to save.
  final Map<String, dynamic>? payload;
  final String? title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = Theme.of(context).tokens;
    final saving = ref.watch(savePlanControllerProvider);
    final body = payload;

    if (body == null) return const SizedBox.shrink();

    return Padding(
      padding: EdgeInsets.only(top: tokens.sm),
      child: FilledButton.tonal(
        onPressed: saving.isLoading
            ? null
            : () async {
                final id = await ref
                    .read(savePlanControllerProvider.notifier)
                    .save(payload: body, title: title);

                // `context.mounted` rather than a State field: this is a
                // ConsumerWidget and the await gives the user time to leave.
                if (id != null && context.mounted) {
                  context.push('${Routes.plan}/$id');
                }
              },
        child: saving.isLoading
            ? const SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Text('Save this plan'),
      ),
    );
  }
}
