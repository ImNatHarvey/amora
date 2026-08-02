import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/simple_plan.dart';
import '../../theme/app_tokens.dart';
import '../../util/manila_time.dart';
import 'plan_request_providers.dart';

/// Phase 2's verification surface: budget in, costed plan out.
///
/// Deliberately plain. There is no map, no card, no colour and no motion, and
/// that is the point — this screen exists to answer one question, which is
/// whether the curated data produces a plan worth having. Any styling here
/// would make a bad answer look better than it is. The designed experience is
/// Phase 4's job (`docs/00-architecture.md` §8).
class PlanRequestScreen extends ConsumerStatefulWidget {
  const PlanRequestScreen({super.key});

  @override
  ConsumerState<PlanRequestScreen> createState() => _PlanRequestScreenState();
}

class _PlanRequestScreenState extends ConsumerState<PlanRequestScreen> {
  final _formKey = GlobalKey<FormState>();
  final _budgetController = TextEditingController(text: '200');

  OriginArea? _origin;
  late DateTime _plannedForManila = _defaultTime();

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

  void _submit() {
    if (!_formKey.currentState!.validate()) return;

    final origin = _origin;
    if (origin == null) return;

    // Pesos in the field, centavos on the wire. Money is never a double
    // (CLAUDE.md conventions), so the conversion happens here at the boundary
    // and nowhere else.
    final pesos = int.parse(_budgetController.text.trim());

    ref.read(planControllerProvider.notifier).submit(
          budgetPhpCents: pesos * 100,
          plannedForUtc: manilaToUtc(_plannedForManila),
          origin: origin,
        );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.tokens;

    final areas = ref.watch(originAreasProvider);
    final result = ref.watch(planControllerProvider);

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
                        initialValue: _origin ?? list.first,
                        decoration: const InputDecoration(
                          labelText: 'Starting from',
                          border: OutlineInputBorder(),
                        ),
                        items: [
                          for (final area in list)
                            DropdownMenuItem(
                              value: area,
                              child: Text(
                                '${area.area} (${area.placeCount} places)',
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
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Build a plan'),
              ),
              SizedBox(height: tokens.lg),
              const Divider(),
              SizedBox(height: tokens.md),
              result.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, _) => _ErrorRetry(
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

/// `₱180`, or `₱180.50` when the centavos are not round.
///
/// Money is integer centavos everywhere else in the app; this is the single
/// point where it becomes text for a human.
///
/// Zero reads as "free" by default, which is the design system's position on ₱0
/// — good news, never muted (docs 02 §2).
///
/// The rule, learned by reading all three wrong on a device: "free" belongs
/// wherever ₱0 is *the price of something* — a place, a leg, a plan total. Pass
/// [zeroIsFree] false wherever it is an addend in a breakdown or a constraint
/// being echoed back, because "places ₱200 · fares free", "budget free" and
/// "none fit free" all read as a category rather than an amount.
String _pesos(int cents, {bool zeroIsFree = true}) {
  if (cents == 0) return zeroIsFree ? 'free' : '₱0';
  final pesos = cents ~/ 100;
  final remainder = cents % 100;
  return remainder == 0
      ? '₱$pesos'
      : '₱$pesos.${remainder.toString().padLeft(2, '0')}';
}

String _distance(int metres) =>
    metres < 1000 ? '$metres m' : '${(metres / 1000).toStringAsFixed(1)} km';

class _ErrorRetry extends StatelessWidget {
  const _ErrorRetry({required this.message, required this.onRetry});

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
                : 'Places were open within ${_distance(plan.radiusM!)}, but '
                    'none fit ${_pesos(plan.budgetPhpCents, zeroIsFree: false)}.',
            style: theme.textTheme.bodyMedium,
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${plan.stops.length} stops from ${plan.originArea}',
          style: theme.textTheme.titleMedium,
        ),
        SizedBox(height: tokens.xs),
        Text(
          '${formatManila(plannedFor)} · '
          'budget ${_pesos(plan.budgetPhpCents, zeroIsFree: false)}'
          '${plan.radiusM == null ? '' : ' · within ${_distance(plan.radiusM!)}'}'
          ' · ${timed.elapsed.inMilliseconds} ms',
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        SizedBox(height: tokens.md),
        for (var i = 0; i < plan.stops.length; i += 1) ...[
          if (i < plan.legs.length) _LegLine(leg: plan.legs[i]),
          _StopLine(stop: plan.stops[i], plannedFor: plannedFor),
        ],
        SizedBox(height: tokens.md),
        const Divider(),
        _TotalsBlock(totals: plan.totals),
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

class _LegLine extends StatelessWidget {
  const _LegLine({required this.leg});

  final PlanLeg leg;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // An unpriced leg is stated plainly rather than hidden or guessed at. It is
    // a gap in the fare data, and seeing it is how the gap gets closed (D5).
    final fare = leg.fareKnown
        ? '${leg.mode} · ${_pesos(leg.farePhpCents ?? 0)}'
        : 'fare not recorded';

    return Padding(
      padding: EdgeInsets.only(
        left: theme.tokens.md,
        top: theme.tokens.xs,
        bottom: theme.tokens.xs,
      ),
      child: Text(
        '↳ ${_distance(leg.distanceM)} · $fare',
        style: theme.textTheme.bodySmall?.copyWith(
          color: leg.fareKnown
              ? theme.colorScheme.onSurfaceVariant
              : theme.colorScheme.error,
        ),
      ),
    );
  }
}

class _StopLine extends StatelessWidget {
  const _StopLine({required this.stop, required this.plannedFor});

  final PlanStop stop;
  final DateTime plannedFor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final place = stop.place;

    final price = place.priceMaxPhpCents == null ||
            place.priceMaxPhpCents == place.priceMinPhpCents
        ? _pesos(place.priceMinPhpCents)
        : '${_pesos(place.priceMinPhpCents)}–${_pesos(place.priceMaxPhpCents!)}';

    final hours = place.openingHours?.describe(plannedFor) ?? 'hours unknown';

    return Padding(
      padding: EdgeInsets.only(bottom: theme.tokens.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${stop.seq}. ${place.name}',
            style: theme.textTheme.bodyLarge,
          ),
          Text(
            '${place.category}'
            '${place.barangay == null ? '' : ' · ${place.barangay}'}'
            ' · $price · $hours',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _TotalsBlock extends StatelessWidget {
  const _TotalsBlock({required this.totals});

  final PlanTotals totals;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(height: theme.tokens.sm),
        Text(
          totals.isComplete
              ? 'Total ${_pesos(totals.totalPhpCents)}'
              : 'At least ${_pesos(totals.totalPhpCents)}',
          style: theme.textTheme.titleMedium,
        ),
        Text(
          'places ${_pesos(totals.placesPhpCents, zeroIsFree: false)} · '
          'fares ${_pesos(totals.faresPhpCents, zeroIsFree: false)}',
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        // Saying "total" when a leg is unpriced would present a floor as a
        // final figure. The wording above already hedges; this says why.
        if (!totals.isComplete) ...[
          SizedBox(height: theme.tokens.xs),
          Text(
            '${totals.unpricedLegs} '
            '${totals.unpricedLegs == 1 ? 'leg has' : 'legs have'} no recorded '
            'fare, so the real total is higher.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.error),
          ),
        ],
      ],
    );
  }
}
