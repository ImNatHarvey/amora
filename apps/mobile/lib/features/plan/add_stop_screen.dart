import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../data/plans_repository.dart';
import '../../data/profiles_repository.dart';
import '../../data/retrieval_repository.dart';
import '../../models/simple_plan.dart';
import '../../theme/app_tokens.dart';
import '../../ui/error_retry.dart';
import 'plan_providers.dart';
import '../../ui/button_spinner.dart';

/// The barangays a user-added stop may sit in.
///
/// `known_areas`, not `origin_areas` — see [RetrievalRepository.knownAreas].
/// Keyed off the profile's city for the same reason `originAreasProvider` is:
/// the day a second municipality has data, this needs no change.
final knownAreasProvider = FutureProvider<List<KnownArea>>((ref) async {
  final profile = await ref.watch(currentProfileProvider.future);
  final city = profile?.city;
  if (city == null || city.isEmpty) return const [];

  return ref.watch(retrievalRepositoryProvider).knownAreas(city);
});

/// Adding a stop Amora does not know about.
///
/// **This is not a coverage strategy** (`00-architecture.md` §12.5). A user who
/// enters their own café and is shown it back has a notes app, not Amora — the
/// promise is that *we already knew*. This exists for the narrower case §8 names:
/// a missing stop inside a city we already cover.
///
/// What lands is quarantined by `add_user_place`: excluded from retrieval for
/// everyone including its submitter, so one bad row can never reach anyone
/// else's plan (invariant 5).
class AddStopScreen extends ConsumerStatefulWidget {
  const AddStopScreen({required this.planId, super.key});

  final String planId;

  @override
  ConsumerState<AddStopScreen> createState() => _AddStopScreenState();
}

class _AddStopScreenState extends ConsumerState<AddStopScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _price = TextEditingController();
  final _mapController = MapController();

  String? _barangay;
  LatLng? _pin;
  bool _saving = false;
  String? _error;

  /// Bocaue town centre, used only as somewhere for the map to open.
  ///
  /// Not a fact about any place and never stored: the pin the user drops is the
  /// coordinate, and until they drop one there is none.
  static const _mapStart = LatLng(14.7969, 120.9236);

  @override
  void dispose() {
    _name.dispose();
    _price.dispose();
    _mapController.dispose();
    super.dispose();
  }

  /// True while nothing is chosen, so the helper text stays neutral rather than
  /// warning about a barangay the user has not picked.
  bool _selectedHasFares(List<KnownArea> areas) {
    if (_barangay == null) return true;
    return areas.any((a) => a.area == _barangay && a.hasFares);
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_pin == null) {
      setState(() => _error = 'Tap the map to mark where it is.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final placeId = await ref.read(plansRepositoryProvider).addUserPlace(
            name: _name.text.trim(),
            category: 'other',
            barangay: _barangay!,
            lat: _pin!.latitude,
            lng: _pin!.longitude,
            // Pesos in the field, centavos everywhere else. One conversion, at
            // the boundary (CLAUDE.md conventions).
            priceMinPhpCents: (int.tryParse(_price.text.trim()) ?? 0) * 100,
          );

      await ref
          .read(savedPlanProvider(widget.planId).notifier)
          .addPlace(placeId);

      if (mounted) context.pop();
    } catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = '$error';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.tokens;
    final areas = ref.watch(knownAreasProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Add a stop')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: EdgeInsets.all(tokens.md),
            children: [
              Text(
                'Only you will see this stop. It stays out of everyone '
                'else’s plans.',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              SizedBox(height: tokens.md),

              TextFormField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'What is it called?',
                  border: OutlineInputBorder(),
                ),
                validator: (value) => (value ?? '').trim().isEmpty
                    ? 'A stop needs a name.'
                    : null,
              ),
              SizedBox(height: tokens.md),

              areas.when(
                loading: () => const LinearProgressIndicator(),
                error: (error, _) => ErrorRetry(
                  message: '$error',
                  onRetry: () => ref.invalidate(knownAreasProvider),
                ),
                data: (list) => DropdownButtonFormField<String>(
                  initialValue: _barangay,
                  decoration: InputDecoration(
                    labelText: 'Which barangay?',
                    border: const OutlineInputBorder(),
                    // Not decoration: fares are keyed by barangay and matched
                    // by exact text, so this is what decides whether the leg
                    // to this stop can be priced at all. When we have no fare
                    // for the barangay chosen, say so here rather than letting
                    // the total come back hedged with no explanation.
                    helperText: _selectedHasFares(list)
                        ? 'This is how we work out the fare to get there.'
                        : 'No fare recorded to $_barangay yet, so the trip '
                            'there will show as unpriced.',
                  ),
                  items: [
                    for (final area in list)
                      DropdownMenuItem(
                        value: area.area,
                        child: Text(area.area),
                      ),
                  ],
                  onChanged: (value) => setState(() => _barangay = value),
                  validator: (value) =>
                      value == null ? 'Pick a barangay.' : null,
                ),
              ),
              SizedBox(height: tokens.md),

              TextFormField(
                controller: _price,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  labelText: 'Roughly what does one person spend?',
                  prefixText: '₱',
                  border: OutlineInputBorder(),
                  helperText: 'Leave it at 0 if it is free.',
                ),
              ),
              SizedBox(height: tokens.lg),

              Text('Where is it?', style: theme.textTheme.titleMedium),
              SizedBox(height: tokens.xs),
              Text(
                _pin == null
                    ? 'Tap the map to drop a pin.'
                    : 'Tap again to move the pin.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              SizedBox(height: tokens.sm),
              SizedBox(
                height: 260,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(tokens.radiusMedium),
                  child: FlutterMap(
                    mapController: _mapController,
                    options: MapOptions(
                      initialCenter: _pin ?? _mapStart,
                      initialZoom: 14,
                      interactionOptions: const InteractionOptions(
                        flags: InteractiveFlag.pinchZoom | InteractiveFlag.drag,
                      ),
                      onTap: (_, point) => setState(() => _pin = point),
                    ),
                    children: [
                      TileLayer(
                        urlTemplate:
                            'https://{s}.basemaps.cartocdn.com/${theme.brightness == Brightness.dark ? 'dark_all' : 'light_all'}/{z}/{x}/{y}{r}.png',
                        subdomains: const ['a', 'b', 'c', 'd'],
                        userAgentPackageName: 'com.amora.mobile',
                        retinaMode: RetinaMode.isHighDensity(context),
                      ),
                      if (_pin != null)
                        MarkerLayer(
                          markers: [
                            Marker(
                              point: _pin!,
                              width: 40,
                              height: 40,
                              child: Icon(
                                Icons.place_outlined,
                                color: theme.colorScheme.primary,
                                size: tokens.iconLarge,
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
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
                onPressed: _saving ? null : _submit,
                child: _saving
                    ? const ButtonSpinner()
                    : const Text('Add to this plan'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
