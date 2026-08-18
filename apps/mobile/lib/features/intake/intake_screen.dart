import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../data/profiles_repository.dart';
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

  /// The budget chip expands into a sheet where the amount is the whole screen.
  ///
  /// `02-design-system.md` §5's rule survives the move to conversation:
  /// wherever a budget is entered it is the main event on that surface. A
  /// bottom sheet rather than a dialog, because the presets and the amount need
  /// room to breathe and a dialog constrains both.
  ///
  /// **The saved "usual budget" seeds the field, not the constraint.** Writing
  /// it straight into `IntakeConstraints` would be an inferred value applied
  /// silently, which §8 forbids — and it would suppress the starter chips,
  /// since those only show while nothing is established. Opening the sheet on
  /// their usual number is visible and is correctable before it commits.
  Future<int?> _askBudget(int? currentCents) {
    final usual =
        ref.read(currentProfileProvider).valueOrNull?.usualBudgetPhpCents;

    return showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _BudgetSheet(currentCents: currentCents ?? usual),
    );
  }

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
          // Ideas and saved plans lost their home when the button column did
          // (Gate B). Both live in this branch, so the bar stays visible and
          // back returns here rather than to another tab.
          //
          // Ideas has to be reachable from the *filled* conversation too, not
          // only the empty state — "actually, what could we even do" is a thing
          // someone thinks halfway through, and an affordance that vanishes
          // once you start typing is not an affordance.
          IconButton(
            onPressed: () => context.push(Routes.ideas),
            icon: const Icon(Icons.lightbulb_outline),
            tooltip: 'Find something to do',
          ),
          IconButton(
            onPressed: () => context.push(Routes.plans),
            icon: const Icon(Icons.bookmark_outline),
            tooltip: 'Your plans',
          ),
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
/// A widget rather than a controller built inside `showModalBottomSheet`,
/// because the controller has to outlive the sheet's **exit animation**.
/// Creating it in the caller and disposing it from `whenComplete` throws "A
/// TextEditingController was used after being disposed" — the future completes
/// when `pop` is called, while the field is still on screen fading out. Letting
/// the sheet's own State own it makes the lifetime exactly right by
/// construction.
///
/// **Presets are shortcuts, never the only path.** Tapping one fills the field
/// rather than submitting, so the amount stays editable afterwards and an
/// unusual number is no harder to enter than a common one.
///
/// The OS numeric keyboard is used rather than a bespoke keypad. That is a
/// deliberate departure from the payment-app reference: a custom keypad has to
/// re-earn 48 dp targets and 1.3× font scaling by hand, and it loses TalkBack
/// for free. What the reference contributes is the *hierarchy* — the amount
/// dominates the surface — not the widget.
class _BudgetSheet extends StatefulWidget {
  const _BudgetSheet({required this.currentCents});

  final int? currentCents;

  @override
  State<_BudgetSheet> createState() => _BudgetSheetState();
}

class _BudgetSheetState extends State<_BudgetSheet> {
  /// Peso amounts, not centavos — this is the surface where the user thinks in
  /// pesos, and the conversion happens once at [_submit].
  static const _presets = [0, 200, 500, 1000];

  late final _field = TextEditingController(
    text: widget.currentCents == null
        ? ''
        : (widget.currentCents! ~/ 100).toString(),
  );

  @override
  void initState() {
    super.initState();
    // Redraws so the preset chips reflect what is typed, in both directions:
    // typing 500 by hand selects the ₱500 chip.
    _field.addListener(_onChanged);
  }

  void _onChanged() => setState(() {});

  @override
  void dispose() {
    _field.removeListener(_onChanged);
    _field.dispose();
    super.dispose();
  }

  int? get _pesos => int.tryParse(_field.text.trim());

  void _pick(int pesos) {
    _field.value = TextEditingValue(
      text: '$pesos',
      selection: TextSelection.collapsed(offset: '$pesos'.length),
    );
  }

  void _submit() => Navigator.of(context).pop(_pesos);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.tokens;

    return Padding(
      // The keyboard is the whole point of this sheet, so its inset has to be
      // honoured or the field it raises sits underneath it.
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: Padding(
          padding: EdgeInsets.all(tokens.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Budget for the two of you',
                style: theme.textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              SizedBox(height: tokens.xs),
              // §9's convention, stated where it is entered rather than only in
              // the docs: prices are per person, the budget is not.
              Text(
                'For the whole date, not each.',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: tokens.lg),
              TextField(
                controller: _field,
                autofocus: true,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                textAlign: TextAlign.center,
                // The amount is the main event on this surface (§5).
                style: theme.textTheme.displaySmall,
                decoration: const InputDecoration(
                  prefixText: '₱',
                  border: OutlineInputBorder(),
                  // Zero is a first-class answer, not a lesser one (§9).
                  helperText: '0 is fine — free plans are still plans.',
                  helperMaxLines: 2,
                ),
                onSubmitted: (_) => _submit(),
              ),
              SizedBox(height: tokens.lg),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: tokens.sm,
                runSpacing: tokens.sm,
                children: [
                  for (final preset in _presets)
                    ChoiceChip(
                      label: Text(preset == 0 ? 'Free' : '₱$preset'),
                      selected: _pesos == preset,
                      onSelected: (_) => _pick(preset),
                    ),
                ],
              ),
              SizedBox(height: tokens.lg),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  SizedBox(width: tokens.sm),
                  FilledButton(onPressed: _submit, child: const Text('Set')),
                ],
              ),
            ],
          ),
        ),
      ),
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
          // Phrased as something a person would type, not as a menu. No
          // ordinals and no list markers: a numbered starter reads as step one
          // of a form, which is the shape D10 decided against.
          Wrap(
            spacing: tokens.sm,
            runSpacing: tokens.sm,
            children: [
              ActionChip(
                label: const Text('Tonight, under ₱200'),
                onPressed: () => onPick(
                  IntakeConstraints(
                    plannedForUtc: tonight,
                    budgetPhpCents: 20000,
                  ),
                ),
              ),
              ActionChip(
                label: const Text('Something this weekend'),
                onPressed: () =>
                    onPick(IntakeConstraints(plannedForUtc: saturday)),
              ),
              // The ₱0 path deserves an opener of its own. §9 treats a free
              // date as a real budget rather than a failure to have one, and
              // until now nothing on the empty state said so.
              ActionChip(
                label: const Text('Something free tonight'),
                onPressed: () => onPick(
                  IntakeConstraints(plannedForUtc: tonight, budgetPhpCents: 0),
                ),
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
