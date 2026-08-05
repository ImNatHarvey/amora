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
class LegLine extends StatelessWidget {
  const LegLine({required this.leg, super.key});

  final PlanLeg leg;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // An unpriced leg is stated plainly rather than hidden or guessed at. It is
    // a gap in the fare data, and seeing it is how the gap gets closed (D5).
    final fare = leg.fareKnown
        ? '${leg.mode} · ${pesos(leg.farePhpCents ?? 0)}'
        : 'fare not recorded';

    return Padding(
      padding: EdgeInsets.only(
        left: theme.tokens.md,
        top: theme.tokens.xs,
        bottom: theme.tokens.xs,
      ),
      child: Text(
        '↳ ${distance(leg.distanceM)} · $fare',
        style: theme.textTheme.bodySmall?.copyWith(
          color: leg.fareKnown
              ? theme.colorScheme.onSurfaceVariant
              : theme.colorScheme.error,
        ),
      ),
    );
  }
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
    final place = stop.place;

    // Stored prices are per person, and the total below is for the party — so
    // the two figures must not sit side by side unlabelled or they read as a
    // contradiction. "each" is the cheapest way to make that unambiguous.
    final range = place.priceMaxPhpCents == null ||
            place.priceMaxPhpCents == place.priceMinPhpCents
        ? pesos(place.priceMinPhpCents)
        : '${pesos(place.priceMinPhpCents)}–${pesos(place.priceMaxPhpCents!)}';
    // A free place takes no per-head qualifier — "free each" is absurd. Note
    // priceMax is null, not 0, for most free places, so this has to coalesce.
    final isFree =
        place.priceMinPhpCents == 0 && (place.priceMaxPhpCents ?? 0) == 0;
    final price = isFree || partySize == 1 ? range : '$range each';

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
