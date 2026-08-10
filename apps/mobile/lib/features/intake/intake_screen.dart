import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../models/intake.dart';
import '../../theme/app_tokens.dart';
import '../../ui/error_retry.dart';
import '../../util/manila_time.dart';
import '../plan_request/plan_request_providers.dart';
import 'constraint_chips.dart';
import 'intake_providers.dart';

/// The intake. Say what you want; the constraints appear as chips you can fix.
///
/// D10 decided this over a structured form, against the recommendation, and
/// both sides are recorded in `00-architecture.md` §9 so it does not get
/// relitigated. What is not conceded is that the model still never sources a
/// fact: extraction emits constraint values only, and the Phase 2 form survives
/// underneath as the fallback and as the only way to test retrieval with no
/// model in the loop.
///
/// **The conversation stops at the itinerary** (`02-design-system.md` §9). Once
/// the constraints resolve, the result is a plan — a document to keep and walk
/// around with, not a message to scroll back through.
class IntakeScreen extends ConsumerStatefulWidget {
  const IntakeScreen({super.key});

  @override
  ConsumerState<IntakeScreen> createState() => _IntakeScreenState();
}

class _IntakeScreenState extends ConsumerState<IntakeScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _send() {
    final text = _input.text;
    if (text.trim().isEmpty) return;
    _input.clear();
    ref.read(intakeControllerProvider.notifier).say(text);
  }

  /// A starter chip. **Skips extraction entirely** — it is already a structured
  /// value, so the friendliest path is also the cheapest (§7 step 0).
  void _starter(IntakeConstraints next) {
    ref.read(intakeControllerProvider.notifier).setConstraint(next);
  }

  Future<void> _edit(IntakeField field, IntakeConstraints current) async {
    final controller = ref.read(intakeControllerProvider.notifier);

    switch (field) {
      case IntakeField.budget:
        final pesos = await _askBudget(current.budgetPhpCents);
        if (pesos != null) {
          controller.setConstraint(
            current.copyWith(budgetPhpCents: pesos * 100),
          );
        }

      case IntakeField.time:
        final when = await _askTime(current.plannedForUtc);
        if (when != null) {
          controller.setConstraint(current.copyWith(plannedForUtc: when));
        }

      case IntakeField.origin:
        final area = await _askOrigin();
        if (area != null) {
          controller.setConstraint(current.copyWith(originArea: area));
        }
    }
  }

  /// The budget chip expands into the big centred field, not a cramped row.
  ///
  /// `02-design-system.md` §5's rule survives the move to conversation:
  /// wherever a budget is entered it is the main event on that surface.
  Future<int?> _askBudget(int? currentCents) => showDialog<int>(
        context: context,
        builder: (context) => _BudgetDialog(currentCents: currentCents),
      );

  Future<DateTime?> _askTime(DateTime? currentUtc) async {
    final start = currentUtc == null ? DateTime.now() : toManila(currentUtc);

    final date = await showDatePicker(
      context: context,
      initialDate: start,
      firstDate: DateTime(start.year - 1),
      lastDate: DateTime(start.year + 1),
    );
    if (date == null || !mounted) return null;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(start),
    );
    if (time == null) return null;

    // Manila wall clock in, UTC instant out — the same conversion the retime
    // sheet makes, and wrong by eight hours if skipped.
    return manilaToUtc(
      DateTime(date.year, date.month, date.day, time.hour, time.minute),
    );
  }

  Future<String?> _askOrigin() async {
    final areas = await ref.read(originAreasProvider.future);
    if (!mounted || areas.isEmpty) return null;

    return showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Starting from'),
        children: [
          for (final area in areas)
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop(area.area),
              child: Text(area.area),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.tokens;
    final async = ref.watch(intakeControllerProvider);
    final state = async.valueOrNull ?? const IntakeState();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Plan something'),
        actions: [
          // The Phase 2 form, kept reachable. It is the fallback when
          // extraction fails and the only way to exercise retrieval with no
          // model in the loop — so it must not be dev-only.
          TextButton(
            onPressed: () => context.push(Routes.planRequest),
            child: const Text('Use the form'),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Once anything is established the chips take over from the
            // starters, so a tapped starter visibly does something.
            if (state.constraints.hasAny || state.messages.isNotEmpty)
              Padding(
                padding: EdgeInsets.fromLTRB(
                    tokens.md, tokens.md, tokens.md, tokens.sm),
                child: ConstraintChips(
                  constraints: state.constraints,
                  onEdit: (field) => _edit(field, state.constraints),
                ),
              ),

            Expanded(
              child: state.isEmpty && !state.constraints.hasAny
                  ? _Starters(onPick: _starter)
                  : ListView.builder(
                      controller: _scroll,
                      padding: EdgeInsets.all(tokens.md),
                      itemCount: state.messages.length,
                      itemBuilder: (context, i) =>
                          _MessageRow(message: state.messages[i]),
                    ),
            ),

            if (state.error != null)
              Padding(
                padding: EdgeInsets.all(tokens.md),
                child: ErrorRetry(
                  message: state.error!,
                  onRetry: () =>
                      ref.read(intakeControllerProvider.notifier).reset(),
                ),
              ),

            // A real progress state while a request is in flight, and nothing
            // at all otherwise. §6 forbids animating for delight and a
            // simulated "thinking" pause is the purest form of it.
            if (state.busy) const LinearProgressIndicator(),

            if (state.constraints.isComplete)
              Padding(
                padding: EdgeInsets.symmetric(horizontal: tokens.md),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => context.push(Routes.planRequest),
                    child: const Text('Plan it'),
                  ),
                ),
              ),

            Padding(
              padding: EdgeInsets.all(tokens.md),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _input,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      decoration: const InputDecoration(
                        hintText: 'What are you thinking?',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  SizedBox(width: tokens.sm),
                  IconButton.filled(
                    onPressed: state.busy ? null : _send,
                    icon: const Icon(Icons.arrow_upward),
                    tooltip: 'Send',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// What the budget chip expands into.
///
/// A widget rather than a controller built inside `showDialog`, because the
/// controller has to outlive the dialog's **exit animation**. Creating it in
/// the caller and disposing it from `whenComplete` throws "A
/// TextEditingController was used after being disposed" — the future completes
/// when `pop` is called, while the field is still on screen fading out. Letting
/// the dialog's own State own it makes the lifetime exactly right by
/// construction.
class _BudgetDialog extends StatefulWidget {
  const _BudgetDialog({required this.currentCents});

  final int? currentCents;

  @override
  State<_BudgetDialog> createState() => _BudgetDialogState();
}

class _BudgetDialogState extends State<_BudgetDialog> {
  late final _field = TextEditingController(
    text: widget.currentCents == null
        ? ''
        : (widget.currentCents! ~/ 100).toString(),
  );

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  void _submit() => Navigator.of(context).pop(int.tryParse(_field.text.trim()));

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Budget for the two of you'),
      content: TextField(
        controller: _field,
        autofocus: true,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.headlineSmall,
        decoration: const InputDecoration(
          prefixText: '₱',
          border: OutlineInputBorder(),
          // Zero is a first-class answer, not a lesser one (§9).
          helperText: '0 is fine — free plans are still plans.',
        ),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Set')),
      ],
    );
  }
}

/// The empty state: never a blank thread with nothing to press.
class _Starters extends StatelessWidget {
  const _Starters({required this.onPick});

  final void Function(IntakeConstraints) onPick;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.tokens;

    // Concrete openers, and each one is already a structured value — tapping
    // skips extraction entirely.
    final now = DateTime.now();
    final tonight = manilaToUtc(DateTime(now.year, now.month, now.day, 19));
    final saturday = manilaToUtc(
      DateTime(now.year, now.month, now.day, 18)
          .add(Duration(days: (DateTime.saturday - now.weekday + 7) % 7)),
    );

    return Padding(
      padding: EdgeInsets.all(tokens.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('What are you two up to?', style: theme.textTheme.headlineSmall),
          SizedBox(height: tokens.sm),
          Text(
            'Tell me your budget, when, and where you are starting from — or '
            'just tap one of these.',
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          SizedBox(height: tokens.lg),
          Wrap(
            spacing: tokens.sm,
            runSpacing: tokens.sm,
            children: [
              ActionChip(
                label: const Text('Tonight'),
                onPressed: () => onPick(IntakeConstraints(plannedForUtc: tonight)),
              ),
              ActionChip(
                label: const Text('This weekend'),
                onPressed: () =>
                    onPick(IntakeConstraints(plannedForUtc: saturday)),
              ),
              ActionChip(
                label: const Text('Under ₱200'),
                onPressed: () =>
                    onPick(const IntakeConstraints(budgetPhpCents: 20000)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// One line. Plain rows, not bubbles-in-boxes (`02-design-system.md` §9).
///
/// No avatar, no name label, no persona illustration: Amora is not a character,
/// and giving it a face invites users to ask it things the database cannot
/// answer.
class _MessageRow extends StatelessWidget {
  const _MessageRow({required this.message});

  final IntakeMessage message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.tokens;

    return Padding(
      padding: EdgeInsets.symmetric(vertical: tokens.sm),
      child: Align(
        alignment:
            message.isUser ? Alignment.centerRight : Alignment.centerLeft,
        child: ConstrainedBox(
          // Short lines matter more here than anywhere: a cramped chat reads as
          // a support widget, not a planner.
          constraints: const BoxConstraints(maxWidth: 320),
          child: Text(
            message.text,
            textAlign: message.isUser ? TextAlign.right : TextAlign.left,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: message.isUser
                  ? theme.colorScheme.onSurface
                  : theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}
