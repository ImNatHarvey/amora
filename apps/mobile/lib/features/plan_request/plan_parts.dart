import 'package:flutter/material.dart';

import '../../models/simple_plan.dart';
import '../../theme/app_tokens.dart';
import '../../util/format.dart';

/// The pieces a plan is drawn from, shared by both composers.
///
/// Phase 2's nearest-first builder and Phase 3's model produce the same stop,
/// leg and totals shapes — costed by the same Postgres functions — so they must
/// render identically too. If a fare read one way under one composer and
/// another way under the other, comparing them would be comparing the
/// presentation rather than the plans.
///
/// Deliberately plain: no cards, no colour, no motion. Phase 4 designs the real
/// plan experience; styling here would flatter whichever output happened to get
/// it first.
/// How one leg reads: `450 m · jeepney · ₱30`, or the gap stated plainly.
///
/// Built from [PlanLeg.segments] rather than from `mode`, which today is a list
/// of one. §12.3: a day trip out of Bocaue is a bus, then an MRT ride, then a
/// jeep, and that arrives as an additive `plan_leg_segments` table. Reading the
/// list now costs a `join` and saves rewriting every screen that draws a leg.
String legSummary(PlanLeg leg) {
  final parts = [
    for (final segment in leg.segments)
      // An unpriced segment is stated plainly rather than hidden or guessed at.
      // It is a gap in the fare data, and seeing it is how the gap gets closed
      // (D5) — an estimate here would look complete and be wrong.
      segment.fareKnown
          ? '${segment.mode} · ${pesos(segment.farePhpCents ?? 0)}'
          : 'fare not recorded',
  ];

  return '${distance(leg.distanceM)} · ${parts.join(' → ')}';
}

class LegLine extends StatelessWidget {
  const LegLine({required this.leg, super.key});

  final PlanLeg leg;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: EdgeInsets.only(
        left: theme.tokens.md,
        top: theme.tokens.xs,
        bottom: theme.tokens.xs,
      ),
      child: Text(
        '↳ ${legSummary(leg)}',
        style: theme.textTheme.bodySmall?.copyWith(
          // Any unpriced segment colours the whole line: the total below is a
          // floor, and the row that caused it should be the one that says so.
          color: leg.segments.every((s) => s.fareKnown)
              ? theme.colorScheme.onSurfaceVariant
              : theme.colorScheme.error,
        ),
      ),
    );
  }
}

/// The price of a stop, per person, worded so it cannot be misread.
///
/// Stored prices are per person and a plan total is for the party, so the two
/// figures must never sit side by side unlabelled — they read as a
/// contradiction. "each" is the cheapest way to make that unambiguous.
///
/// A free place takes no per-head qualifier, because "free each" is absurd.
/// `priceMax` is null rather than 0 for most free places, so this has to
/// coalesce rather than compare.
String stopPrice(PlanStop stop, int partySize) {
  final place = stop.place;
  final range = place.priceMaxPhpCents == null ||
          place.priceMaxPhpCents == place.priceMinPhpCents
      ? pesos(place.priceMinPhpCents)
      : '${pesos(place.priceMinPhpCents)}–${pesos(place.priceMaxPhpCents!)}';

  final isFree =
      place.priceMinPhpCents == 0 && (place.priceMaxPhpCents ?? 0) == 0;
  return isFree || partySize == 1 ? range : '$range each';
}

/// `cafe · Poblacion · ₱60–₱120 each · 10:00–21:00`.
///
/// One function because two screens draw this line — the flat row below and the
/// timeline's numbered tile — and the money wording in it is a rule, not
/// formatting. Two copies is how `_pesos` ended up byte-identical in two files
/// and one of them fixable without the other.
String stopFacts(PlanStop stop, DateTime plannedFor, int partySize) {
  final place = stop.place;
  final hours = place.openingHours?.describe(plannedFor) ?? 'hours unknown';

  return '${place.category}'
      '${place.barangay == null ? '' : ' · ${place.barangay}'}'
      ' · ${stopPrice(stop, partySize)} · $hours';
}

class StopLine extends StatelessWidget {
  const StopLine({
    required this.stop,
    required this.plannedFor,
    required this.partySize,
    super.key,
  });

  final PlanStop stop;
  final DateTime plannedFor;
  final int partySize;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: EdgeInsets.only(bottom: theme.tokens.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${stop.seq}. ${stop.place.name}',
            style: theme.textTheme.bodyLarge,
          ),
          Text(
            stopFacts(stop, plannedFor, partySize),
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class TotalsBlock extends StatelessWidget {
  const TotalsBlock({required this.totals, super.key});

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
              ? 'Total ${pesos(totals.totalPhpCents)}'
              : 'At least ${pesos(totals.totalPhpCents)}',
          style: theme.textTheme.titleMedium,
        ),
        Text(
          'places ${pesos(totals.placesPhpCents, zeroIsFree: false)} · '
          'fares ${pesos(totals.faresPhpCents, zeroIsFree: false)}',
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
