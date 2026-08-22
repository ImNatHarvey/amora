import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/memories_repository.dart';
import '../../models/simple_plan.dart';
import '../../theme/app_tokens.dart';

/// "Which one was closed?" — then it is recorded, and that is all.
///
/// §10.2 calls stale hours the worst error Amora can ship, and the reason is not
/// the wasted fare: the couple abandons the plan, so it is never completed, so no
/// report is written, so nothing is ever corrected. The failure with the highest
/// cost produces the least signal.
///
/// So this asks for as close to nothing as possible. No note is required, no
/// completion, no rating, no photo. Two taps from the plan. Every field added
/// here is a reason somebody standing outside a locked door puts their phone away
/// instead.
///
/// Deliberately **not** placed as a third icon button on each timeline row. That
/// row already carries a drag handle, a clock and a ✕ from Phase 5, and a fourth
/// control would make the frequent actions harder to hit in order to speed up a
/// rare one.
Future<void> showReportClosureDialog({
  required BuildContext context,
  required WidgetRef ref,
  required String planId,
  required SimplePlan plan,
}) async {
  if (plan.stops.isEmpty) return;

  final stop = await showDialog<PlanStop>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Which one was closed?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final stop in plan.stops)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(stop.place.name),
              onTap: () => Navigator.of(context).pop(stop),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ],
    ),
  );

  if (stop == null || !context.mounted) return;

  await reportClosureFor(
    context: context,
    ref: ref,
    placeId: stop.place.id,
    placeName: stop.place.name,
    planId: planId,
  );
}

/// Files the report and says so. Shared by the plan screen and place detail, so
/// the two cannot drift on what a successful report looks like.
///
/// [planId] is optional because a closure may be reported while merely browsing a
/// place — `report_closure` takes a null plan by design.
Future<void> reportClosureFor({
  required BuildContext context,
  required WidgetRef ref,
  required String placeId,
  required String placeName,
  String? planId,
}) async {
  // Read before the await: a messenger resolved from a context that may have been
  // disposed while the write was in flight is the standard way this crashes.
  final messenger = ScaffoldMessenger.of(context);

  try {
    await ref.read(memoriesRepositoryProvider).reportClosure(
          placeId: placeId,
          planId: planId,
        );

    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        // Says what it will do, because the user gets nothing else out of this.
        // They are reporting a place they cannot get into, for the benefit of
        // whoever plans next — the least we owe them is confirmation it landed.
        content: Text('Thanks — we will check $placeName before suggesting it again.'),
      ),
    );
  } on Object catch (error) {
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(content: Text('$error')));
  }
}

/// The button itself, so the plan screen and place detail carry the same wording.
class ReportClosureButton extends StatelessWidget {
  const ReportClosureButton({
    required this.onPressed,
    this.label = 'Something was closed',
    super.key,
  });

  final VoidCallback onPressed;
  final String label;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).tokens;

    return Padding(
      padding: EdgeInsets.only(top: tokens.xs),
      child: TextButton.icon(
        onPressed: onPressed,
        icon: Icon(Icons.report_outlined, size: tokens.iconInline),
        label: Text(label),
      ),
    );
  }
}
