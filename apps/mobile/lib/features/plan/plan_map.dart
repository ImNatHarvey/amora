import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../models/simple_plan.dart';
import '../../theme/app_tokens.dart';

/// The plan, drawn.
///
/// `flutter_map` with CARTO basemap tiles — chosen at D7 because Google Maps
/// requires a billing account and this must cost ₱0.
///
/// Two rules from `docs/02-design-system.md` §5 that are not decoration:
///
///   * **The number is the link between map and timeline.** Same number, same
///     colour, always. A marker that disagrees with the tile below it makes the
///     plan unreadable while walking, which is the one moment it has to work.
///   * **Dashed for walking, solid for paid transit**, mirroring the timeline
///     exactly, so "do I pay for this leg" is answerable at a glance.
class PlanMap extends StatelessWidget {
  const PlanMap({required this.plan, this.height = 280, super.key});

  final SimplePlan plan;
  final double height;

  /// Origin first, then every stop in order — the route as walked.
  ///
  /// The origin is included because the first leg starts there rather than at a
  /// stop. Null-safe because a payload from before origin coordinates were kept
  /// has no origin to draw from; the route then simply begins at stop 1.
  List<LatLng> get _route => [
        if (plan.originLat != null && plan.originLng != null)
          LatLng(plan.originLat!, plan.originLng!),
        for (final stop in plan.stops) LatLng(stop.place.lat, stop.place.lng),
      ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.tokens;
    final route = _route;

    if (route.isEmpty) return const SizedBox.shrink();

    // A dark map under a dark app. The alternative is a bright slab in the
    // middle of a dark screen, which `02-design-system.md` §2 rules out by
    // requiring both modes to be checked rather than one to be tolerated.
    final style =
        theme.brightness == Brightness.dark ? 'dark_all' : 'light_all';

    return SizedBox(
      height: height,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(tokens.radiusMedium),
        child: FlutterMap(
          options: MapOptions(
            initialCameraFit: CameraFit.coordinates(
              coordinates: route,
              // Generous, because a marker sitting on the very edge of the
              // viewport reads as cropped rather than as the end of the route.
              padding: EdgeInsets.all(tokens.xl),
            ),
            interactionOptions: const InteractionOptions(
              // No rotation: a north-up map is the one people can match against
              // the street they are standing on.
              flags: InteractiveFlag.pinchZoom | InteractiveFlag.drag,
            ),
          ),
          children: [
            TileLayer(
              urlTemplate:
                  'https://{s}.basemaps.cartocdn.com/$style/{z}/{x}/{y}{r}.png',
              subdomains: const ['a', 'b', 'c', 'd'],
              // Both the OSM and CARTO tile policies expect a caller to
              // identify itself. An anonymous client is one they are entitled
              // to block.
              userAgentPackageName: 'com.amora.mobile',
              retinaMode: RetinaMode.isHighDensity(context),
            ),
            PolylineLayer(polylines: _legPolylines(theme, route)),
            MarkerLayer(markers: _stopMarkers(theme)),
          ],
        ),
      ),
    );
  }

  /// One polyline per leg, so each can carry its own mode's styling.
  ///
  /// Drawing the route as a single line would be simpler and would lose the
  /// only thing the styling is for: which parts cost money.
  List<Polyline> _legPolylines(ThemeData theme, List<LatLng> route) {
    final polylines = <Polyline>[];
    // When the origin is missing the route starts at stop 1, so leg N connects
    // route[N] to route[N+1] instead of route[N-1] to route[N].
    final offset = plan.originLat != null && plan.originLng != null ? 0 : 1;

    for (var i = 0; i < plan.legs.length; i += 1) {
      final from = i + offset;
      final to = from + 1;
      if (from < 0 || to >= route.length) continue;

      final leg = plan.legs[i];
      final isWalk = leg.segments.every((s) => s.mode == 'walk');

      polylines.add(
        Polyline(
          points: [route[from], route[to]],
          strokeWidth: 4,
          color: leg.segments.every((s) => s.fareKnown)
              ? theme.colorScheme.primary
              // An unpriced leg is drawn as the gap it is, matching the
              // timeline row that says "fare not recorded".
              : theme.colorScheme.error,
          // `segments` must be even-length and >= 2 — asserted by the package,
          // and that assert reads `segments.length`, which is why this cannot
          // be a const constructor call however much it looks like one.
          pattern: isWalk
              ? StrokePattern.dashed(segments: const [8, 6])
              : const StrokePattern.solid(),
        ),
      );
    }

    return polylines;
  }

  List<Marker> _stopMarkers(ThemeData theme) => [
        for (final stop in plan.stops)
          Marker(
            point: LatLng(stop.place.lat, stop.place.lng),
            width: 32,
            height: 32,
            child: _NumberedMarker(number: stop.seq),
          ),
      ];
}

/// The numbered circle. Identical in shape and colour to the timeline's, which
/// is the entire point of it.
class _NumberedMarker extends StatelessWidget {
  const _NumberedMarker({required this.number});

  final int number;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.primary,
        shape: BoxShape.circle,
        // A ring in the surface colour, so a marker stays legible against dark
        // parkland and pale roads alike.
        border: Border.all(color: theme.colorScheme.surface, width: 2),
      ),
      child: Center(
        child: Text(
          '$number',
          style: theme.textTheme.labelMedium
              ?.copyWith(color: theme.colorScheme.onPrimary),
        ),
      ),
    );
  }
}
