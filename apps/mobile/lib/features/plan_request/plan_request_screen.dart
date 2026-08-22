import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/intake.dart';
import '../../models/simple_plan.dart';
import '../../theme/app_tokens.dart';
import '../../ui/error_retry.dart';
import '../../util/format.dart';
import '../../util/manila_time.dart';
import '../plan/save_plan_button.dart';
import 'generated_plan_view.dart';
import 'plan_parts.dart';
import 'plan_request_providers.dart';
import '../../ui/button_spinner.dart';

/// Phase 2's verification surface: budget in, costed plan out.
///
/// Deliberately plain. There is no map, no card, no colour and no motion, and
/// that is the point — this screen exists to answer one question, which is
/// whether the curated data produces a plan worth having. Any styling here
/// would make a bad answer look better than it is. The designed experience is
/// Phase 4's job (`docs/00-architecture.md` §8).
class PlanRequestScreen extends ConsumerStatefulWidget {
  const PlanRequestScreen({this.constraints, super.key});

  /// What the intake conversation already established, if it sent us here.
  ///
  /// Null when the form is opened directly — "Use the form" from an empty
  /// conversation, or a deep link — and every field below then falls back to
  /// the defaults it always had. The form has to work standalone: it is the
  /// fallback when extraction fails (`docs/00-architecture.md` §8).
  final IntakeConstraints? constraints;

  @override
  ConsumerState<PlanRequestScreen> createState() => _PlanRequestScreenState();
}

class _PlanRequestScreenState extends ConsumerState<PlanRequestScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _budgetController = TextEditingController(
    text: switch (widget.constraints?.budgetPhpCents) {
      final int cents => (cents / 100).round().toString(),
      _ => '200',
    },
  );

  OriginArea? _origin;

  /// The barangay the conversation named, held until the area list loads.
  ///
  /// The dropdown needs an [OriginArea] — a name plus coordinates plus a place
  /// count — and only the server has those. So the name waits here and is
  /// matched against the list the moment it arrives.
  late String? _pendingOriginArea = widget.constraints?.originArea;

  late DateTime _plannedForManila = switch (widget.constraints?.plannedForUtc) {
    final DateTime utc => toManila(utc),
    _ => _defaultTime(),
  };

  /// The area the conversation named, or the first one, or whatever the user
  /// has since picked.
  ///
  /// Falling back to `list.first` is what this screen always did, and it is
  /// still right for a form opened cold. What was wrong was doing it when the
  /// conversation had already said "Lolomboy" — the answer was thrown away and
  /// the dropdown silently showed whichever barangay sorts first.
  OriginArea _resolveOrigin(List<OriginArea> list) {
    final named = _pendingOriginArea;
    if (named == null) return list.first;

    final match = list.where((a) => a.area == named).firstOrNull;
    // Cleared either way: an area the server does not offer must not keep
    // overriding a choice the user makes afterwards.
    _pendingOriginArea = null;
    return _origin = match ?? list.first;
  }

  /// Now, in Manila, rounded up to the next half hour — nobody plans for 18:03.
  static DateTime _defaultTime() {
    final now = toManila(DateTime.now().toUtc());
    final minute = now.minute < 30 ? 30 : 60;
    return DateTime(now.year, now.month, now.day, now.hour)
        .add(Duration(minutes: minute));
  }

  @override
  void dispose() {
    _budgetController.dispose();
    super.dispose();
  }

  Future<void> _pickTime() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _plannedForManila,
      firstDate: DateTime(_plannedForManila.year - 1),
      lastDate: DateTime(_plannedForManila.year + 1),
    );
    if (date == null || !mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_plannedForManila),
    );
    if (time == null || !mounted) return;

    setState(() {
      _plannedForManila =
          DateTime(date.year, date.month, date.day, time.hour, time.minute);
    });
  }

  /// Reads the form, or null when it is not usable yet.
  ///
  /// Both buttons need exactly the same three values, so parsing them once
  /// keeps the crude builder and the model on identical input — which is the
  /// only way comparing their output means anything.
  ({int budgetPhpCents, DateTime plannedForUtc, OriginArea origin})? _request() {
    if (!_formKey.currentState!.validate()) return null;

    final origin = _origin;
    if (origin == null) return null;

    // Pesos in the field, centavos on the wire. Money is never a double
    // (CLAUDE.md conventions), so the conversion happens here at the boundary
    // and nowhere else.
    final pesos = int.parse(_budgetController.text.trim());

    return (
      budgetPhpCents: pesos * 100,
      plannedForUtc: manilaToUtc(_plannedForManila),
      origin: origin,
    );
  }

  void _submit() {
    final request = _request();
    if (request == null) return;

    ref.read(planControllerProvider.notifier).submit(
          budgetPhpCents: request.budgetPhpCents,
          plannedForUtc: request.plannedForUtc,
          origin: request.origin,
        );
  }

  void _generate() {
    final request = _request();
    if (request == null) return;

    ref.read(generationControllerProvider.notifier).generate(
          budgetPhpCents: request.budgetPhpCents,
          plannedForUtc: request.plannedForUtc,
          origin: request.origin,
        );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.tokens;

    final areas = ref.watch(originAreasProvider);
    final result = ref.watch(planControllerProvider);
    final generated = ref.watch(generationControllerProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Plan something')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: EdgeInsets.all(tokens.md),
            children: [
              TextFormField(
                controller: _budgetController,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  labelText: 'Budget',
                  prefixText: '₱',
                  border: OutlineInputBorder(),
                  // Zero is a first-class answer, not a lesser one (docs §9).
                  helperText: '0 is fine — free plans are still plans.',
                ),
                validator: (value) {
                  final text = (value ?? '').trim();
                  if (text.isEmpty) return 'Enter a budget.';
                  if (int.tryParse(text) == null) return 'Numbers only.';
                  return null;
                },
              ),
              SizedBox(height: tokens.md),
              areas.when(
                loading: () => const LinearProgressIndicator(),
                error: (error, _) => Text(
                  '$error',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: theme.colorScheme.error),
                ),
                data: (list) => list.isEmpty
                    ? Text(
                        'No areas have curated places yet, so there is nowhere '
                        'to start from.',
                        style: theme.textTheme.bodyMedium,
                      )
                    : DropdownButtonFormField<OriginArea>(
                        initialValue: _origin ?? _resolveOrigin(list),
                        decoration: const InputDecoration(
                          labelText: 'Starting from',
                          border: OutlineInputBorder(),
                        ),
                        items: [
                          for (final area in list)
                            DropdownMenuItem(
                              value: area,
                              child: Text(
                                '${area.area} '
                                '(${area.placeCount} '
                                '${area.placeCount == 1 ? "place" : "places"})',
                              ),
                            ),
                        ],
                        onChanged: (value) => setState(() => _origin = value),
                      ),
              ),
              SizedBox(height: tokens.md),
              OutlinedButton.icon(
                onPressed: _pickTime,
                icon: const Icon(Icons.schedule),
                label: Text('When: ${formatManila(_plannedForManila)}'),
              ),
              SizedBox(height: tokens.lg),
              FilledButton(
                onPressed: result.isLoading
                    ? null
                    : () {
                        // The dropdown shows the first area before anything is
                        // picked; adopt it so submitting without touching it
                        // does what it looks like it will do.
                        _origin ??= areas.valueOrNull?.firstOrNull;
                        _submit();
                      },
                child: result.isLoading
                    ? const ButtonSpinner()
                    : const Text('Build a plan'),
              ),
              SizedBox(height: tokens.sm),
              // Same three inputs, the other composer. Side by side on purpose:
              // "did the model beat nearest-first" is the question Phase 3
              // exists to answer, and it is only answerable if both are one tap
              // apart on identical input.
              OutlinedButton(
                onPressed: generated.isLoading
                    ? null
                    : () {
                        _origin ??= areas.valueOrNull?.firstOrNull;
                        _generate();
                      },
                child: generated.isLoading
                    ? const ButtonSpinner()
                    : const Text('Generate with AI'),
              ),
              SizedBox(height: tokens.lg),
              const Divider(),
              generated.when(
                loading: () => const SizedBox.shrink(),
                error: (error, _) => Padding(
                  padding: EdgeInsets.only(top: tokens.md),
                  child: ErrorRetry(
                    message: '$error',
                    onRetry: () => ref.invalidate(generationControllerProvider),
                  ),
                ),
                data: (timed) => timed == null
                    ? const SizedBox.shrink()
                    : GeneratedPlanView(timed: timed),
              ),
              SizedBox(height: tokens.md),
              result.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, _) => ErrorRetry(
                  message: '$error',
                  onRetry: () =>
                      ref.invalidate(planControllerProvider),
                ),
                data: (timed) => timed == null
                    ? Text(
                        'No plan yet. Set a budget and press the button.',
                        style: theme.textTheme.bodyMedium,
                      )
                    : _PlanView(timed: timed),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlanView extends StatelessWidget {
  const _PlanView({required this.timed});

  final TimedPlan timed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.tokens;
    final plan = timed.plan;
    final plannedFor = toManila(plan.plannedForUtc);

    if (plan.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Nothing fits.', style: theme.textTheme.titleMedium),
          SizedBox(height: tokens.sm),
          Text(
            plan.radiusM == null
                ? 'No curated place near ${plan.originArea} is open at '
                    '${formatManila(plannedFor)}.'
                : 'Places were open within ${distance(plan.radiusM!)}, but '
                    'none fit ${pesos(plan.budgetPhpCents, zeroIsFree: false)}.',
            style: theme.textTheme.bodyMedium,
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${plan.stops.length} stops from ${plan.originArea}'
          '${plan.partySize == 1 ? '' : ' for ${plan.partySize}'}',
          style: theme.textTheme.titleMedium,
        ),
        SizedBox(height: tokens.xs),
        Text(
          '${formatManila(plannedFor)} · '
          'budget ${pesos(plan.budgetPhpCents, zeroIsFree: false)}'
          '${plan.radiusM == null ? '' : ' · within ${distance(plan.radiusM!)}'}'
          ' · ${timed.elapsed.inMilliseconds} ms',
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        SizedBox(height: tokens.md),
        for (var i = 0; i < plan.stops.length; i += 1) ...[
          if (i < plan.legs.length) LegLine(leg: plan.legs[i]),
          StopLine(
            stop: plan.stops[i],
            plannedFor: plannedFor,
            partySize: plan.partySize,
          ),
        ],
        SizedBox(height: tokens.md),
        const Divider(),
        TotalsBlock(totals: plan.totals),
        SavePlanButton(payload: plan.sourcePayload),
        if (plan.candidateActivities.isNotEmpty) ...[
          SizedBox(height: tokens.md),
          const Divider(),
          SizedBox(height: tokens.sm),
          Text(
            'You have the gear for ${plan.candidateActivities.length} '
            'activities',
            style: theme.textTheme.titleSmall,
          ),
          SizedBox(height: tokens.xs),
          Text(
            plan.candidateActivities.map((a) => a.title).join(' · '),
            style: theme.textTheme.bodySmall,
          ),
        ],
      ],
    );
  }
}
