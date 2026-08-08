import 'package:flutter/material.dart';

import '../../models/simple_plan.dart';
import '../../theme/app_tokens.dart';
import '../../util/format.dart';
import '../../util/manila_time.dart';

/// What the user chose in [showRetimeSheet].
///
/// [startTimeUtc] is a real instant, converted from the Manila wall clock the
/// picker shows, because that is what `plan_items.start_time` stores.
typedef Retiming = ({DateTime? startTimeUtc, int? durationMinutes});

/// Durations offered as chips.
///
/// A closed list rather than a number field: nobody knows a café visit lasts 47
/// minutes, and a free-text box invites a precision the answer does not have.
const _durationChoices = <int>[30, 60, 90, 120];

/// Asks when a stop starts and how long it lasts.
///
/// Returns null when dismissed, which callers must treat as "change nothing" —
/// distinct from a returned record whose fields are null, which means the user
/// deliberately cleared them.
Future<Retiming?> showRetimeSheet({
  required BuildContext context,
  required PlanStop stop,
  required DateTime planDateUtc,
}) {
  return showModalBottomSheet<Retiming>(
    context: context,
    isScrollControlled: true,
    builder: (context) => _RetimeSheet(stop: stop, planDateUtc: planDateUtc),
  );
}

class _RetimeSheet extends StatefulWidget {
  const _RetimeSheet({required this.stop, required this.planDateUtc});

  final PlanStop stop;

  /// The plan's own instant. Supplies the **date** a picked time belongs to —
  /// the picker only yields hours and minutes, and a time without a date cannot
  /// become an instant.
  final DateTime planDateUtc;

  @override
  State<_RetimeSheet> createState() => _RetimeSheetState();
}

class _RetimeSheetState extends State<_RetimeSheet> {
  TimeOfDay? _start;
  int? _duration;

  @override
  void initState() {
    super.initState();
    final existing = widget.stop.startTimeUtc;
    if (existing != null) {
      final manila = toManila(existing);
      _start = TimeOfDay(hour: manila.hour, minute: manila.minute);
    }
    _duration = widget.stop.durationMinutes;
  }

  /// The picked wall-clock time as a real UTC instant.
  ///
  /// **This conversion is the whole risk in this screen.** `showTimePicker`
  /// returns what a clock in Bocaue reads; the column stores UTC. Combining the
  /// two without `manilaToUtc` shifts every retimed stop eight hours and the
  /// plan still renders perfectly plausibly — an evening becomes a morning and
  /// nothing looks broken.
  DateTime? get _startUtc {
    final start = _start;
    if (start == null) return null;

    final planDay = toManila(widget.planDateUtc);
    return manilaToUtc(
      DateTime(planDay.year, planDay.month, planDay.day, start.hour, start.minute),
    );
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _start ?? const TimeOfDay(hour: 18, minute: 0),
    );
    if (picked != null) setState(() => _start = picked);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.tokens;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.all(tokens.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.stop.place.name, style: theme.textTheme.titleMedium),
            SizedBox(height: tokens.lg),

            Row(
              children: [
                Expanded(
                  child: Text('Starts at', style: theme.textTheme.bodyLarge),
                ),
                OutlinedButton(
                  onPressed: _pickTime,
                  child: Text(
                    _start == null
                        ? 'Pick a time'
                        : formatManilaTime(
                            DateTime(2026, 1, 1, _start!.hour, _start!.minute),
                          ),
                  ),
                ),
              ],
            ),
            SizedBox(height: tokens.lg),

            Text('For how long', style: theme.textTheme.bodyLarge),
            SizedBox(height: tokens.sm),
            Wrap(
              spacing: tokens.sm,
              children: [
                for (final minutes in _durationChoices)
                  ChoiceChip(
                    label: Text(duration(minutes)),
                    selected: _duration == minutes,
                    // Tapping the selected chip clears it. Somebody who does
                    // not know how long they will stay should be able to say
                    // so, rather than being forced to pick a number.
                    onSelected: (selected) => setState(
                      () => _duration = selected ? minutes : null,
                    ),
                  ),
              ],
            ),
            SizedBox(height: tokens.xl),

            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                SizedBox(width: tokens.sm),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(
                    (startTimeUtc: _startUtc, durationMinutes: _duration),
                  ),
                  child: const Text('Save'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
