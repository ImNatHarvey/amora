import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/places_repository.dart';
import '../../models/place.dart';
import '../../models/place_note.dart';
import '../../theme/app_tokens.dart';
import '../../ui/error_retry.dart';
import '../../util/format.dart';
import '../../util/manila_time.dart';

/// What we actually know about one place.
///
/// This is the screen D2 is describing when it says Amora replaces five tabs:
/// the price is here, the hours are here, and `place_notes` — the lived
/// experience that would otherwise send someone to Reddit — is here too. That
/// table has existed since Phase 0 with no renderer, so until now the claim was
/// only half true.
class PlaceDetailScreen extends ConsumerWidget {
  const PlaceDetailScreen({required this.placeId, super.key});

  final String placeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final tokens = theme.tokens;
    final place = ref.watch(placeProvider(placeId));

    return Scaffold(
      appBar: AppBar(title: const Text('Place')),
      body: SafeArea(
        child: place.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Padding(
            padding: EdgeInsets.all(tokens.md),
            child: ErrorRetry(
              message: '$error',
              onRetry: () => ref.invalidate(placeProvider(placeId)),
            ),
          ),
          data: (found) => found == null
              ? Padding(
                  padding: EdgeInsets.all(tokens.md),
                  child: Text(
                    'That place is not in the catalogue.',
                    style: theme.textTheme.bodyLarge,
                  ),
                )
              : _PlaceView(place: found),
        ),
      ),
    );
  }
}

class _PlaceView extends ConsumerWidget {
  const _PlaceView({required this.place});

  final Place place;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final tokens = theme.tokens;
    final notes = ref.watch(placeNotesProvider(place.id));
    final now = toManila(DateTime.now().toUtc());

    // Per person, like every price in the app. Free takes no qualifier.
    final max = place.priceMaxPhpCents;
    final range = max == null || max == place.priceMinPhpCents
        ? pesos(place.priceMinPhpCents)
        : '${pesos(place.priceMinPhpCents)}–${pesos(max)}';
    final isFree = place.priceMinPhpCents == 0 && (max ?? 0) == 0;

    return ListView(
      padding: EdgeInsets.all(tokens.md),
      children: [
        Text(place.name, style: theme.textTheme.headlineSmall),
        SizedBox(height: tokens.xs),
        Text(
          [
            place.category,
            if (place.barangay != null) place.barangay!,
            if (place.address != null) place.address!,
          ].join(' · '),
          style: theme.textTheme.bodyMedium
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),

        SizedBox(height: tokens.lg),
        _Row(
          label: 'Price',
          value: isFree ? range : '$range each',
          // Free is good news and is never muted (design system §2).
          color: isFree ? tokens.costFree : null,
        ),
        _Row(
          label: 'Open today',
          value: place.openingHours?.describe(now) ?? 'hours not recorded',
        ),

        // Absent on every row today — nothing has been collected — so these
        // must not render as empty labels. When a number does exist, tapping it
        // should dial, which is what url_launcher is already installed for.
        if (place.contactNumber != null)
          _LinkRow(
            label: 'Phone',
            value: place.contactNumber!,
            uri: Uri.parse('tel:${place.contactNumber}'),
          ),
        if (place.socialUrl != null)
          _LinkRow(
            label: 'Page',
            value: place.socialUrl!,
            uri: Uri.parse(place.socialUrl!),
          ),

        if (place.verifiedOn != null || place.verifiedMethod != null) ...[
          SizedBox(height: tokens.sm),
          Text(
            _provenance(place),
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],

        if (place.notes != null) ...[
          SizedBox(height: tokens.lg),
          Text(place.notes!, style: theme.textTheme.bodyMedium),
        ],

        SizedBox(height: tokens.lg),
        const Divider(),
        SizedBox(height: tokens.sm),
        Text('What people say', style: theme.textTheme.titleMedium),
        SizedBox(height: tokens.sm),
        notes.when(
          loading: () => const LinearProgressIndicator(),
          error: (error, _) => ErrorRetry(
            message: '$error',
            onRetry: () => ref.invalidate(placeNotesProvider(place.id)),
          ),
          data: (list) => list.isEmpty
              ? Text(
                  'Nothing recorded about this one yet.',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final note in list) _NoteBlock(note: note),
                  ],
                ),
        ),
      ],
    );
  }

  /// "verified in person · Aug 2026", or by phone, or from local knowledge.
  ///
  /// The design system requires a catalogue's weakest rows to stay
  /// distinguishable from its strongest (§2). §10.4a made the three methods
  /// legitimate but explicitly not equal, so the row says which it was.
  String _provenance(Place place) {
    final how = switch (place.verifiedMethod) {
      'visited' => 'verified in person',
      'phoned' => 'verified by phone',
      'resident' => 'from local knowledge',
      _ => 'verified',
    };
    final when = place.verifiedOn;
    if (when == null) return how;
    return '$how · ${_monthYear(when)}';
  }

  static String _monthYear(DateTime date) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[date.month - 1]} ${date.year}';
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value, this.color});

  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: EdgeInsets.only(bottom: theme.tokens.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodyLarge?.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }
}

class _LinkRow extends StatelessWidget {
  const _LinkRow({required this.label, required this.value, required this.uri});

  final String label;
  final String value;
  final Uri uri;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      // 48 dp minimum, no exceptions (design system §5).
      onTap: () => launchUrl(uri, mode: LaunchMode.externalApplication),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: _Row(
          label: label,
          value: value,
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }
}

class _NoteBlock extends StatelessWidget {
  const _NoteBlock({required this.note});

  final PlaceNote note;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.tokens;

    return Padding(
      padding: EdgeInsets.only(bottom: tokens.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(note.body, style: theme.textTheme.bodyMedium),
          if (note.addedAt != null)
            Text(
              // A two-year-old note and last week's are not equally useful.
              formatManila(toManila(note.addedAt!)),
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
        ],
      ),
    );
  }
}
