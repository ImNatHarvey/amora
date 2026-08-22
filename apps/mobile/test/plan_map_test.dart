import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/plan/plan_map.dart';
import 'package:mobile/models/place.dart';
import 'package:mobile/models/simple_plan.dart';
import 'package:mobile/theme/app_theme.dart';

/// Gate D — `docs/02-design-system.md` §10.3.
///
/// Every assertion here is paired. A map that failed to build at all would
/// satisfy "the pin did not write back to places" and "no overflow occurred"
/// on its own, so each of those sits next to a positive that only passes when
/// the map actually rendered and the gesture actually landed.
void main() {
  Place place(String name, double lat, double lng) => Place(
        id: 'p-$name',
        slug: name.toLowerCase(),
        name: name,
        category: 'cafe',
        barangay: 'Poblacion',
        lat: lat,
        lng: lng,
        priceMinPhpCents: 12500,
      );

  PlanStop stop(int seq, Place place) => PlanStop(
        seq: seq,
        place: place,
        distanceFromOriginM: 400,
        partyPricePhpCents: place.priceMinPhpCents * 2,
      );

  SimplePlan planWith({required List<PlanStop> stops}) => SimplePlan(
        plannedForUtc: DateTime.utc(2026, 8, 7, 10),
        budgetPhpCents: 40000,
        originArea: 'Poblacion',
        radiusM: 3000,
        stops: stops,
        legs: const [],
        totals: const PlanTotals(
          placesPhpCents: 25000,
          faresPhpCents: 0,
          totalPhpCents: 25000,
          unpricedLegs: 0,
          isComplete: true,
        ),
        candidateActivities: const [],
      );

  /// Two real demo coordinates, far enough apart to give the camera something
  /// to fit rather than a single point.
  final kapeAtKultura = place('Kape at Kultura', 14.8021, 120.9315);
  final krusSaWawa = place('Krus sa Wawa', 14.8015, 120.9304);

  Widget host(Widget child) => MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(body: SingleChildScrollView(child: child)),
      );

  /// Picks pin [label] up with a long press and moves it by [by].
  ///
  /// The long press is the gesture the map uses, because a pan recogniser on a
  /// marker loses the arena to the map's own drag. The hold below must exceed
  /// kLongPressTimeout or nothing is picked up at all.
  Future<void> dragPin(WidgetTester tester, String label, Offset by) async {
    final gesture =
        await tester.startGesture(tester.getCenter(find.text(label)));
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 100));
    for (var i = 0; i < 4; i += 1) {
      await gesture.moveBy(Offset(by.dx / 4, by.dy / 4));
      await tester.pump(const Duration(milliseconds: 20));
    }
    await gesture.up();
    await tester.pumpAndSettle();
  }

  group('the map is absent rather than empty', () {
    testWidgets('a plan with no coordinates draws no map at all',
        (tester) async {
      await tester.pumpWidget(host(PlanMap(plan: planWith(stops: const []))));
      await tester.pump();

      expect(find.byType(FlutterMap), findsNothing);
    });

    testWidgets('but a plan with stops does draw one', (tester) async {
      // The positive twin of the test above. Without it, a PlanMap that threw
      // on every build would pass the "no map" assertion perfectly.
      await tester.pumpWidget(
        host(PlanMap(plan: planWith(stops: [stop(1, kapeAtKultura)]))),
      );
      await tester.pump();

      expect(find.byType(FlutterMap), findsOneWidget);
      expect(find.text('1'), findsOneWidget);
    });
  });

  group('height cap', () {
    testWidgets('does not bite on a tall viewport at 1.0x', (tester) async {
      tester.view.physicalSize = const Size(400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        host(PlanMap(plan: planWith(stops: [stop(1, kapeAtKultura)]))),
      );
      await tester.pump();

      // The preferred height, unclamped. This is the control: without it the
      // test below could pass because the map is always short.
      expect(tester.getSize(find.byType(FlutterMap)).height, 280);
    });

    testWidgets('bites on a short viewport at 1.3x, leaving room for a row',
        (tester) async {
      tester.view.physicalSize = const Size(400, 380);
      tester.view.devicePixelRatio = 1.0;
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      await tester.pumpWidget(
        host(PlanMap(plan: planWith(stops: [stop(1, kapeAtKultura)]))),
      );
      await tester.pump();

      final height = tester.getSize(find.byType(FlutterMap)).height;

      // 380 − kToolbarHeight(56) − 96×1.3(124.8) = 199.2.
      expect(height, lessThan(280));
      expect(height, closeTo(199.2, 0.5));

      // And what the cap is for: a stop row's worth of space is left under it.
      expect(380 - height, greaterThan(96 * 1.3));
    });
  });

  group('dragging a pin', () {
    testWidgets('moves it, says so, and never touches the place',
        (tester) async {
      final fixture = planWith(stops: [stop(1, kapeAtKultura), stop(2, krusSaWawa)]);

      await tester.pumpWidget(host(PlanMap(plan: fixture)));
      await tester.pump();

      expect(find.textContaining('moved on this plan only'), findsNothing);

      await dragPin(tester, '1', const Offset(40, 40));

      // Positive: the drag registered.
      expect(find.text('One pin moved on this plan only.'), findsOneWidget);

      // Invariant 5: the curated row is untouched. On its own this would pass
      // even if the gesture had done nothing, which is why it sits after the
      // assertion above rather than instead of it.
      expect(fixture.stops.first.place.lat, 14.8021);
      expect(fixture.stops.first.place.lng, 120.9315);
    });

    testWidgets('reset puts every pin back', (tester) async {
      await tester.pumpWidget(
        host(PlanMap(plan: planWith(stops: [stop(1, kapeAtKultura)]))),
      );
      await tester.pump();

      await dragPin(tester, '1', const Offset(40, 40));
      expect(find.textContaining('moved on this plan only'), findsOneWidget);

      await tester.tap(find.text('Reset'));
      await tester.pumpAndSettle();

      expect(find.textContaining('moved on this plan only'), findsNothing);
      // The map is still there — reset clears the adjustment, not the plan.
      expect(find.byType(FlutterMap), findsOneWidget);
    });

    testWidgets('a completed plan does not accept the drag', (tester) async {
      await tester.pumpWidget(
        host(
          PlanMap(
            plan: planWith(stops: [stop(1, kapeAtKultura)]),
            adjustable: false,
          ),
        ),
      );
      await tester.pump();

      await dragPin(tester, '1', const Offset(40, 40));

      expect(find.textContaining('moved on this plan only'), findsNothing);
      // Paired with the adjustable case above: the same gesture on the same
      // fixture does produce the message, so this is the flag working rather
      // than the drag never landing.
      expect(find.byType(FlutterMap), findsOneWidget);
    });
  });
}
