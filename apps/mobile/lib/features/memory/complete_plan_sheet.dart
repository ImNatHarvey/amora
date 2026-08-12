import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../data/memories_repository.dart';
import '../../models/simple_plan.dart';
import '../../theme/app_tokens.dart';
import '../../util/format.dart';
import 'memory_providers.dart';

/// "How did it go?" — the one sheet that closes an outing.
///
/// It asks for four things at once, and the ordering is deliberate: the keepsake
/// first (rating, photo, caption) because that is what the user came to do, then
/// the money, which is what Amora needs. Leading with a grid of price fields
/// would make recording a date feel like filing an expense report.
///
/// **Every money field is prefilled with what we predicted.** The user corrects
/// what was different instead of entering an evening from scratch — which is the
/// difference between a form people finish and one they abandon, and an abandoned
/// form writes no reports at all.
///
/// A worthwhile bias to have written down: a prefilled figure submitted untouched
/// is recorded as though observed. That is defensible here because the user *was
/// there*, and because it is conservative in the one direction that matters —
/// §10.5 only overrides a seeded price when the median diverges by more than 20%,
/// so confirmations pull the median toward the seed and can never invent a wrong
/// price. Prefilling can slow a correction down; it cannot manufacture one.
///
/// Amounts are what the **party** handed over, never per person. `complete_plan`
/// divides by `party_size` before storing a report so it is comparable with the
/// seeded per-person price (§9). Dividing here as well would halve every report.
Future<bool> showCompletePlanSheet({
  required BuildContext context,
  required String planId,
  required SimplePlan plan,
}) async {
  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => _CompletePlanSheet(planId: planId, plan: plan),
  );
  return saved ?? false;
}

class _CompletePlanSheet extends ConsumerStatefulWidget {
  const _CompletePlanSheet({required this.planId, required this.plan});

  final String planId;
  final SimplePlan plan;

  @override
  ConsumerState<_CompletePlanSheet> createState() => _CompletePlanSheetState();
}

class _CompletePlanSheetState extends ConsumerState<_CompletePlanSheet> {
  /// Controllers owned by this State, not created beside `showModalBottomSheet`.
  ///
  /// A controller created outside and disposed from the future's `whenComplete`
  /// throws "used after being disposed": the future completes when `pop` is
  /// called, while the field is still on screen fading out. That cost a Phase 3b
  /// session and is written down in HANDOFF.md; this is the shape that avoids it.
  late final List<TextEditingController> _stopSpend;
  late final List<TextEditingController> _legFare;
  final _caption = TextEditingController();

  int? _rating;
  XFile? _photo;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _stopSpend = [
      for (final stop in widget.plan.stops)
        TextEditingController(text: _pesoField(stop.partyPricePhpCents)),
    ];
    _legFare = [
      for (final leg in widget.plan.legs)
        // An unpriced leg gets an EMPTY field rather than no field. That is the
        // most valuable input on this sheet: a leg reads unpriced because
        // transit_fares has no row for that barangay pair, and the couple who
        // just paid it is the only source that will ever exist (D5). Hiding the
        // field because we have nothing to prefill would discard exactly the fare
        // we most need.
        TextEditingController(
          text: leg.fareKnown ? _pesoField(leg.farePhpCents ?? 0) : '',
        ),
    ];
  }

  /// A prefill an adult can edit: `400`, or `400.50` when it is not round.
  ///
  /// Not [pesos], which renders ₱0 as "free" — the word is right in a plan's
  /// totals and wrong inside a text field, where it is not a number you can
  /// correct.
  static String _pesoField(int cents) {
    final whole = cents ~/ 100;
    final remainder = cents % 100;
    return remainder == 0
        ? '$whole'
        : '$whole.${remainder.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    for (final controller in _stopSpend) {
      controller.dispose();
    }
    for (final controller in _legFare) {
      controller.dispose();
    }
    _caption.dispose();
    super.dispose();
  }

  Future<void> _pick(ImageSource source) async {
    final picked =
        await ref.read(memoriesRepositoryProvider).pickPhoto(source: source);
    if (picked != null && mounted) setState(() => _photo = picked);
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      // Uploaded first, and only now — not when the photo was picked. An upload
      // on pick leaves an orphaned object in the bucket every time somebody
      // changes their mind or closes the sheet.
      String? photoPath;
      final photo = _photo;
      if (photo != null) {
        photoPath = await ref
            .read(memoriesRepositoryProvider)
            .uploadPhoto(planId: widget.planId, photo: photo);
      }

      // seq is one-based on the wire, matching read_plan and therefore matching
      // what this screen is holding. complete_plan converts to the tables'
      // zero-based columns in one place.
      final stopSpends = <Map<String, dynamic>>[];
      for (var i = 0; i < _stopSpend.length; i += 1) {
        final cents = centavosFromPesoText(_stopSpend[i].text);
        // A cleared field is omitted rather than sent as 0. The report then
        // carries a null cost, which means "we did not record this" — sending 0
        // would file it as evidence the place is free.
        if (cents != null) {
          stopSpends.add({'seq': i + 1, 'spent_php_cents': cents});
        }
      }

      final legFares = <Map<String, dynamic>>[];
      for (var i = 0; i < _legFare.length; i += 1) {
        final cents = centavosFromPesoText(_legFare[i].text);
        if (cents != null) {
          legFares.add({'seq': i + 1, 'fare_php_cents': cents});
        }
      }

      final memory =
          await ref.read(completePlanControllerProvider.notifier).complete(
                planId: widget.planId,
                stopSpends: stopSpends,
                legFares: legFares,
                rating: _rating,
                caption: _caption.text.trim().isEmpty ? null : _caption.text.trim(),
                photoPath: photoPath,
              );

      if (!mounted) return;
      if (memory == null) {
        // The controller holds the error; surface it here rather than closing a
        // sheet full of figures the user would have to type again.
        setState(() {
          _busy = false;
          _error = '${ref.read(completePlanControllerProvider).error}';
        });
        return;
      }

      Navigator.of(context).pop(true);
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = '$error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.tokens;
    final plan = widget.plan;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        tokens.md,
        tokens.md,
        tokens.md,
        // Room for the keyboard, which otherwise covers the money fields — the
        // half of this sheet that needs typing.
        tokens.md + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('How did it go?', style: theme.textTheme.headlineSmall),
            SizedBox(height: tokens.xs),
            Text(
              'Only the amounts matter to us — correct anything that was '
              'different, and skip what you would rather not say.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            SizedBox(height: tokens.md),

            _RatingRow(
              rating: _rating,
              onChanged: (value) => setState(() => _rating = value),
            ),
            SizedBox(height: tokens.md),

            _PhotoRow(
              photo: _photo,
              onCamera: () => _pick(ImageSource.camera),
              onGallery: () => _pick(ImageSource.gallery),
              onClear: () => setState(() => _photo = null),
            ),
            SizedBox(height: tokens.md),

            TextField(
              controller: _caption,
              maxLines: 2,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Anything worth remembering?',
                hintText: 'Optional',
              ),
            ),
            SizedBox(height: tokens.lg),

            Text('What each stop cost', style: theme.textTheme.titleMedium),
            SizedBox(height: tokens.xs),
            Text(
              // Said explicitly because it is the one thing a user could
              // reasonably read either way, and reading it wrong halves or
              // doubles every figure they enter.
              'For all ${plan.partySize} of you, not each.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            SizedBox(height: tokens.sm),
            for (var i = 0; i < plan.stops.length; i += 1)
              _MoneyField(
                key: ValueKey('stop-spend-$i'),
                controller: _stopSpend[i],
                label: plan.stops[i].place.name,
              ),

            SizedBox(height: tokens.md),
            Text('What you paid to get around',
                style: theme.textTheme.titleMedium),
            SizedBox(height: tokens.sm),
            for (var i = 0; i < plan.legs.length; i += 1)
              _MoneyField(
                key: ValueKey('leg-fare-$i'),
                controller: _legFare[i],
                label: '${plan.legs[i].fromName} → ${plan.legs[i].toName}',
                // Named for what it is: we have no fare for this barangay pair,
                // and whatever they paid is the first record of it.
                helper: plan.legs[i].fareKnown
                    ? null
                    : 'We had no fare for this — what did it cost?',
              ),

            if (_error != null) ...[
              SizedBox(height: tokens.md),
              Text(
                _error!,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.error),
              ),
            ],

            SizedBox(height: tokens.lg),
            FilledButton(
              onPressed: _busy ? null : _submit,
              child: Text(_busy ? 'Saving…' : 'Save this outing'),
            ),
            SizedBox(height: tokens.xs),
            Text(
              // Editing is locked afterwards, and that is worth saying before
              // the tap rather than discovering by finding the handles gone.
              'Once saved, this plan stops being editable — its stops are what '
              'your report describes.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

/// One to five, or nothing at all.
///
/// No default. A rating nobody gave is not a three, and seeding the middle would
/// fabricate the only subjective figure the app stores.
class _RatingRow extends StatelessWidget {
  const _RatingRow({required this.rating, required this.onChanged});

  final int? rating;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      children: [
        for (var star = 1; star <= 5; star += 1)
          IconButton(
            // Tapping the current rating clears it, so a mistap is recoverable
            // without a separate "clear" affordance.
            onPressed: () => onChanged(rating == star ? null : star),
            tooltip: '$star of 5',
            icon: Icon(
              rating != null && star <= rating! ? Icons.star : Icons.star_border,
              color: rating != null && star <= rating!
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurfaceVariant,
            ),
          ),
      ],
    );
  }
}

class _PhotoRow extends StatelessWidget {
  const _PhotoRow({
    required this.photo,
    required this.onCamera,
    required this.onGallery,
    required this.onClear,
  });

  final XFile? photo;
  final VoidCallback onCamera;
  final VoidCallback onGallery;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.tokens;

    if (photo != null) {
      return Row(
        children: [
          Icon(Icons.check_circle, color: theme.colorScheme.primary),
          SizedBox(width: tokens.sm),
          Expanded(
            child: Text('Photo ready', style: theme.textTheme.bodyMedium),
          ),
          TextButton(onPressed: onClear, child: const Text('Remove')),
        ],
      );
    }

    return Row(
      children: [
        OutlinedButton.icon(
          onPressed: onCamera,
          icon: const Icon(Icons.photo_camera),
          label: const Text('Take a photo'),
        ),
        SizedBox(width: tokens.sm),
        TextButton(onPressed: onGallery, child: const Text('Choose one')),
      ],
    );
  }
}

class _MoneyField extends StatelessWidget {
  const _MoneyField({
    required this.controller,
    required this.label,
    this.helper,
    super.key,
  });

  final TextEditingController controller;
  final String label;
  final String? helper;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).tokens;

    return Padding(
      padding: EdgeInsets.only(bottom: tokens.sm),
      child: TextField(
        controller: controller,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(
          labelText: label,
          helperText: helper,
          // Not a hint — the sign belongs in the field so nobody types it and
          // wonders whether it counted. centavosFromPesoText tolerates one
          // anyway, because people type what they are used to.
          prefixText: '₱',
        ),
      ),
    );
  }
}
