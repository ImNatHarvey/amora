import 'dart:math' as math;

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
/// Three rules from `docs/02-design-system.md` §5 and §10.3 that are not
/// decoration:
///
///   * **The number is the link between map and timeline.** Same number, same
///     colour, always. A marker that disagrees with the tile below it makes the
///     plan unreadable while walking, which is the one moment it has to work.
///   * **Dashed for walking, solid for paid transit**, mirroring the timeline
///     exactly, so "do I pay for this leg" is answerable at a glance.
///   * **A pin may be dragged, and a drag never leaves this screen.** §10.3
///     calls it a correction to this plan only; invariant 5 is what makes that
///     a rule rather than a preference — `places` is curated data and a user
///     gesture must not edit it.
class PlanMap extends StatefulWidget {
  const PlanMap({
    required this.plan,
    this.height,
    this.adjustable = true,
    super.key,
  });

  final SimplePlan plan;

  /// Preferred height. The resolved height is this capped by the viewport — see
  /// [_resolveHeight], which is the §10.3 rule about one stop row staying
  /// visible.
  final double? height;

  /// Whether pins may be dragged. False on a completed plan, where every other
  /// edit affordance is closed off too.
  final bool adjustable;

  @override
  State<PlanMap> createState() => _PlanMapState();
}

class _PlanMapState extends State<PlanMap> {
  /// Preferred height before the viewport cap.
  static const double _preferredHeight = 280;

  /// Never shrink below this: a map smaller than this shows no context at all
  /// and is worse than the absent state.
  static const double _minHeight = 140;

  /// About what one timeline row occupies at a text scale of 1 — a numbered
  /// circle beside two lines of body text, plus its padding. Scaled, not fixed,
  /// because the whole point of the cap is that the row grows with the text.
  static const double _stopRowHeight = 96;

  /// Zoom used when the route encloses no area, so there is nothing to fit.
  /// Street level: close enough to read the block the single stop sits on.
  static const double _singlePointZoom = 16;

  final MapController _controller = MapController();
  final GlobalKey _mapKey = GlobalKey();

  /// Pin positions the user has dragged, keyed by [PlanStop.seq].
  ///
  /// Lives here and nowhere else. It is not written to `places` (invariant 5),
  /// not sent to the server, and not persisted — a drag annotates the plan you
  /// are looking at, which is exactly what §10.3 asks for.
  final Map<int, LatLng> _adjusted = {};

  int? _draggingSeq;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Origin first, then every stop in order — the route as walked.
  ///
  /// The origin is included because the first leg starts there rather than at a
  /// stop. Null-safe because a payload from before origin coordinates were kept
  /// has no origin to draw from; the route then simply begins at stop 1.
  List<LatLng> get _route => [
        if (widget.plan.originLat != null && widget.plan.originLng != null)
          LatLng(widget.plan.originLat!, widget.plan.originLng!),
        for (final stop in widget.plan.stops) _positionOf(stop),
      ];

  LatLng _positionOf(PlanStop stop) =>
      _adjusted[stop.seq] ?? LatLng(stop.place.lat, stop.place.lng);

  /// Whether these points enclose any area at all.
  ///
  /// Two stops at identical coordinates are as degenerate as one stop, and both
  /// reach the same assert inside `CameraFit`, so this asks about spread rather
  /// than counting.
  static bool _hasArea(List<LatLng> points) {
    if (points.length < 2) return false;
    final first = points.first;
    return points.any(
      (p) => p.latitude != first.latitude || p.longitude != first.longitude,
    );
  }

  /// §10.3: "Map height is capped so at least one stop row is visible beneath
  /// it at 1.3× font scale."
  ///
  /// The cap is expressed against the viewport rather than as a constant,
  /// because the thing it protects — a stop row — grows with the text scale
  /// while a constant would not. On a portrait phone at 1.0 the preferred
  /// height already satisfies it and the cap does not bite; in landscape, or at
  /// a large scale on a short viewport, it does.
  double _resolveHeight(BuildContext context) {
    final media = MediaQuery.of(context);
    final reserved =
        kToolbarHeight + media.textScaler.scale(_stopRowHeight);
    final ceiling = media.size.height - reserved;

    return math.min(
      widget.height ?? _preferredHeight,
      math.max(_minHeight, ceiling),
    );
  }

  void _moveTo(int seq, Offset globalPosition) {
    final box = _mapKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;

    final local = box.globalToLocal(globalPosition);
    setState(
      () => _adjusted[seq] = _controller.camera.screenOffsetToLatLng(local),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.tokens;
    final route = _route;

    // §10.3: with no coordinates the map is absent, not empty. An empty map of
    // Bocaue is a bare empty state, which §5 forbids.
    if (route.isEmpty) return const SizedBox.shrink();

    // A dark map under a dark app. The alternative is a bright slab in the
    // middle of a dark screen, which `02-design-system.md` §2 rules out by
    // requiring both modes to be checked rather than one to be tolerated.
    final style =
        theme.brightness == Brightness.dark ? 'dark_all' : 'light_all';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          key: _mapKey,
          height: _resolveHeight(context),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(tokens.radiusMedium),
            child: FlutterMap(
              mapController: _controller,
              options: MapOptions(
                // CameraFit.coordinates asserts `zoom.isFinite` when the
                // bounds have zero area, so a plan that is one stop with no
                // origin — which Phase 5 allows you to delete your way down to,
                // and which every pre-origin saved payload already is — would
                // take the whole screen down. Centre on the point instead.
                initialCameraFit: _hasArea(route)
                    ? CameraFit.coordinates(
                        coordinates: route,
                        // Generous, because a marker sitting on the very edge
                        // of the viewport reads as cropped rather than as the
                        // end of the route.
                        padding: EdgeInsets.all(tokens.xl),
                      )
                    : null,
                initialCenter: route.first,
                initialZoom: _singlePointZoom,
                interactionOptions: InteractionOptions(
                  // No rotation: a north-up map is the one people can match
                  // against the street they are standing on.
                  //
                  // While a pin is being dragged the map itself must not pan,
                  // or the gesture moves both and the pin never catches up.
                  flags: _draggingSeq != null
                      ? InteractiveFlag.none
                      : InteractiveFlag.pinchZoom | InteractiveFlag.drag,
                ),
              ),
              children: [
                TileLayer(
                  urlTemplate:
                      'https://{s}.basemaps.cartocdn.com/$style/{z}/{x}/{y}{r}.png',
                  subdomains: const ['a', 'b', 'c', 'd'],
                  // Both the OSM and CARTO tile policies expect a caller to
                  // identify itself. An anonymous client is one they are
                  // entitled to block.
                  userAgentPackageName: 'com.amora.mobile',
                  retinaMode: RetinaMode.isHighDensity(context),
                ),
                PolylineLayer(polylines: _legPolylines(theme, route)),
                MarkerLayer(markers: _stopMarkers()),
              ],
            ),
          ),
        ),
        if (_adjusted.isNotEmpty) ...[
          SizedBox(height: tokens.xs),
          // Offered because a drag is a correction, and a correction the user
          // cannot take back is a trap. It also names what a moved pin means,
          // which no amount of marker styling can.
          Row(
            children: [
              Expanded(
                child: Text(
                  _adjusted.length == 1
                      ? 'One pin moved on this plan only.'
                      : '${_adjusted.length} pins moved on this plan only.',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ),
              TextButton(
                onPressed: () => setState(_adjusted.clear),
                child: const Text('Reset'),
              ),
            ],
          ),
        ],
      ],
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
    final offset =
        widget.plan.originLat != null && widget.plan.originLng != null ? 0 : 1;

    for (var i = 0; i < widget.plan.legs.length; i += 1) {
      final from = i + offset;
      final to = from + 1;
      if (from < 0 || to >= route.length) continue;

      final leg = widget.plan.legs[i];
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

  List<Marker> _stopMarkers() => [
        for (final stop in widget.plan.stops)
          Marker(
            point: _positionOf(stop),
            // 48 rather than the circle's 32: the design system's minimum touch
            // target, and a pin that has to be dragged needs to be grabbable.
            width: 48,
            height: 48,
            // Long press to pick the pin up, then move — not a plain pan.
            //
            // A pan recogniser on the marker loses the gesture arena to the
            // map's own drag, so the pin simply never moved. A long press wins
            // it outright, and it is also the better gesture: panning the map
            // with a finger that happens to start on a marker must not drag the
            // marker, and with a pan recogniser here it would.
            child: widget.adjustable
                ? GestureDetector(
                    onLongPressStart: (_) =>
                        setState(() => _draggingSeq = stop.seq),
                    onLongPressMoveUpdate: (details) =>
                        _moveTo(stop.seq, details.globalPosition),
                    onLongPressEnd: (_) => setState(() => _draggingSeq = null),
                    onLongPressCancel: () => setState(() => _draggingSeq = null),
                    child: _NumberedMarker(
                      number: stop.seq,
                      moved: _adjusted.containsKey(stop.seq),
                      dragging: _draggingSeq == stop.seq,
                    ),
                  )
                : _NumberedMarker(number: stop.seq),
          ),
      ];
}

/// The numbered circle. Identical in shape and colour to the timeline's, which
/// is the entire point of it.
class _NumberedMarker extends StatelessWidget {
  const _NumberedMarker({
    required this.number,
    this.moved = false,
    this.dragging = false,
  });

  final int number;

  /// Whether this pin has been dragged away from its place's coordinates.
  final bool moved;

  final bool dragging;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: AnimatedScale(
        scale: dragging ? 1.2 : 1,
        duration: const Duration(milliseconds: 120),
        child: SizedBox(
          width: 32,
          height: 32,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: theme.colorScheme.primary,
              shape: BoxShape.circle,
              // A ring in the surface colour, so a marker stays legible against
              // dark parkland and pale roads alike. A moved pin takes the
              // tertiary ring instead — the shape and number stay identical,
              // because those are what tie it to the timeline row.
              border: Border.all(
                color: moved
                    ? theme.colorScheme.tertiary
                    : theme.colorScheme.surface,
                width: moved ? 3 : 2,
              ),
            ),
            child: Center(
              child: Text(
                '$number',
                style: theme.textTheme.labelMedium
                    ?.copyWith(color: theme.colorScheme.onPrimary),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
